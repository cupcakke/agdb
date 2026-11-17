const std = @import("std");
const Allocator = std.mem.Allocator;
const tokenizer_mod = @import("tokenizer.zig");
const vector_mod = @import("vector.zig");
const ssi_mod = @import("ssi.zig");
const ranker_mod = @import("ranker.zig");
const tensor_mod = @import("tensor.zig");
const types = @import("types.zig");
const io = @import("io.zig");

pub const RankIndexConfig = struct {
    num_ngrams: usize = 3,
    num_hash_functions: usize = 16,
    seed: u64 = 0x4147_4442_5252_414B,
    embedding_dim: u32 = 256,
    original_score_weight: f32 = 0.5,
    compaction_min_stale: usize = 64,
};

pub const RankedDocument = struct {
    doc_id: u64,
    position: u64,
    score: f32,
};

pub const RankIndex = struct {
    allocator: Allocator,
    ssi: ssi_mod.SSI,
    ranker: ranker_mod.Ranker,
    config: RankIndexConfig,
    doc_token_map: std.AutoHashMapUnmanaged(u64, []u32),
    doc_positions: std.AutoHashMapUnmanaged(u64, u64),
    position_docs: std.AutoHashMapUnmanaged(u64, u64),
    stale_count: usize,
    next_position: u64,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RankIndexConfig) !Self {
        if (config.num_ngrams == 0 or config.num_hash_functions == 0 or config.embedding_dim == 0) {
            return error.InvalidConfig;
        }
        if (!std.math.isFinite(config.original_score_weight) or
            config.original_score_weight < 0.0 or
            config.original_score_weight > 1.0)
        {
            return error.InvalidConfig;
        }

        var ssi = ssi_mod.SSI.init(allocator);
        errdefer ssi.deinit();

        var ranker = try ranker_mod.Ranker.init(allocator, config.num_ngrams, config.num_hash_functions, config.seed);
        errdefer ranker.deinit();

        return .{
            .allocator = allocator,
            .ssi = ssi,
            .ranker = ranker,
            .config = config,
            .doc_token_map = .empty,
            .doc_positions = .empty,
            .position_docs = .empty,
            .stale_count = 0,
            .next_position = 1,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.ssi.deinit();
        self.ranker.deinit();

        var it = self.doc_token_map.valueIterator();
        while (it.next()) |tokens| {
            self.allocator.free(tokens.*);
        }
        self.doc_token_map.deinit(self.allocator);
        self.doc_positions.deinit(self.allocator);
        self.position_docs.deinit(self.allocator);
    }

    pub fn addDocument(self: *Self, doc_id: u64, body: []const u8) !void {
        const tokens = try tokenizeToU32(self.allocator, body);
        errdefer self.allocator.free(tokens);

        if (tokens.len == 0) return error.EmptyDocument;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.next_position == std.math.maxInt(u64)) return error.PositionExhausted;

        try self.doc_token_map.ensureUnusedCapacity(self.allocator, 1);
        try self.doc_positions.ensureUnusedCapacity(self.allocator, 1);
        try self.position_docs.ensureUnusedCapacity(self.allocator, 1);

        const position = self.next_position;
        try self.ssi.addSequence(tokens, position, true);
        self.next_position = position + 1;

        const old_tokens = self.doc_token_map.get(doc_id);
        const old_position = self.doc_positions.get(doc_id);

        self.doc_token_map.putAssumeCapacity(doc_id, tokens);
        self.doc_positions.putAssumeCapacity(doc_id, position);
        self.position_docs.putAssumeCapacity(position, doc_id);

        if (old_position) |op| {
            _ = self.position_docs.remove(op);
            self.stale_count += 1;
        }
        if (old_tokens) |ot| {
            self.allocator.free(ot);
        }

        self.maybeCompactLocked();
    }

    pub fn removeDocument(self: *Self, doc_id: u64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        var removed = false;
        if (self.doc_token_map.fetchRemove(doc_id)) |kv| {
            self.allocator.free(kv.value);
            removed = true;
        }
        if (self.doc_positions.fetchRemove(doc_id)) |kv| {
            _ = self.position_docs.remove(kv.value);
            self.stale_count += 1;
            removed = true;
        }
        if (removed) self.maybeCompactLocked();
        return removed;
    }

    pub fn rerank(
        self: *Self,
        query: []const u8,
        candidates: []const u64,
        scores: []f32,
        allocator: Allocator,
    ) !void {
        if (candidates.len != scores.len) return error.LengthMismatch;
        if (candidates.len == 0) return;
        for (scores) |s| {
            if (!std.math.isFinite(s)) return error.InvalidScore;
        }

        const query_tokens = try tokenizeToU32(allocator, query);
        defer allocator.free(query_tokens);

        const blended = try allocator.alloc(f32, scores.len);
        defer allocator.free(blended);

        {
            self.mutex.lock();
            defer self.mutex.unlock();

            const weight = self.config.original_score_weight;
            for (candidates, scores, blended) |id, score, *out| {
                var ngram: f32 = 0.0;
                if (self.doc_token_map.get(id)) |doc_tokens| {
                    const raw = try self.ranker.scoreSequenceWithQuery(doc_tokens, query_tokens, &self.ssi);
                    const value: f32 = @floatCast(raw);
                    if (!std.math.isFinite(value)) return error.InvalidScore;
                    ngram = value;
                }
                const mixed = score * weight + ngram * (1.0 - weight);
                if (!std.math.isFinite(mixed)) return error.InvalidScore;
                out.* = mixed;
            }
        }

        @memcpy(scores, blended);
    }

    pub fn rerankSorted(
        self: *Self,
        query: []const u8,
        candidates: []u64,
        scores: []f32,
        allocator: Allocator,
    ) !void {
        if (candidates.len != scores.len) return error.LengthMismatch;
        const n = candidates.len;
        if (n == 0) return;

        const order = try allocator.alloc(usize, n);
        defer allocator.free(order);
        const ids_copy = try allocator.alloc(u64, n);
        defer allocator.free(ids_copy);
        const scores_copy = try allocator.alloc(f32, n);
        defer allocator.free(scores_copy);

        try self.rerank(query, candidates, scores, allocator);

        @memcpy(ids_copy, candidates);
        @memcpy(scores_copy, scores);
        for (order, 0..) |*slot, idx| slot.* = idx;

        const Ctx = struct {
            values: []const f32,
            fn greater(ctx: @This(), a: usize, b: usize) bool {
                return ctx.values[a] > ctx.values[b];
            }
        };
        std.mem.sort(usize, order, Ctx{ .values = scores_copy }, Ctx.greater);

        for (order, 0..) |src, dst| {
            candidates[dst] = ids_copy[src];
            scores[dst] = scores_copy[src];
        }
    }

    pub fn topK(self: *Self, query: []const u8, k: usize, allocator: Allocator) ![]RankedDocument {
        if (k == 0) return try allocator.alloc(RankedDocument, 0);

        const query_tokens = try tokenizeToU32(allocator, query);
        defer allocator.free(query_tokens);

        var out = std.ArrayListUnmanaged(RankedDocument).empty;
        errdefer out.deinit(allocator);

        self.mutex.lock();
        defer self.mutex.unlock();

        const fetch = k +| self.stale_count;
        const segments = try self.ranker.topKHeap(&self.ssi, query_tokens, fetch, allocator);
        defer {
            for (segments) |*seg| seg.deinit(allocator);
            allocator.free(segments);
        }

        try out.ensureTotalCapacity(allocator, @min(k, segments.len));
        for (segments) |seg| {
            if (out.items.len >= k) break;
            const position: u64 = @intCast(seg.position);
            const doc_id = self.position_docs.get(position) orelse continue;
            out.appendAssumeCapacity(.{
                .doc_id = doc_id,
                .position = position,
                .score = @floatCast(seg.score),
            });
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn jaccardSimilarity(self: *Self, doc_id_a: u64, doc_id_b: u64) !f32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const tokens_a = self.doc_token_map.get(doc_id_a) orelse return error.DocumentNotFound;
        const tokens_b = self.doc_token_map.get(doc_id_b) orelse return error.DocumentNotFound;

        const sig_a = try self.ranker.minHashSignature(tokens_a);
        defer self.allocator.free(sig_a);
        const sig_b = try self.ranker.minHashSignature(tokens_b);
        defer self.allocator.free(sig_b);

        return ranker_mod.Ranker.jaccardSimilarityFromSignatures(sig_a, sig_b);
    }

    pub fn documentCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.doc_token_map.count();
    }

    pub fn embed(self: *const Self, allocator: Allocator, body: []const u8) !tensor_mod.Tensor {
        return embedToTensor(allocator, body, self.config.embedding_dim);
    }

    fn maybeCompactLocked(self: *Self) void {
        if (self.stale_count < self.config.compaction_min_stale) return;
        if (self.stale_count <= self.position_docs.count()) return;
        self.compactLocked() catch {};
    }

    fn compactLocked(self: *Self) !void {
        const live = self.position_docs.count();
        const positions = try self.allocator.alloc(u64, live);
        defer self.allocator.free(positions);

        var it = self.position_docs.keyIterator();
        var n: usize = 0;
        while (it.next()) |key| {
            positions[n] = key.*;
            n += 1;
        }
        std.mem.sort(u64, positions, {}, std.sort.asc(u64));

        var fresh = ssi_mod.SSI.init(self.allocator);
        errdefer fresh.deinit();

        for (positions) |position| {
            const doc_id = self.position_docs.get(position) orelse return error.CorruptIndex;
            const tokens = self.doc_token_map.get(doc_id) orelse return error.CorruptIndex;
            try fresh.addSequence(tokens, position, true);
        }

        self.ssi.deinit();
        self.ssi = fresh;
        self.stale_count = 0;
    }
};

pub fn tokenizeToU32(allocator: Allocator, body: []const u8) ![]u32 {
    var list = std.ArrayListUnmanaged(u32).empty;
    errdefer list.deinit(allocator);

    var token_list = try tokenizer_mod.tokenize(allocator, body, .{});
    defer token_list.deinit();

    try list.ensureTotalCapacity(allocator, token_list.items.len);
    for (token_list.items) |tok| {
        const hash = io.stableHashU32(tok.text, 0x4147_4442_544F_4B45);
        list.appendAssumeCapacity(hash);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn embedToTensor(allocator: Allocator, body: []const u8, dim: u32) !tensor_mod.Tensor {
    const n: usize = @intCast(dim);

    const vec = try vector_mod.featureHashEmbed(allocator, body, dim);
    defer allocator.free(vec);
    if (vec.len < n) return error.DimensionMismatch;

    const shape = [1]usize{n};
    var t = try tensor_mod.Tensor.init(allocator, &shape);
    errdefer t.deinit();

    if (t.data.len < n) return error.DimensionMismatch;
    for (t.data[0..n], vec[0..n]) |*dst, src| dst.* = src;

    return t;
}

test "RankIndex add and topK returns only live documents" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(1, "vector embeddings for similarity search");
    try ri.addDocument(2, "graph indexes for connected data");
    try ri.addDocument(3, "vector and graph hybrid databases");

    const result = try ri.topK("vector search", 2, a);
    defer a.free(result);

    try std.testing.expect(result.len <= 2);
    for (result) |r| {
        try std.testing.expect(r.doc_id >= 1 and r.doc_id <= 3);
    }
}

test "RankIndex removed documents never surface in topK" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(1, "vector embeddings for similarity search");
    try ri.addDocument(2, "vector search engines");
    try std.testing.expect(ri.removeDocument(1));
    try std.testing.expect(!ri.removeDocument(1));
    try std.testing.expectEqual(@as(usize, 1), ri.documentCount());

    const result = try ri.topK("vector search", 5, a);
    defer a.free(result);

    for (result) |r| {
        try std.testing.expect(r.doc_id != 1);
    }
}

test "RankIndex replacement keeps a single live version" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(7, "first version of the document");
    try ri.addDocument(7, "second version of the document");
    try std.testing.expectEqual(@as(usize, 1), ri.documentCount());

    const result = try ri.topK("document", 10, a);
    defer a.free(result);

    var seen: usize = 0;
    for (result) |r| {
        if (r.doc_id == 7) seen += 1;
    }
    try std.testing.expect(seen <= 1);
}

test "RankIndex empty body is rejected and preserves existing document" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(5, "alpha beta gamma");
    try std.testing.expectError(error.EmptyDocument, ri.addDocument(5, ""));
    try std.testing.expectEqual(@as(usize, 1), ri.documentCount());
}

test "RankIndex rerank produces finite blended scores" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(10, "alpha beta gamma");
    try ri.addDocument(11, "delta epsilon zeta");

    const ids = [_]u64{ 10, 11, 99 };
    var scores = [_]f32{ 0.5, 0.5, 0.5 };
    try ri.rerank("alpha", &ids, &scores, a);

    for (scores) |s| {
        try std.testing.expect(std.math.isFinite(s));
    }
}

test "RankIndex rerank rejects length mismatch and non-finite input without mutation" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(10, "alpha beta gamma");

    const ids = [_]u64{ 10, 11 };
    var short_scores = [_]f32{0.5};
    try std.testing.expectError(error.LengthMismatch, ri.rerank("alpha", &ids, &short_scores, a));

    var bad_scores = [_]f32{ 0.25, std.math.nan(f32) };
    try std.testing.expectError(error.InvalidScore, ri.rerank("alpha", &ids, &bad_scores, a));
    try std.testing.expectEqual(@as(f32, 0.25), bad_scores[0]);
}

test "RankIndex rerankSorted orders by descending score" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(10, "alpha beta gamma");
    try ri.addDocument(11, "delta epsilon zeta");

    var ids = [_]u64{ 10, 11 };
    var scores = [_]f32{ 0.5, 0.5 };
    try ri.rerankSorted("alpha", &ids, &scores, a);

    try std.testing.expect(scores[0] >= scores[1]);
}

test "RankIndex jaccardSimilarity" {
    const a = std.testing.allocator;
    var ri = try RankIndex.init(a, .{});
    defer ri.deinit();

    try ri.addDocument(1, "alpha beta gamma delta");
    try ri.addDocument(2, "alpha beta gamma delta");

    const sim = try ri.jaccardSimilarity(1, 2);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sim, 1e-6);
    try std.testing.expectError(error.DocumentNotFound, ri.jaccardSimilarity(1, 42));
}

test "RankIndex rejects invalid config" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidConfig, RankIndex.init(a, .{ .num_ngrams = 0 }));
    try std.testing.expectError(error.InvalidConfig, RankIndex.init(a, .{ .embedding_dim = 0 }));
}

test "embedToTensor produces correct size" {
    const a = std.testing.allocator;
    var t = try embedToTensor(a, "hello world", 64);
    defer t.deinit();

    try std.testing.expectEqual(@as(usize, 64), t.shape.totalSize());
    try std.testing.expect(t.data.len >= 64);
}
