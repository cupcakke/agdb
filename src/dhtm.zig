const std = @import("std");
const htm = @import("htm.zig");
const simd = @import("simd.zig");
const tsc = @import("tsc.zig");

pub const DHTM_MAX_NODES: usize = 64;
pub const DHTM_MAX_WRITE_SET: usize = 256;
pub const DHTM_MAX_READ_SET: usize = 1024;
pub const DHTM_COORD_TIMEOUT_NS: u64 = 10 * std.time.ns_per_s;
pub const DHTM_PREPARE_TIMEOUT_NS: u64 = 2 * std.time.ns_per_s;
pub const DHTM_MAX_RETRY_HTM: u32 = 8;
pub const DHTM_FALLBACK_LOCK_SPIN: u32 = 1024;
pub const DHTM_VERSION_MAGIC: u32 = 0x44_48_54_4D;

pub const DHTMNodeId = u32;
pub const DHTMTransactionId = u64;
pub const INVALID_NODE: DHTMNodeId = 0xFFFF_FFFF;
pub const INVALID_TX: DHTMTransactionId = 0;

pub const DHTMPhase = enum(u8) {
    idle,
    local_htm,
    prepare_sent,
    all_prepared,
    commit_sent,
    committed,
    abort_sent,
    aborted,
    fallback_lock,
};

pub const DHTMAbortReason = enum(u8) {
    none,
    htm_capacity,
    htm_conflict,
    htm_explicit,
    remote_conflict,
    coordinator_timeout,
    participant_timeout,
    validation_failure,
    write_set_overflow,
    network_error,
    unknown,
};

pub const DHTMParticipantState = enum(u8) {
    idle,
    preparing,
    prepared,
    committing,
    committed,
    aborting,
    aborted,
    failed,
};

pub const DHTMVersionRecord = extern struct {
    magic: u32,
    node_id: DHTMNodeId,
    tx_id: DHTMTransactionId,
    version: u64,
    lock_flag: std.atomic.Value(u32) align(4),
    _pad: [4]u8,

    pub fn init(node_id: DHTMNodeId) DHTMVersionRecord {
        return .{
            .magic = DHTM_VERSION_MAGIC,
            .node_id = node_id,
            .tx_id = INVALID_TX,
            .version = 0,
            .lock_flag = std.atomic.Value(u32).init(0),
            ._pad = [_]u8{0} ** 4,
        };
    }

    pub fn tryLock(self: *DHTMVersionRecord, tx_id: DHTMTransactionId) bool {
        const result = self.lock_flag.cmpxchgStrong(0, 1, .acq_rel, .acquire);
        if (result == null) {
            self.tx_id = tx_id;
            return true;
        }
        return false;
    }

    pub fn unlock(self: *DHTMVersionRecord) void {
        self.tx_id = INVALID_TX;
        self.lock_flag.store(0, .release);
    }

    pub fn isLocked(self: *const DHTMVersionRecord) bool {
        return self.lock_flag.load(.acquire) != 0;
    }

    pub fn bump(self: *DHTMVersionRecord) u64 {
        self.version += 1;
        return self.version;
    }
};

pub const DHTMWriteEntry = struct {
    address: u64,
    size: u32,
    node_id: DHTMNodeId,
    old_version: u64,
};

pub const DHTMReadEntry = struct {
    address: u64,
    version_at_read: u64,
    node_id: DHTMNodeId,
};

pub const DHTMTransaction = struct {
    tx_id: DHTMTransactionId,
    coordinator_node: DHTMNodeId,
    originating_node: DHTMNodeId,
    phase: std.atomic.Value(u8),
    abort_reason: DHTMAbortReason,
    write_set: [DHTM_MAX_WRITE_SET]DHTMWriteEntry,
    write_set_count: u32,
    read_set: [DHTM_MAX_READ_SET]DHTMReadEntry,
    read_set_count: u32,
    htm_retries: u32,
    start_tsc: u64,
    commit_tsc: u64,
    participants: [DHTM_MAX_NODES]DHTMNodeId,
    participant_count: u32,
    prepared_count: std.atomic.Value(u32),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(tx_id: DHTMTransactionId, coord: DHTMNodeId, origin: DHTMNodeId) DHTMTransaction {
        var tx = std.mem.zeroes(DHTMTransaction);
        tx.tx_id = tx_id;
        tx.coordinator_node = coord;
        tx.originating_node = origin;
        tx.phase = std.atomic.Value(u8).init(@intFromEnum(DHTMPhase.idle));
        tx.abort_reason = .none;
        tx.start_tsc = tsc.rdtsc();
        tx.prepared_count = std.atomic.Value(u32).init(0);
        return tx;
    }

    pub fn getPhase(self: *const Self) DHTMPhase {
        return @enumFromInt(self.phase.load(.acquire));
    }

    pub fn setPhase(self: *Self, p: DHTMPhase) void {
        self.phase.store(@intFromEnum(p), .release);
    }

    pub fn addWrite(self: *Self, addr: u64, size: u32, node_id: DHTMNodeId, old_version: u64) !void {
        if (self.write_set_count >= DHTM_MAX_WRITE_SET) return error.WriteSetOverflow;
        self.write_set[self.write_set_count] = .{
            .address = addr,
            .size = size,
            .node_id = node_id,
            .old_version = old_version,
        };
        self.write_set_count += 1;
    }

    pub fn addRead(self: *Self, addr: u64, version: u64, node_id: DHTMNodeId) !void {
        if (self.read_set_count >= DHTM_MAX_READ_SET) return error.ReadSetOverflow;
        self.read_set[self.read_set_count] = .{
            .address = addr,
            .version_at_read = version,
            .node_id = node_id,
        };
        self.read_set_count += 1;
    }

    pub fn addParticipant(self: *Self, node_id: DHTMNodeId) !void {
        if (self.participant_count >= DHTM_MAX_NODES) return error.TooManyParticipants;
        for (self.participants[0..self.participant_count]) |p| {
            if (p == node_id) return;
        }
        self.participants[self.participant_count] = node_id;
        self.participant_count += 1;
    }

    pub fn checkConflictSIMD(self: *const Self, other: *const DHTMTransaction) bool {
        if (self.write_set_count == 0 or other.write_set_count == 0) return false;
        var self_addrs: [DHTM_MAX_WRITE_SET]u64 = undefined;
        var other_addrs: [DHTM_MAX_WRITE_SET]u64 = undefined;
        for (self.write_set[0..self.write_set_count], 0..) |e, i| {
            self_addrs[i] = e.address;
        }
        for (other.write_set[0..other.write_set_count], 0..) |e, i| {
            other_addrs[i] = e.address;
        }
        const result = simd.simdConflictScan(
            self_addrs[0..self.write_set_count],
            other_addrs[0..other.write_set_count],
        );
        return result.conflict_found;
    }

    pub fn readWriteConflict(self: *const Self, other: *const DHTMTransaction) bool {
        if (self.write_set_count == 0 or other.read_set_count == 0) return false;
        var write_addrs: [DHTM_MAX_WRITE_SET]u64 = undefined;
        var read_addrs: [DHTM_MAX_READ_SET]u64 = undefined;
        for (self.write_set[0..self.write_set_count], 0..) |e, i| {
            write_addrs[i] = e.address;
        }
        for (other.read_set[0..other.read_set_count], 0..) |e, i| {
            read_addrs[i] = e.address;
        }
        const result = simd.simdConflictScan(
            write_addrs[0..self.write_set_count],
            read_addrs[0..other.read_set_count],
        );
        return result.conflict_found;
    }

    pub fn elapsedNs(self: *const Self) u64 {
        return tsc.rdtsc() -% self.start_tsc;
    }
};

pub const PrepareMsg = extern struct {
    tx_id: DHTMTransactionId,
    coordinator: DHTMNodeId,
    write_count: u32,
    timestamp_tsc: u64,
    checksum: u32,
    _pad: [4]u8,
};

pub const PrepareAck = extern struct {
    tx_id: DHTMTransactionId,
    participant: DHTMNodeId,
    success: u8,
    abort_reason: u8,
    _pad: [2]u8,
    prepared_version: u64,
};

pub const CommitMsg = extern struct {
    tx_id: DHTMTransactionId,
    coordinator: DHTMNodeId,
    commit: u8,
    _pad: [3]u8,
    commit_tsc: u64,
};

pub const DHTMParticipant = struct {
    node_id: DHTMNodeId,
    version_records: std.AutoHashMap(u64, *DHTMVersionRecord),
    active_txs: std.AutoHashMap(DHTMTransactionId, *DHTMTransaction),
    committed_count: std.atomic.Value(u64),
    aborted_count: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, node_id: DHTMNodeId) !DHTMParticipant {
        return .{
            .node_id = node_id,
            .version_records = std.AutoHashMap(u64, *DHTMVersionRecord).init(allocator),
            .active_txs = std.AutoHashMap(DHTMTransactionId, *DHTMTransaction).init(allocator),
            .committed_count = std.atomic.Value(u64).init(0),
            .aborted_count = std.atomic.Value(u64).init(0),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        var vr_it = self.version_records.valueIterator();
        while (vr_it.next()) |vr| {
            self.allocator.destroy(vr.*);
        }
        self.version_records.deinit();
        var tx_it = self.active_txs.valueIterator();
        while (tx_it.next()) |tx| {
            self.allocator.destroy(tx.*);
        }
        self.active_txs.deinit();
        self.mutex.unlock();
    }

    pub fn registerAddress(self: *Self, addr: u64) !*DHTMVersionRecord {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.version_records.get(addr)) |vr| return vr;
        const vr = try self.allocator.create(DHTMVersionRecord);
        vr.* = DHTMVersionRecord.init(self.node_id);
        try self.version_records.put(addr, vr);
        return vr;
    }

    pub fn prepare(self: *Self, tx: *DHTMTransaction) !PrepareAck {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (tx.write_set[0..tx.write_set_count]) |entry| {
            if (entry.node_id != self.node_id) continue;
            const vr = self.version_records.get(entry.address) orelse {
                return PrepareAck{
                    .tx_id = tx.tx_id,
                    .participant = self.node_id,
                    .success = 0,
                    .abort_reason = @intFromEnum(DHTMAbortReason.validation_failure),
                    ._pad = [_]u8{0} ** 2,
                    .prepared_version = 0,
                };
            };
            if (vr.version != entry.old_version) {
                return PrepareAck{
                    .tx_id = tx.tx_id,
                    .participant = self.node_id,
                    .success = 0,
                    .abort_reason = @intFromEnum(DHTMAbortReason.remote_conflict),
                    ._pad = [_]u8{0} ** 2,
                    .prepared_version = vr.version,
                };
            }
        }

        for (tx.write_set[0..tx.write_set_count]) |entry| {
            if (entry.node_id != self.node_id) continue;
            if (self.version_records.get(entry.address)) |vr| {
                if (!vr.tryLock(tx.tx_id)) {
                    return PrepareAck{
                        .tx_id = tx.tx_id,
                        .participant = self.node_id,
                        .success = 0,
                        .abort_reason = @intFromEnum(DHTMAbortReason.remote_conflict),
                        ._pad = [_]u8{0} ** 2,
                        .prepared_version = 0,
                    };
                }
            }
        }

        try self.active_txs.put(tx.tx_id, tx);
        tx.setPhase(.all_prepared);
        return PrepareAck{
            .tx_id = tx.tx_id,
            .participant = self.node_id,
            .success = 1,
            .abort_reason = @intFromEnum(DHTMAbortReason.none),
            ._pad = [_]u8{0} ** 2,
            .prepared_version = 0,
        };
    }

    pub fn commit(self: *Self, tx_id: DHTMTransactionId) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const tx = self.active_txs.fetchRemove(tx_id) orelse return;
        for (tx.value.write_set[0..tx.value.write_set_count]) |entry| {
            if (entry.node_id != self.node_id) continue;
            if (self.version_records.get(entry.address)) |vr| {
                _ = vr.bump();
                vr.unlock();
            }
        }
        _ = self.committed_count.fetchAdd(1, .acq_rel);
    }

    pub fn abort(self: *Self, tx_id: DHTMTransactionId) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const tx = self.active_txs.fetchRemove(tx_id) orelse return;
        for (tx.value.write_set[0..tx.value.write_set_count]) |entry| {
            if (entry.node_id != self.node_id) continue;
            if (self.version_records.get(entry.address)) |vr| {
                if (vr.tx_id == tx_id) vr.unlock();
            }
        }
        _ = self.aborted_count.fetchAdd(1, .acq_rel);
    }

    pub fn participantStats(self: *const Self) ParticipantStats {
        return .{
            .node_id = self.node_id,
            .committed = self.committed_count.load(.acquire),
            .aborted = self.aborted_count.load(.acquire),
            .active_txs = self.active_txs.count(),
            .tracked_addresses = self.version_records.count(),
        };
    }
};

pub const ParticipantStats = struct {
    node_id: DHTMNodeId,
    committed: u64,
    aborted: u64,
    active_txs: usize,
    tracked_addresses: usize,
};

pub const DHTMCoordinatorConfig = struct {
    node_id: DHTMNodeId,
    prepare_timeout_ns: u64 = DHTM_PREPARE_TIMEOUT_NS,
    coord_timeout_ns: u64 = DHTM_COORD_TIMEOUT_NS,
    max_htm_retries: u32 = DHTM_MAX_RETRY_HTM,
    use_htm_fast_path: bool = true,
};

pub const DHTMCoordinator = struct {
    config: DHTMCoordinatorConfig,
    participants: [DHTM_MAX_NODES]?*DHTMParticipant,
    participant_count: u32,
    tx_counter: std.atomic.Value(u64),
    active_txs: std.AutoHashMap(DHTMTransactionId, *DHTMTransaction),
    committed_total: std.atomic.Value(u64),
    aborted_total: std.atomic.Value(u64),
    htm_committed: std.atomic.Value(u64),
    htm_aborted: std.atomic.Value(u64),
    fallback_committed: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: DHTMCoordinatorConfig) !*DHTMCoordinator {
        const self = try allocator.create(DHTMCoordinator);
        self.* = DHTMCoordinator{
            .config = config,
            .participants = [_]?*DHTMParticipant{null} ** DHTM_MAX_NODES,
            .participant_count = 0,
            .tx_counter = std.atomic.Value(u64).init(1),
            .active_txs = std.AutoHashMap(DHTMTransactionId, *DHTMTransaction).init(allocator),
            .committed_total = std.atomic.Value(u64).init(0),
            .aborted_total = std.atomic.Value(u64).init(0),
            .htm_committed = std.atomic.Value(u64).init(0),
            .htm_aborted = std.atomic.Value(u64).init(0),
            .fallback_committed = std.atomic.Value(u64).init(0),
            .mutex = .{},
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        var it = self.active_txs.valueIterator();
        while (it.next()) |tx| {
            self.allocator.destroy(tx.*);
        }
        self.active_txs.deinit();
        self.mutex.unlock();
        self.allocator.destroy(self);
    }

    pub fn addParticipant(self: *Self, participant: *DHTMParticipant) !void {
        if (self.participant_count >= DHTM_MAX_NODES) return error.TooManyParticipants;
        self.participants[self.participant_count] = participant;
        self.participant_count += 1;
    }

    pub fn begin(self: *Self) !*DHTMTransaction {
        const tx_id = self.tx_counter.fetchAdd(1, .acq_rel);
        const tx = try self.allocator.create(DHTMTransaction);
        tx.* = DHTMTransaction.init(tx_id, self.config.node_id, self.config.node_id);
        self.mutex.lock();
        try self.active_txs.put(tx_id, tx);
        self.mutex.unlock();
        return tx;
    }

    pub fn executeHTM(self: *Self, tx: *DHTMTransaction, body: anytype) !bool {
        if (!htm.has_rtm or !self.config.use_htm_fast_path) return false;

        var retries: u32 = 0;
        while (retries < self.config.max_htm_retries) : (retries += 1) {
            const status = htm.xbegin();
            if (status == htm.HTM_STARTED) {
                body.execute(tx) catch {
                    htm.xabort(1);
                };
                htm.xend();
                tx.commit_tsc = tsc.rdtsc();
                tx.setPhase(.committed);
                _ = self.htm_committed.fetchAdd(1, .acq_rel);
                return true;
            }
            const abort_bits = status & 0xFF;
            if (abort_bits & htm.HTM_ABORT_RETRY != 0) {
                std.atomic.spinLoopHint();
                continue;
            }
            if (abort_bits & htm.HTM_ABORT_CAPACITY != 0) {
                tx.abort_reason = .htm_capacity;
                _ = self.htm_aborted.fetchAdd(1, .acq_rel);
                return false;
            }
            tx.abort_reason = .htm_conflict;
            _ = self.htm_aborted.fetchAdd(1, .acq_rel);
            return false;
        }
        tx.abort_reason = .htm_conflict;
        _ = self.htm_aborted.fetchAdd(1, .acq_rel);
        return false;
    }

    pub fn twoPhaseCommit(self: *Self, tx: *DHTMTransaction) !void {
        tx.setPhase(.prepare_sent);

        var all_prepared = true;
        for (self.participants[0..self.participant_count]) |maybe_p| {
            const p = maybe_p orelse continue;
            var found = false;
            for (tx.participants[0..tx.participant_count]) |pid| {
                if (pid == p.node_id) {
                    found = true;
                    break;
                }
            }
            if (!found) continue;

            const ack = try p.prepare(tx);
            if (ack.success == 0) {
                all_prepared = false;
                tx.abort_reason = @enumFromInt(ack.abort_reason);
                break;
            }
        }

        if (!all_prepared) {
            tx.setPhase(.abort_sent);
            self.broadcastAbort(tx);
            tx.setPhase(.aborted);
            _ = self.aborted_total.fetchAdd(1, .acq_rel);
            return error.TransactionAborted;
        }

        tx.setPhase(.commit_sent);
        self.broadcastCommit(tx);
        tx.commit_tsc = tsc.rdtsc();
        tx.setPhase(.committed);
        _ = self.committed_total.fetchAdd(1, .acq_rel);
        _ = self.fallback_committed.fetchAdd(1, .acq_rel);
    }

    fn broadcastCommit(self: *Self, tx: *DHTMTransaction) void {
        for (self.participants[0..self.participant_count]) |maybe_p| {
            const p = maybe_p orelse continue;
            p.commit(tx.tx_id);
        }
    }

    fn broadcastAbort(self: *Self, tx: *DHTMTransaction) void {
        for (self.participants[0..self.participant_count]) |maybe_p| {
            const p = maybe_p orelse continue;
            p.abort(tx.tx_id);
        }
    }

    pub fn finalize(self: *Self, tx: *DHTMTransaction) void {
        self.mutex.lock();
        _ = self.active_txs.remove(tx.tx_id);
        self.mutex.unlock();
        self.allocator.destroy(tx);
    }

    pub fn coordinatorStats(self: *const Self) CoordinatorStats {
        return .{
            .node_id = self.config.node_id,
            .committed_total = self.committed_total.load(.acquire),
            .aborted_total = self.aborted_total.load(.acquire),
            .htm_committed = self.htm_committed.load(.acquire),
            .htm_aborted = self.htm_aborted.load(.acquire),
            .fallback_committed = self.fallback_committed.load(.acquire),
            .active_tx_count = self.active_txs.count(),
            .participant_count = self.participant_count,
        };
    }
};

pub const CoordinatorStats = struct {
    node_id: DHTMNodeId,
    committed_total: u64,
    aborted_total: u64,
    htm_committed: u64,
    htm_aborted: u64,
    fallback_committed: u64,
    active_tx_count: usize,
    participant_count: u32,
};

pub const DHTMRuntime = struct {
    coordinator: *DHTMCoordinator,
    local_participant: *DHTMParticipant,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, node_id: DHTMNodeId) !DHTMRuntime {
        const coord_cfg = DHTMCoordinatorConfig{ .node_id = node_id };
        const coord = try DHTMCoordinator.init(allocator, coord_cfg);
        errdefer coord.deinit();
        const participant = try allocator.create(DHTMParticipant);
        errdefer allocator.destroy(participant);
        participant.* = try DHTMParticipant.init(allocator, node_id);
        errdefer participant.deinit();
        try coord.addParticipant(participant);
        return .{
            .coordinator = coord,
            .local_participant = participant,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.local_participant.deinit();
        self.allocator.destroy(self.local_participant);
        self.coordinator.deinit();
    }

    pub fn registerAddress(self: *Self, addr: u64) !*DHTMVersionRecord {
        return self.local_participant.registerAddress(addr);
    }

    pub fn begin(self: *Self) !*DHTMTransaction {
        const tx = try self.coordinator.begin();
        try tx.addParticipant(self.local_participant.node_id);
        return tx;
    }

    pub fn commit(self: *Self, tx: *DHTMTransaction) !void {
        try self.coordinator.twoPhaseCommit(tx);
        self.coordinator.finalize(tx);
    }

    pub fn abort(self: *Self, tx: *DHTMTransaction) void {
        self.coordinator.broadcastAbort(tx);
        tx.setPhase(.aborted);
        _ = self.coordinator.aborted_total.fetchAdd(1, .acq_rel);
        self.coordinator.finalize(tx);
    }

    pub fn runtimeStats(self: *const Self) DHTMRuntimeStats {
        return .{
            .coordinator = self.coordinator.coordinatorStats(),
            .participant = self.local_participant.participantStats(),
        };
    }
};

pub const DHTMRuntimeStats = struct {
    coordinator: CoordinatorStats,
    participant: ParticipantStats,
};

test "dhtm transaction write set and conflict" {
    const a = std.testing.allocator;
    var rt = try DHTMRuntime.init(a, 1);
    defer rt.deinit();

    const tx1 = try rt.begin();
    try tx1.addWrite(0x1000, 8, 1, 0);
    try tx1.addWrite(0x2000, 8, 1, 0);

    const tx2 = try rt.begin();
    try tx2.addWrite(0x1000, 8, 1, 0);
    try tx2.addWrite(0x3000, 8, 1, 0);

    try std.testing.expect(tx1.checkConflictSIMD(tx2));

    rt.abort(tx1);
    rt.abort(tx2);
}

test "dhtm version record locking" {
    var vr = DHTMVersionRecord.init(1);
    try std.testing.expect(vr.tryLock(42));
    try std.testing.expect(!vr.tryLock(43));
    try std.testing.expect(vr.isLocked());
    vr.unlock();
    try std.testing.expect(!vr.isLocked());
    try std.testing.expect(vr.tryLock(99));
    vr.unlock();
}

test "dhtm two phase commit" {
    const a = std.testing.allocator;
    var rt = try DHTMRuntime.init(a, 1);
    defer rt.deinit();

    const addr: u64 = 0xDEAD_0000;
    const vr = try rt.registerAddress(addr);
    try std.testing.expectEqual(@as(u64, 0), vr.version);

    const tx = try rt.begin();
    try tx.addWrite(addr, 8, 1, 0);
    try rt.commit(tx);

    const stats = rt.runtimeStats();
    try std.testing.expectEqual(@as(u64, 1), stats.coordinator.committed_total);
    try std.testing.expectEqual(@as(u64, 1), vr.version);
}
