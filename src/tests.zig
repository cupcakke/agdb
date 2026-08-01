const std = @import("std");
const agdb = @import("agdb");
const tsc = @import("tsc.zig");
const concurrency = @import("concurrency.zig");

test "end to end put and search" {
    const testing = std.testing;
    const tmp_dir = "agdb-it-e2e";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    var db = try agdb.Database.open(testing.allocator, .{
        .data_dir = tmp_dir,
        .embedding_dim = 64,
    });
    defer db.close();

    const empty: [0][]const u8 = .{};
    const id_a = try db.putBytes(.document, 0, "agdb stores documents and supports text and vector search", &empty);
    const id_b = try db.putBytes(.document, 0, "vectors live next to text in a unified store", &empty);
    const id_c = try db.putBytes(.document, 0, "unrelated content about cooking and recipes", &empty);
    _ = id_b;
    _ = id_c;
    try db.flush();

    var text_hits = try db.searchText("vector search", 5);
    defer text_hits.deinit();
    try testing.expect(text_hits.items.len >= 1);
    try testing.expectEqual(id_a, text_hits.items[0].id);

    var hybrid_hits = try db.searchHybrid("unified store", null, 5, 0.6);
    defer hybrid_hits.deinit();
    try testing.expect(hybrid_hits.items.len >= 1);

    try db.compact();
    try testing.expect(db.count() == 3);
}

test "kv durability across reopen" {
    const testing = std.testing;
    const tmp_dir = "agdb-it-kv";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const path = try std.fmt.allocPrint(testing.allocator, "{s}/kv.dat", .{tmp_dir});
    defer testing.allocator.free(path);

    {
        const store = try agdb.kv.KvStore.open(testing.allocator, path, 0);
        try store.put("a", "1");
        try store.put("b", "two");
        try store.put("c", "thrice");
        _ = try store.delete("b");
        try store.flush();
        store.close();
    }
    {
        const store2 = try agdb.kv.KvStore.open(testing.allocator, path, 0);
        defer store2.close();
        const val_a = try store2.get(testing.allocator, "a");
        defer if (val_a) |v| testing.allocator.free(v);
        const val_c = try store2.get(testing.allocator, "c");
        defer if (val_c) |v| testing.allocator.free(v);
        try testing.expectEqualStrings("1", val_a.?);
        try testing.expectEqualStrings("thrice", val_c.?);
        try testing.expect(!store2.contains("b"));
    }
}

test "bm25 + vector combined" {
    const testing = std.testing;
    var bm = agdb.bm25.Bm25Index.init(testing.allocator, .{});
    defer bm.deinit();
    var vi = agdb.vector.VectorIndex.init(testing.allocator, 8, .cosine);
    defer vi.deinit();

    try bm.addDocument(1, "alpha beta gamma");
    try bm.addDocument(2, "delta epsilon zeta");
    try vi.upsert(1, &[_]f32{ 1, 0, 0, 0, 0, 0, 0, 0 });
    try vi.upsert(2, &[_]f32{ 0, 1, 0, 0, 0, 0, 0, 0 });

    const text_hits = try bm.search(testing.allocator, "alpha", 3);
    defer testing.allocator.free(text_hits);
    const vec_hits = try vi.search(testing.allocator, &[_]f32{ 0, 1, 0, 0, 0, 0, 0, 0 }, 3);
    defer testing.allocator.free(vec_hits);

    try testing.expect(text_hits[0].doc_id == 1);
    try testing.expect(vec_hits[0].doc_id == 2);
}

test "json round trip" {
    const testing = std.testing;
    const src =
        \\{"id":7,"kind":"document","body":"hello","tags":["a","b"]}
    ;
    var v = try agdb.json.parse(testing.allocator, src);
    defer v.deinit(testing.allocator);
    const out = try agdb.json.stringify(testing.allocator, v);
    defer testing.allocator.free(out);
    var v2 = try agdb.json.parse(testing.allocator, out);
    defer v2.deinit(testing.allocator);
    try testing.expectEqualStrings("hello", v2.getField("body").?.asString().?);
}

test "tokenizer normalize" {
    const testing = std.testing;
    var tl = try agdb.tokenizer.tokenize(testing.allocator, "Hello, AGDB! 1234", .{});
    defer tl.deinit();
    try testing.expect(tl.items.len == 3);
    try testing.expectEqualStrings("hello", tl.items[0].text);
    try testing.expectEqualStrings("agdb", tl.items[1].text);
    try testing.expectEqualStrings("1234", tl.items[2].text);
}

test "dst fiber basic schedule and yield" {
    const testing = std.testing;
    tsc.initSimulation(0xDEADBEEF);
    defer {
        tsc.is_simulation = false;
    }

    var counter = std.atomic.Value(u32).init(0);

    const FiberFn = struct {
        fn run(ptr: *anyopaque) void {
            const c: *std.atomic.Value(u32) = @ptrCast(@alignCast(ptr));
            _ = c.fetchAdd(1, .acq_rel);
            concurrency.FiberScheduler.yield();
            _ = c.fetchAdd(1, .acq_rel);
        }
    };

    concurrency.FiberScheduler.init(testing.allocator);
    defer concurrency.FiberScheduler.deinit();

    try concurrency.FiberScheduler.spawn(&FiberFn.run, @ptrCast(&counter));
    try concurrency.FiberScheduler.spawn(&FiberFn.run, @ptrCast(&counter));

    concurrency.FiberScheduler.run();

    try testing.expectEqual(@as(u32, 4), counter.load(.acquire));
}

test "dst virtual clock advances monotonically" {
    const testing = std.testing;
    tsc.initSimulation(42);
    defer {
        tsc.is_simulation = false;
    }

    const t0 = tsc.virtualNow();
    tsc.advanceVirtualClock(1000);
    const t1 = tsc.virtualNow();
    tsc.advanceVirtualClock(500);
    const t2 = tsc.virtualNow();

    try testing.expect(t1 > t0);
    try testing.expect(t2 > t1);
    try testing.expectEqual(t0 + 1000, t1);
    try testing.expectEqual(t1 + 500, t2);
}

test "dst fault injection coordinator basic" {
    const testing = std.testing;
    tsc.initSimulation(1337);
    defer {
        tsc.is_simulation = false;
    }

    var dst = concurrency.DSTCoordinator.init(testing.allocator, 1337);
    defer dst.deinit();

    dst.setFaultRate(1.0);
    try testing.expect(dst.checkFault(.disk_write));

    dst.setFaultRate(0.0);
    try testing.expect(!dst.checkFault(.disk_write));
}

test "dst stm transaction commit and retry" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(555);
    defer {
        tsc.is_simulation = false;
    }

    const pheap_mod = @import("pheap.zig");
    const wal_mod = @import("wal.zig");
    const tx_mod = @import("transaction.zig");

    const heap = try pheap_mod.PersistentHeap.init(alloc, "/tmp/dst_stm_test.dat", 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, "/tmp/dst_stm_test.wal", null);
    defer wal.deinit();

    var tx_mgr = try tx_mod.TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const tx1 = try tx_mgr.begin();
    try testing.expect(tx1.reg_state.hasFlag(tx_mod.TX_FLAG_STM));

    try tx1.stmLogRead(1024, 8, tx_mgr.stmReadVersion(1024));
    try tx1.stmBufferWrite(2048, "hello-stm");

    try tx_mgr.commit(tx1);
    try testing.expectEqual(@as(usize, 0), tx_mgr.getActiveTransactionCount());
    try testing.expectEqual(@as(u64, 1), tx_mgr.stm_versions.getVersion(2048));
}

test "dst kv sim backend put and get" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(7777);
    defer {
        tsc.is_simulation = false;
    }

    const kv_mod = @import("kv.zig");

    var store = try kv_mod.KvStore.open(alloc, "/tmp/dst_kv_sim.kv", 0);
    defer store.close();

    try store.put("key1", "value1");
    try store.put("key2", "value2");

    const v1 = try store.get(alloc, "key1");
    defer if (v1) |v| alloc.free(v);
    try testing.expectEqualStrings("value1", v1.?);

    _ = try store.delete("key1");
    try testing.expect(!store.contains("key1"));
    try testing.expect(store.contains("key2"));
}

test "dst wal sim backend transaction lifecycle" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(2025);
    defer {
        tsc.is_simulation = false;
    }

    const wal_mod = @import("wal.zig");

    var wal = try wal_mod.WAL.init(alloc, "/tmp/dst_wal_sim.wal", null);
    defer wal.deinit();

    try testing.expect(wal.vfs.kind == .sim);
    try testing.expectEqual(wal_mod.WAL_MAGIC, wal.header.magic);

    var tx = try wal.beginTransaction();
    try wal.appendRecord(&tx, .write, 4096, 128);
    try wal.commitTransaction(&tx);
    try testing.expect(tx.state == .committed);

    const records = try wal.getRecords(wal_mod.WALHeader.init(0).tail_offset, 16);
    defer records.deinit();
    _ = records;
}

test "dst pheap sim backend alloc read write" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(3141592);
    defer {
        tsc.is_simulation = false;
    }

    const pheap_mod = @import("pheap.zig");

    const heap = try pheap_mod.PersistentHeap.init(alloc, "/tmp/dst_pheap_sim.dat", 1024 * 1024, null);
    defer heap.deinit() catch {};

    try testing.expect(heap.vfs.kind == .sim);
    try testing.expect(heap.pool_uuid != 0);

    const ptr = try heap.allocate({}, 64, 8);
    try testing.expect(!ptr.isNull());

    const data = "DST-PHEAP-SIM-TEST";
    try heap.write(ptr.offset, data);

    var buf: [18]u8 = undefined;
    try heap.read(ptr.offset, &buf);
    try testing.expectEqualSlices(u8, data, &buf);
}

test "dst sim torn write fault recovery" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(0xC0FFEE);
    defer {
        tsc.is_simulation = false;
    }

    const pheap_mod = @import("pheap.zig");

    const heap = try pheap_mod.PersistentHeap.init(alloc, "/tmp/dst_torn.dat", 1024 * 1024, null);
    defer heap.deinit() catch {};

    const sim = heap.getSimBackend().?;

    const base_offset: u64 = 65536;
    sim.armFault(.{
        .kind = .torn_write,
        .trigger_offset = base_offset,
        .trigger_size = 64,
        .partial_bytes = 4,
        .armed = true,
    });

    const full_data = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    const torn_result = heap.write(base_offset, full_data);
    try testing.expectError(error.SimulatedTornWrite, torn_result);

    var partial_buf: [4]u8 = undefined;
    try heap.read(base_offset, &partial_buf);
    try testing.expectEqualSlices(u8, "ABCD", &partial_buf);

    var rest_buf: [28]u8 = undefined;
    try heap.read(base_offset + 4, &rest_buf);
    const all_zero = for (rest_buf) |b| {
        if (b != 0) break false;
    } else true;
    try testing.expect(all_zero);
}

test "dst concurrent stm isolation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(0xABCD1234);
    defer {
        tsc.is_simulation = false;
    }

    const pheap_mod = @import("pheap.zig");
    const wal_mod = @import("wal.zig");
    const tx_mod = @import("transaction.zig");

    const heap = try pheap_mod.PersistentHeap.init(alloc, "/tmp/dst_stm_iso.dat", 2 * 1024 * 1024, null);
    defer heap.deinit() catch {};

    var wal = try wal_mod.WAL.init(alloc, "/tmp/dst_stm_iso.wal", null);
    defer wal.deinit();

    var tx_mgr = try tx_mod.TransactionManager.init(alloc, wal, heap);
    defer tx_mgr.deinit();

    const shared_offset: u64 = 8192;

    const initial_ver = tx_mgr.stmReadVersion(shared_offset);

    const tx_a = try tx_mgr.begin();
    try tx_a.stmLogRead(shared_offset, 8, initial_ver);
    try tx_a.stmBufferWrite(shared_offset, "TXA-DATA");

    const tx_b = try tx_mgr.begin();
    try tx_b.stmLogRead(shared_offset, 8, initial_ver);
    try tx_b.stmBufferWrite(shared_offset, "TXB-DATA");

    try tx_mgr.commit(tx_a);
    try testing.expectEqual(@as(u64, 1), tx_mgr.stmReadVersion(shared_offset));

    const b_result = tx_mgr.commit(tx_b);
    try testing.expectError(error.STMReadValidationFailed, b_result);
    tx_mgr.rollback(tx_b) catch {};

    try testing.expectEqual(@as(usize, 0), tx_mgr.getActiveTransactionCount());
}
