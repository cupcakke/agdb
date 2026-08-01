const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");
const header = @import("header.zig");
const pointer = @import("pointer.zig");
const security = @import("security.zig");
const mem_utils = @import("mem_utils.zig");
const iouring = @import("iouring.zig");
const tsc = @import("tsc.zig");

pub const WAL_MAGIC: u32 = 0x57414C46;
pub const WAL_VERSION: u32 = 1;
pub const WAL_BLOCK_SIZE: u64 = 4096;
pub const MAX_RECORDS_PER_TRANSACTION: usize = 1024;

const INITIAL_WAL_SIZE: u64 = 1024 * 1024 * 64;
const RECORD_FLAG_HAS_UNDO: u8 = 1;
const RECORD_FLAG_UNDO_COMPRESSED: u8 = 2;
const ASYNC_QUEUE_CAPACITY: usize = 256;

const CRC32C_TABLE: [256]u32 = blk: {
    @setEvalBranchQuota(4096);
    const POLY: u32 = 0x82F63B78;
    var table: [256]u32 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var c: u32 = @as(u32, @intCast(i));
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            c = if ((c & 1) != 0) (c >> 1) ^ POLY else c >> 1;
        }
        table[i] = c;
    }
    break :blk table;
};

pub const RecordType = enum(u8) {
    begin = 1,
    commit = 2,
    rollback = 3,
    allocate = 4,
    free = 5,
    write = 6,
    free_list_add = 7,
    free_list_remove = 8,
    heap_extend = 9,
    root_update = 10,
    ref_count_inc = 11,
    ref_count_dec = 12,
    gc_mark = 13,
    gc_sweep = 14,
    checkpoint = 15,
};

pub const WALHeader = extern struct {
    magic: u32,
    version: u32,
    file_size: u64,
    last_checkpoint: u64,
    transaction_counter: u64,
    head_offset: u64,
    tail_offset: u64,
    checksum: u32,
    reserved: [28]u8,

    pub fn init(file_size: u64) WALHeader {
        return WALHeader{
            .magic = WAL_MAGIC,
            .version = WAL_VERSION,
            .file_size = file_size,
            .last_checkpoint = 0,
            .transaction_counter = 0,
            .head_offset = headerSize(),
            .tail_offset = headerSize(),
            .checksum = 0,
            .reserved = [_]u8{0} ** 28,
        };
    }

    pub fn validate(self: *const WALHeader, actual_file_size: u64) !void {
        if (self.magic != WAL_MAGIC) return error.InvalidWALMagic;
        if (self.version != WAL_VERSION) return error.UnsupportedWALVersion;
        if (self.file_size != actual_file_size) return error.InvalidWALFileSize;
        if (self.file_size < headerSize()) return error.InvalidWALFileSize;
        if (self.head_offset < headerSize()) return error.InvalidWALHeadOffset;
        if (self.tail_offset < headerSize()) return error.InvalidWALTailOffset;
        if (self.head_offset > self.tail_offset) return error.InvalidWALHeadOffset;
        if (self.tail_offset > self.file_size) return error.InvalidWALTailOffset;
        if (self.last_checkpoint > self.head_offset) return error.InvalidWALCheckpoint;
        if (self.last_checkpoint > self.tail_offset) return error.InvalidWALCheckpoint;
        if ((self.head_offset - headerSize()) % recordAlignment() != 0) return error.InvalidWALHeadOffset;
        if (self.computeChecksum() != self.checksum) return error.HeaderChecksumMismatch;
    }

    pub fn computeChecksum(self: *const WALHeader) u32 {
        const bytes = std.mem.asBytes(self);
        const checksum_offset = @offsetOf(WALHeader, "checksum");
        var crc: u32 = 0xFFFFFFFF;
        for (bytes[0..checksum_offset]) |byte| {
            crc = crc32cByte(crc, byte);
        }
        for (bytes[checksum_offset + @sizeOf(u32) ..]) |byte| {
            crc = crc32cByte(crc, byte);
        }
        return crc ^ 0xFFFFFFFF;
    }

    pub fn updateChecksum(self: *WALHeader) void {
        self.checksum = 0;
        self.checksum = self.computeChecksum();
    }
};

pub const WALRecord = extern struct {
    record_type: u8,
    flags: u8,
    padding: [6]u8,
    transaction_id: u64,
    sequence: u64,
    offset: u64,
    size: u64,
    old_value_offset: u64,
    old_value_size: u64,
    data_checksum: u32,
    record_checksum: u32,

    pub fn init(
        record_type: RecordType,
        tx_id: u64,
        seq: u64,
        offset: u64,
        size: u64,
    ) WALRecord {
        return WALRecord{
            .record_type = @intFromEnum(record_type),
            .flags = 0,
            .padding = [_]u8{0} ** 6,
            .transaction_id = tx_id,
            .sequence = seq,
            .offset = offset,
            .size = size,
            .old_value_offset = 0,
            .old_value_size = 0,
            .data_checksum = 0,
            .record_checksum = 0,
        };
    }

    pub fn getType(self: *const WALRecord) !RecordType {
        return std.meta.intToEnum(RecordType, self.record_type) catch error.InvalidRecordType;
    }

    pub fn hasUndoData(self: *const WALRecord) bool {
        return (self.flags & RECORD_FLAG_HAS_UNDO) != 0;
    }

    pub fn isUndoCompressed(self: *const WALRecord) bool {
        return (self.flags & RECORD_FLAG_UNDO_COMPRESSED) != 0;
    }

    pub fn setUndoData(self: *WALRecord, old_value_offset: u64, data: []const u8) void {
        self.flags |= RECORD_FLAG_HAS_UNDO;
        self.old_value_offset = old_value_offset;
        self.old_value_size = @as(u64, @intCast(data.len));
        self.data_checksum = computeDataChecksum(data);
    }

    pub fn clearUndoData(self: *WALRecord) void {
        self.flags &= ~@as(u8, RECORD_FLAG_HAS_UNDO | RECORD_FLAG_UNDO_COMPRESSED);
        self.old_value_offset = 0;
        self.old_value_size = 0;
        self.data_checksum = 0;
    }

    pub fn computeChecksum(self: *const WALRecord) u32 {
        const bytes = std.mem.asBytes(self);
        const checksum_offset = @offsetOf(WALRecord, "record_checksum");
        var crc: u32 = 0xFFFFFFFF;
        for (bytes[0..checksum_offset]) |byte| {
            crc = crc32cByte(crc, byte);
        }
        return crc ^ 0xFFFFFFFF;
    }

    pub fn updateChecksum(self: *WALRecord) void {
        self.record_checksum = 0;
        self.record_checksum = self.computeChecksum();
    }

    pub fn validate(self: *const WALRecord) !void {
        _ = try self.getType();
        const known_flags: u8 = RECORD_FLAG_HAS_UNDO | RECORD_FLAG_UNDO_COMPRESSED;
        if ((self.flags & ~known_flags) != 0) return error.InvalidRecordFlags;
        if (!std.mem.eql(u8, self.padding[0..], &[_]u8{ 0, 0, 0, 0, 0, 0 })) return error.InvalidRecordPadding;
        if (!self.hasUndoData()) {
            if (self.old_value_offset != 0) return error.InvalidUndoOffset;
            if (self.old_value_size != 0) return error.InvalidUndoSize;
            if (self.data_checksum != 0) return error.UnexpectedChecksumField;
        }
        if (self.computeChecksum() != self.record_checksum) return error.RecordChecksumMismatch;
    }

    pub fn validateWithoutChecksumForPending(self: *const WALRecord) !void {
        _ = try self.getType();
        const known_flags: u8 = RECORD_FLAG_HAS_UNDO | RECORD_FLAG_UNDO_COMPRESSED;
        if ((self.flags & ~known_flags) != 0) return error.InvalidRecordFlags;
        if (!std.mem.eql(u8, self.padding[0..], &[_]u8{ 0, 0, 0, 0, 0, 0 })) return error.InvalidRecordPadding;
    }
};

pub const Transaction = struct {
    id: u64,
    state: State,
    records: std.ArrayList(WALRecord),
    undo_data: std.ArrayList([]u8),
    start_offset: u64,
    allocator: std.mem.Allocator,
    deinitialized: bool,

    pub const State = enum(u8) {
        active,
        committed,
        rolled_back,
        prepared,
    };

    pub fn init(allocator_ptr: std.mem.Allocator, id: u64) Transaction {
        return Transaction{
            .id = id,
            .state = .active,
            .records = std.ArrayList(WALRecord).init(allocator_ptr),
            .undo_data = std.ArrayList([]u8).init(allocator_ptr),
            .start_offset = 0,
            .allocator = allocator_ptr,
            .deinitialized = false,
        };
    }

    pub fn deinit(self: *Transaction) void {
        if (self.deinitialized) return;
        for (self.undo_data.items) |data| {
            self.allocator.free(data);
        }
        self.undo_data.deinit();
        self.records.deinit();
        self.deinitialized = true;
    }

    pub fn addRecord(self: *Transaction, record: WALRecord) !void {
        if (self.deinitialized) return error.TransactionDeinitialized;
        if (self.records.items.len >= MAX_RECORDS_PER_TRANSACTION) return error.TooManyRecords;
        try self.records.append(record);
    }

    pub fn addUndoData(self: *Transaction, data: []const u8) !void {
        if (self.deinitialized) return error.TransactionDeinitialized;
        const copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(copy);
        try self.undo_data.append(copy);
    }

    pub fn addRecordWithUndoData(self: *Transaction, record: WALRecord, data: []const u8) !void {
        if (self.deinitialized) return error.TransactionDeinitialized;
        if (self.records.items.len >= MAX_RECORDS_PER_TRANSACTION) return error.TooManyRecords;
        const copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(copy);
        try self.undo_data.append(copy);
        errdefer {
            const idx = self.undo_data.items.len - 1;
            self.allocator.free(self.undo_data.items[idx]);
            _ = self.undo_data.pop();
        }
        try self.records.append(record);
    }

    pub fn getRecordCount(self: *const Transaction) usize {
        if (self.deinitialized) return 0;
        return self.records.items.len;
    }
};

pub const AsyncEntry = struct {
    wal_tx: Transaction,
    completed: std.atomic.Value(bool),
    result: anyerror!void,

    pub fn init(allocator: std.mem.Allocator, id: u64) AsyncEntry {
        return .{
            .wal_tx = Transaction.init(allocator, id),
            .completed = std.atomic.Value(bool).init(false),
            .result = {},
        };
    }

    pub fn deinit(self: *AsyncEntry, allocator: std.mem.Allocator) void {
        self.wal_tx.deinit();
        allocator.destroy(self);
    }
};

pub const AppendHookFn = *const fn (ctx: *anyopaque, record: *const WALRecord) void;

pub const WalFaultKind = enum(u8) {
    none,
    torn_write,
    power_off_mid_write,
    corrupt_record,
};

pub const WalFaultSpec = struct {
    kind: WalFaultKind = .none,
    trigger_tx_id: u64 = 0,
    trigger_record_idx: usize = 0,
    partial_records: usize = 0,
    armed: bool = false,
};

pub const SimWalBackend = struct {
    buf: []u8,
    capacity: u64,
    allocator: std.mem.Allocator,
    fault: WalFaultSpec,

    pub fn init(allocator: std.mem.Allocator, initial_size: u64) !SimWalBackend {
        const aligned = std.mem.alignForward(u64, initial_size, 4096);
        const buf = try allocator.alloc(u8, @intCast(aligned));
        @memset(buf, 0);
        return SimWalBackend{
            .buf = buf,
            .capacity = aligned,
            .allocator = allocator,
            .fault = .{},
        };
    }

    pub fn deinit(self: *SimWalBackend) void {
        self.allocator.free(self.buf);
    }

    pub fn armFault(self: *SimWalBackend, spec: WalFaultSpec) void {
        self.fault = spec;
        self.fault.armed = true;
    }

    pub fn disarmFault(self: *SimWalBackend) void {
        self.fault.armed = false;
        self.fault.kind = .none;
    }

    pub fn writeAt(self: *SimWalBackend, offset: u64, data: []const u8) !void {
        const end = offset + @as(u64, @intCast(data.len));
        if (end > self.capacity) return error.WalCapacityExceeded;
        if (self.fault.armed) {
            const kind = self.fault.kind;
            self.fault.armed = false;
            self.fault.kind = .none;
            switch (kind) {
                .power_off_mid_write => return error.SimulatedPowerOff,
                .torn_write => {
                    const half = data.len / 2;
                    if (half > 0) {
                        @memcpy(self.buf[@intCast(offset)..@intCast(offset + @as(u64, @intCast(half)))], data[0..half]);
                    }
                    return error.SimulatedTornWrite;
                },
                .corrupt_record => {
                    @memcpy(self.buf[@intCast(offset)..@intCast(end)], data);
                    self.buf[@intCast(offset)] ^= 0xFF;
                    return;
                },
                .none => {},
            }
        }
        @memcpy(self.buf[@intCast(offset)..@intCast(end)], data);
    }

    pub fn readAt(self: *const SimWalBackend, offset: u64, buf: []u8) !void {
        if (offset + @as(u64, @intCast(buf.len)) > self.capacity) return error.OutOfBounds;
        @memcpy(buf, self.buf[@intCast(offset)..@intCast(offset + @as(u64, @intCast(buf.len)))]);
    }

    pub fn grow(self: *SimWalBackend, new_size: u64) !void {
        if (new_size <= self.capacity) return;
        const aligned = std.mem.alignForward(u64, new_size, 4096);
        const new_buf = try self.allocator.realloc(self.buf, @intCast(aligned));
        const old_cap = self.capacity;
        @memset(new_buf[@intCast(old_cap)..], 0);
        self.buf = new_buf;
        self.capacity = aligned;
    }

    pub fn sync(self: *SimWalBackend) !void {
        _ = self;
    }

    pub fn fsync(self: *SimWalBackend) !void {
        _ = self;
    }
};

pub const WalVfsKind = enum { prod, sim };

pub const WalVfsHandle = struct {
    kind: WalVfsKind,
    prod_mapping: []align(4096) u8,
    prod_mapped_size: u64,
    prod_file: std.fs.File,
    sim: ?*SimWalBackend,

    pub fn basePtr(self: *WalVfsHandle) [*]u8 {
        switch (self.kind) {
            .prod => return self.prod_mapping.ptr,
            .sim => return self.sim.?.buf.ptr,
        }
    }

    pub fn currentMappedSize(self: *const WalVfsHandle) u64 {
        switch (self.kind) {
            .prod => return self.prod_mapped_size,
            .sim => return self.sim.?.capacity,
        }
    }

    pub fn writeAt(self: *WalVfsHandle, offset: u64, data: []const u8) !void {
        switch (self.kind) {
            .prod => {
                const start: usize = @intCast(offset);
                const end: usize = @intCast(offset + @as(u64, @intCast(data.len)));
                if (end > self.prod_mapping.len) return error.WritePastMapping;
                @memcpy(self.prod_mapping[start..end], data);
            },
            .sim => try self.sim.?.writeAt(offset, data),
        }
    }

    pub fn readAt(self: *const WalVfsHandle, offset: u64, buf: []u8) !void {
        switch (self.kind) {
            .prod => {
                const start: usize = @intCast(offset);
                const end: usize = @intCast(offset + @as(u64, @intCast(buf.len)));
                if (end > self.prod_mapping.len) return error.ReadPastMapping;
                @memcpy(buf, self.prod_mapping[start..end]);
            },
            .sim => try self.sim.?.readAt(offset, buf),
        }
    }

    pub fn syncRange(self: *WalVfsHandle, slice: []align(4096) u8) !void {
        switch (self.kind) {
            .prod => try posix.msync(slice, posix.MSF.SYNC),
            .sim => try self.sim.?.sync(),
        }
    }

    pub fn syncAll(self: *WalVfsHandle) !void {
        switch (self.kind) {
            .prod => {
                try posix.msync(self.prod_mapping, posix.MSF.SYNC);
                try posix.fsync(self.prod_file.handle);
            },
            .sim => {
                try self.sim.?.sync();
                try self.sim.?.fsync();
            },
        }
    }

    pub fn grow(self: *WalVfsHandle, new_size: u64) !void {
        switch (self.kind) {
            .prod => {
                try posix.msync(self.prod_mapping, posix.MSF.SYNC);
                try self.prod_file.setEndPos(new_size);
                const new_len: usize = @intCast(new_size);
                const new_map = try posix.mmap(
                    null,
                    new_len,
                    posix.PROT.READ | posix.PROT.WRITE,
                    .{ .TYPE = .SHARED },
                    self.prod_file.handle,
                    0,
                );
                posix.munmap(self.prod_mapping);
                self.prod_mapping = new_map;
                self.prod_mapped_size = new_size;
            },
            .sim => try self.sim.?.grow(new_size),
        }
    }
};

pub const WAL = struct {
    vfs: WalVfsHandle,
    file_path: []const u8,
    header: *WALHeader,
    security: ?*security.SecurityManager,
    allocator: std.mem.Allocator,
    lock: std.Thread.Mutex,
    sequence_counter: u64,
    async_queue: mem_utils.LockFreeQueue,
    writer_thread: ?std.Thread,
    shutdown_flag: std.atomic.Value(bool),
    writer_started: std.atomic.Value(bool),
    writer_cond: std.Thread.Condition,
    writer_mutex: std.Thread.Mutex,
    append_hook: ?AppendHookFn,
    append_hook_ctx: ?*anyopaque,

    const Self = @This();

    pub fn init(
        allocator_ptr: std.mem.Allocator,
        file_path: []const u8,
        security_mgr: ?*security.SecurityManager,
    ) !*WAL {
        const self = try allocator_ptr.create(WAL);
        errdefer allocator_ptr.destroy(self);

        const path_copy = try allocator_ptr.dupe(u8, file_path);
        errdefer allocator_ptr.free(path_copy);

        var async_queue = try mem_utils.LockFreeQueue.init(allocator_ptr, ASYNC_QUEUE_CAPACITY);
        errdefer async_queue.deinit();

        if (tsc.is_simulation) {
            const sim_backend = try allocator_ptr.create(SimWalBackend);
            errdefer allocator_ptr.destroy(sim_backend);
            sim_backend.* = try SimWalBackend.init(allocator_ptr, INITIAL_WAL_SIZE);
            errdefer sim_backend.deinit();

            const vfs = WalVfsHandle{
                .kind = .sim,
                .prod_mapping = &[_]u8{},
                .prod_mapped_size = 0,
                .prod_file = undefined,
                .sim = sim_backend,
            };

            self.* = WAL{
                .vfs = vfs,
                .file_path = path_copy,
                .header = @ptrCast(@alignCast(sim_backend.buf.ptr)),
                .security = security_mgr,
                .allocator = allocator_ptr,
                .lock = std.Thread.Mutex{},
                .sequence_counter = 0,
                .async_queue = async_queue,
                .writer_thread = null,
                .shutdown_flag = std.atomic.Value(bool).init(false),
                .writer_started = std.atomic.Value(bool).init(false),
                .writer_cond = std.Thread.Condition{},
                .writer_mutex = std.Thread.Mutex{},
                .append_hook = null,
                .append_hook_ctx = null,
            };

            self.header.* = WALHeader.init(INITIAL_WAL_SIZE);
            self.header.file_size = INITIAL_WAL_SIZE;
            try self.flushHeader();

            return self;
        }

        const file = std.fs.cwd().openFile(file_path, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(file_path, .{ .read = true, .truncate = false, .exclusive = false }),
            else => return err,
        };
        errdefer file.close();

        const stat = try file.stat();
        const file_size: u64 = if (stat.size == 0) INITIAL_WAL_SIZE else stat.size;
        if (file_size < headerSize()) return error.InvalidWALFileSize;

        if (stat.size == 0) {
            try file.setEndPos(file_size);
        }

        const map_len = try toUsize(file_size);
        const mapping = try posix.mmap(
            null,
            map_len,
            posix.PROT.READ | posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );
        errdefer posix.munmap(mapping);

        const header_ptr: *WALHeader = @ptrCast(@alignCast(mapping.ptr));

        const vfs = WalVfsHandle{
            .kind = .prod,
            .prod_mapping = mapping,
            .prod_mapped_size = file_size,
            .prod_file = file,
            .sim = null,
        };

        self.* = WAL{
            .vfs = vfs,
            .file_path = path_copy,
            .header = header_ptr,
            .security = security_mgr,
            .allocator = allocator_ptr,
            .lock = std.Thread.Mutex{},
            .sequence_counter = 0,
            .async_queue = async_queue,
            .writer_thread = null,
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .writer_started = std.atomic.Value(bool).init(false),
            .writer_cond = std.Thread.Condition{},
            .writer_mutex = std.Thread.Mutex{},
            .append_hook = null,
            .append_hook_ctx = null,
        };

        if (stat.size == 0) {
            self.header.* = WALHeader.init(file_size);
            try self.flushHeader();
        } else {
            try self.header.validate(file_size);
            self.sequence_counter = try self.recoverSequenceCounter();
        }

        return self;
    }

    pub fn deinit(self: *WAL) void {
        self.shutdown_flag.store(true, .release);

        self.writer_mutex.lock();
        self.writer_cond.broadcast();
        self.writer_mutex.unlock();

        if (self.writer_thread) |thread| {
            thread.join();
            self.writer_thread = null;
        }

        self.flushAsyncQueue() catch {};
        self.async_queue.deinit();

        self.flush() catch {};

        switch (self.vfs.kind) {
            .prod => {
                posix.munmap(self.vfs.prod_mapping);
                self.vfs.prod_file.close();
            },
            .sim => {
                if (self.vfs.sim) |sim| {
                    sim.deinit();
                    self.allocator.destroy(sim);
                }
            },
        }

        self.allocator.free(self.file_path);
        self.allocator.destroy(self);
    }

    pub fn getSimBackend(self: *WAL) ?*SimWalBackend {
        if (self.vfs.kind == .sim) return self.vfs.sim;
        return null;
    }

    fn ensureWriterRunning(self: *WAL) !void {
        if (self.writer_started.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            self.writer_thread = try std.Thread.spawn(.{}, writerThreadFn, .{self});
        }
    }

    fn writerThreadFn(self: *WAL) void {
        while (true) {
            self.writer_mutex.lock();
            while (!self.shutdown_flag.load(.acquire) and self.async_queue.isEmpty()) {
                self.writer_cond.wait(&self.writer_mutex);
            }
            self.writer_mutex.unlock();

            if (self.shutdown_flag.load(.acquire)) break;
            _ = self.drainAsyncQueueOnce() catch {};
        }
        _ = self.drainAsyncQueueOnce() catch {};
    }

    fn drainAsyncQueueOnce(self: *WAL) !bool {
        var batch = std.ArrayList(*AsyncEntry).init(self.allocator);
        defer batch.deinit();

        while (self.async_queue.dequeue()) |raw| {
            const entry: *AsyncEntry = @ptrCast(@alignCast(raw));
            try batch.append(entry);
        }
        if (batch.items.len == 0) return false;

        self.lock.lock();
        for (batch.items) |entry| {
            const write_result = self.writeTransactionRecordsLocked(&entry.wal_tx);
            if (write_result) |_| {
                entry.wal_tx.state = .committed;
            } else |err| {
                entry.result = err;
            }
        }
        self.lock.unlock();

        self.sync() catch {};

        for (batch.items) |entry| {
            entry.completed.store(true, .release);
        }
        return true;
    }

    pub fn setAppendHook(self: *Self, hook: AppendHookFn, ctx: *anyopaque) void {
        self.append_hook = hook;
        self.append_hook_ctx = ctx;
    }

    pub fn clearAppendHook(self: *Self) void {
        self.append_hook = null;
        self.append_hook_ctx = null;
    }

    pub fn flushAsyncQueue(self: *WAL) !void {
        _ = try self.drainAsyncQueueOnce();
    }

    pub fn enqueueAsyncTransaction(self: *WAL, tx: *Transaction) !*AsyncEntry {
        if (tx.deinitialized) return error.TransactionDeinitialized;
        if (tx.state != .active) return error.TransactionNotActive;

        var commit_record = WALRecord.init(.commit, tx.id, self.getNextSequenceLocked(), 0, 0);
        commit_record.updateChecksum();
        try tx.addRecord(commit_record);
        errdefer _ = tx.records.pop();

        const entry = try self.allocator.create(AsyncEntry);
        errdefer self.allocator.destroy(entry);

        entry.wal_tx = tx.*;
        entry.completed = std.atomic.Value(bool).init(false);
        entry.result = {};

        tx.records = std.ArrayList(WALRecord).init(tx.allocator);
        tx.undo_data = std.ArrayList([]u8).init(tx.allocator);
        tx.deinitialized = true;

        if (!self.async_queue.enqueue(@as(*anyopaque, @ptrCast(entry)))) {
            entry.wal_tx.deinit();
            self.allocator.destroy(entry);
            tx.deinitialized = false;
            _ = tx.records.pop();
            return error.AsyncQueueFull;
        }

        try self.ensureWriterRunning();

        self.writer_mutex.lock();
        self.writer_cond.signal();
        self.writer_mutex.unlock();

        return entry;
    }

    pub fn waitAsync(self: *WAL, entry: *AsyncEntry) !void {
        while (!entry.completed.load(.acquire)) {
            std.Thread.yield() catch std.atomic.spinLoopHint();
        }
        const r = entry.result;
        entry.wal_tx.deinit();
        self.allocator.destroy(entry);
        return r;
    }

    pub fn beginTransaction(self: *Self) !Transaction {
        self.lock.lock();
        defer self.lock.unlock();

        const next_id = try checkedAdd(self.header.transaction_counter, 1);
        var tx = Transaction.init(self.allocator, next_id);
        errdefer tx.deinit();

        tx.start_offset = self.header.tail_offset;
        var begin_record = WALRecord.init(.begin, tx.id, self.getNextSequenceLocked(), 0, 0);
        begin_record.updateChecksum();
        try tx.addRecord(begin_record);

        self.header.transaction_counter = next_id;
        try self.flushHeader();

        return tx;
    }

    pub fn endTransaction(self: *Self, tx: *Transaction) !void {
        if (!tx.deinitialized and tx.state == .active) {
            self.rollbackTransaction(tx) catch |err| {
                tx.deinit();
                return err;
            };
        }
        tx.deinit();
    }

    pub fn appendRecord(self: *Self, tx: *Transaction, record_type: RecordType, offset: u64, size: u64) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.deinitialized) return error.TransactionDeinitialized;
        if (tx.state != .active) return error.TransactionNotActive;
        _ = try checkedAdd(offset, size);

        var record = WALRecord.init(record_type, tx.id, self.getNextSequenceLocked(), offset, size);
        record.updateChecksum();
        try tx.addRecord(record);
    }

    pub fn appendRecordWithData(self: *Self, tx: *Transaction, record_type: RecordType, offset: u64, size: u64, old_data: []const u8) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.deinitialized) return error.TransactionDeinitialized;
        if (tx.state != .active) return error.TransactionNotActive;
        _ = try checkedAdd(offset, size);
        if (old_data.len == 0) return error.EmptyUndoData;
        if (old_data.len != size) return error.UndoSizeMismatch;

        var record = WALRecord.init(record_type, tx.id, self.getNextSequenceLocked(), offset, size);
        record.flags |= RECORD_FLAG_HAS_UNDO;

        const compressed = try mem_utils.compressMemory(old_data, self.allocator);
        defer self.allocator.free(compressed);

        const use_compression = compressed.len + 8 < old_data.len;

        if (use_compression) {
            var stored_buf = try self.allocator.alloc(u8, 8 + compressed.len);
            defer self.allocator.free(stored_buf);
            std.mem.writeInt(u64, stored_buf[0..8], @as(u64, @intCast(old_data.len)), .little);
            @memcpy(stored_buf[8..], compressed);
            record.flags |= RECORD_FLAG_UNDO_COMPRESSED;
            record.old_value_size = @as(u64, @intCast(stored_buf.len));
            record.data_checksum = computeDataChecksum(stored_buf);
            record.updateChecksum();
            try tx.addRecordWithUndoData(record, stored_buf);
        } else {
            record.old_value_size = @as(u64, @intCast(old_data.len));
            record.data_checksum = computeDataChecksum(old_data);
            record.updateChecksum();
            try tx.addRecordWithUndoData(record, old_data);
        }
    }

    pub fn commitTransaction(self: *Self, tx: *Transaction) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.deinitialized) return error.TransactionDeinitialized;
        if (tx.state != .active and tx.state != .prepared) return error.TransactionNotActive;

        var commit_record = WALRecord.init(.commit, tx.id, self.getNextSequenceLocked(), 0, 0);
        commit_record.updateChecksum();
        try tx.addRecord(commit_record);
        errdefer _ = tx.records.pop();

        try self.writeTransactionRecordsLocked(tx);
        try self.sync();
        tx.state = .committed;
    }

    pub fn rollbackTransaction(self: *Self, tx: *Transaction) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (tx.deinitialized) return error.TransactionDeinitialized;
        if (tx.state == .committed) return error.TransactionAlreadyCommitted;
        if (tx.state == .rolled_back) return;

        var rollback_record = WALRecord.init(.rollback, tx.id, self.getNextSequenceLocked(), 0, 0);
        rollback_record.updateChecksum();
        try tx.addRecord(rollback_record);
        errdefer _ = tx.records.pop();

        try self.writeTransactionRecordsLocked(tx);
        try self.sync();
        tx.state = .rolled_back;
    }

    fn writeTransactionRecordsLocked(self: *Self, tx: *Transaction) !void {
        if (tx.records.items.len == 0) return error.EmptyTransaction;

        const start_offset = self.header.tail_offset;
        var total_size: u64 = 0;
        var undo_count: usize = 0;

        for (tx.records.items) |record| {
            try record.validateWithoutChecksumForPending();
            total_size = try checkedAdd(total_size, recordSize());
            if (record.hasUndoData()) {
                if (undo_count >= tx.undo_data.items.len) return error.UndoDataCountMismatch;
                total_size = try checkedAdd(total_size, @as(u64, @intCast(tx.undo_data.items[undo_count].len)));
                undo_count += 1;
            }
        }

        if (undo_count != tx.undo_data.items.len) return error.UndoDataCountMismatch;

        const end_off = try checkedAdd(start_offset, total_size);
        try self.ensureMappedCapacity(end_off);

        const buffer_len = try toUsize(total_size);
        var buffer = try self.allocator.alloc(u8, buffer_len);
        defer self.allocator.free(buffer);
        @memset(buffer, 0);

        var rel: usize = 0;
        var undo_index: usize = 0;
        var wal_cur: u64 = start_offset;

        for (tx.records.items, 0..) |*record_slot, idx| {
            var record = record_slot.*;

            if (record.hasUndoData()) {
                const data = tx.undo_data.items[undo_index];
                const data_off = try checkedAdd(wal_cur, recordSize());
                record.setUndoData(data_off, data);
                if (record_slot.isUndoCompressed()) record.flags |= RECORD_FLAG_UNDO_COMPRESSED;
                undo_index += 1;
            } else {
                record.clearUndoData();
            }
            try validateRecordSemantics(&record, idx == 0);
            record.updateChecksum();
            const rb = std.mem.asBytes(&record);
            @memcpy(buffer[rel .. rel + rb.len], rb);
            rel += rb.len;
            wal_cur = try checkedAdd(wal_cur, recordSize());
            if (record.hasUndoData()) {
                const data = tx.undo_data.items[undo_index - 1];
                @memcpy(buffer[rel .. rel + data.len], data);
                rel += data.len;
                wal_cur = try checkedAdd(wal_cur, @as(u64, @intCast(data.len)));
            }
            record_slot.* = record;

            if (self.append_hook) |hook| {
                if (self.append_hook_ctx) |ctx| {
                    hook(ctx, record_slot);
                }
            }
        }

        switch (self.vfs.kind) {
            .prod => {
                const start_u = try toUsize(start_offset);
                @memcpy(self.vfs.prod_mapping[start_u .. start_u + rel], buffer[0..rel]);
            },
            .sim => {
                try self.vfs.sim.?.writeAt(start_offset, buffer[0..rel]);
            },
        }

        self.header.tail_offset = end_off;
        self.header.file_size = self.vfs.currentMappedSize();
        try self.flushHeader();
    }

    pub fn checkpoint(self: *Self) !void {
        self.lock.lock();
        defer self.lock.unlock();

        var cp_record = WALRecord.init(.checkpoint, 0, self.getNextSequenceLocked(), self.header.tail_offset, 0);
        cp_record.updateChecksum();

        const cp_end = try checkedAdd(self.header.tail_offset, recordSize());
        try self.ensureMappedCapacity(cp_end);

        const rb = std.mem.asBytes(&cp_record);
        const start_u = try toUsize(self.header.tail_offset);
        switch (self.vfs.kind) {
            .prod => @memcpy(self.vfs.prod_mapping[start_u .. start_u + rb.len], rb),
            .sim => try self.vfs.sim.?.writeAt(self.header.tail_offset, rb),
        }

        self.header.tail_offset = cp_end;
        self.header.head_offset = cp_end;
        self.header.last_checkpoint = cp_end;
        self.header.file_size = self.vfs.currentMappedSize();
        try self.flushHeader();
    }

    pub fn truncate(self: *Self, new_offset: u64) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if (new_offset < headerSize()) return error.InvalidTruncateOffset;
        if (new_offset > self.header.tail_offset) return error.InvalidTruncateOffset;

        if (new_offset != self.header.tail_offset) {
            var offset = headerSize();
            while (offset < new_offset) {
                const parsed = try self.readRecordAtLocked(offset);
                offset = parsed.next_offset;
            }
            if (offset != new_offset) return error.InvalidTruncateOffset;
        }

        self.header.head_offset = new_offset;
        if (self.header.last_checkpoint < new_offset) {
            self.header.last_checkpoint = new_offset;
        }
        try self.flushHeader();
    }

    pub fn flush(self: *Self) !void {
        self.lock.lock();
        defer self.lock.unlock();
        switch (self.vfs.kind) {
            .prod => try posix.msync(self.vfs.prod_mapping, posix.MSF.SYNC),
            .sim => try self.vfs.sim.?.sync(),
        }
    }

    fn flushHeader(self: *Self) !void {
        self.header.updateChecksum();
        switch (self.vfs.kind) {
            .prod => {
                const hs = try toUsize(headerSize());
                try posix.msync(self.vfs.prod_mapping[0..hs], posix.MSF.SYNC);
            },
            .sim => try self.vfs.sim.?.sync(),
        }
    }

    pub fn sync(self: *Self) !void {
        switch (self.vfs.kind) {
            .prod => {
                try posix.msync(self.vfs.prod_mapping, posix.MSF.SYNC);
                try posix.fsync(self.vfs.prod_file.handle);
            },
            .sim => {
                try self.vfs.sim.?.sync();
                try self.vfs.sim.?.fsync();
            },
        }
    }

    pub fn getSize(self: *Self) u64 {
        self.lock.lock();
        defer self.lock.unlock();
        return self.header.tail_offset;
    }

    pub fn getTransactionCount(self: *Self) u64 {
        self.lock.lock();
        defer self.lock.unlock();
        return self.header.transaction_counter;
    }

    pub fn getLastCheckpoint(self: *Self) u64 {
        self.lock.lock();
        defer self.lock.unlock();
        return self.header.last_checkpoint;
    }

    fn getNextSequenceLocked(self: *Self) u64 {
        const ov = @addWithOverflow(self.sequence_counter, 1);
        if (ov[1] != 0) {
            self.sequence_counter = 1;
        } else {
            self.sequence_counter = ov[0];
        }
        return self.sequence_counter;
    }

    fn recoverSequenceCounter(self: *Self) !u64 {
        var max_sequence: u64 = 0;
        var offset = self.header.head_offset;

        while (offset < self.header.tail_offset) {
            const parsed = self.readRecordAtLocked(offset) catch break;
            if (parsed.record.sequence > max_sequence) {
                max_sequence = parsed.record.sequence;
            }
            offset = parsed.next_offset;
        }

        return max_sequence;
    }

    fn ensureMappedCapacity(self: *Self, required_size: u64) !void {
        if (required_size <= self.vfs.currentMappedSize()) return;

        var new_size = self.vfs.currentMappedSize();
        while (new_size < required_size) {
            if (new_size > std.math.maxInt(u64) / 2) return error.WALFileTooLarge;
            new_size *= 2;
        }

        try self.vfs.grow(new_size);

        self.header = @ptrCast(@alignCast(self.vfs.basePtr()));
        self.header.file_size = new_size;
        self.header.updateChecksum();
        try self.flushHeader();
    }

    const ParsedRecord = struct {
        record: WALRecord,
        next_offset: u64,
    };

    fn readRecordAtLocked(self: *Self, offset: u64) !ParsedRecord {
        if (offset < headerSize()) return error.InvalidRecordOffset;
        const record_end = try checkedAdd(offset, recordSize());
        if (record_end > self.header.tail_offset) return error.TruncatedRecord;

        const start = try toUsize(offset);
        const end = try toUsize(record_end);
        var record: WALRecord = undefined;
        const base = self.vfs.basePtr();
        @memcpy(std.mem.asBytes(&record), base[start..end]);

        try record.validate();
        try validateRecordSemantics(&record, false);

        var next_offset = record_end;
        if (record.hasUndoData()) {
            if (record.old_value_offset != record_end) return error.InvalidUndoOffset;
            const undo_end = try checkedAdd(record.old_value_offset, record.old_value_size);
            if (undo_end > self.header.tail_offset) return error.InvalidUndoOffset;
            const undo_start = try toUsize(record.old_value_offset);
            const undo_end_u = try toUsize(undo_end);
            const undo_data = base[undo_start..undo_end_u];
            if (computeDataChecksum(undo_data) != record.data_checksum) return error.DataChecksumMismatch;
            next_offset = undo_end;
        }

        return ParsedRecord{
            .record = record,
            .next_offset = next_offset,
        };
    }

    pub fn getUndoData(self: *Self, record: *const WALRecord) ![]u8 {
        self.lock.lock();
        defer self.lock.unlock();
        return self.getUndoDataOwnedLocked(record);
    }

    fn getUndoDataOwnedLocked(self: *Self, record: *const WALRecord) ![]u8 {
        if (!record.hasUndoData()) return &[_]u8{};
        if (record.old_value_size == 0) return error.InvalidUndoSize;
        if (record.old_value_offset < headerSize()) return error.InvalidUndoOffset;

        const data_start = record.old_value_offset;
        const data_end = try checkedAdd(data_start, record.old_value_size);

        if (data_end > self.header.tail_offset) return error.InvalidUndoOffset;
        if (data_end > self.vfs.currentMappedSize()) return error.InvalidUndoOffset;

        const start_u = try toUsize(data_start);
        const end_u = try toUsize(data_end);
        const base = self.vfs.basePtr();
        const stored = base[start_u..end_u];
        if (computeDataChecksum(stored) != record.data_checksum) return error.DataChecksumMismatch;

        if (record.isUndoCompressed()) {
            if (stored.len < 8) return error.InvalidUndoSize;
            const uncompressed_size = std.mem.readInt(u64, stored[0..8], .little);
            const compressed_payload = stored[8..];
            const decompressed = try mem_utils.decompressMemory(compressed_payload, self.allocator);
            if (@as(u64, @intCast(decompressed.len)) != uncompressed_size) {
                self.allocator.free(decompressed);
                return error.UndoSizeMismatch;
            }
            return decompressed;
        }

        return try self.allocator.dupe(u8, stored);
    }

    pub fn getRedoData(self: *Self, record: *const WALRecord) ![]const u8 {
        _ = self;
        _ = record;
        return error.RedoDataNotStored;
    }

    pub fn getUndoRootOffset(self: *Self, record: *const WALRecord) !u64 {
        const undo_bytes = try self.getUndoData(record);
        defer if (undo_bytes.len > 0) self.allocator.free(undo_bytes);
        if (undo_bytes.len < 8) return error.InvalidUndoData;
        return std.mem.readInt(u64, undo_bytes[0..8], .little);
    }

    pub fn getTransactionLsn(self: *Self, tx: *const Transaction) !u64 {
        _ = self;
        if (tx.start_offset == 0) return error.InvalidTransactionOffset;
        return tx.start_offset;
    }

    pub fn getRecords(self: *Self, from_offset: u64, max_records: usize) !std.ArrayList(WALRecord) {
        self.lock.lock();
        defer self.lock.unlock();

        var result = std.ArrayList(WALRecord).init(self.allocator);
        errdefer result.deinit();

        var offset = from_offset;
        var count: usize = 0;

        while (offset < self.header.tail_offset and count < max_records) {
            const parsed = try self.readRecordAtLocked(offset);
            try result.append(parsed.record);
            offset = parsed.next_offset;
            count += 1;
        }

        return result;
    }

    pub fn getTransactions(self: *Self) !std.ArrayList(Transaction) {
        self.lock.lock();
        defer self.lock.unlock();

        var tx_map = std.AutoHashMap(u64, usize).init(self.allocator);
        defer tx_map.deinit();

        var result = std.ArrayList(Transaction).init(self.allocator);
        errdefer {
            for (result.items) |*tx| tx.deinit();
            result.deinit();
        }

        var offset = headerSize();
        while (offset < self.header.tail_offset) {
            const parsed = try self.readRecordAtLocked(offset);
            const rec = parsed.record;
            const rt = try rec.getType();

            switch (rt) {
                .begin => {
                    const idx = result.items.len;
                    var tx = Transaction.init(self.allocator, rec.transaction_id);
                    tx.start_offset = offset;
                    try tx.records.append(rec);
                    try result.append(tx);
                    try tx_map.put(rec.transaction_id, idx);
                },
                .commit => {
                    if (tx_map.get(rec.transaction_id)) |idx| {
                        try result.items[idx].records.append(rec);
                        result.items[idx].state = .committed;
                    }
                },
                .rollback => {
                    if (tx_map.get(rec.transaction_id)) |idx| {
                        try result.items[idx].records.append(rec);
                        result.items[idx].state = .rolled_back;
                    }
                },
                else => {
                    if (tx_map.get(rec.transaction_id)) |idx| {
                        try result.items[idx].records.append(rec);
                    }
                },
            }

            offset = parsed.next_offset;
        }

        return result;
    }
};

fn validateRecordSemantics(record: *const WALRecord, must_be_begin: bool) !void {
    const record_type = try record.getType();

    if (must_be_begin and record_type != .begin) return error.TransactionMustStartWithBegin;

    switch (record_type) {
        .begin, .commit, .rollback => {
            if (record.offset != 0) return error.InvalidRecordOffset;
            if (record.size != 0) return error.InvalidRecordSize;
            if (record.hasUndoData()) return error.InvalidUndoDataForRecordType;
        },
        .checkpoint => {
            if (record.transaction_id != 0) return error.InvalidTransactionId;
            if (record.size != 0) return error.InvalidRecordSize;
            if (record.hasUndoData()) return error.InvalidUndoDataForRecordType;
        },
        .write,
        .free,
        .root_update,
        .ref_count_dec,
        .free_list_remove,
        .heap_extend,
        .allocate,
        .free_list_add,
        .ref_count_inc,
        .gc_mark,
        .gc_sweep,
        => {
            _ = try checkedAdd(record.offset, record.size);
        },
    }

    if (!record.hasUndoData()) {
        if (record.old_value_offset != 0) return error.InvalidUndoOffset;
        if (record.old_value_size != 0) return error.InvalidUndoSize;
        if (record.data_checksum != 0) return error.UnexpectedChecksumField;
    } else {
        if (record.old_value_size == 0) return error.InvalidUndoSize;
        if (record.old_value_offset < headerSize()) return error.InvalidUndoOffset;
    }
}

fn computeDataChecksum(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc = crc32cByte(crc, byte);
    }
    return crc ^ 0xFFFFFFFF;
}

fn crc32cByte(crc: u32, byte: u8) u32 {
    return (crc >> 8) ^ CRC32C_TABLE[(crc ^ @as(u32, byte)) & 0xFF];
}

fn checkedAdd(a: u64, b: u64) !u64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return error.IntegerOverflow;
    return result[0];
}

fn toUsize(value: u64) !usize {
    if (value > std.math.maxInt(usize)) return error.ValueTooLarge;
    return @as(usize, @intCast(value));
}

fn headerSize() u64 {
    return @as(u64, @intCast(@sizeOf(WALHeader)));
}

fn recordSize() u64 {
    return @as(u64, @intCast(@sizeOf(WALRecord)));
}

fn recordAlignment() u64 {
    return @as(u64, @intCast(@alignOf(WALRecord)));
}

test "wal initialization" {
    const testing = std.testing;
    _ = header;
    _ = pointer;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_wal.wal";
    std.fs.cwd().deleteFile(test_path) catch {};

    var wal = try WAL.init(alloc, test_path, null);
    defer wal.deinit();

    try testing.expect(wal.header.magic == WAL_MAGIC);
    try testing.expect(wal.header.version == WAL_VERSION);
    try testing.expect(wal.header.tail_offset == headerSize());

    std.fs.cwd().deleteFile(test_path) catch {};
}

test "transaction lifecycle" {
    const testing = std.testing;
    _ = header;
    _ = pointer;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_wal_tx.wal";
    std.fs.cwd().deleteFile(test_path) catch {};

    var wal = try WAL.init(alloc, test_path, null);
    defer wal.deinit();

    var tx = try wal.beginTransaction();
    defer wal.endTransaction(&tx) catch {};

    try wal.appendRecord(&tx, .write, 100, 64);
    try testing.expect(tx.getRecordCount() == 2);

    try wal.commitTransaction(&tx);
    try testing.expect(tx.state == .committed);

    const records = try wal.getRecords(headerSize(), 16);
    defer records.deinit();

    try testing.expect(records.items.len == 3);

    std.fs.cwd().deleteFile(test_path) catch {};
}

test "transaction with undo data" {
    const testing = std.testing;
    _ = header;
    _ = pointer;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const test_path = "/tmp/test_wal_undo.wal";
    std.fs.cwd().deleteFile(test_path) catch {};

    var wal = try WAL.init(alloc, test_path, null);
    defer wal.deinit();

    var tx = try wal.beginTransaction();
    defer wal.endTransaction(&tx) catch {};

    const old_data = "previous-value";
    try wal.appendRecordWithData(&tx, .write, 128, old_data.len, old_data);
    try wal.commitTransaction(&tx);

    const records = try wal.getRecords(headerSize(), 16);
    defer records.deinit();

    try testing.expect(records.items.len == 3);
    try testing.expect(records.items[1].hasUndoData());

    const undo = try wal.getUndoData(&records.items[1]);
    defer alloc.free(undo);
    try testing.expect(std.mem.eql(u8, undo, old_data));

    std.fs.cwd().deleteFile(test_path) catch {};
}

test "sim wal power off fault" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(12345);
    defer {
        tsc.is_simulation = false;
    }

    var wal = try WAL.init(alloc, "/tmp/sim_wal_poweroff.wal", null);
    defer wal.deinit();

    try testing.expect(wal.vfs.kind == .sim);

    const sim = wal.getSimBackend().?;
    sim.armFault(.{
        .kind = .power_off_mid_write,
        .trigger_tx_id = 1,
        .armed = true,
    });

    var tx = try wal.beginTransaction();
    try wal.appendRecord(&tx, .write, 4096, 64);
    const result = wal.commitTransaction(&tx);
    try testing.expectError(error.SimulatedPowerOff, result);
    tx.deinit();
}
