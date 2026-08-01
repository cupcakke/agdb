const std = @import("std");
const mem_utils = @import("../mem_utils.zig");
const wal_mod = @import("../wal.zig");
const rdma_channel_mod = @import("../rdma_channel.zig");

pub const FRAME_MAGIC: u32 = 0x57414C54;
pub const FRAME_HEADER_SIZE: usize = 24;
pub const MAX_FRAME_PAYLOAD: usize = 1024 * 1024;
pub const DEFAULT_WAL_PORT: u16 = 7442;
pub const CONNECT_TIMEOUT_MS: u64 = 5000;
pub const SEND_TIMEOUT_MS: u64 = 2000;
pub const RECONNECT_BACKOFF_MS: u64 = 500;
pub const MAX_RECONNECT_ATTEMPTS: u32 = 8;
pub const DEFAULT_BATCH_CAPACITY: usize = 256;

pub const FrameHeader = extern struct {
    magic: u32,
    payload_len: u32,
    lsn: u64,
    tenant_id: u64,

    pub fn init(payload_len: u32, lsn: u64, tenant_id: u64) FrameHeader {
        return .{
            .magic = FRAME_MAGIC,
            .payload_len = payload_len,
            .lsn = lsn,
            .tenant_id = tenant_id,
        };
    }

    pub fn validate(self: *const FrameHeader) !void {
        if (self.magic != FRAME_MAGIC) return error.InvalidFrameMagic;
        if (self.payload_len > MAX_FRAME_PAYLOAD) return error.FrameTooLarge;
    }
};

comptime {
    std.debug.assert(@sizeOf(FrameHeader) == FRAME_HEADER_SIZE);
}

pub const RemoteWALConfig = struct {
    endpoint_host: [256]u8,
    endpoint_port: u16,
    tenant_id: u64,
    connect_timeout_ms: u64,
    send_timeout_ms: u64,
    batch_capacity: usize,
    tls_enabled: bool,

    pub fn init(host: []const u8, port: u16, tenant_id: u64) RemoteWALConfig {
        var cfg = RemoteWALConfig{
            .endpoint_host = [_]u8{0} ** 256,
            .endpoint_port = port,
            .tenant_id = tenant_id,
            .connect_timeout_ms = CONNECT_TIMEOUT_MS,
            .send_timeout_ms = SEND_TIMEOUT_MS,
            .batch_capacity = DEFAULT_BATCH_CAPACITY,
            .tls_enabled = false,
        };
        const n = @min(host.len, cfg.endpoint_host.len - 1);
        @memcpy(cfg.endpoint_host[0..n], host[0..n]);
        return cfg;
    }

    pub fn hostSlice(self: *const RemoteWALConfig) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.endpoint_host, 0) orelse self.endpoint_host.len;
        return self.endpoint_host[0..end];
    }
};

pub const TransportState = enum(u8) {
    disconnected,
    connecting,
    connected,
    draining,
    failed,
};

pub const WALFrameItem = struct {
    record: wal_mod.WALRecord,
    payload: ?[]const u8,
    payload_len: u32,
    lsn: u64,
};

pub const RemoteWALTransport = struct {
    config: RemoteWALConfig,
    state: std.atomic.Value(u8),
    stream: ?std.net.Stream,
    send_mutex: std.Thread.Mutex,
    lsn_counter: std.atomic.Value(u64),
    bytes_sent: std.atomic.Value(u64),
    frames_sent: std.atomic.Value(u64),
    reconnect_attempts: u32,
    allocator: std.mem.Allocator,
    rdma_shipper: ?*rdma_channel_mod.RDMAWALShipper,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: RemoteWALConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .config = config,
            .state = std.atomic.Value(u8).init(@intFromEnum(TransportState.disconnected)),
            .stream = null,
            .send_mutex = .{},
            .lsn_counter = std.atomic.Value(u64).init(1),
            .bytes_sent = std.atomic.Value(u64).init(0),
            .frames_sent = std.atomic.Value(u64).init(0),
            .reconnect_attempts = 0,
            .allocator = allocator,
            .rdma_shipper = null,
        };
        return self;
    }

    pub fn attachRDMAShipper(self: *Self, shipper: *rdma_channel_mod.RDMAWALShipper) void {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();
        self.rdma_shipper = shipper;
    }

    pub fn detachRDMAShipper(self: *Self) void {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();
        self.rdma_shipper = null;
    }

    pub fn deinit(self: *Self) void {
        self.disconnect();
        self.allocator.destroy(self);
    }

    pub fn connect(self: *Self) !void {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();

        if (self.getState() == .connected) return;
        self.setState(.connecting);

        const host = self.config.hostSlice();
        if (host.len == 0) {
            self.setState(.failed);
            return error.NoEndpointConfigured;
        }

        const addr = std.net.Address.parseIp4(host, self.config.endpoint_port) catch blk: {
            const list = try std.net.getAddressList(self.allocator, host, self.config.endpoint_port);
            defer list.deinit();
            if (list.addrs.len == 0) {
                self.setState(.disconnected);
                return error.ResolutionFailed;
            }
            break :blk list.addrs[0];
        };

        const stream = std.net.tcpConnectToAddress(addr) catch |err| {
            self.setState(.disconnected);
            self.reconnect_attempts += 1;
            return err;
        };

        self.stream = stream;
        self.reconnect_attempts = 0;
        self.setState(.connected);
    }

    pub fn disconnect(self: *Self) void {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
        self.setState(.disconnected);
    }

    pub fn sendRecord(self: *Self, record: *const wal_mod.WALRecord, extra_data: ?[]const u8) !u64 {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();

        const record_bytes = std.mem.asBytes(record);
        const extra_len: u32 = if (extra_data) |d| @intCast(d.len) else 0;
        const payload_len: u32 = @intCast(record_bytes.len + extra_len);
        const lsn = self.lsn_counter.fetchAdd(1, .acq_rel);

        if (self.rdma_shipper) |shipper| {
            try shipper.shipRecord(record, extra_data, lsn);
            _ = self.bytes_sent.fetchAdd(FRAME_HEADER_SIZE + payload_len, .release);
            _ = self.frames_sent.fetchAdd(1, .release);
            return lsn;
        }

        if (self.getState() != .connected) return error.NotConnected;

        const hdr = FrameHeader.init(payload_len, lsn, self.config.tenant_id);
        const stream = self.stream orelse return error.NotConnected;

        stream.writeAll(std.mem.asBytes(&hdr)) catch |err| {
            self.stream = null;
            self.setState(.disconnected);
            return err;
        };
        stream.writeAll(record_bytes) catch |err| {
            self.stream = null;
            self.setState(.disconnected);
            return err;
        };
        if (extra_data) |d| {
            stream.writeAll(d) catch |err| {
                self.stream = null;
                self.setState(.disconnected);
                return err;
            };
        }

        _ = self.bytes_sent.fetchAdd(FRAME_HEADER_SIZE + payload_len, .release);
        _ = self.frames_sent.fetchAdd(1, .release);
        return lsn;
    }

    pub fn sendBatch(self: *Self, items: []const WALFrameItem) !u32 {
        var sent: u32 = 0;
        for (items) |*item| {
            _ = try self.sendRecord(&item.record, item.payload);
            sent += 1;
        }
        return sent;
    }

    pub fn readAck(self: *Self) !u64 {
        self.send_mutex.lock();
        defer self.send_mutex.unlock();
        const stream = self.stream orelse return error.NotConnected;
        var ack: u64 = undefined;
        try stream.readAll(std.mem.asBytes(&ack));
        return ack;
    }

    pub fn ensureConnected(self: *Self) !void {
        if (self.getState() == .connected) return;
        var attempts: u32 = 0;
        while (attempts < MAX_RECONNECT_ATTEMPTS) : (attempts += 1) {
            self.connect() catch {
                std.time.sleep(RECONNECT_BACKOFF_MS * std.time.ns_per_ms * (@as(u64, 1) << @intCast(@min(attempts, 6))));
                continue;
            };
            return;
        }
        return error.MaxReconnectAttemptsExceeded;
    }

    fn getState(self: *const Self) TransportState {
        return @enumFromInt(self.state.load(.acquire));
    }

    fn setState(self: *Self, s: TransportState) void {
        self.state.store(@intFromEnum(s), .release);
    }

    pub fn stats(self: *const Self) TransportStats {
        return .{
            .state = self.getState(),
            .bytes_sent = self.bytes_sent.load(.acquire),
            .frames_sent = self.frames_sent.load(.acquire),
            .current_lsn = self.lsn_counter.load(.acquire),
            .reconnect_attempts = self.reconnect_attempts,
        };
    }
};

pub const TransportStats = struct {
    state: TransportState,
    bytes_sent: u64,
    frames_sent: u64,
    current_lsn: u64,
    reconnect_attempts: u32,
};

pub const WALProxy = struct {
    allocator: std.mem.Allocator,
    transports: std.AutoHashMap(u64, *RemoteWALTransport),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) WALProxy {
        return .{
            .allocator = allocator,
            .transports = std.AutoHashMap(u64, *RemoteWALTransport).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        var it = self.transports.valueIterator();
        while (it.next()) |tp| {
            tp.*.deinit();
        }
        self.transports.deinit();
        self.mutex.unlock();
    }

    pub fn registerTenant(self: *Self, tenant_id: u64, config: RemoteWALConfig) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.transports.contains(tenant_id)) return;
        const tp = try RemoteWALTransport.init(self.allocator, config);
        errdefer tp.deinit();
        try self.transports.put(tenant_id, tp);
    }

    pub fn removeTenant(self: *Self, tenant_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.transports.fetchRemove(tenant_id)) |kv| {
            kv.value.deinit();
        }
    }

    pub fn getTransport(self: *Self, tenant_id: u64) ?*RemoteWALTransport {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.transports.get(tenant_id);
    }

    pub fn forwardRecord(self: *Self, tenant_id: u64, record: *const wal_mod.WALRecord, data: ?[]const u8) !u64 {
        const tp = self.getTransport(tenant_id) orelse return error.TenantNotRegistered;
        try tp.ensureConnected();
        return tp.sendRecord(record, data);
    }

    pub fn queryLSN(self: *Self, tenant_id: u64) !u64 {
        const tp = self.getTransport(tenant_id) orelse return error.TenantNotRegistered;
        if (tp.getState() != .connected) return error.NotConnected;
        return tp.lsn_counter.load(.acquire) - 1;
    }

    pub fn tenantCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.transports.count();
    }
};

pub const StatelessComputeNode = struct {
    proxy: *WALProxy,
    tenant_id: u64,
    node_id: u64,
    local_lsn: std.atomic.Value(u64),
    pending_acks: std.atomic.Value(u32),

    const Self = @This();

    pub fn init(proxy: *WALProxy, tenant_id: u64, node_id: u64) StatelessComputeNode {
        return .{
            .proxy = proxy,
            .tenant_id = tenant_id,
            .node_id = node_id,
            .local_lsn = std.atomic.Value(u64).init(0),
            .pending_acks = std.atomic.Value(u32).init(0),
        };
    }

    pub fn appendWAL(self: *Self, record: *const wal_mod.WALRecord, payload: ?[]const u8) !u64 {
        const lsn = try self.proxy.forwardRecord(self.tenant_id, record, payload);
        _ = self.local_lsn.fetchAdd(1, .acq_rel);
        _ = self.pending_acks.fetchAdd(1, .acq_rel);
        return lsn;
    }

    pub fn syncLSN(self: *Self) !u64 {
        const remote_lsn = try self.proxy.queryLSN(self.tenant_id);
        const local = self.local_lsn.load(.acquire);
        if (remote_lsn < local) return error.LSNMismatch;
        self.pending_acks.store(0, .release);
        return remote_lsn;
    }

    pub fn isStateless() bool {
        return true;
    }

    pub fn nodeId(self: *const Self) u64 {
        return self.node_id;
    }

    pub fn pendingAcks(self: *const Self) u32 {
        return self.pending_acks.load(.acquire);
    }
};

pub const WALReceiver = struct {
    allocator: std.mem.Allocator,
    server: std.net.Server,
    wal: *wal_mod.WAL,
    running: std.atomic.Value(bool),
    accept_thread: ?std.Thread,
    bytes_received: std.atomic.Value(u64),
    frames_received: std.atomic.Value(u64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, wal: *wal_mod.WAL, port: u16) !WALReceiver {
        const addr = try std.net.Address.parseIp4("0.0.0.0", port);
        const server = try addr.listen(.{ .reuse_address = true });
        return .{
            .allocator = allocator,
            .server = server,
            .wal = wal,
            .running = std.atomic.Value(bool).init(false),
            .accept_thread = null,
            .bytes_received = std.atomic.Value(u64).init(0),
            .frames_received = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .release);
        self.server.deinit();
        if (self.accept_thread) |t| t.join();
    }

    pub fn start(self: *Self) !void {
        self.running.store(true, .release);
        self.accept_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
    }

    fn acceptLoop(self: *Self) void {
        while (self.running.load(.acquire)) {
            const conn = self.server.accept() catch continue;
            const ctx = self.allocator.create(ConnCtx) catch {
                conn.stream.close();
                continue;
            };
            ctx.* = .{ .receiver = self, .conn = conn };
            const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch {
                conn.stream.close();
                self.allocator.destroy(ctx);
                continue;
            };
            t.detach();
        }
    }

    const ConnCtx = struct {
        receiver: *WALReceiver,
        conn: std.net.Server.Connection,
    };

    fn handleConn(ctx: *ConnCtx) void {
        defer ctx.receiver.allocator.destroy(ctx);
        defer ctx.conn.stream.close();
        ctx.receiver.receiveFrames(ctx.conn.stream) catch {};
    }

    fn receiveFrames(self: *Self, stream: std.net.Stream) !void {
        while (self.running.load(.acquire)) {
            var hdr: FrameHeader = undefined;
            stream.readAll(std.mem.asBytes(&hdr)) catch return;
            hdr.validate() catch return;

            if (hdr.payload_len == 0 or hdr.payload_len > MAX_FRAME_PAYLOAD) return;
            const payload = try self.allocator.alloc(u8, hdr.payload_len);
            defer self.allocator.free(payload);
            try stream.readAll(payload);

            _ = self.bytes_received.fetchAdd(FRAME_HEADER_SIZE + hdr.payload_len, .release);
            _ = self.frames_received.fetchAdd(1, .release);

            if (hdr.payload_len >= @sizeOf(wal_mod.WALRecord)) {
                const record: wal_mod.WALRecord = std.mem.bytesToValue(wal_mod.WALRecord, payload[0..@sizeOf(wal_mod.WALRecord)]);
                applyRemoteRecord(self.wal, &record) catch |err| {
                    std.log.warn("WAL remote record apply failed: {}", .{err});
                };
            }

            var ack: u64 = hdr.lsn;
            _ = stream.writeAll(std.mem.asBytes(&ack)) catch {};
        }
    }

    fn applyRemoteRecord(wal: *wal_mod.WAL, record: *const wal_mod.WALRecord) !void {
        const rec_type = try record.getType();
        var tx = try wal.beginTransaction();
        errdefer wal.endTransaction(&tx) catch {};
        try wal.appendRecord(&tx, rec_type, record.offset, record.size);
        try wal.commitTransaction(&tx);
        try wal.endTransaction(&tx);
    }

    pub fn receiverStats(self: *const Self) ReceiverStats {
        return .{
            .bytes_received = self.bytes_received.load(.acquire),
            .frames_received = self.frames_received.load(.acquire),
        };
    }
};

pub const ReceiverStats = struct {
    bytes_received: u64,
    frames_received: u64,
};

pub fn parseFrameEndpoint(endpoint: []const u8, default_port: u16) struct { host: []const u8, port: u16 } {
    if (std.mem.lastIndexOfScalar(u8, endpoint, ':')) |colon| {
        const port = std.fmt.parseInt(u16, endpoint[colon + 1 ..], 10) catch default_port;
        return .{ .host = endpoint[0..colon], .port = port };
    }
    return .{ .host = endpoint, .port = default_port };
}
