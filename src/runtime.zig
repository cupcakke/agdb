const std = @import("std");
const pheap = @import("pheap.zig");
const allocator_mod = @import("allocator.zig");
const wal_mod = @import("wal.zig");
const transaction_mod = @import("transaction.zig");
const recovery_mod = @import("recovery.zig");
const pointer_mod = @import("pointer.zig");
const concurrency_mod = @import("concurrency.zig");
const gc_mod = @import("gc.zig");
const snapshot_mod = @import("snapshot.zig");
const security_mod = @import("security.zig");
const api_mod = @import("api.zig");
const schema_mod = @import("schema.zig");
const mem_utils_mod = @import("mem_utils.zig");
const gpu_mod = @import("gpu.zig");
const numa_mod = @import("numa.zig");
const jit_alloc_mod = @import("jit_alloc.zig");
const replay_mod = @import("replay.zig");
const database_mod = @import("database.zig");

pub const PersistentHeap = pheap.PersistentHeap;
pub const PersistentAllocator = allocator_mod.PersistentAllocator;
pub const WAL = wal_mod.WAL;
pub const TransactionManager = transaction_mod.TransactionManager;
pub const Transaction = transaction_mod.Transaction;
pub const RecoveryEngine = recovery_mod.RecoveryEngine;
pub const RefCountGC = gc_mod.RefCountGC;
pub const SnapshotManager = snapshot_mod.SnapshotManager;
pub const SecurityManager = security_mod.SecurityManager;
pub const PersistentStore = api_mod.PersistentStore;
pub const SchemaRegistry = schema_mod.SchemaRegistry;
pub const PersistentPtr = pointer_mod.PersistentPtr;

pub const RuntimeConfig = struct {
    heap_path: []const u8,
    heap_size: u64,
    wal_path: []const u8,
    snapshot_dir: []const u8,
    enable_encryption: bool,
    master_key: ?[]const u8,
    gc_threshold: u64,
    snapshot_interval_ms: u64,
    enable_numa: bool = false,
    enable_trace: bool = false,
    trace_path: []const u8 = "agdb.replay",
    enable_gpu: bool = false,
    gpu_lib_path: []const u8 = "",
    enable_jit_alloc: bool = false,
    jit_recompile_threshold: u64 = 10_000,

    pub fn default(base_dir: []const u8) RuntimeConfig {
        _ = base_dir;
        return .{
            .heap_path = "agdb.heap",
            .heap_size = 1024 * 1024 * 256,
            .wal_path = "agdb.wal",
            .snapshot_dir = "snapshots",
            .enable_encryption = false,
            .master_key = null,
            .gc_threshold = 1024,
            .snapshot_interval_ms = 60_000,
        };
    }
};

pub const RuntimeStats = struct {
    heap_used: u64,
    heap_total: u64,
    allocation_count: u64,
    free_count: u64,
    wal_size: u64,
    transaction_count: u64,
    gc_stats: gc_mod.GCStats,
    snapshot_count: u64,
};

pub const Runtime = struct {
    heap: *PersistentHeap,
    alloc: *PersistentAllocator,
    wal: *WAL,
    tx_manager: *TransactionManager,
    recovery: *RecoveryEngine,
    gc: *RefCountGC,
    snapshots: *SnapshotManager,
    security: *SecurityManager,
    store: *PersistentStore,
    arena: *std.heap.ArenaAllocator,
    parent_allocator: std.mem.Allocator,
    config: RuntimeConfig,
    numa_topo: ?numa_mod.NumaTopology,
    trace_writer: ?*replay_mod.TraceWriter,
    gpu_ctx: ?*gpu_mod.GPUContext,
    jit_alloc: ?*jit_alloc_mod.AdaptiveAllocator,

    pub fn init(parent_alloc: std.mem.Allocator, config: RuntimeConfig) !*Runtime {
        const arena_ptr = try parent_alloc.create(std.heap.ArenaAllocator);
        errdefer parent_alloc.destroy(arena_ptr);
        arena_ptr.* = std.heap.ArenaAllocator.init(parent_alloc);
        errdefer arena_ptr.deinit();
        const arena_alloc = arena_ptr.allocator();

        const self = try parent_alloc.create(Runtime);
        errdefer parent_alloc.destroy(self);

        self.* = Runtime{
            .heap = undefined,
            .alloc = undefined,
            .wal = undefined,
            .tx_manager = undefined,
            .recovery = undefined,
            .gc = undefined,
            .snapshots = undefined,
            .security = undefined,
            .store = undefined,
            .arena = arena_ptr,
            .parent_allocator = parent_alloc,
            .config = config,
            .numa_topo = null,
            .trace_writer = null,
            .gpu_ctx = null,
            .jit_alloc = null,
        };

        self.security = try arena_alloc.create(SecurityManager);
        self.security.* = try SecurityManager.init(arena_alloc, config.master_key, config.enable_encryption);

        if (config.enable_numa) {
            self.numa_topo = numa_mod.NumaTopology.detect(arena_alloc);
        }

        const actual_size = if (config.heap_size == 0) 1024 * 1024 * 1024 else config.heap_size;
        const heap_path = try arena_alloc.dupe(u8, config.heap_path);
        const wal_path = try arena_alloc.dupe(u8, config.wal_path);

        self.heap = try PersistentHeap.init(arena_alloc, heap_path, actual_size, self.security);
        errdefer self.heap.deinit() catch {};

        if (self.numa_topo) |*topo| {
            const base = self.heap.getBaseAddress();
            const heap_slice = base[0..actual_size];
            _ = numa_mod.bindMemoryToNode(heap_slice, topo.localNode());
        }

        self.wal = try WAL.init(arena_alloc, wal_path, self.security);
        errdefer self.wal.deinit();

        self.recovery = try arena_alloc.create(RecoveryEngine);
        self.recovery.* = RecoveryEngine.init(self.heap, self.wal, arena_alloc);
        try self.recovery.recover();

        self.alloc = try PersistentAllocator.init(arena_alloc, self.heap, self.wal);
        errdefer self.alloc.deinit();

        self.tx_manager = try TransactionManager.init(arena_alloc, self.wal, self.heap);
        errdefer self.tx_manager.deinit();
        self.tx_manager.setAllocatorHook(@ptrCast(self.alloc), undoAllocationThunk);

        self.gc = try RefCountGC.init(arena_alloc, self.alloc, self.wal);
        errdefer self.gc.deinit();

        var snapshot_path: ?[]const u8 = null;
        if (config.snapshot_dir.len > 0) {
            snapshot_path = try arena_alloc.dupe(u8, config.snapshot_dir);
        }
        self.snapshots = try SnapshotManager.init(arena_alloc, self.heap, snapshot_path);
        errdefer self.snapshots.deinit();

        self.store = try PersistentStore.init(arena_alloc, self.alloc, self.tx_manager, self.gc);

        if (config.enable_trace) {
            if (replay_mod.TraceWriter.init(arena_alloc, config.trace_path, 65536)) |tw_val| {
                if (arena_alloc.create(replay_mod.TraceWriter)) |tw| {
                    tw.* = tw_val;
                    self.trace_writer = tw;
                    self.wal.setAppendHook(walAppendHook, tw);
                } else |_| {}
            } else |_| {}
        }

        if (config.enable_gpu) {
            if (gpu_mod.GPUContext.init(arena_alloc, config.gpu_lib_path)) |gctx| {
                registerCosineSimilarityKernel(gctx) catch {};
                self.gpu_ctx = gctx;
            } else |_| {}
        }

        if (config.enable_jit_alloc) {
            const ja = arena_alloc.create(jit_alloc_mod.AdaptiveAllocator) catch null;
            if (ja) |j| {
                j.* = jit_alloc_mod.AdaptiveAllocator.init(arena_alloc, config.jit_recompile_threshold);
                self.jit_alloc = j;
            }
        }

        return self;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.jit_alloc) |ja| {
            ja.deinit();
            self.jit_alloc = null;
        }
        if (self.gpu_ctx) |gctx| {
            gctx.deinit();
            self.gpu_ctx = null;
        }
        if (self.trace_writer) |tw| {
            self.wal.clearAppendHook();
            tw.deinit();
            self.trace_writer = null;
        }
        self.snapshots.deinit();
        self.gc.deinit();
        self.tx_manager.deinit();
        self.alloc.deinit();
        self.wal.deinit();
        self.heap.deinit() catch {};
        self.security.deinit();
        const parent = self.parent_allocator;
        const arena_ptr = self.arena;
        arena_ptr.deinit();
        parent.destroy(arena_ptr);
        parent.destroy(self);
    }

    pub fn makeDatabaseConfig(self: *Runtime, data_dir: []const u8) database_mod.DatabaseConfig {
        return database_mod.DatabaseConfig{
            .data_dir = data_dir,
            .gpu_ctx = self.gpu_ctx,
            .jit_alloc = self.jit_alloc,
        };
    }

    pub fn beginTransaction(self: *Runtime) !*Transaction {
        return self.tx_manager.begin();
    }

    fn undoAllocationThunk(ctx: *anyopaque, offset: u64, size: u64) anyerror!void {
        const alloc_ptr: *PersistentAllocator = @ptrCast(@alignCast(ctx));
        try alloc_ptr.undoAllocation(offset, size);
    }

    pub fn commit(self: *Runtime, tx: *Transaction) !void {
        try self.tx_manager.commit(tx);
    }

    pub fn rollback(self: *Runtime, tx: *Transaction) !void {
        try self.tx_manager.rollback(tx);
    }

    pub fn allocate(self: *Runtime, size: u64, alignment: u64) !PersistentPtr {
        const ptr = try self.alloc.alloc(size, alignment);
        errdefer self.alloc.free(ptr) catch {};
        self.tx_manager.lock.lock();
        defer self.tx_manager.lock.unlock();
        if (self.tx_manager.active_transactions.count() > 0) {
            const latest_id = self.tx_manager.transaction_counter;
            if (self.tx_manager.active_transactions.getPtr(latest_id)) |tx| {
                try tx.trackAllocation(ptr.offset, size);
            }
        }
        return ptr;
    }

    pub fn free(self: *Runtime, ptr: PersistentPtr) !void {
        try self.alloc.free(ptr);
    }

    pub fn getRoot(self: *Runtime) ?PersistentPtr {
        return self.heap.getRoot();
    }

    pub fn setRoot(self: *Runtime, tx: *Transaction, ptr: PersistentPtr) !void {
        try self.heap.setRoot(tx, ptr);
    }

    pub fn createSnapshot(self: *Runtime) !u64 {
        return self.snapshots.createSnapshot();
    }

    pub fn restoreSnapshot(self: *Runtime, snapshot_id: u64) !void {
        try self.snapshots.restoreSnapshot(snapshot_id);
    }

    pub fn runGC(self: *Runtime) !gc_mod.GCStats {
        return self.gc.runCollection();
    }

    pub fn getStats(self: *Runtime) RuntimeStats {
        return RuntimeStats{
            .heap_used = self.alloc.getUsedSize(),
            .heap_total = self.heap.getSize(),
            .allocation_count = self.alloc.getAllocationCount(),
            .free_count = self.alloc.getFreeCount(),
            .wal_size = self.wal.getSize(),
            .transaction_count = self.tx_manager.getTransactionCount(),
            .gc_stats = self.gc.getStats(),
            .snapshot_count = self.snapshots.getSnapshotCount(),
        };
    }

    pub fn flush(self: *Runtime) !void {
        try self.heap.flush();
        try self.wal.flush();
    }
};

fn walAppendHook(ctx: *anyopaque, record: *const wal_mod.WALRecord) void {
    const tw: *replay_mod.TraceWriter = @ptrCast(@alignCast(ctx));
    tw.record(
        .wal_append,
        0,
        record.transaction_id,
        record.sequence,
        record.offset,
        record.size,
    ) catch {};
}

fn cosineSimilarityKernel(ctx: *gpu_mod.GPUContext, inputs: []const gpu_mod.GPUValue, allocator: std.mem.Allocator) anyerror!gpu_mod.GPUValue {
    _ = ctx;
    if (inputs.len != 3) return gpu_mod.GPUError.InvalidArgument;
    if (inputs[0].getType() != .array_float32) return gpu_mod.GPUError.InvalidArgument;
    if (inputs[1].getType() != .array_float32) return gpu_mod.GPUError.InvalidArgument;
    if (inputs[2].getType() != .int64) return gpu_mod.GPUError.InvalidArgument;

    const matrix = inputs[0].array_float32;
    const query = inputs[1].array_float32;
    const n_i64 = inputs[2].int64;

    if (n_i64 <= 0) return gpu_mod.GPUError.InvalidArgument;
    const n: usize = @intCast(n_i64);
    const dim = query.data.len;
    if (dim == 0) return gpu_mod.GPUError.InvalidArgument;
    if (matrix.data.len != n * dim) return gpu_mod.GPUError.InvalidArgument;

    var q_norm_sq: f32 = 0;
    for (query.data) |x| q_norm_sq += x * x;
    const q_norm: f32 = @sqrt(q_norm_sq);

    var out = try gpu_mod.GPUArray(f32).initOwned(allocator, n);
    errdefer out.deinit();

    for (0..n) |i| {
        const row = matrix.data[i * dim .. (i + 1) * dim];
        var dot: f32 = 0;
        var row_norm_sq: f32 = 0;
        for (row, 0..) |x, j| {
            dot += x * query.data[j];
            row_norm_sq += x * x;
        }
        const row_norm: f32 = @sqrt(row_norm_sq);
        out.data[i] = if (row_norm > 0 and q_norm > 0) dot / (row_norm * q_norm) else 0;
    }

    return gpu_mod.GPUValue{ .array_float32 = out };
}

fn registerCosineSimilarityKernel(gctx: *gpu_mod.GPUContext) !void {
    const input_types = [_]gpu_mod.GPUValueType{ .array_float32, .array_float32, .int64 };
    try gctx.registerKernel(
        "cosine_similarity",
        &input_types,
        .array_float32,
        cosineSimilarityKernel,
    );
}

test "runtime smoke" {
    const testing = std.testing;
    const tmp_root = "agdb-test-runtime";
    std.fs.cwd().deleteTree(tmp_root) catch {};
    try std.fs.cwd().makePath(tmp_root);
    defer std.fs.cwd().deleteTree(tmp_root) catch {};

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const heap_path = try std.fmt.allocPrint(alloc, "{s}/heap.dat", .{tmp_root});
    defer alloc.free(heap_path);
    const wal_path = try std.fmt.allocPrint(alloc, "{s}/wal.dat", .{tmp_root});
    defer alloc.free(wal_path);
    const snap_path = try std.fmt.allocPrint(alloc, "{s}/snapshots", .{tmp_root});
    defer alloc.free(snap_path);

    const config = RuntimeConfig{
        .heap_path = heap_path,
        .heap_size = 1024 * 1024 * 4,
        .wal_path = wal_path,
        .snapshot_dir = snap_path,
        .enable_encryption = false,
        .master_key = null,
        .gc_threshold = 64,
        .snapshot_interval_ms = 60_000,
    };

    var rt = try Runtime.init(alloc, config);
    defer rt.deinit();

    const tx = try rt.beginTransaction();
    const ptr = try rt.allocate(128, 64);
    try rt.setRoot(tx, ptr);
    try rt.commit(tx);

    const stats = rt.getStats();
    try testing.expect(stats.allocation_count >= 1);
    try testing.expect(stats.heap_total >= 1024 * 1024);
}
