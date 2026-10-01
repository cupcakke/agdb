const std = @import("std");
const tokenizer = @import("tokenizer.zig");

pub const Bm25Params = struct {
    k1: f32 = 1.5,
    b: f32 = 0.75,
    tokenize_opts: tokenizer.TokenizerOptions = .{ .lowercase = true, .min_token_len = 1 },
};

pub const Posting = struct {
    doc_id: u64,
    tf: u32,
};

pub const SearchHit = struct {
    doc_id: u64,
    score: f32,
};

const index_magic: u32 = 0x42_4D_32_35;
const index_version_v1: u32 = 1;
const index_version_v2: u32 = 2;
const epsilon: f32 = 1e-6;

const BinaryReader = struct {
    data: []const u8,
    off: usize = 0,

    fn remaining(self: *const BinaryReader) usize {
        return self.data.len - self.off;
    }

    fn readU8(self: *BinaryReader) !u8 {
        if (self.remaining() < 1) return error.InvalidIndex;
        const val = self.data[self.off];
        self.off += 1;
        return val;
    }

    fn readU32(self: *BinaryReader) !u32 {
        if (self.remaining() < 4) return error.InvalidIndex;
        const val = std.mem.readInt(u32, self.data[self.off..][0..4], .little);
        self.off += 4;
        return val;
    }

    fn readU64(self: *BinaryReader) !u64 {
        if (self.remaining() < 8) return error.InvalidIndex;
        const val = std.mem.readInt(u64, self.data[self.off..][0..8], .little);
        self.off += 8;
        return val;
    }
};

fn writeU8(buf: []u8, off: *usize, val: u8) void {
    buf[off.*] = val;
    off.* += 1;
}

fn writeU32(buf: []u8, off: *usize, val: u32) void {
    std.mem.writeInt(u32, buf[off.*..][0..4], val, .little);
    off.* += 4;
}

fn writeU64(buf: []u8, off: *usize, val: u64) void {
    std.mem.writeInt(u64, buf[off.*..][0..8], val, .little);
    off.* += 8;
}

pub const Bm25Index = struct {
    allocator: std.mem.Allocator,
    params: Bm25Params,
    postings: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(Posting)),
    doc_terms: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(u64)),
    doc_lengths: std.AutoHashMapUnmanaged(u64, u32),
    doc_id_set: std.AutoHashMapUnmanaged(u64, void),
    total_terms: u64,
    total_docs: u64,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, params: Bm25Params) Self {
        return .{
            .allocator = allocator,
            .params = params,
            .postings = .{},
            .doc_terms = .{},
            .doc_lengths = .{},
            .doc_id_set = .{},
            .total_terms = 0,
            .total_docs = 0,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        var p_it = self.postings.iterator();
        while (p_it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.postings.deinit(self.allocator);

        var dt_it = self.doc_terms.iterator();
        while (dt_it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.doc_terms.deinit(self.allocator);

        self.doc_lengths.deinit(self.allocator);
        self.doc_id_set.deinit(self.allocator);
        self.total_terms = 0;
        self.total_docs = 0;
    }

    fn validateParams(params: Bm25Params) !void {
        if (!std.math.isFinite(params.k1) or params.k1 < 0.0) {
            return error.InvalidParameters;
        }
        if (!std.math.isFinite(params.b) or params.b < 0.0 or params.b > 1.0) {
            return error.InvalidParameters;
        }
    }

    pub fn addDocument(self: *Self, doc_id: u64, text: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try validateParams(self.params);

        var tokens = try tokenizer.tokenize(self.allocator, text, self.params.tokenize_opts);
        defer tokens.deinit();

        if (tokens.items.len == 0) {
            self.removeDocumentLocked(doc_id);
            return;
        }

        const doc_len = std.math.cast(u32, tokens.items.len) orelse return error.DocumentTooLong;

        var tf_counts: std.AutoHashMapUnmanaged(u64, u32) = .{};
        defer tf_counts.deinit(self.allocator);

        for (tokens.items) |tok| {
            const h = tokenizer.hashToken(tok.text);
            const gop = try tf_counts.getOrPut(self.allocator, h);
            if (gop.found_existing) {
                if (gop.value_ptr.* == std.math.maxInt(u32)) return error.TermFrequencyTooLarge;
                gop.value_ptr.* += 1;
            } else {
                gop.value_ptr.* = 1;
            }
        }

        const old_len = self.doc_lengths.get(doc_id);
        const prev_terms = self.total_terms - (if (old_len) |ol| @as(u64, ol) else 0);
        if (prev_terms > std.math.maxInt(u64) - @as(u64, doc_len)) return error.IndexTooLarge;
        if (old_len == null and self.total_docs == std.math.maxInt(u64)) return error.IndexTooLarge;

        self.removeDocumentLocked(doc_id);

        var term_list: std.ArrayListUnmanaged(u64) = .{};
        errdefer term_list.deinit(self.allocator);
        try term_list.ensureTotalCapacity(self.allocator, tf_counts.count());
        errdefer self.unwindPostings(doc_id, term_list.items);

        var tf_it = tf_counts.iterator();
        while (tf_it.next()) |entry| {
            const term_hash = entry.key_ptr.*;
            const tf = entry.value_ptr.*;

            const gop = try self.postings.getOrPut(self.allocator, term_hash);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{};
            }
            gop.value_ptr.append(self.allocator, .{ .doc_id = doc_id, .tf = tf }) catch |err| {
                if (gop.value_ptr.items.len == 0) {
                    gop.value_ptr.deinit(self.allocator);
                    _ = self.postings.remove(term_hash);
                }
                return err;
            };
            term_list.appendAssumeCapacity(term_hash);
        }

        try self.doc_lengths.ensureUnusedCapacity(self.allocator, 1);
        try self.doc_id_set.ensureUnusedCapacity(self.allocator, 1);
        try self.doc_terms.ensureUnusedCapacity(self.allocator, 1);

        self.doc_lengths.putAssumeCapacity(doc_id, doc_len);
        self.doc_terms.putAssumeCapacity(doc_id, term_list);
        self.doc_id_set.putAssumeCapacity(doc_id, {});
        self.total_docs += 1;
        self.total_terms += doc_len;
    }

    fn unwindPostings(self: *Self, doc_id: u64, terms: []const u64) void {
        for (terms) |term_hash| {
            const list_ptr = self.postings.getPtr(term_hash) orelse continue;
            var i: usize = 0;
            while (i < list_ptr.items.len) {
                if (list_ptr.items[i].doc_id == doc_id) {
                    _ = list_ptr.swapRemove(i);
                    break;
                }
                i += 1;
            }
            if (list_ptr.items.len == 0) {
                list_ptr.deinit(self.allocator);
                _ = self.postings.remove(term_hash);
            }
        }
    }

    fn removeDocumentLocked(self: *Self, doc_id: u64) void {
        if (self.doc_terms.fetchRemove(doc_id)) |kv| {
            var terms = kv.value;
            defer terms.deinit(self.allocator);
            self.unwindPostings(doc_id, terms.items);
        }

        if (self.doc_lengths.fetchRemove(doc_id)) |kv| {
            const removed_len: u64 = kv.value;
            if (self.total_terms >= removed_len) {
                self.total_terms -= removed_len;
            } else {
                self.total_terms = 0;
            }
        }

        if (self.doc_id_set.remove(doc_id)) {
            if (self.total_docs > 0) self.total_docs -= 1;
        }
    }

    pub fn removeDocument(self: *Self, doc_id: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.removeDocumentLocked(doc_id);
    }

    pub fn search(self: *Self, allocator: std.mem.Allocator, query: []const u8, top_k: usize) ![]SearchHit {
        self.mutex.lock();
        defer self.mutex.unlock();

        try validateParams(self.params);

        if (top_k == 0 or self.total_docs == 0 or self.total_terms == 0) {
            return try allocator.alloc(SearchHit, 0);
        }

        var q_tokens = try tokenizer.tokenize(allocator, query, self.params.tokenize_opts);
        defer q_tokens.deinit();

        if (q_tokens.items.len == 0) {
            return try allocator.alloc(SearchHit, 0);
        }

        const doc_count_f: f64 = @floatFromInt(self.total_docs);
        const total_terms_f: f64 = @floatFromInt(self.total_terms);
        const avgdl: f64 = total_terms_f / doc_count_f;
        const k1: f64 = self.params.k1;
        const b: f64 = self.params.b;

        var scores = std.AutoHashMap(u64, f64).init(allocator);
        defer scores.deinit();

        var seen_terms = std.AutoHashMap(u64, void).init(allocator);
        defer seen_terms.deinit();

        for (q_tokens.items) |tok| {
            const term_hash = tokenizer.hashToken(tok.text);
            const seen_gop = try seen_terms.getOrPut(term_hash);
            if (seen_gop.found_existing) continue;

            const term_postings = self.postings.get(term_hash) orelse continue;
            if (term_postings.items.len == 0) continue;

            const df: f64 = @floatFromInt(term_postings.items.len);
            const idf_num = doc_count_f - df + 0.5;
            const idf_den = df + 0.5;
            const idf = @log(@max(idf_num / idf_den, 1e-6) + 1.0);

            for (term_postings.items) |p| {
                const dl_raw = self.doc_lengths.get(p.doc_id) orelse 1;
                const dl: f64 = if (dl_raw == 0) 1.0 else @floatFromInt(dl_raw);
                const tf_f: f64 = @floatFromInt(p.tf);
                const denom = tf_f + k1 * (1.0 - b + b * (dl / avgdl));
                const score_contrib = idf * (tf_f * (k1 + 1.0)) / @max(denom, 1e-6);

                const gop = try scores.getOrPut(p.doc_id);
                if (!gop.found_existing) {
                    gop.value_ptr.* = 0.0;
                }
                gop.value_ptr.* += score_contrib;
            }
        }

        if (scores.count() == 0) {
            return try allocator.alloc(SearchHit, 0);
        }

        const all_hits = try allocator.alloc(SearchHit, scores.count());
        errdefer allocator.free(all_hits);

        var i: usize = 0;
        var s_it = scores.iterator();
        while (s_it.next()) |s| {
            all_hits[i] = SearchHit{ .doc_id = s.key_ptr.*, .score = @floatCast(s.value_ptr.*) };
            i += 1;
        }

        std.mem.sort(SearchHit, all_hits, {}, lessThan);

        const limit = @min(top_k, all_hits.len);
        if (limit == all_hits.len) return all_hits;

        const out = try allocator.alloc(SearchHit, limit);
        @memcpy(out, all_hits[0..limit]);
        allocator.free(all_hits);
        return out;
    }

    fn lessThan(_: void, a: SearchHit, b: SearchHit) bool {
        if (a.score == b.score) return a.doc_id < b.doc_id;
        return a.score > b.score;
    }

    pub fn docCount(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.total_docs;
    }

    pub fn termCount(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.postings.count();
    }

    pub fn writeInt(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, comptime T: type, value: T) !void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        try buffer.appendSlice(allocator, &bytes);
    }

    pub fn serialize(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        try validateParams(self.params);

        var posting_total: usize = 0;
        var p_count_it = self.postings.iterator();
        while (p_count_it.next()) |entry| {
            if (entry.value_ptr.items.len > std.math.maxInt(u32)) return error.IndexTooLarge;
            posting_total += entry.value_ptr.items.len;
        }

        const doc_len_count: usize = self.doc_lengths.count();
        const term_count: usize = self.postings.count();
        const size: usize = 49 + doc_len_count * 12 + 8 + term_count * 12 + posting_total * 12;

        const buf = try allocator.alloc(u8, size);
        errdefer allocator.free(buf);

        var off: usize = 0;
        writeU32(buf, &off, index_magic);
        writeU32(buf, &off, index_version_v2);
        writeU32(buf, &off, @bitCast(self.params.k1));
        writeU32(buf, &off, @bitCast(self.params.b));
        writeU8(buf, &off, if (self.params.tokenize_opts.lowercase) 1 else 0);
        writeU64(buf, &off, @as(u64, @intCast(self.params.tokenize_opts.min_token_len)));
        writeU64(buf, &off, self.total_docs);
        writeU64(buf, &off, self.total_terms);
        writeU64(buf, &off, doc_len_count);

        var dl_it = self.doc_lengths.iterator();
        while (dl_it.next()) |e| {
            writeU64(buf, &off, e.key_ptr.*);
            writeU32(buf, &off, e.value_ptr.*);
        }

        writeU64(buf, &off, term_count);

        var p_it = self.postings.iterator();
        while (p_it.next()) |e| {
            writeU64(buf, &off, e.key_ptr.*);
            writeU32(buf, &off, @intCast(e.value_ptr.items.len));
            for (e.value_ptr.items) |posting| {
                writeU64(buf, &off, posting.doc_id);
                writeU32(buf, &off, posting.tf);
            }
        }

        std.debug.assert(off == size);
        return buf;
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Self {
        var reader = BinaryReader{ .data = data };

        const magic = try reader.readU32();
        if (magic != index_magic) return error.InvalidIndex;

        const version = try reader.readU32();
        if (version != index_version_v1 and version != index_version_v2) {
            return error.IncompatibleVersion;
        }

        const k1: f32 = @bitCast(try reader.readU32());
        const b: f32 = @bitCast(try reader.readU32());

        var params = Bm25Params{ .k1 = k1, .b = b };
        if (version == index_version_v2) {
            const lc_byte = try reader.readU8();
            if (lc_byte > 1) return error.InvalidIndex;
            const min_len = try reader.readU64();
            const min_len_field = std.math.cast(@TypeOf(params.tokenize_opts.min_token_len), min_len) orelse return error.InvalidIndex;
            params.tokenize_opts.lowercase = (lc_byte != 0);
            params.tokenize_opts.min_token_len = min_len_field;
        }

        validateParams(params) catch return error.InvalidIndex;

        var self = Self.init(allocator, params);
        errdefer self.deinit();

        const serialized_total_docs = try reader.readU64();
        const serialized_total_terms = try reader.readU64();
        const doc_len_count = try reader.readU64();

        if (doc_len_count != serialized_total_docs) return error.InvalidIndex;
        if (doc_len_count > reader.remaining() / 12) return error.InvalidIndex;

        const doc_len_u32 = std.math.cast(u32, doc_len_count) orelse return error.InvalidIndex;
        try self.doc_lengths.ensureTotalCapacity(self.allocator, doc_len_u32);
        try self.doc_id_set.ensureTotalCapacity(self.allocator, doc_len_u32);

        var remaining_tf = std.AutoHashMap(u64, u32).init(allocator);
        defer remaining_tf.deinit();
        try remaining_tf.ensureTotalCapacity(doc_len_u32);

        var computed_terms: u64 = 0;
        var i: u64 = 0;
        while (i < doc_len_count) : (i += 1) {
            const id = try reader.readU64();
            const len = try reader.readU32();
            if (len == 0) return error.InvalidIndex;

            if (computed_terms > std.math.maxInt(u64) - @as(u64, len)) return error.InvalidIndex;
            computed_terms += len;

            if (self.doc_lengths.contains(id)) return error.InvalidIndex;
            self.doc_lengths.putAssumeCapacity(id, len);
            self.doc_id_set.putAssumeCapacity(id, {});
            remaining_tf.putAssumeCapacity(id, len);
        }

        if (computed_terms != serialized_total_terms) return error.InvalidIndex;
        self.total_docs = serialized_total_docs;
        self.total_terms = computed_terms;

        const term_count = try reader.readU64();
        if (term_count > reader.remaining() / 12) return error.InvalidIndex;

        const term_count_u32 = std.math.cast(u32, term_count) orelse return error.InvalidIndex;
        try self.postings.ensureTotalCapacity(self.allocator, term_count_u32);

        i = 0;
        while (i < term_count) : (i += 1) {
            const term_hash = try reader.readU64();
            const plen = try reader.readU32();

            if (@as(u64, plen) > serialized_total_docs) return error.InvalidIndex;
            if (plen > reader.remaining() / 12) return error.InvalidIndex;

            if (self.postings.contains(term_hash)) return error.InvalidIndex;

            if (plen == 0) {
                continue;
            }

            var list: std.ArrayListUnmanaged(Posting) = .{};
            errdefer list.deinit(self.allocator);
            try list.ensureTotalCapacity(self.allocator, plen);

            var seen_doc_ids = std.AutoHashMap(u64, void).init(allocator);
            defer seen_doc_ids.deinit();
            try seen_doc_ids.ensureTotalCapacity(plen);

            var j: u32 = 0;
            while (j < plen) : (j += 1) {
                const doc_id = try reader.readU64();
                const tf = try reader.readU32();
                if (tf == 0) return error.InvalidIndex;

                if (seen_doc_ids.contains(doc_id)) return error.InvalidIndex;
                seen_doc_ids.putAssumeCapacity(doc_id, {});

                const rem = remaining_tf.getPtr(doc_id) orelse return error.InvalidIndex;
                if (tf > rem.*) return error.InvalidIndex;
                rem.* -= tf;

                list.appendAssumeCapacity(.{ .doc_id = doc_id, .tf = tf });
            }

            self.postings.putAssumeCapacity(term_hash, list);
        }

        if (reader.remaining() != 0) return error.InvalidIndex;

        var r_it = remaining_tf.iterator();
        while (r_it.next()) |entry| {
            if (entry.value_ptr.* != 0) return error.InvalidIndex;
        }

        try self.rebuildDocTerms();
        return self;
    }

    fn rebuildDocTerms(self: *Self) !void {
        const doc_count_u32 = std.math.cast(u32, self.doc_lengths.count()) orelse return error.IndexTooLarge;
        try self.doc_terms.ensureTotalCapacity(self.allocator, doc_count_u32);
        var it = self.postings.iterator();
        while (it.next()) |entry| {
            const term_hash = entry.key_ptr.*;
            for (entry.value_ptr.items) |posting| {
                const gop = try self.doc_terms.getOrPut(self.allocator, posting.doc_id);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{};
                }
                try gop.value_ptr.append(self.allocator, term_hash);
            }
        }
    }
};

test "bm25 basic" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();
    try idx.addDocument(1, "the quick brown fox jumps over the lazy dog");
    try idx.addDocument(2, "agdb is a fast unified database in zig");
    try idx.addDocument(3, "zig zig zig fast fast fast");

    const hits = try idx.search(testing.allocator, "zig fast", 10);
    defer testing.allocator.free(hits);
    try testing.expect(hits.len >= 1);
    try testing.expectEqual(@as(u64, 3), hits[0].doc_id);
}

test "bm25 remove" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();
    try idx.addDocument(1, "hello world");
    try idx.addDocument(2, "hello agdb");
    try idx.removeDocument(1);
    const hits = try idx.search(testing.allocator, "hello", 5);
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 1), hits.len);
    try testing.expectEqual(@as(u64, 2), hits[0].doc_id);
    try testing.expectEqual(@as(u64, 1), idx.docCount());
    try testing.expectEqual(@as(u64, 2), idx.termCount());

    try idx.removeDocument(1);
    try testing.expectEqual(@as(u64, 1), idx.docCount());
}

test "bm25 reindex document" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();
    try idx.addDocument(7, "alpha alpha beta");
    try idx.addDocument(7, "gamma delta");
    try testing.expectEqual(@as(u64, 1), idx.docCount());
    try testing.expectEqual(@as(u64, 2), idx.termCount());

    const stale = try idx.search(testing.allocator, "alpha", 5);
    defer testing.allocator.free(stale);
    try testing.expectEqual(@as(usize, 0), stale.len);

    const fresh = try idx.search(testing.allocator, "gamma", 5);
    defer testing.allocator.free(fresh);
    try testing.expectEqual(@as(usize, 1), fresh.len);
    try testing.expectEqual(@as(u64, 7), fresh[0].doc_id);
}

test "bm25 serialize roundtrip" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();
    try idx.addDocument(1, "alpha bravo charlie");
    try idx.addDocument(2, "bravo charlie delta");
    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);
    var idx2 = try Bm25Index.deserialize(testing.allocator, bytes);
    defer idx2.deinit();
    try testing.expectEqual(idx.docCount(), idx2.docCount());
    try testing.expectEqual(idx.termCount(), idx2.termCount());
    try testing.expectEqual(idx.total_terms, idx2.total_terms);
    const hits = try idx2.search(testing.allocator, "bravo", 5);
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 2), hits.len);
}

test "bm25 replacement and term pruning" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha alpha beta");
    try idx.addDocument(2, "beta gamma");
    try idx.addDocument(1, "delta");

    try testing.expectEqual(@as(u64, 2), idx.docCount());
    try testing.expectEqual(@as(u64, 3), idx.termCount());
    try testing.expectEqual(@as(u64, 3), idx.total_terms);

    const old_hits = try idx.search(testing.allocator, "alpha", 10);
    defer testing.allocator.free(old_hits);
    try testing.expectEqual(@as(usize, 0), old_hits.len);

    const new_hits = try idx.search(testing.allocator, "delta", 10);
    defer testing.allocator.free(new_hits);
    try testing.expectEqual(@as(usize, 1), new_hits.len);
    try testing.expectEqual(@as(u64, 1), new_hits[0].doc_id);

    try idx.removeDocument(1);
    try testing.expectEqual(@as(u64, 1), idx.docCount());
    try testing.expectEqual(@as(u64, 2), idx.termCount());
    try testing.expectEqual(@as(u64, 2), idx.total_terms);

    try idx.removeDocument(2);
    try testing.expectEqual(@as(u64, 0), idx.docCount());
    try testing.expectEqual(@as(u64, 0), idx.termCount());
    try testing.expectEqual(@as(u64, 0), idx.total_terms);
}

test "bm25 replacement reuses existing terms" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha beta");
    try idx.addDocument(2, "alpha");
    try idx.addDocument(1, "alpha alpha gamma");

    try testing.expectEqual(@as(u64, 2), idx.docCount());
    try testing.expectEqual(@as(u64, 2), idx.termCount());
    try testing.expectEqual(@as(u64, 4), idx.total_terms);

    const hits = try idx.search(testing.allocator, "alpha", 10);
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 2), hits.len);

    const removed_hits = try idx.search(testing.allocator, "beta", 10);
    defer testing.allocator.free(removed_hits);
    try testing.expectEqual(@as(usize, 0), removed_hits.len);
}

test "bm25 empty document replacement" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha beta");
    try idx.addDocument(1, "");
    try idx.addDocument(2, "");

    try testing.expectEqual(@as(u64, 0), idx.docCount());
    try testing.expectEqual(@as(u64, 0), idx.termCount());
    try testing.expectEqual(@as(u64, 0), idx.total_terms);

    const hits = try idx.search(testing.allocator, "alpha", 10);
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 0), hits.len);

    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    var restored = try Bm25Index.deserialize(testing.allocator, bytes);
    defer restored.deinit();

    try testing.expectEqual(@as(u64, 0), restored.docCount());
    try testing.expectEqual(@as(u64, 0), restored.termCount());
    try testing.expectEqual(@as(u64, 0), restored.total_terms);
}

test "bm25 deterministic ties and zero top k" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(42, "same");
    try idx.addDocument(7, "same");
    try idx.addDocument(19, "same");

    const hits = try idx.search(testing.allocator, "same", 2);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 2), hits.len);
    try testing.expectEqual(@as(u64, 7), hits[0].doc_id);
    try testing.expectEqual(@as(u64, 19), hits[1].doc_id);

    const empty_hits = try idx.search(testing.allocator, "same", 0);
    defer testing.allocator.free(empty_hits);
    try testing.expectEqual(@as(usize, 0), empty_hits.len);
}

test "bm25 repeated query terms are counted once" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha alpha beta");
    try idx.addDocument(2, "alpha gamma");

    const single_hits = try idx.search(testing.allocator, "alpha", 10);
    defer testing.allocator.free(single_hits);

    const repeated_hits = try idx.search(testing.allocator, "alpha alpha alpha", 10);
    defer testing.allocator.free(repeated_hits);

    try testing.expectEqual(single_hits.len, repeated_hits.len);
    for (single_hits, repeated_hits) |single_hit, repeated_hit| {
        try testing.expectEqual(single_hit.doc_id, repeated_hit.doc_id);
        try testing.expectEqual(single_hit.score, repeated_hit.score);
    }
}

test "bm25 serialization preserves tokenizer options" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{
        .k1 = 1.2,
        .b = 0.5,
        .tokenize_opts = .{
            .lowercase = false,
            .min_token_len = 2,
        },
    });
    defer idx.deinit();

    try idx.addDocument(1, "Alpha beta a");

    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    var restored = try Bm25Index.deserialize(testing.allocator, bytes);
    defer restored.deinit();

    try testing.expectEqual(idx.params.k1, restored.params.k1);
    try testing.expectEqual(idx.params.b, restored.params.b);
    try testing.expectEqual(
        idx.params.tokenize_opts.lowercase,
        restored.params.tokenize_opts.lowercase,
    );
    try testing.expectEqual(
        idx.params.tokenize_opts.min_token_len,
        restored.params.tokenize_opts.min_token_len,
    );

    const hits = try restored.search(testing.allocator, "Alpha", 10);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 1), hits.len);
    try testing.expectEqual(@as(u64, 1), hits[0].doc_id);
}

test "bm25 rejects invalid parameters" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{ .k1 = -1.0 });
    defer idx.deinit();

    try testing.expectError(error.InvalidParameters, idx.addDocument(1, "alpha"));
    try testing.expectError(error.InvalidParameters, idx.search(testing.allocator, "alpha", 10));
    try testing.expectError(error.InvalidParameters, idx.serialize(testing.allocator));

    idx.params.k1 = 1.5;
    idx.params.b = 1.5;
    try testing.expectError(error.InvalidParameters, idx.addDocument(1, "alpha"));

    idx.params.b = 0.75;
    idx.params.k1 = std.math.inf(f32);
    try testing.expectError(error.InvalidParameters, idx.serialize(testing.allocator));

    idx.params.k1 = std.math.nan(f32);
    try testing.expectError(error.InvalidParameters, idx.search(testing.allocator, "alpha", 10));
}

test "bm25 rejects truncated and trailing serialized data" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha beta");

    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    for (0..bytes.len) |length| {
        try testing.expectError(
            error.InvalidIndex,
            Bm25Index.deserialize(testing.allocator, bytes[0..length]),
        );
    }

    const extended = try testing.allocator.alloc(u8, bytes.len + 1);
    defer testing.allocator.free(extended);

    @memcpy(extended[0..bytes.len], bytes);
    extended[bytes.len] = 0;

    try testing.expectError(
        error.InvalidIndex,
        Bm25Index.deserialize(testing.allocator, extended),
    );
}

test "bm25 rejects invalid posting frequencies" {
    const testing = std.testing;
    var idx = Bm25Index.init(testing.allocator, .{});
    defer idx.deinit();

    try idx.addDocument(1, "alpha");

    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    std.mem.writeInt(u32, bytes[bytes.len - 4 ..][0..4], 2, .little);

    try testing.expectError(
        error.InvalidIndex,
        Bm25Index.deserialize(testing.allocator, bytes),
    );
}

test "bm25 legacy deserialization removes empty terms" {
    const testing = std.testing;

    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(testing.allocator);

    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 0x42_4D_32_35);
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, @bitCast(@as(f32, 1.5)));
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, @bitCast(@as(f32, 0.75)));
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 9);
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 2);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, tokenizer.hashToken("alpha"));
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, 9);
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 1);
    try Bm25Index.writeInt(&buffer, testing.allocator, u64, tokenizer.hashToken("retired"));
    try Bm25Index.writeInt(&buffer, testing.allocator, u32, 0);

    var idx = try Bm25Index.deserialize(testing.allocator, buffer.items);
    defer idx.deinit();

    try testing.expectEqual(@as(u64, 1), idx.docCount());
    try testing.expectEqual(@as(u64, 1), idx.termCount());
    try testing.expectEqual(@as(u64, 1), idx.total_terms);

    const hits = try idx.search(testing.allocator, "alpha", 10);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 1), hits.len);
    try testing.expectEqual(@as(u64, 9), hits[0].doc_id);
}
