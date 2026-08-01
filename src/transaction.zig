const std = @import("std");
const wal_mod = @import("wal.zig");
const pheap = @import("pheap.zig");
const pointer = @import("pointer.zig");
const header = @import("header.zig");
const mem_utils = @import("mem_utils.zig");
const htm = @import("htm.zig");
const seqlock = @import("seqlock.zig");
const tsc = @import("tsc.zig");
const dhtm_mod = @import("dhtm.zig");
const concurrency = @import("concurrency.zig");

pub const TransactionState = enum(u8) {
    inactive,
    active,
    prepared,
    committed,
    rolled_back,
    failed,
};

pub const TX_FLAG_IN_HTM: u8 = 0x01;
pub const TX_FLAG_READ_VALIDATED: u8 = 0x02;
pub const TX_FLAG_PREFETCHED: u8 = 0x04;
pub const TX_FLAG_STM: u8 = 0x08;

pub const RegisterResidentTxState = extern struct {
    id: u64,
    start_tsc: u64,
    read_hash: u64,
    write_hash: u64,
    state: u8,
    flags: u8,
    htm_retries: u16,
    read_count: u16,
    write_count: u16,
    _pad: [24]u8,

    comptime {
        if (@sizeOf(RegisterResidentTxState) != 64)
            @compileError("RegisterResidentTxState must be exactly 64 bytes (one cache line)");
    }

    pub fn init(id: u64, start: u64) RegisterResidentTxState {
        return .{
            .id = id,
            .start_tsc = start,
            .read_hash = 0,
            .write_hash = 0,
            .state = @intFromEnum(TransactionState.active),
            .flags = 0,
            .htm_retries = 0,
            .read_count = 0,
            .write_count = 0,
            ._pad = [_]u8{0} ** 24,
        };
    }

    pub fn hashOffset(self: *RegisterResidentTxState, offset: u64, is_write: bool) void {
        const mix = offset ^ (offset >> 33) ^ 0xff51afd7ed558ccd;
        if (is_write) {
            self.write_hash ^= mix;
            if (self.write_count < std.math.maxInt(u16)) self.write_count += 1;
        } else {
            self.read_hash ^= mix;
            if (self.read_count < std.math.maxInt(u16)) self.read_count += 1;
        }
    }

    pub fn setFlag(self: *RegisterResidentTxState, flag: u8) void {
        self.flags |= flag;
    }

    pub fn clearFlag(self: *RegisterResidentTxState, flag: u8) void {
        self.flags &= ~flag;
    }

    pub fn hasFlag(self: *const RegisterResidentTxState, flag: u8) bool {
        return (self.flags & flag) != 0;
    }

    pub fn syncState(self: *RegisterResidentTxState, s: TransactionState) void {
        self.state = @intFromEnum(s);
    }
};

pub const OperationType = enum(u8) {
    read,
    write,
    allocate,
    free,
    root_update,
};

pub const ConflictType = enum(u8) {
    write_write,
    write_read,
    read_write,
};

pub const ConflictInfo = struct {
    conflicting_tx_id: u64,
    conflict_type: ConflictType,
    conflicting_offset: u64,
};

pub const RetryConfig = struct {
    max_attempts: u32,
    base_delay_ns: u64,
    max_delay_ns: u64,
    jitter: bool,

    pub fn default() RetryConfig {
        return RetryConfig{
            .max_attempts = 5,
            .base_delay_ns = 1_000_000,
            .max_delay_ns = 100_000_000,
            .jitter = true,
        };
    }
};

pub const Operation = struct {
    op_type: OperationType,
    offset: u64,
    size: u64,
    old_data: ?[]const u8,
    new_data: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator_ptr: std.mem.Allocator, op_type: OperationType, offset: u64, size: u64) Operation {
        return Operation{
            .op_type = op_type,
            .offset = offset,
            .size = size,
            .old_data = null,
            .new_data = null,
            .allocator = allocator_ptr,
        };
    }

    pub fn deinit(self: *Operation) void {
        if (self.old_data) |data| {
            self.allocator.free(data);
        }
        if (self.new_data) |data| {
            self.allocator.free(data);
        }
    }

    pub fn setOldData(self: *Operation, data: []const u8) !void {
        if (self.old_data) |old| {
            self.allocator.free(old);
        }
        self.old_data = try self.allocator.dupe(u8, data);
    }

    pub fn setNewData(self: *Operation, data: []const u8) !void {
        if (self.new_data) |old| {
            self.allocator.free(old);
        }
        self.new_data = try self.allocator.dupe(u8, data);
    }
};

pub const PendingAllocation = struct {
    offset: u64,
    size: u64,
};

pub const STMWriteEntry = struct {
    offset: u64,
    size: u64,
    data: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator_ptr: std.mem.Allocator, offset: u64, data: []const u8) !STMWriteEntry {
        const buf = try allocator_ptr.dupe(u8, data);
        return STMWriteEntry{
            .offset = offset,
            .size = @intCast(data.len),
            .data = buf,
            .allocator = allocator_ptr,
        };
    }

    pub fn deinit(self: *STMWriteEntry) void {
        self.allocator.free(self.data);
    }
};

pub const STMReadEntry = struct {
    offset: u64,
    size: u64,
    observed_version: u64,
};

pub const Transaction = struct {
    id: u64,
    state: TransactionState,
    operations: std.ArrayList(Operation),
    wal_tx: ?wal_mod.Transaction,
    start_time: i64,
    start_tsc: u64,
    allocator: std.mem.Allocator,
    read_set: std.ArrayList(u64),
    write_set: std.ArrayList(u64),
    pending_allocations: std.ArrayList(PendingAllocation),
    parent_tx: ?u64,
    tx_arena: mem_utils.ArenaAllocator,
    reg_state: RegisterResidentTxState,
    seq_lock: seqlock.SeqLock,
    stm_write_log: std.ArrayList(STMWriteEntry),
    stm_read_log: std.ArrayList(STMReadEntry),

    pub fn init(allocator_ptr: std.mem.Allocator, id: u64, wal_tx: wal_mod.Transaction) Transaction {
        const start = tsc.rdtsc();
        return Transaction{
            .id = id,
            .state = .active,
            .operations = undefined,
            .wal_tx = wal_tx,
            .start_time = std.time.milliTimestamp(),
            .start_tsc = start,
            .allocator = undefined,
            .read_set = undefined,
            .write_set = undefined,
            .pending_allocations = undefined,
            .parent_tx = null,
            .tx_arena = mem_utils.ArenaAllocator.init(allocator_ptr, 8192),
            .reg_state = RegisterResidentTxState.init(id, start),
            .seq_lock = seqlock.SeqLock.init(),
            .stm_write_log = undefined,
            .stm_read_log = undefined,
        };
    }

    pub fn deinit(self: *Transaction) void {
        for (self.operations.items) |*op| {
            op.deinit();
        }
        self.operations.deinit();
        self.read_set.deinit();
        self.write_set.deinit();
        self.pending_allocations.deinit();
        if (self.wal_tx) |*wal_tx| {
            wal_tx.deinit();
        }
        for (self.stm_write_log.items) |*wentry| {
            wentry.deinit();
        }
        self.stm_write_log.deinit();
        self.stm_read_log.deinit();
        self.tx_arena.deinit();
    }

    pub fn trackAllocation(self: *Transaction, offset: u64, size: u64) !void {
        try self.pending_allocations.append(.{ .offset = offset, .size = size });
    }

    pub fn addOperation(self: *Transaction, op: Operation) !void {
        try self.operations.append(op);
    }

    pub fn addRead(self: *Transaction, offset: u64) !void {
        self.seq_lock.beginWrite();
        errdefer self.seq_lock.endWrite();
        try self.read_set.append(offset);
        self.reg_state.hashOffset(offset, false);
        self.seq_lock.endWrite();
    }

    pub fn addWrite(self: *Transaction, offset: u64) !void {
        self.seq_lock.beginWrite();
        errdefer self.seq_lock.endWrite();
        try self.write_set.append(offset);
        self.reg_state.hashOffset(offset, true);
        self.seq_lock.endWrite();
    }

    pub fn getOperationCount(self: *const Transaction) usize {
        return self.operations.items.len;
    }

    pub fn hasConflict(self: *const Transaction, other: *const Transaction) bool {
        for (self.write_set.items) |ws| {
            for (other.read_set.items) |rs| {
                if (ws == rs) return true;
            }
            for (other.write_set.items) |ows| {
                if (ws == ows) return true;
            }
        }
        for (self.read_set.items) |rs| {
            for (other.write_set.items) |ws| {
                if (rs == ws) return true;
            }
        }
        return false;
    }

    pub fn stmBufferWrite(self: *Transaction, offset: u64, data: []const u8) !void {
        const entry = try STMWriteEntry.init(self.allocator, offset, data);
        try self.stm_write_log.append(entry);
        try self.addWrite(offset);
    }

    pub fn stmLogRead(self: *Transaction, offset: u64, size: u64, observed_version: u64) !void {
        try self.stm_read_log.append(STMReadEntry{
            .offset = offset,
            .size = size,
            .observed_version = observed_version,
        });
        try self.addRead(offset);
    }
};

pub const STMVersionTable = struct {
    versions: std.AutoHashMap(u64, u64),
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) STMVersionTable {
        return .{
            .versions = std.AutoHashMap(u64, u64).init(allocator),
            .mu = .{},
        };
    }

    pub fn deinit(self: *STMVersionTable) void {
        self.versions.deinit();
    }

    pub fn getVersion(self: *STMVersionTable, offset: u64) u64 {
        self.mu.lock();
        defer self.mu.unlock();
        return self.versions.get(offset) orelse 0;
    }

    pub fn bumpVersion(self: *STMVersionTable, offset: u64) !u64 {
        self.mu.lock();
        defer self.mu.unlock();
        const old = self.versions.get(offset) orelse 0;
        const new_ver = old +% 1;
        try self.versions.put(offset, new_ver);
        return new_ver;
    }

    pub fn validateReads(self: *STMVersionTable, tx: *const Transaction) bool {
        for (tx.stm_read_log.items) |rentry| {
            const current_ver = self.getVersion(rentry.offset);
            if (current_ver != rentry.observed_version) return false;
        }
        return true;
    }
};

pub const TransactionManager = struct {
    wal: *wal_mod.WAL,
    heap: *pheap.PersistentHeap,
    allocator_ref: ?*anyopaque,
    undo_allocation_fn: ?*const fn (ctx: *anyopaque, offset: u64, size: u64) anyerror!void,
    active_transactions: std.AutoHashMap(u64, Transaction),
    transaction_counter: u64,
    lock: std.Thread.RwLock,
    allocator: std.mem.Allocator,
    max_active_transactions: usize,
    htm_fallback: std.Thread.Mutex,
    htm_stats: htm.HTMStats,
    dhtm_runtime: ?*dhtm_mod.DHTMRuntime,
    stm_versions: STMVersionTable,
    stm_global_clock: std.atomic.Value(u64),

    pub fn setAllocatorHook(
        self: *@This(),
        ctx: *anyopaque,
        undo_fn: *const fn (ctx: *anyopaque, offset: u64, size: u64) anyerror!void,
    ) void {
        self.allocator_ref = ctx;
        self.undo_allocation_fn = undo_fn;
    }

    pub fn setDHTMRuntime(self: *@This(), rt: *dhtm_mod.DHTMRuntime) void {
        self.dhtm_runtime = rt;
    }

    const Self = @This();

    pub fn init(allocator_ptr: std.mem.Allocator, wal: *wal_mod.WAL, heap: *pheap.PersistentHeap) !*TransactionManager {
        const self = try allocator_ptr.create(TransactionManager);
        errdefer allocator_ptr.destroy(self);

        self.* = TransactionManager{
            .wal = wal,
            .heap = heap,
            .allocator_ref = null,
            .undo_allocation_fn = null,
            .active_transactions = std.AutoHashMap(u64, Transaction).init(allocator_ptr),
            .transaction_counter = 0,
            .lock = std.Thread.RwLock{},
            .allocator = allocator_ptr,
            .max_active_transactions = 1024,
            .htm_fallback = std.Thread.Mutex{},
            .htm_stats = htm.HTMStats{},
            .dhtm_runtime = null,
            .stm_versions = STMVersionTable.init(allocator_ptr),
            .stm_global_clock = std.atomic.Value(u64).init(1),
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        var iter = self.active_transactions.iterator();
        while (iter.next()) |entry| {
            var tx = entry.value_ptr;
            tx.deinit();
        }
        self.active_transactions.deinit();
        self.stm_versions.deinit();
        self.allocator.destroy(self);
    }

    pub fn begin(self: *Self) !*Transaction {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.active_transactions.count() >= self.max_active_transactions) {
            return error.TooManyActiveTransactions;
        }

        self.transaction_counter += 1;
        const id = self.transaction_counter;

        const wal_tx = try self.wal.beginTransaction();

        const tx = Transaction.init(self.allocator, id, wal_tx);
        try self.active_transactions.put(id, tx);

        const entry = self.active_transactions.getPtr(id).?;
        entry.state = .active;

        const arena_alloc = entry.tx_arena.allocator();
        entry.allocator = arena_alloc;
        entry.operations = std.ArrayList(Operation).init(arena_alloc);
        entry.read_set = std.ArrayList(u64).init(arena_alloc);
        entry.write_set = std.ArrayList(u64).init(arena_alloc);
        entry.pending_allocations = std.ArrayList(PendingAllocation).init(arena_alloc);
        entry.stm_write_log = std.ArrayList(STMWriteEntry).init(arena_alloc);
        entry.stm_read_log = std.ArrayList(STMReadEntry).init(arena_alloc);

        if (tsc.is_simulation) {
            entry.reg_state.setFlag(TX_FLAG_STM);
            _ = entry.reg_state.start_tsc;
            entry.reg_state.start_tsc = self.stm_global_clock.load(.acquire);
        }

        return entry;
    }

    fn checkConflictsLocked(self: *const Self, tx: *const Transaction) ?ConflictInfo {
        var iter = self.active_transactions.iterator();
        while (iter.next()) |entry| {
            const other = entry.value_ptr;
            if (other.id == tx.id) continue;
            if (other.state != .active and other.state != .prepared) continue;

            for (tx.write_set.items) |ws| {
                for (other.write_set.items) |ows| {
                    if (ws == ows) return ConflictInfo{
                        .conflicting_tx_id = other.id,
                        .conflict_type = .write_write,
                        .conflicting_offset = ws,
                    };
                }
                for (other.read_set.items) |rs| {
                    if (ws == rs) return ConflictInfo{
                        .conflicting_tx_id = other.id,
                        .conflict_type = .write_read,
                        .conflicting_offset = ws,
                    };
                }
            }

            for (tx.read_set.items) |rs| {
                for (other.write_set.items) |ws| {
                    if (rs == ws) return ConflictInfo{
                        .conflicting_tx_id = other.id,
                        .conflict_type = .read_write,
                        .conflicting_offset = rs,
                    };
                }
            }
        }
        return null;
    }

    pub fn checkConflicts(self: *Self, tx: *const Transaction) ?ConflictInfo {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.checkConflictsLocked(tx);
    }

    fn stmCommitLocked(self: *Self, tx: *Transaction) !void {
        if (!self.stm_versions.validateReads(tx)) {
            tx.state = .failed;
            tx.reg_state.syncState(.failed);
            if (self.active_transactions.fetchRemove(tx.id)) |entry| {
                var removed_tx = entry.value;
                removed_tx.deinit();
            }
            return error.STMReadValidationFailed;
        }

        if (self.checkConflictsLocked(tx)) |_| {
            tx.state = .failed;
            tx.reg_state.syncState(.failed);
            if (self.active_transactions.fetchRemove(tx.id)) |entry| {
                var removed_tx = entry.value;
                removed_tx.deinit();
            }
            return error.TransactionConflict;
        }

        for (tx.stm_write_log.items) |*wentry| {
            try self.heap.write(wentry.offset, wentry.data);
            _ = try self.stm_versions.bumpVersion(wentry.offset);
        }

        _ = self.stm_global_clock.fetchAdd(1, .acq_rel);

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.commitTransaction(wal_tx);
        }

        tx.state = .committed;
        tx.reg_state.syncState(.committed);

        if (self.active_transactions.fetchRemove(tx.id)) |entry| {
            var removed_tx = entry.value;
            removed_tx.deinit();
        }

        try self.heap.flush();
    }

    pub fn commit(self: *Self, tx: *Transaction) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.state != .active) {
            return error.TransactionNotActive;
        }

        if (tsc.is_simulation and tx.reg_state.hasFlag(TX_FLAG_STM)) {
            return self.stmCommitLocked(tx);
        }

        if (self.checkConflictsLocked(tx)) |_| {
            tx.state = .failed;
            return error.TransactionConflict;
        }

        if (self.dhtm_runtime) |drt| {
            const dhtm_tx = try drt.begin();
            for (tx.write_set.items) |offset| {
                const vr = drt.registerAddress(offset) catch {
                    drt.abort(dhtm_tx);
                    tx.state = .failed;
                    return error.TransactionAborted;
                };
                dhtm_tx.addWrite(offset, 8, drt.local_participant.node_id, vr.version) catch {
                    drt.abort(dhtm_tx);
                    tx.state = .failed;
                    return error.TransactionAborted;
                };
            }
            drt.commit(dhtm_tx) catch |err| {
                tx.state = .failed;
                if (tx.wal_tx) |*wal_tx| {
                    self.wal.rollbackTransaction(wal_tx) catch {};
                }
                return err;
            };
        }

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.commitTransaction(wal_tx);
        }

        tx.state = .committed;

        if (self.active_transactions.fetchRemove(tx.id)) |entry| {
            var removed_tx = entry.value;
            removed_tx.deinit();
        }

        try self.heap.flush();
    }

    pub fn rollback(self: *Self, tx: *Transaction) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.state != .active and tx.state != .failed) {
            return error.TransactionNotActive;
        }

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.rollbackTransaction(wal_tx);
        }

        if (self.undo_allocation_fn) |undo_fn| {
            if (self.allocator_ref) |ctx| {
                for (tx.pending_allocations.items) |pa| {
                    undo_fn(ctx, pa.offset, pa.size) catch {};
                }
            }
        }

        tx.state = .rolled_back;

        if (self.active_transactions.fetchRemove(tx.id)) |entry| {
            var removed_tx = entry.value;
            removed_tx.deinit();
        }
    }

    pub fn prepare(self: *Self, tx: *Transaction) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (tx.state != .active) {
            return error.TransactionNotActive;
        }

        tx.state = .prepared;
    }

    pub fn getActiveTransactionCount(self: *Self) usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.active_transactions.count();
    }

    pub fn getTransaction(self: *Self, id: u64) ?*Transaction {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        return self.active_transactions.getPtr(id);
    }

    pub fn recordRead(self: *Self, tx: *Transaction, offset: u64) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        try tx.addRead(offset);
    }

    pub fn recordWrite(self: *Self, tx: *Transaction, offset: u64, size: u64, old_data: []const u8) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var op = Operation.init(self.allocator, .write, offset, size);
        try op.setOldData(old_data);
        try tx.addOperation(op);
        try tx.addWrite(offset);

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.appendRecordWithData(wal_tx, .write, offset, size, old_data);
        }
    }

    pub fn recordAllocate(self: *Self, tx: *Transaction, offset: u64, size: u64) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        const op = Operation.init(self.allocator, .allocate, offset, size);
        try tx.addOperation(op);

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.appendRecord(wal_tx, .allocate, offset, size);
        }
    }

    pub fn recordFree(self: *Self, tx: *Transaction, offset: u64, size: u64, old_data: []const u8) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var op = Operation.init(self.allocator, .free, offset, size);
        try op.setOldData(old_data);
        try tx.addOperation(op);
        try tx.addWrite(offset);

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.appendRecordWithData(wal_tx, .free, offset, size, old_data);
        }
    }

    pub fn recordRootUpdate(self: *Self, tx: *Transaction, old_root: ?pointer.PersistentPtr, new_root: pointer.PersistentPtr) !void {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        var op = Operation.init(self.allocator, .root_update, new_root.offset, @sizeOf(pointer.PersistentPtr));
        if (old_root) |root| {
            try op.setOldData(std.mem.asBytes(&root));
        }
        try op.setNewData(std.mem.asBytes(&new_root));
        try tx.addOperation(op);

        if (tx.wal_tx) |*wal_tx| {
            try self.wal.appendRecord(wal_tx, .root_update, new_root.offset, @sizeOf(pointer.PersistentPtr));
        }
    }

    pub fn getTransactionCount(self: *Self) u64 {
        return self.transaction_counter;
    }

    pub fn timeoutTransactions(self: *Self, timeout_ms: u64) !usize {
        self.lock.lock();
        defer self.lock.unlock();

        const current_time = std.time.milliTimestamp();
        var timed_out: usize = 0;

        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.active_transactions.iterator();
        while (iter.next()) |entry| {
            const tx = entry.value_ptr;
            const elapsed_ms: u64 = if (current_time > tx.start_time) @intCast(current_time - tx.start_time) else 0;
            if (elapsed_ms > timeout_ms) {
                try to_remove.append(entry.key_ptr.*);
                timed_out += 1;
            }
        }

        for (to_remove.items) |id| {
            if (self.active_transactions.fetchRemove(id)) |entry| {
                var tx = entry.value;
                if (tx.wal_tx) |*wal_tx| {
                    try self.wal.rollbackTransaction(wal_tx);
                }
                tx.deinit();
            }
        }

        return timed_out;
    }

    pub fn retryableCommit(
        self: *Self,
        context: anytype,
        comptime work_fn: fn (ctx: @TypeOf(context), tx: *Transaction) anyerror!void,
        config: RetryConfig,
    ) !void {
        var attempt: u32 = 0;
        while (attempt < config.max_attempts) : (attempt += 1) {
            const tx = try self.begin();

            work_fn(context, tx) catch |work_err| {
                self.rollback(tx) catch {};
                return work_err;
            };

            self.commit(tx) catch |commit_err| {
                if (commit_err == error.TransactionConflict or commit_err == error.STMReadValidationFailed) {
                    self.rollback(tx) catch {};
                    if (attempt + 1 < config.max_attempts) {
                        if (tsc.is_simulation) {
                            concurrency.FiberScheduler.yield();
                        } else {
                            var delay = config.base_delay_ns;
                            var i: u32 = 0;
                            while (i < attempt) : (i += 1) {
                                delay = @min(delay *| 2, config.max_delay_ns);
                            }
                            if (config.jitter) {
                                var prng = std.Random.DefaultPrng.init(@as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())))));
                                const jitter_ns = prng.random().intRangeAtMost(u64, 0, delay / 2);
                                delay = @min(delay +| jitter_ns, config.max_delay_ns);
                            }
                            std.time.sleep(delay);
                        }
                        continue;
                    }
                    return error.MaxRetriesExceeded;
                }
                return commit_err;
            };

            return;
        }
        return error.MaxRetriesExceeded;
    }

    pub fn htmCommitTx(self: *Self, tx: *Transaction) !void {
        if (tx.state != .active) {
            return error.TransactionNotActive;
        }

        if (tsc.is_simulation and tx.reg_state.hasFlag(TX_FLAG_STM)) {
            self.lock.lock();
            defer self.lock.unlock();
            return self.stmCommitLocked(tx);
        }

        var found_conflict: ?ConflictInfo = null;
        var validated_via_htm = false;

        var attempts: u32 = 0;
        const max_htm_attempts: u32 = 6;

        while (attempts < max_htm_attempts) : (attempts += 1) {
            const htm_result = htm.htmBegin();
            switch (htm_result) {
                .success => {
                    found_conflict = self.checkConflictsLocked(tx);
                    htm.htmCommit();
                    validated_via_htm = true;
                    _ = @atomicRmw(u64, &self.htm_stats.htm_commits, .Add, 1, .seq_cst);
                    break;
                },
                .aborted => |code| {
                    _ = @atomicRmw(u64, &self.htm_stats.htm_aborts, .Add, 1, .seq_cst);
                    if (code & htm.HTM_ABORT_CONFLICT != 0) {
                        _ = @atomicRmw(u64, &self.htm_stats.conflict_aborts, .Add, 1, .seq_cst);
                    }
                    if (code & htm.HTM_ABORT_CAPACITY != 0) {
                        _ = @atomicRmw(u64, &self.htm_stats.capacity_aborts, .Add, 1, .seq_cst);
                    }
                    if (!htm.shouldRetry(code, .{})) break;
                    std.atomic.spinLoopHint();
                },
                .not_supported => break,
            }
        }

        if (!validated_via_htm) {
            self.lock.lockShared();
            found_conflict = self.checkConflictsLocked(tx);
            self.lock.unlockShared();
            _ = @atomicRmw(u64, &self.htm_stats.fallback_commits, .Add, 1, .seq_cst);
        }

        if (found_conflict != null) {
            tx.state = .failed;
            tx.reg_state.syncState(.failed);
            return error.TransactionConflict;
        }

        if (self.dhtm_runtime) |drt| {
            const dhtm_tx = try drt.begin();
            for (tx.write_set.items) |offset| {
                const vr = drt.registerAddress(offset) catch {
                    drt.abort(dhtm_tx);
                    tx.state = .failed;
                    tx.reg_state.syncState(.failed);
                    return error.TransactionAborted;
                };
                dhtm_tx.addWrite(offset, 8, drt.local_participant.node_id, vr.version) catch {
                    drt.abort(dhtm_tx);
                    tx.state = .failed;
                    tx.reg_state.syncState(.failed);
                    return error.TransactionAborted;
                };
            }
            drt.commit(dhtm_tx) catch |err| {
                tx.state = .failed;
                tx.reg_state.syncState(.failed);
                return err;
            };
        }

        if (tx.wal_tx) |*wal_tx| {
            self.lock.lock();
            defer self.lock.unlock();
            try self.wal.commitTransaction(wal_tx);
        }

        tx.state = .committed;
        tx.reg_state.syncState(.committed);

        self.lock.lock();
        defer self.lock.unlock();
        if (self.active_transactions.fetchRemove(tx.id)) |entry| {
            var removed_tx = entry.value;
            removed_tx.deinit();
        }
        try self.heap.flush();
    }

    pub fn stmReadVersion(self: *Self, offset: u64) u64 {
        return self.stm_versions.getVersion(offset);
    }
};

test "transaction basic lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_lifecycle.dat";
    const test_wal_path = "/tmp/test_tx_lifecycle.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx = try tx_mgr.begin();
    try tx.addWrite(100);
    try tx.addRead(200);
    try testing.expectEqual(@as(usize, 1), tx_mgr.getActiveTransactionCount());

    try tx_mgr.commit(tx);

    try testing.expectEqual(@as(usize, 0), tx_mgr.getActiveTransactionCount());
}

test "transaction conflict detection" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_conflict.dat";
    const test_wal_path = "/tmp/test_tx_conflict.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx1 = try tx_mgr.begin();
    try tx1.addWrite(200);

    const tx2 = try tx_mgr.begin();
    try tx2.addWrite(200);

    const conflict = tx_mgr.checkConflicts(tx2);
    try testing.expect(conflict != null);
    try testing.expectEqual(tx1.id, conflict.?.conflicting_tx_id);
    try testing.expectEqual(ConflictType.write_write, conflict.?.conflict_type);
    try testing.expectEqual(@as(u64, 200), conflict.?.conflicting_offset);

    try tx_mgr.rollback(tx1);

    const no_conflict = tx_mgr.checkConflicts(tx2);
    try testing.expect(no_conflict == null);

    try tx_mgr.rollback(tx2);
}

test "transaction read-write conflict detection" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_rw_conflict.dat";
    const test_wal_path = "/tmp/test_tx_rw_conflict.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx1 = try tx_mgr.begin();
    try tx1.addRead(300);

    const tx2 = try tx_mgr.begin();
    try tx2.addWrite(300);

    const conflict = tx_mgr.checkConflicts(tx2);
    try testing.expect(conflict != null);
    try testing.expectEqual(tx1.id, conflict.?.conflicting_tx_id);
    try testing.expectEqual(ConflictType.write_read, conflict.?.conflict_type);
    try testing.expectEqual(@as(u64, 300), conflict.?.conflicting_offset);

    try tx_mgr.rollback(tx1);
    try tx_mgr.rollback(tx2);
}

test "commit blocked by conflict returns error" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_commit_conflict.dat";
    const test_wal_path = "/tmp/test_tx_commit_conflict.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx1 = try tx_mgr.begin();
    try tx1.addWrite(400);

    const tx2 = try tx_mgr.begin();
    try tx2.addWrite(400);

    const result = tx_mgr.commit(tx2);
    try testing.expectError(error.TransactionConflict, result);
    try testing.expectEqual(TransactionState.failed, tx2.state);

    try tx_mgr.rollback(tx1);
    try tx_mgr.rollback(tx2);
}

test "retryable commit succeeds on first attempt" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_retry_ok.dat";
    const test_wal_path = "/tmp/test_tx_retry_ok.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const Ctx = struct { offset: u64 };
    const work = struct {
        fn do(ctx: Ctx, tx: *Transaction) anyerror!void {
            try tx.addWrite(ctx.offset);
        }
    }.do;

    const config = RetryConfig{
        .max_attempts = 3,
        .base_delay_ns = 1,
        .max_delay_ns = 1,
        .jitter = false,
    };

    try tx_mgr.retryableCommit(Ctx{ .offset = 500 }, work, config);
    try testing.expectEqual(@as(usize, 0), tx_mgr.getActiveTransactionCount());
}

test "retryable commit returns MaxRetriesExceeded when permanently blocked" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_heap_path = "/tmp/test_tx_retry_exhaust.dat";
    const test_wal_path = "/tmp/test_tx_retry_exhaust.wal";
    std.fs.cwd().deleteFile(test_heap_path) catch {};
    std.fs.cwd().deleteFile(test_wal_path) catch {};

    var heap = try pheap.PersistentHeap.init(alloc, test_heap_path, 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, test_wal_path, null);
    defer wal.deinit();

    var tx_mgr = try TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx1 = try tx_mgr.begin();
    try tx1.addWrite(600);

    const Ctx = struct {};
    const work = struct {
        fn do(ctx: Ctx, tx: *Transaction) anyerror!void {
            _ = ctx;
            try tx.addWrite(600);
        }
    }.do;

    const config = RetryConfig{
        .max_attempts = 2,
        .base_delay_ns = 1,
        .max_delay_ns = 1,
        .jitter = false,
    };

    const result = tx_mgr.retryableCommit(Ctx{}, work, config);
    try testing.expectError(error.MaxRetriesExceeded, result);

    try tx_mgr.rollback(tx1);
    try testing.expectEqual(@as(usize, 0), tx_mgr.getActiveTransactionCount());
}

test "stm version table tracks writes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var vt = STMVersionTable.init(alloc);
    defer vt.deinit();

    try testing.expectEqual(@as(u64, 0), vt.getVersion(1000));
    _ = try vt.bumpVersion(1000);
    try testing.expectEqual(@as(u64, 1), vt.getVersion(1000));
    _ = try vt.bumpVersion(1000);
    try testing.expectEqual(@as(u64, 2), vt.getVersion(1000));
}
