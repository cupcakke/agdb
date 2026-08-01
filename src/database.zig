const std = @import("std");
const kv_mod = @import("kv.zig");
const bm25_mod = @import("bm25.zig");
const vector_mod = @import("vector.zig");
const record_mod = @import("record.zig");
const json_mod = @import("json.zig");
const rank_index_mod = @import("rank_index.zig");
const gpu_mod = @import("gpu.zig");
const jit_alloc_mod = @import("jit_alloc.zig");
const dhtm_mod = @import("dhtm.zig");

pub const DatabaseConfig = struct {
    data_dir: []const u8,
    embedding_dim: u32 = 256,
    distance: vector_mod.Distance = .cosine,
    bm25_k1: f32 = 1.5,
    bm25_b: f32 = 0.75,
    schema_id: u64 = 0x4147_4442_5343_4830,
    auto_embed: bool = true,
    enable_rank_index: bool = false,
    gpu_ctx: ?*gpu_mod.GPUContext = null,
    jit_alloc: ?*jit_alloc_mod.AdaptiveAllocator = null,
    gpu_search_threshold: usize = 64,
    dhtm_runtime: ?*dhtm_mod.DHTMRuntime = null,
};

pub const QueryResult = struct {
    id: u64,
    score: f32,
    source: Source,
    record: record_mod.Record,

    pub const Source = enum { bm25, vector, hybrid };

    pub fn deinit(self: *QueryResult, allocator: std.mem.Allocator) void {
        self.record.deinit(allocator);
    }
};

pub const QueryResults = struct {
    items: []QueryResult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *QueryResults) void {
        for (self.items) |*r| r.deinit(self.allocator);
        self.allocator.free(self.items);
    }
};

pub const Database = struct {
    allocator: std.mem.Allocator,
    config: DatabaseConfig,
    kv: *kv_mod.KvStore,
    bm25: bm25_mod.Bm25Index,
    vec: vector_mod.VectorIndex,
    next_id: u64,
    mutex: std.Thread.Mutex,
    data_dir_owned: []const u8,
    rank_index: ?*rank_index_mod.RankIndex,
    dhtm: ?*dhtm_mod.DHTMRuntime,
    dhtm_owned: bool,

    const Self = @This();

    const NEXT_ID_KEY = "__agdb_next_id";
    const BM25_KEY = "__agdb_bm25_state";
    const VECTOR_KEY = "__agdb_vector_state";

    pub fn open(allocator: std.mem.Allocator, config: DatabaseConfig) !*Self {
        try std.fs.cwd().makePath(config.data_dir);

        const effective_alloc: std.mem.Allocator = if (config.jit_alloc) |ja|
            ja.allocator()
        else
            allocator;

        const data_dir_owned = try allocator.dupe(u8, config.data_dir);
        errdefer allocator.free(data_dir_owned);

        const kv_path = try std.fmt.allocPrint(allocator, "{s}/store.kv", .{config.data_dir});
        defer allocator.free(kv_path);

        const kv_store = try kv_mod.KvStore.open(effective_alloc, kv_path, config.schema_id);
        errdefer kv_store.close();

        var bm25_index: bm25_mod.Bm25Index = undefined;
        if (try kv_store.get(effective_alloc, BM25_KEY)) |bytes| {
            defer effective_alloc.free(bytes);
            bm25_index = bm25_mod.Bm25Index.deserialize(effective_alloc, bytes) catch bm25_mod.Bm25Index.init(effective_alloc, .{ .k1 = config.bm25_k1, .b = config.bm25_b });
        } else {
            bm25_index = bm25_mod.Bm25Index.init(effective_alloc, .{ .k1 = config.bm25_k1, .b = config.bm25_b });
        }
        errdefer bm25_index.deinit();

        var vec_index: vector_mod.VectorIndex = undefined;
        if (try kv_store.get(effective_alloc, VECTOR_KEY)) |bytes| {
            defer effective_alloc.free(bytes);
            vec_index = vector_mod.VectorIndex.deserialize(effective_alloc, bytes) catch try vector_mod.VectorIndex.init(effective_alloc, config.embedding_dim, config.distance);
        } else {
            vec_index = try vector_mod.VectorIndex.init(effective_alloc, config.embedding_dim, config.distance);
        }
        errdefer vec_index.deinit();

        var next_id: u64 = 1;
        if (try kv_store.get(effective_alloc, NEXT_ID_KEY)) |bytes| {
            defer effective_alloc.free(bytes);
            if (bytes.len >= 8) {
                next_id = std.mem.readInt(u64, bytes[0..8], .little);
            }
        }

        var dhtm_rt: ?*dhtm_mod.DHTMRuntime = config.dhtm_runtime;
        var dhtm_owned_val: bool = false;
        if (dhtm_rt == null) dhtm_blk: {
            const rt_ptr = effective_alloc.create(dhtm_mod.DHTMRuntime) catch break :dhtm_blk;
            rt_ptr.* = dhtm_mod.DHTMRuntime.init(effective_alloc, 1) catch {
                effective_alloc.destroy(rt_ptr);
                break :dhtm_blk;
            };
            dhtm_rt = rt_ptr;
            dhtm_owned_val = true;
        }
        errdefer {
            if (dhtm_owned_val) {
                if (dhtm_rt) |dr| {
                    dr.deinit();
                    effective_alloc.destroy(dr);
                }
            }
        }

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = effective_alloc,
            .config = config,
            .kv = kv_store,
            .bm25 = bm25_index,
            .vec = vec_index,
            .next_id = next_id,
            .mutex = .{},
            .data_dir_owned = data_dir_owned,
            .rank_index = null,
            .dhtm = dhtm_rt,
            .dhtm_owned = dhtm_owned_val,
        };

        if (config.enable_rank_index) {
            if (effective_alloc.create(rank_index_mod.RankIndex)) |r| {
                if (rank_index_mod.RankIndex.init(effective_alloc, .{})) |ri_val| {
                    r.* = ri_val;
                    self.rank_index = r;
                } else |_| {
                    effective_alloc.destroy(r);
                }
            } else |_| {}
        }

        return self;
    }

    pub fn close(self: *Self) void {
        self.flushState() catch {};
        if (self.rank_index) |ri| {
            ri.deinit();
            self.allocator.destroy(ri);
            self.rank_index = null;
        }
        if (self.dhtm_owned) {
            if (self.dhtm) |dr| {
                dr.deinit();
                self.allocator.destroy(dr);
                self.dhtm = null;
            }
        }
        self.kv.close();
        self.bm25.deinit();
        self.vec.deinit();
        self.allocator.free(self.data_dir_owned);
        const outer = if (self.config.jit_alloc != null) self.config.jit_alloc.?.backing else self.allocator;
        outer.destroy(self);
    }

    fn flushState(self: *Self) !void {
        const bm25_bytes = try self.bm25.serialize(self.allocator);
        defer self.allocator.free(bm25_bytes);
        try self.kv.put(BM25_KEY, bm25_bytes);

        const vec_bytes = try self.vec.serialize(self.allocator);
        defer self.allocator.free(vec_bytes);
        try self.kv.put(VECTOR_KEY, vec_bytes);

        var next_id_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &next_id_bytes, self.next_id, .little);
        try self.kv.put(NEXT_ID_KEY, &next_id_bytes);
    }

    pub fn flush(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.flushState();
        try self.kv.flush();
    }

    pub fn nextId(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        const id = self.next_id;
        self.next_id +|= 1;
        return id;
    }

    pub fn put(self: *Self, record: record_mod.Record) !u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var assigned_id = record.id;
        if (assigned_id == 0) {
            assigned_id = self.next_id;
            self.next_id += 1;
        } else if (assigned_id >= self.next_id) {
            self.next_id = assigned_id + 1;
        }

        if (self.dhtm) |dhtm_rt| {
            const vr = try dhtm_rt.registerAddress(assigned_id);
            const old_ver = vr.version;
            const tx = try dhtm_rt.begin();
            tx.addWrite(assigned_id, 8, dhtm_rt.local_participant.node_id, old_ver) catch {
                dhtm_rt.abort(tx);
                return error.OutOfMemory;
            };
            dhtm_rt.commit(tx) catch |e| return e;
        }

        var stored = record;
        stored.id = assigned_id;
        if (stored.embedding == null and self.config.auto_embed and stored.body.len > 0) {
            stored.embedding = try vector_mod.hashEmbed(self.allocator, stored.body, self.config.embedding_dim);
        }
        errdefer if (record.embedding == null and stored.embedding != null) {
            self.allocator.free(stored.embedding.?);
        };

        const key_buf = try idKey(self.allocator, assigned_id);
        defer self.allocator.free(key_buf);

        const encoded = try record_mod.RecordWriter.encode(self.allocator, stored);
        defer self.allocator.free(encoded);

        try self.kv.put(key_buf, encoded);
        var kv_committed = true;
        errdefer if (kv_committed) {
            _ = self.kv.delete(key_buf) catch {};
        };

        try self.bm25.addDocument(assigned_id, stored.body);
        var bm25_committed = true;
        errdefer if (bm25_committed) {
            self.bm25.removeDocument(assigned_id) catch {};
        };

        if (stored.embedding) |emb| {
            if (emb.len == self.config.embedding_dim) {
                try self.vec.upsert(assigned_id, emb);
            }
        }

        if (self.rank_index) |ri| {
            ri.addDocument(assigned_id, stored.body) catch {};
        }

        _ = &kv_committed;
        _ = &bm25_committed;

        if (record.embedding == null and stored.embedding != null) {
            self.allocator.free(stored.embedding.?);
        }
        return assigned_id;
    }

    pub fn putBytes(self: *Self, kind: record_mod.RecordKind, id: u64, body: []const u8, tags: []const []const u8) !u64 {
        const tag_copy = try self.allocator.alloc([]const u8, tags.len);
        var tags_initialized: usize = 0;
        errdefer {
            var ti: usize = 0;
            while (ti < tags_initialized) : (ti += 1) {
                self.allocator.free(tag_copy[ti]);
            }
            self.allocator.free(tag_copy);
        }
        for (tags, 0..) |t, i| {
            tag_copy[i] = try self.allocator.dupe(u8, t);
            tags_initialized = i + 1;
        }
        const body_copy = try self.allocator.dupe(u8, body);
        errdefer self.allocator.free(body_copy);
        const now = std.time.microTimestamp();
        var rec = record_mod.Record{
            .id = id,
            .kind = kind,
            .created_at_us = now,
            .updated_at_us = now,
            .tags = tag_copy,
            .body = body_copy,
            .embedding = null,
        };
        defer rec.deinit(self.allocator);
        return try self.put(rec);
    }

    pub fn get(self: *Self, id: u64) !?record_mod.Record {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key_buf = try idKey(self.allocator, id);
        defer self.allocator.free(key_buf);

        const bytes = try self.kv.get(self.allocator, key_buf);
        if (bytes == null) return null;
        defer self.allocator.free(bytes.?);
        return try record_mod.RecordReader.decode(self.allocator, bytes.?);
    }

    pub fn delete(self: *Self, id: u64) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.dhtm) |dhtm_rt| {
            const vr = try dhtm_rt.registerAddress(id);
            const old_ver = vr.version;
            const tx = try dhtm_rt.begin();
            tx.addWrite(id, 8, dhtm_rt.local_participant.node_id, old_ver) catch {
                dhtm_rt.abort(tx);
                return error.OutOfMemory;
            };
            dhtm_rt.commit(tx) catch |e| return e;
        }
        const key_buf = try idKey(self.allocator, id);
        defer self.allocator.free(key_buf);
        const existed = try self.kv.delete(key_buf);
        if (!existed) return false;
        try self.bm25.removeDocument(id);
        _ = self.vec.remove(id);
        if (self.rank_index) |ri| {
            ri.removeDocument(id);
        }
        return true;
    }

    pub fn searchText(self: *Self, query: []const u8, top_k: usize) !QueryResults {
        const results: QueryResults = blk: {
            self.mutex.lock();
            defer self.mutex.unlock();
            const hits = try self.bm25.search(self.allocator, query, top_k);
            defer self.allocator.free(hits);
            break :blk try self.materializeHitsBm25(hits);
        };
        if (self.rank_index) |ri| {
            const n = results.items.len;
            if (n > 0) {
                const ids = self.allocator.alloc(u64, n) catch return results;
                defer self.allocator.free(ids);
                const scores = self.allocator.alloc(f32, n) catch return results;
                defer self.allocator.free(scores);
                for (results.items, 0..) |r, i| {
                    ids[i] = r.id;
                    scores[i] = r.score;
                }
                ri.rerank(query, ids, scores, self.allocator) catch {};
                for (results.items, 0..) |*r, i| {
                    r.score = scores[i];
                }
            }
        }
        return results;
    }

    pub fn searchVector(self: *Self, vector: []const f32, top_k: usize) !QueryResults {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.config.gpu_ctx) |gctx| {
            const n = self.vec.vectorCount();
            if (n >= self.config.gpu_search_threshold) {
                const hits = self.searchVectorGpu(gctx, vector, top_k) catch null;
                if (hits) |h| {
                    defer self.allocator.free(h);
                    return self.materializeHitsVector(h);
                }
            }
        }

        const hits = try self.vec.search(self.allocator, vector, top_k);
        defer self.allocator.free(hits);
        return self.materializeHitsVector(hits);
    }

    pub fn searchHybrid(self: *Self, query: []const u8, vector: ?[]const f32, top_k: usize, alpha: f32) !QueryResults {
        self.mutex.lock();
        defer self.mutex.unlock();

        const text_hits = try self.bm25.search(self.allocator, query, top_k * 4);
        defer self.allocator.free(text_hits);

        var query_vec_owned: ?[]f32 = null;
        defer if (query_vec_owned) |v| self.allocator.free(v);

        const vector_query: []const f32 = blk: {
            if (vector) |v| break :blk v;
            if (self.config.auto_embed and query.len > 0) {
                query_vec_owned = try vector_mod.hashEmbed(self.allocator, query, self.config.embedding_dim);
                break :blk query_vec_owned.?;
            }
            break :blk &[_]f32{};
        };

        var vec_hits: []vector_mod.SearchHit = &[_]vector_mod.SearchHit{};
        defer if (vec_hits.len > 0) self.allocator.free(vec_hits);

        if (vector_query.len == self.config.embedding_dim) {
            const n = self.vec.vectorCount();
            const use_gpu = self.config.gpu_ctx != null and n >= self.config.gpu_search_threshold;
            if (use_gpu) {
                vec_hits = self.searchVectorGpu(self.config.gpu_ctx.?, vector_query, top_k * 4) catch
                    try self.vec.search(self.allocator, vector_query, top_k * 4);
            } else {
                vec_hits = try self.vec.search(self.allocator, vector_query, top_k * 4);
            }
        }

        var combined = std.AutoHashMap(u64, f32).init(self.allocator);
        defer combined.deinit();

        const max_bm = blk: {
            var m: f32 = 0;
            for (text_hits) |h| if (h.score > m) {
                m = h.score;
            };
            break :blk m;
        };
        const max_vec = blk: {
            var m: f32 = 0;
            for (vec_hits) |h| {
                const s = @as(f32, @floatCast(h.score));
                if (s > m) {
                    m = s;
                }
            }
            break :blk m;
        };

        for (text_hits) |h| {
            const normalized = if (max_bm > 0) h.score / max_bm else 0;
            const gop = try combined.getOrPut(h.doc_id);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += alpha * normalized;
        }
        for (vec_hits) |h| {
            const s = @as(f32, @floatCast(h.score));
            const normalized = if (max_vec > 0) s / max_vec else 0;
            const gop = try combined.getOrPut(h.doc_id);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += (1.0 - alpha) * normalized;
        }

        const ScoredId = struct {
            id: u64,
            score: f32,
            fn cmp(_: void, a: @This(), b: @This()) bool {
                return a.score > b.score;
            }
        };
        var all = try self.allocator.alloc(ScoredId, combined.count());
        defer self.allocator.free(all);
        var idx: usize = 0;
        var it = combined.iterator();
        while (it.next()) |e| {
            all[idx] = .{ .id = e.key_ptr.*, .score = e.value_ptr.* };
            idx += 1;
        }
        std.mem.sort(ScoredId, all, {}, ScoredId.cmp);
        const limit = @min(top_k, all.len);

        var out = try self.allocator.alloc(QueryResult, limit);
        var emitted: usize = 0;
        errdefer {
            for (out[0..emitted]) |*r| r.deinit(self.allocator);
            self.allocator.free(out);
        }
        var i: usize = 0;
        while (i < limit) : (i += 1) {
            const rec = try self.loadRecord(all[i].id) orelse continue;
            out[emitted] = .{
                .id = all[i].id,
                .score = all[i].score,
                .source = .hybrid,
                .record = rec,
            };
            emitted += 1;
        }
        if (emitted < out.len) {
            out = try self.allocator.realloc(out, emitted);
        }
        return QueryResults{ .items = out, .allocator = self.allocator };
    }

    fn searchVectorGpu(self: *Self, gctx: *gpu_mod.GPUContext, query: []const f32, top_k: usize) ![]vector_mod.SearchHit {
        self.vec.lock.lockShared();
        defer self.vec.lock.unlockShared();

        const entries = self.vec.entries.items;
        const n = entries.len;
        if (n == 0) return self.allocator.alloc(vector_mod.SearchHit, 0);
        const dim = self.config.embedding_dim;

        const matrix = try self.allocator.alloc(f32, n * dim);
        defer self.allocator.free(matrix);

        for (entries, 0..) |entry, i| {
            const src_len = @min(entry.vector.len, dim);
            @memcpy(matrix[i * dim .. i * dim + src_len], entry.vector[0..src_len]);
            if (src_len < dim) @memset(matrix[i * dim + src_len .. (i + 1) * dim], 0);
        }

        const matrix_val = gpu_mod.GPUValue{ .array_float32 = gpu_mod.GPUArray(f32).init(matrix) };
        const query_val = gpu_mod.GPUValue{ .array_float32 = gpu_mod.GPUArray(f32).init(@constCast(query)) };
        const n_val = gpu_mod.GPUValue{ .int64 = @intCast(n) };
        const inputs = [_]gpu_mod.GPUValue{ matrix_val, query_val, n_val };

        var result = try gctx.runKernel("cosine_similarity", &inputs, .array_float32);
        defer result.deinit();

        const scores = result.array_float32.data;
        const actual_k = @min(top_k, n);

        const all_hits = try self.allocator.alloc(vector_mod.SearchHit, n);
        defer self.allocator.free(all_hits);
        for (entries, 0..) |entry, i| {
            all_hits[i] = .{ .doc_id = entry.doc_id, .score = scores[i] };
        }

        std.mem.sort(vector_mod.SearchHit, all_hits, {}, struct {
            fn gt(_: void, a: vector_mod.SearchHit, b: vector_mod.SearchHit) bool {
                return a.score > b.score;
            }
        }.gt);

        const out = try self.allocator.alloc(vector_mod.SearchHit, actual_k);
        @memcpy(out, all_hits[0..actual_k]);
        return out;
    }

    fn materializeHitsBm25(self: *Self, hits: []bm25_mod.SearchHit) !QueryResults {
        var out = try self.allocator.alloc(QueryResult, hits.len);
        var emitted: usize = 0;
        errdefer {
            for (out[0..emitted]) |*r| r.deinit(self.allocator);
            self.allocator.free(out);
        }
        for (hits) |h| {
            const rec = try self.loadRecord(h.doc_id) orelse continue;
            out[emitted] = .{
                .id = h.doc_id,
                .score = h.score,
                .source = .bm25,
                .record = rec,
            };
            emitted += 1;
        }
        if (emitted < out.len) {
            out = try self.allocator.realloc(out, emitted);
        }
        return QueryResults{ .items = out, .allocator = self.allocator };
    }

    fn materializeHitsVector(self: *Self, hits: []vector_mod.SearchHit) !QueryResults {
        var out = try self.allocator.alloc(QueryResult, hits.len);
        var emitted: usize = 0;
        errdefer {
            for (out[0..emitted]) |*r| r.deinit(self.allocator);
            self.allocator.free(out);
        }
        for (hits) |h| {
            const rec = try self.loadRecord(h.doc_id) orelse continue;
            out[emitted] = .{
                .id = h.doc_id,
                .score = @as(f32, @floatCast(h.score)),
                .source = .vector,
                .record = rec,
            };
            emitted += 1;
        }
        if (emitted < out.len) {
            out = try self.allocator.realloc(out, emitted);
        }
        return QueryResults{ .items = out, .allocator = self.allocator };
    }

    fn loadRecord(self: *Self, id: u64) !?record_mod.Record {
        const key_buf = try idKey(self.allocator, id);
        defer self.allocator.free(key_buf);
        const bytes = try self.kv.get(self.allocator, key_buf);
        if (bytes == null) return null;
        defer self.allocator.free(bytes.?);
        return try record_mod.RecordReader.decode(self.allocator, bytes.?);
    }

    pub fn count(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.bm25.docCount();
    }

    pub fn compact(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.flushState();
        try self.kv.compact();
    }

    pub fn putJson(self: *Self, kind: record_mod.RecordKind, value: json_mod.Value) !u64 {
        var rec = try record_mod.fromJson(self.allocator, value, kind, 0);
        defer rec.deinit(self.allocator);
        return try self.put(rec);
    }

    pub fn getJson(self: *Self, allocator: std.mem.Allocator, id: u64) !?json_mod.Value {
        var rec = (try self.get(id)) orelse return null;
        defer rec.deinit(self.allocator);
        return try record_mod.toJson(allocator, rec);
    }
};

fn idKey(allocator: std.mem.Allocator, id: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "rec:{x:0>16}", .{id});
}

test "database basic put search delete" {
    const testing = std.testing;
    const tmp_dir = "agdb-test-db";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    var db = try Database.open(testing.allocator, .{
        .data_dir = tmp_dir,
        .embedding_dim = 64,
    });
    defer db.close();

    const tags = [_][]const u8{ "memory", "tdai" };
    const id1 = try db.putBytes(.document, 0, "agdb is a unified zig database", &tags);
    const id2 = try db.putBytes(.document, 0, "memory tdai four layer architecture", &tags);
    _ = id2;
    try testing.expect(id1 >= 1);

    var results = try db.searchText("unified zig", 5);
    defer results.deinit();
    try testing.expect(results.items.len >= 1);
    try testing.expectEqual(id1, results.items[0].id);

    var maybe_rec = try db.get(id1);
    try testing.expect(maybe_rec != null);
    defer if (maybe_rec) |*r| r.deinit(testing.allocator);
    try testing.expectEqualStrings("agdb is a unified zig database", maybe_rec.?.body);
}

test "database persistence" {
    const testing = std.testing;
    const tmp_dir = "agdb-test-db-persist";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    {
        var db = try Database.open(testing.allocator, .{
            .data_dir = tmp_dir,
            .embedding_dim = 32,
        });
        defer db.close();
        const empty_tags = [_][]const u8{};
        _ = try db.putBytes(.document, 0, "persistent record", &empty_tags);
        try db.flush();
    }
    {
        var db = try Database.open(testing.allocator, .{
            .data_dir = tmp_dir,
            .embedding_dim = 32,
        });
        defer db.close();
        var results = try db.searchText("persistent", 1);
        defer results.deinit();
        try testing.expect(results.items.len == 1);
    }
}
