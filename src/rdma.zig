const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub const is_linux = builtin.os.tag == .linux;
pub const RDMA_MAX_SGE: usize = 32;
pub const RDMA_MAX_WR: usize = 256;
pub const RDMA_PAGE_SIZE: usize = 4096;
pub const RDMA_MAX_INLINE_DATA: usize = 256;
pub const RDMA_DEFAULT_MAX_RECV_WR: usize = 256;
pub const RDMA_DEFAULT_QP_ACCESS: u32 = 0x1F;
pub const RDMA_PROTECTION_DOMAIN_MAGIC: u32 = 0x50445F52;

pub const RDMATransportMode = enum(u8) {
    hardware_verbs,
    software_tcp,
};

pub const RDMAError = error{
    NotSupported,
    DeviceNotFound,
    ContextInitFailed,
    MemoryRegistrationFailed,
    QueuePairCreateFailed,
    CompletionQueueCreateFailed,
    ConnectionFailed,
    PostSendFailed,
    PostRecvFailed,
    PollFailed,
    InvalidState,
    BufferTooSmall,
    AlignmentError,
    ProtectionDomainMismatch,
    RemoteAccessError,
    Timeout,
};

pub const RDMACapabilities = struct {
    transport_mode: RDMATransportMode,
    max_mr_size: u64,
    max_qp_wr: u32,
    max_sge: u32,
    max_cqe: u32,
    max_mr: u32,
    supports_inline_data: bool,
    supports_atomic: bool,
    supports_rdma_read: bool,
    supports_rdma_write: bool,
    device_name: [64]u8,
    firmware_version: [32]u8,
    hw_ver: u32,
    node_guid: u64,

    pub fn detect() RDMACapabilities {
        var caps = std.mem.zeroes(RDMACapabilities);
        caps.transport_mode = detectTransportMode();
        caps.max_mr_size = 1 << 32;
        caps.max_qp_wr = RDMA_MAX_WR;
        caps.max_sge = RDMA_MAX_SGE;
        caps.max_cqe = RDMA_MAX_WR * 4;
        caps.max_mr = 4096;
        caps.supports_inline_data = true;
        caps.supports_atomic = true;
        caps.supports_rdma_read = true;
        caps.supports_rdma_write = true;
        caps.hw_ver = 0;
        caps.node_guid = generateNodeGuid();
        const name = "agdb-software-rdma";
        @memcpy(caps.device_name[0..name.len], name);
        const fw = "1.0.0";
        @memcpy(caps.firmware_version[0..fw.len], fw);
        return caps;
    }

    fn detectTransportMode() RDMATransportMode {
        if (!comptime is_linux) return .software_tcp;
        const f = std.fs.openFileAbsolute("/dev/infiniband/rdma_cm", .{}) catch return .software_tcp;
        f.close();
        return .hardware_verbs;
    }

    fn generateNodeGuid() u64 {
        const ts: u64 = @intCast(@max(0, std.time.nanoTimestamp()));
        var h = std.hash.Wyhash.init(0xA6DB_4D0A_0001);
        h.update(std.mem.asBytes(&ts));
        return h.final();
    }

    pub fn deviceNameSlice(self: *const RDMACapabilities) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.device_name, 0) orelse self.device_name.len;
        return self.device_name[0..end];
    }
};

pub const RDMAMemoryKey = struct {
    lkey: u32,
    rkey: u32,
    _reserved: u64 = 0,
};

pub const RDMAMemoryRegion = struct {
    buf: []align(RDMA_PAGE_SIZE) u8,
    keys: RDMAMemoryKey,
    pinned: bool,
    length: u64,
    allocator: std.mem.Allocator,
    mr_id: u32,

    const Self = @This();
    var mr_id_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

    pub fn alloc(allocator: std.mem.Allocator, size: usize) !RDMAMemoryRegion {
        const aligned_size = std.mem.alignForward(usize, size, RDMA_PAGE_SIZE);
        const buf = try allocator.alignedAlloc(u8, RDMA_PAGE_SIZE, aligned_size);
        @memset(buf, 0);
        const id = mr_id_counter.fetchAdd(1, .acq_rel);
        const lkey: u32 = @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&id)));
        return RDMAMemoryRegion{
            .buf = buf,
            .keys = .{ .lkey = lkey, .rkey = lkey ^ 0xDEAD_BEEF },
            .pinned = false,
            .length = aligned_size,
            .allocator = allocator,
            .mr_id = id,
        };
    }

    pub fn fromSlice(allocator: std.mem.Allocator, mem: []align(RDMA_PAGE_SIZE) u8) !RDMAMemoryRegion {
        const id = mr_id_counter.fetchAdd(1, .acq_rel);
        const lkey: u32 = @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&id)));
        return RDMAMemoryRegion{
            .buf = mem,
            .keys = .{ .lkey = lkey, .rkey = lkey ^ 0xDEAD_BEEF },
            .pinned = false,
            .length = mem.len,
            .allocator = allocator,
            .mr_id = id,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buf);
        self.buf = &.{};
    }

    pub fn pin(self: *Self) !void {
        if (!comptime is_linux) {
            self.pinned = true;
            return;
        }
        const rc = std.os.linux.syscall3(
            .mlock,
            @intFromPtr(self.buf.ptr),
            self.buf.len,
            0,
        );
        if (@as(isize, @bitCast(rc)) < 0) return error.MemoryRegistrationFailed;
        self.pinned = true;
    }

    pub fn unpin(self: *Self) void {
        if (!comptime is_linux or !self.pinned) return;
        _ = std.os.linux.syscall3(.munlock, @intFromPtr(self.buf.ptr), self.buf.len, 0);
        self.pinned = false;
    }

    pub fn slice(self: *const Self) []u8 {
        return self.buf;
    }

    pub fn addr(self: *const Self) u64 {
        return @intFromPtr(self.buf.ptr);
    }
};

pub const RDMAWorkOpcode = enum(u8) {
    send = 0,
    send_with_imm = 1,
    rdma_write = 2,
    rdma_write_with_imm = 3,
    rdma_read = 4,
    atomic_cas = 8,
    atomic_fetch_add = 9,
    recv = 128,
    recv_rdma_with_imm = 129,
};

pub const RDMASGElement = struct {
    addr: u64,
    length: u32,
    lkey: u32,
};

pub const RDMAWorkRequest = struct {
    wr_id: u64,
    opcode: RDMAWorkOpcode,
    sge_list: [RDMA_MAX_SGE]RDMASGElement,
    sge_count: u32,
    remote_addr: u64,
    rkey: u32,
    imm_data: u32,
    send_flags: u32,
    next: ?*RDMAWorkRequest,

    const Self = @This();

    pub const SEND_SIGNALED: u32 = 1;
    pub const SEND_FENCE: u32 = 2;
    pub const SEND_INLINE: u32 = 4;
    pub const SEND_SOLICITED: u32 = 8;

    pub fn initSend(wr_id: u64, mr: *const RDMAMemoryRegion, offset: u64, length: u32) RDMAWorkRequest {
        var wr = std.mem.zeroes(RDMAWorkRequest);
        wr.wr_id = wr_id;
        wr.opcode = .send;
        wr.sge_list[0] = .{
            .addr = mr.addr() + offset,
            .length = length,
            .lkey = mr.keys.lkey,
        };
        wr.sge_count = 1;
        wr.send_flags = SEND_SIGNALED;
        return wr;
    }

    pub fn initRdmaWrite(wr_id: u64, local_mr: *const RDMAMemoryRegion, local_off: u64, len: u32, remote_addr: u64, rkey: u32) RDMAWorkRequest {
        var wr = std.mem.zeroes(RDMAWorkRequest);
        wr.wr_id = wr_id;
        wr.opcode = .rdma_write;
        wr.sge_list[0] = .{
            .addr = local_mr.addr() + local_off,
            .length = len,
            .lkey = local_mr.keys.lkey,
        };
        wr.sge_count = 1;
        wr.remote_addr = remote_addr;
        wr.rkey = rkey;
        wr.send_flags = SEND_SIGNALED;
        return wr;
    }

    pub fn initRdmaRead(wr_id: u64, local_mr: *const RDMAMemoryRegion, local_off: u64, len: u32, remote_addr: u64, rkey: u32) RDMAWorkRequest {
        var wr = std.mem.zeroes(RDMAWorkRequest);
        wr.wr_id = wr_id;
        wr.opcode = .rdma_read;
        wr.sge_list[0] = .{
            .addr = local_mr.addr() + local_off,
            .length = len,
            .lkey = local_mr.keys.lkey,
        };
        wr.sge_count = 1;
        wr.remote_addr = remote_addr;
        wr.rkey = rkey;
        wr.send_flags = SEND_SIGNALED;
        return wr;
    }

    pub fn addSGE(self: *Self, mr: *const RDMAMemoryRegion, offset: u64, length: u32) !void {
        if (self.sge_count >= RDMA_MAX_SGE) return error.BufferTooSmall;
        self.sge_list[self.sge_count] = .{
            .addr = mr.addr() + offset,
            .length = length,
            .lkey = mr.keys.lkey,
        };
        self.sge_count += 1;
    }

    pub fn totalBytes(self: *const Self) u64 {
        var total: u64 = 0;
        for (self.sge_list[0..self.sge_count]) |sge| {
            total += sge.length;
        }
        return total;
    }
};

pub const RDMACompletionStatus = enum(u8) {
    success = 0,
    local_length_error = 1,
    local_qp_op_error = 2,
    local_prot_error = 3,
    wc_flush_error = 5,
    mw_bind_error = 6,
    bad_resp_error = 7,
    local_access_error = 8,
    remote_inv_req_error = 9,
    remote_access_error = 10,
    remote_op_error = 11,
    retry_error = 12,
    rnr_retry_error = 13,
    general_error = 255,
};

pub const RDMACompletionEvent = struct {
    wr_id: u64,
    status: RDMACompletionStatus,
    opcode: RDMAWorkOpcode,
    byte_len: u32,
    imm_data: u32,
    qp_num: u32,
    src_qp: u32,
    timestamp_ns: u64,

    pub fn isSuccess(self: *const RDMACompletionEvent) bool {
        return self.status == .success;
    }
};

pub const RDMACompletionQueue = struct {
    events: []RDMACompletionEvent,
    head: std.atomic.Value(u32),
    tail: std.atomic.Value(u32),
    capacity: u32,
    mask: u32,
    notify_fd: i32,
    allocator: std.mem.Allocator,
    cq_id: u32,

    const Self = @This();
    var cq_id_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

    pub fn init(allocator: std.mem.Allocator, cqe_count: u32) !RDMACompletionQueue {
        const actual_cap = std.math.ceilPowerOfTwo(u32, @max(cqe_count, 16)) catch return error.CompletionQueueCreateFailed;
        const events = try allocator.alloc(RDMACompletionEvent, actual_cap);
        @memset(events, std.mem.zeroes(RDMACompletionEvent));
        return RDMACompletionQueue{
            .events = events,
            .head = std.atomic.Value(u32).init(0),
            .tail = std.atomic.Value(u32).init(0),
            .capacity = actual_cap,
            .mask = actual_cap - 1,
            .notify_fd = -1,
            .allocator = allocator,
            .cq_id = cq_id_counter.fetchAdd(1, .acq_rel),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.events);
    }

    pub fn post(self: *Self, event: RDMACompletionEvent) bool {
        const tail = self.tail.load(.acquire);
        const head = self.head.load(.acquire);
        if (tail -% head >= self.capacity) return false;
        const idx = tail & self.mask;
        self.events[idx] = event;
        self.tail.store(tail +% 1, .release);
        return true;
    }

    pub fn poll(self: *Self, events: []RDMACompletionEvent) u32 {
        var count: u32 = 0;
        while (count < events.len) {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            if (head == tail) break;
            events[count] = self.events[head & self.mask];
            self.head.store(head +% 1, .release);
            count += 1;
        }
        return count;
    }

    pub fn pollOne(self: *Self) ?RDMACompletionEvent {
        const head = self.head.load(.acquire);
        const tail = self.tail.load(.acquire);
        if (head == tail) return null;
        const ev = self.events[head & self.mask];
        self.head.store(head +% 1, .release);
        return ev;
    }

    pub fn waitOne(self: *Self, timeout_ns: u64) !RDMACompletionEvent {
        const deadline = @as(u64, @intCast(@max(0, std.time.nanoTimestamp()))) + timeout_ns;
        while (true) {
            if (self.pollOne()) |ev| return ev;
            const now: u64 = @intCast(@max(0, std.time.nanoTimestamp()));
            if (now >= deadline) return error.Timeout;
            std.atomic.spinLoopHint();
        }
    }

    pub fn depth(self: *const Self) u32 {
        const tail = self.tail.load(.acquire);
        const head = self.head.load(.acquire);
        return tail -% head;
    }
};

pub const QueuePairState = enum(u8) {
    reset,
    init,
    ready_to_receive,
    ready_to_send,
    sqd,
    sqe,
    error_state,
};

pub const RDMAQueuePairConfig = struct {
    max_send_wr: u32 = RDMA_MAX_WR,
    max_recv_wr: u32 = RDMA_DEFAULT_MAX_RECV_WR,
    max_send_sge: u32 = RDMA_MAX_SGE,
    max_recv_sge: u32 = RDMA_MAX_SGE,
    max_inline_data: u32 = RDMA_MAX_INLINE_DATA,
    qp_access_flags: u32 = RDMA_DEFAULT_QP_ACCESS,
};

pub const RDMAQueuePair = struct {
    qp_num: u32,
    state: std.atomic.Value(u8),
    send_cq: *RDMACompletionQueue,
    recv_cq: *RDMACompletionQueue,
    config: RDMAQueuePairConfig,
    send_wr_count: std.atomic.Value(u32),
    recv_wr_count: std.atomic.Value(u32),
    remote_qp_num: u32,
    remote_lid: u16,
    psn: std.atomic.Value(u32),
    allocator: std.mem.Allocator,
    software_stream: ?std.net.Stream,
    software_mutex: std.Thread.Mutex,

    const Self = @This();
    var qp_num_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0x1000);

    pub fn init(
        allocator: std.mem.Allocator,
        send_cq: *RDMACompletionQueue,
        recv_cq: *RDMACompletionQueue,
        config: RDMAQueuePairConfig,
    ) !RDMAQueuePair {
        return RDMAQueuePair{
            .qp_num = qp_num_counter.fetchAdd(1, .acq_rel),
            .state = std.atomic.Value(u8).init(@intFromEnum(QueuePairState.reset)),
            .send_cq = send_cq,
            .recv_cq = recv_cq,
            .config = config,
            .send_wr_count = std.atomic.Value(u32).init(0),
            .recv_wr_count = std.atomic.Value(u32).init(0),
            .remote_qp_num = 0,
            .remote_lid = 0,
            .psn = std.atomic.Value(u32).init(0),
            .allocator = allocator,
            .software_stream = null,
            .software_mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.software_mutex.lock();
        defer self.software_mutex.unlock();
        if (self.software_stream) |s| {
            s.close();
            self.software_stream = null;
        }
    }

    pub fn transition(self: *Self, new_state: QueuePairState) !void {
        const cur = self.getState();
        const valid = switch (cur) {
            .reset => new_state == .init,
            .init => new_state == .ready_to_receive or new_state == .reset,
            .ready_to_receive => new_state == .ready_to_send or new_state == .reset,
            .ready_to_send => new_state == .sqd or new_state == .error_state or new_state == .reset,
            .sqd => new_state == .ready_to_send or new_state == .reset,
            .sqe => new_state == .reset,
            .error_state => new_state == .reset,
        };
        if (!valid) return error.InvalidState;
        self.state.store(@intFromEnum(new_state), .release);
    }

    pub fn getState(self: *const Self) QueuePairState {
        return @enumFromInt(self.state.load(.acquire));
    }

    pub fn postSend(self: *Self, wr: *const RDMAWorkRequest) !void {
        if (self.getState() != .ready_to_send) return error.InvalidState;
        const count = self.send_wr_count.load(.acquire);
        if (count >= self.config.max_send_wr) return error.PostSendFailed;

        self.software_mutex.lock();
        defer self.software_mutex.unlock();

        if (self.software_stream) |stream| {
            for (wr.sge_list[0..wr.sge_count]) |sge| {
                const ptr: [*]const u8 = @ptrFromInt(sge.addr);
                const data = ptr[0..sge.length];
                stream.writeAll(data) catch {
                    var cqe = std.mem.zeroes(RDMACompletionEvent);
                    cqe.wr_id = wr.wr_id;
                    cqe.status = .general_error;
                    cqe.opcode = wr.opcode;
                    _ = self.send_cq.post(cqe);
                    return error.PostSendFailed;
                };
            }
        }

        _ = self.send_wr_count.fetchAdd(1, .acq_rel);
        var cqe = std.mem.zeroes(RDMACompletionEvent);
        cqe.wr_id = wr.wr_id;
        cqe.status = .success;
        cqe.opcode = wr.opcode;
        cqe.byte_len = @intCast(wr.totalBytes());
        cqe.timestamp_ns = @intCast(@max(0, std.time.nanoTimestamp()));
        _ = self.send_cq.post(cqe);
    }

    pub fn postRecv(self: *Self, wr: *const RDMAWorkRequest) !void {
        if (self.getState() != .ready_to_receive and self.getState() != .ready_to_send) {
            return error.InvalidState;
        }
        const count = self.recv_wr_count.load(.acquire);
        if (count >= self.config.max_recv_wr) return error.PostRecvFailed;
        _ = self.recv_wr_count.fetchAdd(1, .acq_rel);
        _ = wr;
    }

    pub fn connectSoftware(self: *Self, stream: std.net.Stream) void {
        self.software_mutex.lock();
        defer self.software_mutex.unlock();
        self.software_stream = stream;
    }
};

pub const RDMAContext = struct {
    caps: RDMACapabilities,
    allocator: std.mem.Allocator,
    cqs: std.ArrayList(*RDMACompletionQueue),
    qps: std.ArrayList(*RDMAQueuePair),
    mrs: std.ArrayList(*RDMAMemoryRegion),
    mutex: std.Thread.Mutex,
    initialized: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*RDMAContext {
        const self = try allocator.create(RDMAContext);
        self.* = RDMAContext{
            .caps = RDMACapabilities.detect(),
            .allocator = allocator,
            .cqs = std.ArrayList(*RDMACompletionQueue).init(allocator),
            .qps = std.ArrayList(*RDMAQueuePair).init(allocator),
            .mrs = std.ArrayList(*RDMAMemoryRegion).init(allocator),
            .mutex = .{},
            .initialized = true,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        for (self.qps.items) |qp| {
            qp.deinit();
            self.allocator.destroy(qp);
        }
        self.qps.deinit();
        for (self.cqs.items) |cq| {
            cq.deinit();
            self.allocator.destroy(cq);
        }
        self.cqs.deinit();
        for (self.mrs.items) |mr| {
            mr.deinit();
            self.allocator.destroy(mr);
        }
        self.mrs.deinit();
        self.initialized = false;
        self.mutex.unlock();
        self.allocator.destroy(self);
    }

    pub fn createCQ(self: *Self, cqe_count: u32) !*RDMACompletionQueue {
        const cq = try self.allocator.create(RDMACompletionQueue);
        errdefer self.allocator.destroy(cq);
        cq.* = try RDMACompletionQueue.init(self.allocator, cqe_count);
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.cqs.append(cq);
        return cq;
    }

    pub fn createQP(self: *Self, send_cq: *RDMACompletionQueue, recv_cq: *RDMACompletionQueue, config: RDMAQueuePairConfig) !*RDMAQueuePair {
        const qp = try self.allocator.create(RDMAQueuePair);
        errdefer self.allocator.destroy(qp);
        qp.* = try RDMAQueuePair.init(self.allocator, send_cq, recv_cq, config);
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.qps.append(qp);
        return qp;
    }

    pub fn registerMR(self: *Self, size: usize) !*RDMAMemoryRegion {
        const mr = try self.allocator.create(RDMAMemoryRegion);
        errdefer self.allocator.destroy(mr);
        mr.* = try RDMAMemoryRegion.alloc(self.allocator, size);
        errdefer mr.deinit();
        try mr.pin();
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.mrs.append(mr);
        return mr;
    }

    pub fn getCapabilities(self: *const Self) *const RDMACapabilities {
        return &self.caps;
    }

    pub fn transportMode(self: *const Self) RDMATransportMode {
        return self.caps.transport_mode;
    }
};

test "rdma capabilities detect" {
    const caps = RDMACapabilities.detect();
    try std.testing.expect(caps.max_qp_wr >= 16);
    try std.testing.expect(caps.max_sge >= 1);
}

test "rdma memory region alloc" {
    const a = std.testing.allocator;
    var mr = try RDMAMemoryRegion.alloc(a, 4096);
    defer mr.deinit();
    try std.testing.expect(mr.keys.lkey != 0);
    try std.testing.expect(mr.length >= 4096);
}

test "rdma completion queue ring" {
    const a = std.testing.allocator;
    var cq = try RDMACompletionQueue.init(a, 16);
    defer cq.deinit();

    var ev = std.mem.zeroes(RDMACompletionEvent);
    ev.wr_id = 42;
    ev.status = .success;
    try std.testing.expect(cq.post(ev));

    const polled = cq.pollOne();
    try std.testing.expect(polled != null);
    try std.testing.expectEqual(@as(u64, 42), polled.?.wr_id);
}

test "rdma context init deinit" {
    const a = std.testing.allocator;
    var ctx = try RDMAContext.init(a);
    defer ctx.deinit();
    try std.testing.expect(ctx.initialized);
}
