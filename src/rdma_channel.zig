const std = @import("std");
const rdma = @import("rdma.zig");
const wal_mod = @import("wal.zig");

pub const CHANNEL_MAGIC: u64 = 0x4348414E_4E454C52;
pub const WAL_PAGE_SIZE: usize = 4096;
pub const CHANNEL_BUFFER_PAGES: usize = 64;
pub const CHANNEL_BUFFER_SIZE: usize = WAL_PAGE_SIZE * CHANNEL_BUFFER_PAGES;
pub const MAX_INFLIGHT_OPS: usize = 128;
pub const ACK_TIMEOUT_NS: u64 = 5 * std.time.ns_per_s;

pub const RDMAChannelConfig = struct {
    buffer_size: usize = CHANNEL_BUFFER_SIZE,
    max_inflight: usize = MAX_INFLIGHT_OPS,
    qp_config: rdma.RDMAQueuePairConfig = .{},
    use_rdma_write: bool = true,
    use_inline_for_small: bool = true,
    inline_threshold: u32 = 128,
    ack_timeout_ns: u64 = ACK_TIMEOUT_NS,
};

pub const ChannelState = enum(u8) {
    unconnected,
    handshaking,
    ready,
    draining,
    closed,
    error_state,
};

pub const ChannelEndpoint = struct {
    qp_num: u32,
    mr_addr: u64,
    mr_rkey: u32,
    mr_length: u64,
    node_id: u64,

    pub fn toBytes(self: *const ChannelEndpoint) [@sizeOf(ChannelEndpoint)]u8 {
        return std.mem.toBytes(self.*);
    }

    pub fn fromBytes(bytes: [@sizeOf(ChannelEndpoint)]u8) ChannelEndpoint {
        return std.mem.bytesToValue(ChannelEndpoint, &bytes);
    }
};

pub const RDMAFlightEntry = struct {
    wr_id: u64,
    offset: u64,
    length: u32,
    lsn: u64,
    timestamp_ns: u64,
    completed: bool,
    error_status: rdma.RDMACompletionStatus,
};

pub const FlightTracker = struct {
    entries: []RDMAFlightEntry,
    capacity: usize,
    inflight: std.atomic.Value(u32),
    next_wr_id: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !FlightTracker {
        const entries = try allocator.alloc(RDMAFlightEntry, capacity);
        @memset(entries, std.mem.zeroes(RDMAFlightEntry));
        return FlightTracker{
            .entries = entries,
            .capacity = capacity,
            .inflight = std.atomic.Value(u32).init(0),
            .next_wr_id = std.atomic.Value(u64).init(1),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.entries);
    }

    pub fn track(self: *Self, offset: u64, length: u32, lsn: u64) !u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.inflight.load(.acquire) >= self.capacity) return error.TooManyInFlight;

        const wr_id = self.next_wr_id.fetchAdd(1, .acq_rel);
        const slot = wr_id % self.capacity;
        self.entries[slot] = RDMAFlightEntry{
            .wr_id = wr_id,
            .offset = offset,
            .length = length,
            .lsn = lsn,
            .timestamp_ns = @intCast(@max(0, std.time.nanoTimestamp())),
            .completed = false,
            .error_status = .success,
        };
        _ = self.inflight.fetchAdd(1, .acq_rel);
        return wr_id;
    }

    pub fn complete(self: *Self, wr_id: u64, status: rdma.RDMACompletionStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const slot = wr_id % self.capacity;
        if (self.entries[slot].wr_id == wr_id) {
            self.entries[slot].completed = true;
            self.entries[slot].error_status = status;
            if (self.inflight.load(.acquire) > 0) {
                _ = self.inflight.fetchSub(1, .acq_rel);
            }
        }
    }

    pub fn waitForLSN(self: *Self, lsn: u64, timeout_ns: u64) !void {
        const deadline = @as(u64, @intCast(@max(0, std.time.nanoTimestamp()))) + timeout_ns;
        while (true) {
            var all_done = true;
            self.mutex.lock();
            for (self.entries) |*entry| {
                if (!entry.completed and entry.lsn <= lsn and entry.lsn > 0) {
                    all_done = false;
                    if (entry.error_status != .success) {
                        self.mutex.unlock();
                        return error.RemoteAccessError;
                    }
                    break;
                }
            }
            self.mutex.unlock();
            if (all_done) return;
            const now: u64 = @intCast(@max(0, std.time.nanoTimestamp()));
            if (now >= deadline) return error.Timeout;
            std.atomic.spinLoopHint();
        }
    }

    pub fn inflightCount(self: *const Self) u32 {
        return self.inflight.load(.acquire);
    }
};

pub const RDMAChannel = struct {
    ctx: *rdma.RDMAContext,
    qp: *rdma.RDMAQueuePair,
    send_cq: *rdma.RDMACompletionQueue,
    recv_cq: *rdma.RDMACompletionQueue,
    local_mr: *rdma.RDMAMemoryRegion,
    config: RDMAChannelConfig,
    state: std.atomic.Value(u8),
    flight: FlightTracker,
    local_ep: ChannelEndpoint,
    remote_ep: ChannelEndpoint,
    write_offset: std.atomic.Value(u64),
    bytes_written: std.atomic.Value(u64),
    ops_completed: std.atomic.Value(u64),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, ctx: *rdma.RDMAContext, config: RDMAChannelConfig) !*RDMAChannel {
        const self = try allocator.create(RDMAChannel);
        errdefer allocator.destroy(self);

        const send_cq = try ctx.createCQ(@intCast(config.qp_config.max_send_wr));
        const recv_cq = try ctx.createCQ(@intCast(config.qp_config.max_recv_wr));
        const qp = try ctx.createQP(send_cq, recv_cq, config.qp_config);
        const mr = try ctx.registerMR(config.buffer_size);
        const flight = try FlightTracker.init(allocator, config.max_inflight);

        const local_ep = ChannelEndpoint{
            .qp_num = qp.qp_num,
            .mr_addr = mr.addr(),
            .mr_rkey = mr.keys.rkey,
            .mr_length = mr.length,
            .node_id = 0,
        };

        self.* = RDMAChannel{
            .ctx = ctx,
            .qp = qp,
            .send_cq = send_cq,
            .recv_cq = recv_cq,
            .local_mr = mr,
            .config = config,
            .state = std.atomic.Value(u8).init(@intFromEnum(ChannelState.unconnected)),
            .flight = flight,
            .local_ep = local_ep,
            .remote_ep = std.mem.zeroes(ChannelEndpoint),
            .write_offset = std.atomic.Value(u64).init(0),
            .bytes_written = std.atomic.Value(u64).init(0),
            .ops_completed = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };

        try qp.transition(.init);
        try qp.transition(.ready_to_receive);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.flight.deinit();
        self.allocator.destroy(self);
    }

    pub fn connectSoftware(self: *Self, stream: std.net.Stream) !void {
        self.qp.connectSoftware(stream);
        try self.qp.transition(.ready_to_send);
        self.setState(.ready);
    }

    pub fn writeRemote(self: *Self, data: []const u8, remote_offset: u64, lsn: u64) !u64 {
        if (self.getState() != .ready) return error.InvalidState;
        if (data.len > self.local_mr.length) return error.BufferTooSmall;

        const local_offset = self.write_offset.fetchAdd(data.len, .acq_rel) % self.local_mr.length;
        const actual_offset = local_offset - (local_offset % @sizeOf(u8));
        @memcpy(self.local_mr.buf[actual_offset .. actual_offset + data.len], data);

        const wr_id = try self.flight.track(remote_offset, @intCast(data.len), lsn);

        const wr = rdma.RDMAWorkRequest.initRdmaWrite(
            wr_id,
            self.local_mr,
            actual_offset,
            @intCast(data.len),
            self.remote_ep.mr_addr + remote_offset,
            self.remote_ep.mr_rkey,
        );
        try self.qp.postSend(&wr);
        return wr_id;
    }

    pub fn readRemote(self: *Self, remote_offset: u64, length: u32, local_offset: u64) !u64 {
        if (self.getState() != .ready) return error.InvalidState;
        if (local_offset + length > self.local_mr.length) return error.BufferTooSmall;

        const wr_id = try self.flight.track(remote_offset, length, 0);
        const wr = rdma.RDMAWorkRequest.initRdmaRead(
            wr_id,
            self.local_mr,
            local_offset,
            length,
            self.remote_ep.mr_addr + remote_offset,
            self.remote_ep.mr_rkey,
        );
        try self.qp.postSend(&wr);
        return wr_id;
    }

    pub fn drainCompletions(self: *Self, max: u32) u32 {
        var buf: [64]rdma.RDMACompletionEvent = undefined;
        const n = self.send_cq.poll(buf[0..@min(max, 64)]);
        for (buf[0..n]) |ev| {
            self.flight.complete(ev.wr_id, ev.status);
            if (ev.isSuccess()) {
                _ = self.ops_completed.fetchAdd(1, .acq_rel);
                _ = self.bytes_written.fetchAdd(ev.byte_len, .acq_rel);
            }
        }
        return n;
    }

    pub fn localBuffer(self: *Self) []u8 {
        return self.local_mr.buf;
    }

    pub fn localEndpoint(self: *const Self) ChannelEndpoint {
        return self.local_ep;
    }

    pub fn setRemoteEndpoint(self: *Self, ep: ChannelEndpoint) void {
        self.remote_ep = ep;
    }

    pub fn getState(self: *const Self) ChannelState {
        return @enumFromInt(self.state.load(.acquire));
    }

    fn setState(self: *Self, s: ChannelState) void {
        self.state.store(@intFromEnum(s), .release);
    }

    pub fn channelStats(self: *const Self) ChannelStats {
        return .{
            .state = self.getState(),
            .bytes_written = self.bytes_written.load(.acquire),
            .ops_completed = self.ops_completed.load(.acquire),
            .inflight = self.flight.inflightCount(),
            .write_offset = self.write_offset.load(.acquire),
        };
    }
};

pub const ChannelStats = struct {
    state: ChannelState,
    bytes_written: u64,
    ops_completed: u64,
    inflight: u32,
    write_offset: u64,
};

pub const WALPageDescriptor = extern struct {
    lsn: u64,
    tenant_id: u64,
    page_offset: u64,
    page_size: u32,
    checksum: u32,
    flags: u16,
    _pad: [6]u8 = [_]u8{0} ** 6,

    pub const FLAG_COMPRESSED: u16 = 1;
    pub const FLAG_ENCRYPTED: u16 = 2;
    pub const FLAG_LAST_IN_BATCH: u16 = 4;

    pub fn computeChecksum(self: *const WALPageDescriptor, page_data: []const u8) u32 {
        var crc: u32 = 0xFFFFFFFF;
        for (std.mem.asBytes(self)[0 .. @sizeOf(WALPageDescriptor) - 4]) |b| {
            crc ^= @as(u32, b);
            crc = (crc >> 8) ^ crc32_table[crc & 0xFF];
        }
        for (page_data) |b| {
            crc ^= @as(u32, b);
            crc = (crc >> 8) ^ crc32_table[crc & 0xFF];
        }
        return crc ^ 0xFFFFFFFF;
    }
};

pub const RDMAWALShipper = struct {
    channel: *RDMAChannel,
    tenant_id: u64,
    remote_wal_base: u64,
    remote_wal_size: u64,
    local_write_cursor: std.atomic.Value(u64),
    pages_shipped: std.atomic.Value(u64),
    bytes_shipped: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        channel: *RDMAChannel,
        tenant_id: u64,
        remote_wal_base: u64,
        remote_wal_size: u64,
    ) !*RDMAWALShipper {
        const self = try allocator.create(RDMAWALShipper);
        self.* = RDMAWALShipper{
            .channel = channel,
            .tenant_id = tenant_id,
            .remote_wal_base = remote_wal_base,
            .remote_wal_size = remote_wal_size,
            .local_write_cursor = std.atomic.Value(u64).init(0),
            .pages_shipped = std.atomic.Value(u64).init(0),
            .bytes_shipped = std.atomic.Value(u64).init(0),
            .mutex = .{},
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn shipRecord(self: *Self, record: *const wal_mod.WALRecord, payload: ?[]const u8, lsn: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const record_bytes = std.mem.asBytes(record);
        const payload_len: usize = if (payload) |p| p.len else 0;
        const total_len = @sizeOf(WALPageDescriptor) + record_bytes.len + payload_len;

        const cursor = self.local_write_cursor.load(.acquire);
        if (cursor + total_len > self.remote_wal_size) return error.RemoteWALFull;

        var local_buf = self.channel.localBuffer();
        const write_start = cursor % (local_buf.len / 2);

        var desc = std.mem.zeroes(WALPageDescriptor);
        desc.lsn = lsn;
        desc.tenant_id = self.tenant_id;
        desc.page_offset = cursor;
        desc.page_size = @intCast(record_bytes.len + payload_len);

        const desc_bytes = std.mem.asBytes(&desc);
        if (write_start + desc_bytes.len + record_bytes.len + payload_len > local_buf.len) {
            return error.BufferTooSmall;
        }

        @memcpy(local_buf[write_start .. write_start + desc_bytes.len], desc_bytes);
        @memcpy(local_buf[write_start + desc_bytes.len .. write_start + desc_bytes.len + record_bytes.len], record_bytes);
        if (payload) |p| {
            @memcpy(
                local_buf[write_start + desc_bytes.len + record_bytes.len .. write_start + desc_bytes.len + record_bytes.len + p.len],
                p,
            );
        }

        const remote_offset = cursor % self.remote_wal_size;
        _ = try self.channel.writeRemote(
            local_buf[write_start .. write_start + desc_bytes.len + record_bytes.len + payload_len],
            self.remote_wal_base + remote_offset,
            lsn,
        );

        _ = self.local_write_cursor.fetchAdd(total_len, .acq_rel);
        _ = self.pages_shipped.fetchAdd(1, .acq_rel);
        _ = self.bytes_shipped.fetchAdd(total_len, .acq_rel);
    }

    pub fn syncUpTo(self: *Self, lsn: u64, timeout_ns: u64) !void {
        try self.channel.flight.waitForLSN(lsn, timeout_ns);
    }

    pub fn shipperStats(self: *const Self) ShipperStats {
        return .{
            .pages_shipped = self.pages_shipped.load(.acquire),
            .bytes_shipped = self.bytes_shipped.load(.acquire),
            .write_cursor = self.local_write_cursor.load(.acquire),
        };
    }
};

pub const ShipperStats = struct {
    pages_shipped: u64,
    bytes_shipped: u64,
    write_cursor: u64,
};

const crc32_table: [256]u32 = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]u32 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var crc: u32 = @intCast(i);
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            if (crc & 1 != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
        table[i] = crc;
    }
    break :blk table;
};

test "flight tracker track and complete" {
    const a = std.testing.allocator;
    var tracker = try FlightTracker.init(a, 16);
    defer tracker.deinit();

    const wr_id = try tracker.track(0, 4096, 1);
    try std.testing.expectEqual(@as(u32, 1), tracker.inflightCount());
    tracker.complete(wr_id, .success);
    try std.testing.expectEqual(@as(u32, 0), tracker.inflightCount());
}

test "rdma channel init deinit" {
    const a = std.testing.allocator;
    var ctx = try rdma.RDMAContext.init(a);
    defer ctx.deinit();

    var ch = try RDMAChannel.init(a, ctx, .{});
    defer ch.deinit();

    try std.testing.expectEqual(ChannelState.unconnected, ch.getState());
}
