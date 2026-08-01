const std = @import("std");

pub const Distance = enum(u32) {
    cosine = 0,
    inner_product = 1,
    euclidean = 2,
    manhattan = 3,
};

pub const SearchHit = struct {
    doc_id: u64,
    score: f64,
};

pub const VectorIndexError = error{
    VectorDimMismatch,
    InvalidIndex,
    IncompatibleVersion,
    InvalidDistance,
    DuplicateDocId,
    InvalidDimension,
    InvalidVector,
    InvalidQuery,
    IndexCorrupt,
    IndexDeinitialized,
    CountTooLarge,
    SerializedSizeOverflow,
    NumericOverflow,
    InvalidUtf8,
    EmptyEmbedding,
};

pub const InitError = VectorIndexError;
pub const UpsertError = VectorIndexError || std.mem.Allocator.Error;
pub const SearchError = VectorIndexError || std.mem.Allocator.Error;
pub const SerializeError = VectorIndexError || std.mem.Allocator.Error;
pub const DeserializeError = VectorIndexError || std.mem.Allocator.Error;
pub const HashEmbedError = VectorIndexError || std.mem.Allocator.Error;

pub const SERIALIZED_MAGIC: u32 = 0x56_45_43_30;
pub const SERIALIZED_VERSION: u32 = 2;
pub const HASH_EMBED_VERSION: u32 = 2;

const SERIALIZED_HEADER_SIZE: usize = 44;
const SERIALIZED_CHECKSUM_OFFSET: usize = 36;
const HASH_EMBED_SEED_INDEX: u64 = 0x1;
const HASH_EMBED_SEED_SIGN: u64 = 0x2;
const MAX_VECTOR_COUNT: usize = std.math.maxInt(u32);
const MAX_DIMENSION: usize = std.math.maxInt(usize) / @sizeOf(f32);

const VectorEntry = struct {
    doc_id: u64,
    vector: []const f32,
};

const SnapshotEntry = struct {
    doc_id: u64,
    vector: []const f32,
};

pub const VectorIndex = struct {
    allocator: std.mem.Allocator,
    dim: usize,
    distance: Distance,
    entries: std.ArrayListUnmanaged(VectorEntry),
    id_to_idx: std.AutoHashMapUnmanaged(u64, usize),
    lock: std.Thread.RwLock,
    deinitialized: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, dim: usize, distance: Distance) InitError!Self {
        try validateDimension(dim);
        return .{
            .allocator = allocator,
            .dim = dim,
            .distance = distance,
            .entries = .{},
            .id_to_idx = .{},
            .lock = .{},
            .deinitialized = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.deinitialized) return;
        freeEntriesUnique(self.allocator, self.entries.items);
        self.entries.deinit(self.allocator);
        self.entries = .{};
        self.id_to_idx.deinit(self.allocator);
        self.id_to_idx = .{};
        self.deinitialized = true;
    }

    pub fn clear(self: *Self) void {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.deinitialized) return;
        freeEntriesUnique(self.allocator, self.entries.items);
        self.entries.clearRetainingCapacity();
        self.id_to_idx.clearRetainingCapacity();
    }

    pub fn reserve(self: *Self, additional: usize) UpsertError!void {
        self.lock.lock();
        defer self.lock.unlock();
        try self.ensureActiveUnlocked();
        const target = try checkedAdd(self.entries.items.len, additional);
        if (target > MAX_VECTOR_COUNT) return error.CountTooLarge;
        try self.entries.ensureTotalCapacity(self.allocator, target);
        try self.id_to_idx.ensureTotalCapacity(self.allocator, @intCast(target));
    }

    pub fn upsert(self: *Self, doc_id: u64, vector: []const f32) UpsertError!void {
        if (vector.len != self.dim) return error.VectorDimMismatch;
        _ = try validateStorageVector(vector);

        const dup = try self.allocator.dupe(f32, vector);
        var dup_owned = true;
        errdefer if (dup_owned) self.allocator.free(dup);

        self.lock.lock();
        defer self.lock.unlock();
        try self.ensureActiveUnlocked();

        if (self.id_to_idx.get(doc_id)) |idx| {
            if (idx >= self.entries.items.len) return error.IndexCorrupt;
            if (self.entries.items[idx].doc_id != doc_id) return error.IndexCorrupt;
            if (self.entries.items[idx].vector.len != self.dim) return error.IndexCorrupt;
            const old = self.entries.items[idx].vector;
            self.entries.items[idx] = .{
                .doc_id = doc_id,
                .vector = dup,
            };
            dup_owned = false;
            self.allocator.free(old);
            return;
        }

        const new_len = try checkedAdd(self.entries.items.len, 1);
        if (new_len > MAX_VECTOR_COUNT) return error.CountTooLarge;
        try self.entries.ensureTotalCapacity(self.allocator, new_len);
        try self.id_to_idx.ensureTotalCapacity(self.allocator, @intCast(new_len));
        const idx = self.entries.items.len;
        self.entries.appendAssumeCapacity(.{
            .doc_id = doc_id,
            .vector = dup,
        });
        dup_owned = false;
        self.id_to_idx.putAssumeCapacityNoClobber(doc_id, idx);
    }

    pub fn remove(self: *Self, doc_id: u64) bool {
        self.lock.lock();
        defer self.lock.unlock();
        if (self.deinitialized) return false;

        const idx = self.id_to_idx.get(doc_id) orelse return false;
        if (idx >= self.entries.items.len) {
            _ = self.id_to_idx.remove(doc_id);
            return false;
        }
        if (self.entries.items[idx].doc_id != doc_id) {
            _ = self.id_to_idx.remove(doc_id);
            return false;
        }

        const last_idx = self.entries.items.len - 1;
        const removed_vector = self.entries.items[idx].vector;
        _ = self.id_to_idx.remove(doc_id);

        if (idx != last_idx) {
            const moved = self.entries.items[last_idx];
            self.entries.items[idx] = moved;
            if (self.id_to_idx.getPtr(moved.doc_id)) |moved_idx| {
                moved_idx.* = idx;
            }
        }

        self.entries.items[last_idx] = emptyEntry();
        _ = self.entries.pop();
        self.allocator.free(removed_vector);
        return true;
    }

    pub fn search(self: *Self, allocator: std.mem.Allocator, query: []const f32, top_k: usize) SearchError![]SearchHit {
        if (query.len != self.dim) return error.VectorDimMismatch;
        const query_norm = try validateQueryVector(query, self.distance);
        try self.ensureActiveForRead();

        if (top_k == 0) return allocator.alloc(SearchHit, 0);

        const snapshot = try self.snapshotEntries(allocator);
        defer freeSnapshot(allocator, snapshot);

        if (snapshot.len == 0) return allocator.alloc(SearchHit, 0);

        const heap_capacity = @min(top_k, snapshot.len);
        var heap = try BoundedHitHeap.init(allocator, heap_capacity, self.distance);
        defer heap.deinit(allocator);

        for (snapshot) |entry| {
            const score = try scoreVectors(self.distance, entry.vector, query, query_norm);
            heap.push(.{
                .doc_id = entry.doc_id,
                .score = canonicalScore(score),
            });
        }

        return heap.toOwnedSortedSlice(allocator);
    }

    pub fn vectorCount(self: *Self) usize {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        if (self.deinitialized) return 0;
        return self.entries.items.len;
    }

    pub fn contains(self: *Self, doc_id: u64) bool {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        if (self.deinitialized) return false;
        return self.id_to_idx.get(doc_id) != null;
    }

    pub fn get(self: *Self, allocator: std.mem.Allocator, doc_id: u64) SearchError!?[]f32 {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        try self.ensureActiveUnlocked();
        const idx = self.id_to_idx.get(doc_id) orelse return null;
        if (idx >= self.entries.items.len) return error.IndexCorrupt;
        const entry = self.entries.items[idx];
        if (entry.doc_id != doc_id) return error.IndexCorrupt;
        if (entry.vector.len != self.dim) return error.IndexCorrupt;
        return try allocator.dupe(f32, entry.vector);
    }

    pub fn dimension(self: *const Self) usize {
        return self.dim;
    }

    pub fn distanceMetric(self: *const Self) Distance {
        return self.distance;
    }

    pub fn serialize(self: *Self, allocator: std.mem.Allocator) SerializeError![]u8 {
        const snapshot = try self.snapshotEntries(allocator);
        defer freeSnapshot(allocator, snapshot);

        std.mem.sort(SnapshotEntry, snapshot, {}, snapshotEntryLess);

        const total_size = try checkedSerializedSize(self.dim, snapshot.len);
        const record_payload_size = try checkedV2RecordPayloadSize(self.dim);
        const total_size_u64 = try usizeToU64(total_size);
        const dim_u64 = try usizeToU64(self.dim);
        const count_u64 = try usizeToU64(snapshot.len);
        const record_payload_size_u64 = try usizeToU64(record_payload_size);

        const out = try allocator.alloc(u8, total_size);
        errdefer allocator.free(out);

        var writer = ByteWriter.init(out);
        writer.writeU32(SERIALIZED_MAGIC);
        writer.writeU32(SERIALIZED_VERSION);
        writer.writeU64(dim_u64);
        writer.writeU32(@as(u32, @intFromEnum(self.distance)));
        writer.writeU64(count_u64);
        writer.writeU64(total_size_u64);
        writer.writeU64(0);

        for (snapshot) |entry| {
            if (entry.vector.len != self.dim) return error.IndexCorrupt;
            writer.writeU64(record_payload_size_u64);
            writer.writeU64(entry.doc_id);
            for (entry.vector) |value| {
                if (!std.math.isFinite(value)) return error.InvalidVector;
                writer.writeF32(value);
            }
        }

        if (writer.pos != total_size) return error.IndexCorrupt;

        const checksum = checksumSerialized(out);
        std.mem.writeInt(u64, out[SERIALIZED_CHECKSUM_OFFSET..][0..@sizeOf(u64)], checksum, .little);

        return out;
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) DeserializeError!Self {
        var reader = ByteReader.init(data);
        const magic = try reader.readU32();
        if (magic != SERIALIZED_MAGIC) return error.InvalidIndex;

        const version = try reader.readU32();
        if (version == 1) {
            return deserializeV1(allocator, data, &reader);
        }
        if (version == SERIALIZED_VERSION) {
            return deserializeV2(allocator, data, &reader);
        }
        return error.IncompatibleVersion;
    }

    fn ensureActiveUnlocked(self: *Self) VectorIndexError!void {
        if (self.deinitialized) return error.IndexDeinitialized;
    }

    fn ensureActiveForRead(self: *Self) VectorIndexError!void {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        try self.ensureActiveUnlocked();
    }

    fn snapshotEntries(self: *Self, allocator: std.mem.Allocator) SerializeError![]SnapshotEntry {
        self.lock.lockShared();
        defer self.lock.unlockShared();
        try self.ensureActiveUnlocked();

        const snapshot = try allocator.alloc(SnapshotEntry, self.entries.items.len);
        var initialized: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < initialized) : (i += 1) {
                allocator.free(snapshot[i].vector);
            }
            allocator.free(snapshot);
        }

        for (self.entries.items) |entry| {
            if (entry.vector.len != self.dim) return error.IndexCorrupt;
            if (self.id_to_idx.get(entry.doc_id)) |idx| {
                if (idx >= self.entries.items.len) return error.IndexCorrupt;
                if (self.entries.items[idx].doc_id != entry.doc_id) return error.IndexCorrupt;
            } else {
                return error.IndexCorrupt;
            }
            _ = try validateStorageVector(entry.vector);
            const dup = try allocator.dupe(f32, entry.vector);
            snapshot[initialized] = .{
                .doc_id = entry.doc_id,
                .vector = dup,
            };
            initialized += 1;
        }

        return snapshot;
    }
};

const BoundedHitHeap = struct {
    items: []SearchHit,
    len: usize,
    distance: Distance,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, distance: Distance) std.mem.Allocator.Error!BoundedHitHeap {
        return .{
            .items = try allocator.alloc(SearchHit, capacity),
            .len = 0,
            .distance = distance,
        };
    }

    pub fn deinit(self: *BoundedHitHeap, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        self.items = emptySearchHitSlice();
        self.len = 0;
        self.distance = .cosine;
    }

    pub fn push(self: *BoundedHitHeap, hit: SearchHit) void {
        if (self.items.len == 0) return;
        if (self.len < self.items.len) {
            self.items[self.len] = hit;
            self.len += 1;
            self.bubbleUp(self.len - 1);
            return;
        }
        if (isBetter(self.distance, hit, self.items[0])) {
            self.items[0] = hit;
            self.bubbleDown(0);
        }
    }

    fn bubbleUp(self: *BoundedHitHeap, start: usize) void {
        if (start >= self.len) return;
        var i = start;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (isBetter(self.distance, self.items[i], self.items[parent])) {
                std.mem.swap(SearchHit, &self.items[parent], &self.items[i]);
                i = parent;
            } else {
                break;
            }
        }
    }

    fn bubbleDown(self: *BoundedHitHeap, start: usize) void {
        if (start >= self.len) return;
        if (self.len < 2) return;
        var i = start;
        while (i <= (self.len - 2) / 2) {
            const left = i * 2 + 1;
            const right = left + 1;
            var worst = i;
            if (left < self.len and isWorse(self.distance, self.items[left], self.items[worst])) worst = left;
            if (right < self.len and isWorse(self.distance, self.items[right], self.items[worst])) worst = right;
            if (worst == i) break;
            std.mem.swap(SearchHit, &self.items[worst], &self.items[i]);
            i = worst;
        }
    }

    pub fn toOwnedSortedSlice(self: *BoundedHitHeap, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SearchHit {
        const out = try allocator.alloc(SearchHit, self.len);
        @memcpy(out, self.items[0..self.len]);
        if (out.len > 1) {
            std.mem.sort(SearchHit, out, self.distance, resultOrder);
        }
        return out;
    }
};

const ByteWriter = struct {
    data: []u8,
    pos: usize,

    fn init(data: []u8) ByteWriter {
        return .{
            .data = data,
            .pos = 0,
        };
    }

    fn writeU32(self: *ByteWriter, value: u32) void {
        std.mem.writeInt(u32, self.data[self.pos..][0..@sizeOf(u32)], value, .little);
        self.pos += @sizeOf(u32);
    }

    fn writeU64(self: *ByteWriter, value: u64) void {
        std.mem.writeInt(u64, self.data[self.pos..][0..@sizeOf(u64)], value, .little);
        self.pos += @sizeOf(u64);
    }

    fn writeF32(self: *ByteWriter, value: f32) void {
        const bits: u32 = @bitCast(value);
        self.writeU32(bits);
    }
};

const ByteReader = struct {
    data: []const u8,
    pos: usize,

    fn init(data: []const u8) ByteReader {
        return .{
            .data = data,
            .pos = 0,
        };
    }

    fn readU32(self: *ByteReader) VectorIndexError!u32 {
        try self.require(@sizeOf(u32));
        const value = std.mem.readInt(u32, self.data[self.pos..][0..@sizeOf(u32)], .little);
        self.pos += @sizeOf(u32);
        return value;
    }

    fn readU64(self: *ByteReader) VectorIndexError!u64 {
        try self.require(@sizeOf(u64));
        const value = std.mem.readInt(u64, self.data[self.pos..][0..@sizeOf(u64)], .little);
        self.pos += @sizeOf(u64);
        return value;
    }

    fn readF32(self: *ByteReader) VectorIndexError!f32 {
        const bits = try self.readU32();
        const value: f32 = @bitCast(bits);
        if (!std.math.isFinite(value)) return error.InvalidVector;
        return value;
    }

    fn require(self: *ByteReader, len: usize) VectorIndexError!void {
        if (len > self.data.len - self.pos) return error.InvalidIndex;
    }
};

fn deserializeV1(allocator: std.mem.Allocator, data: []const u8, reader: *ByteReader) DeserializeError!VectorIndex {
    const dim_u32 = try reader.readU32();
    const dim: usize = @intCast(dim_u32);
    try validateDimension(dim);

    const dist_val = try reader.readU32();
    const distance = try distanceFromWire(dist_val);

    const count_u64 = try reader.readU64();
    const count = try u64ToUsize(count_u64);
    if (count > MAX_VECTOR_COUNT) return error.CountTooLarge;

    const expected_size = try checkedV1SerializedSize(dim, count);
    if (data.len != expected_size) return error.InvalidIndex;

    var self = try VectorIndex.init(allocator, dim, distance);
    errdefer self.deinit();

    try self.entries.ensureTotalCapacity(self.allocator, count);
    try self.id_to_idx.ensureTotalCapacity(self.allocator, @intCast(count));

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const doc_id = try reader.readU64();
        if (self.id_to_idx.get(doc_id) != null) return error.DuplicateDocId;
        _ = try reader.readU32();

        const vec = try allocator.alloc(f32, dim);
        var vec_owned = true;
        errdefer if (vec_owned) allocator.free(vec);

        var j: usize = 0;
        while (j < dim) : (j += 1) {
            vec[j] = try reader.readF32();
        }

        _ = try validateStorageVector(vec);

        const idx = self.entries.items.len;
        self.entries.appendAssumeCapacity(.{
            .doc_id = doc_id,
            .vector = vec,
        });
        vec_owned = false;
        self.id_to_idx.putAssumeCapacityNoClobber(doc_id, idx);
    }

    if (reader.pos != data.len) return error.InvalidIndex;
    return self;
}

fn deserializeV2(allocator: std.mem.Allocator, data: []const u8, reader: *ByteReader) DeserializeError!VectorIndex {
    const dim_u64 = try reader.readU64();
    const dim = try u64ToUsize(dim_u64);
    try validateDimension(dim);

    const dist_val = try reader.readU32();
    const distance = try distanceFromWire(dist_val);

    const count_u64 = try reader.readU64();
    const count = try u64ToUsize(count_u64);
    if (count > MAX_VECTOR_COUNT) return error.CountTooLarge;

    const declared_len_u64 = try reader.readU64();
    const declared_len = try u64ToUsize(declared_len_u64);
    if (declared_len != data.len) return error.InvalidIndex;

    const declared_checksum = try reader.readU64();
    if (reader.pos != SERIALIZED_HEADER_SIZE) return error.InvalidIndex;
    if (checksumSerialized(data) != declared_checksum) return error.InvalidIndex;

    const expected_size = try checkedSerializedSize(dim, count);
    if (data.len != expected_size) return error.InvalidIndex;

    const expected_record_payload = try checkedV2RecordPayloadSize(dim);
    const expected_record_payload_u64 = try usizeToU64(expected_record_payload);

    var self = try VectorIndex.init(allocator, dim, distance);
    errdefer self.deinit();

    try self.entries.ensureTotalCapacity(self.allocator, count);
    try self.id_to_idx.ensureTotalCapacity(self.allocator, @intCast(count));

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const record_len = try reader.readU64();
        if (record_len != expected_record_payload_u64) return error.InvalidIndex;

        const doc_id = try reader.readU64();
        if (self.id_to_idx.get(doc_id) != null) return error.DuplicateDocId;

        const vec = try allocator.alloc(f32, dim);
        var vec_owned = true;
        errdefer if (vec_owned) allocator.free(vec);

        var j: usize = 0;
        while (j < dim) : (j += 1) {
            vec[j] = try reader.readF32();
        }

        _ = try validateStorageVector(vec);

        const idx = self.entries.items.len;
        self.entries.appendAssumeCapacity(.{
            .doc_id = doc_id,
            .vector = vec,
        });
        vec_owned = false;
        self.id_to_idx.putAssumeCapacityNoClobber(doc_id, idx);
    }

    if (reader.pos != data.len) return error.InvalidIndex;
    return self;
}

fn distanceFromWire(value: u32) VectorIndexError!Distance {
    return switch (value) {
        0 => .cosine,
        1 => .inner_product,
        2 => .euclidean,
        3 => .manhattan,
        else => error.InvalidDistance,
    };
}

fn snapshotEntryLess(_: void, a: SnapshotEntry, b: SnapshotEntry) bool {
    return a.doc_id < b.doc_id;
}

fn resultOrder(distance: Distance, a: SearchHit, b: SearchHit) bool {
    return isBetter(distance, a, b);
}

fn isBetter(distance: Distance, a: SearchHit, b: SearchHit) bool {
    if (a.score == b.score) return a.doc_id < b.doc_id;
    return switch (distance) {
        .cosine, .inner_product => a.score > b.score,
        .euclidean, .manhattan => a.score < b.score,
    };
}

fn isWorse(distance: Distance, a: SearchHit, b: SearchHit) bool {
    if (a.score == b.score) return a.doc_id > b.doc_id;
    return switch (distance) {
        .cosine, .inner_product => a.score < b.score,
        .euclidean, .manhattan => a.score > b.score,
    };
}

fn canonicalScore(score: f64) f64 {
    if (score == 0.0) return 0.0;
    return score;
}

fn validateDimension(dim: usize) VectorIndexError!void {
    if (dim == 0) return error.InvalidDimension;
    if (dim > MAX_DIMENSION) return error.InvalidDimension;
    if (@sizeOf(usize) > @sizeOf(u64)) {
        if (dim > std.math.maxInt(u64)) return error.InvalidDimension;
    }
}

fn validateStorageVector(v: []const f32) VectorIndexError!f64 {
    if (v.len == 0) return error.InvalidDimension;
    const norm = try computeNorm(v, error.InvalidVector);
    if (!std.math.isFinite(norm) or norm <= 0.0) return error.InvalidVector;
    return norm;
}

fn validateQueryVector(v: []const f32, distance: Distance) VectorIndexError!f64 {
    if (v.len == 0) return error.InvalidDimension;
    for (v) |x| {
        if (!std.math.isFinite(x)) return error.InvalidQuery;
    }
    if (distance == .cosine) {
        const norm = try computeNorm(v, error.InvalidQuery);
        if (!std.math.isFinite(norm) or norm <= 0.0) return error.InvalidQuery;
        return norm;
    }
    return 0.0;
}

inline fn scoreVectors(distance: Distance, entry: []const f32, query: []const f32, query_norm: f64) VectorIndexError!f64 {
    if (entry.len != query.len) return error.VectorDimMismatch;
    return switch (distance) {
        .cosine => cosineSimilarity(entry, query, query_norm),
        .inner_product => innerProduct(entry, query),
        .euclidean => euclideanDistance(entry, query),
        .manhattan => manhattanDistance(entry, query),
    };
}

inline fn computeNorm(v: []const f32, invalid_error: VectorIndexError) VectorIndexError!f64 {
    var scale: f64 = 0.0;
    var sumsq: f64 = 1.0;
    var any_nonzero = false;

    for (v) |x32| {
        if (!std.math.isFinite(x32)) return invalid_error;
        const x: f64 = @floatCast(x32);
        const ax = @abs(x);
        if (ax != 0.0) {
            any_nonzero = true;
            if (scale < ax) {
                const ratio = if (scale == 0.0) 0.0 else scale / ax;
                sumsq = 1.0 + sumsq * ratio * ratio;
                scale = ax;
            } else {
                const ratio = ax / scale;
                sumsq += ratio * ratio;
            }
        }
    }

    if (!any_nonzero) return 0.0;
    const norm = scale * @sqrt(sumsq);
    if (!std.math.isFinite(norm)) return error.NumericOverflow;
    return norm;
}

inline fn computeNormF64(v: []const f64) VectorIndexError!f64 {
    var scale: f64 = 0.0;
    var sumsq: f64 = 1.0;
    var any_nonzero = false;

    for (v) |x| {
        if (!std.math.isFinite(x)) return error.InvalidVector;
        const ax = @abs(x);
        if (ax != 0.0) {
            any_nonzero = true;
            if (scale < ax) {
                const ratio = if (scale == 0.0) 0.0 else scale / ax;
                sumsq = 1.0 + sumsq * ratio * ratio;
                scale = ax;
            } else {
                const ratio = ax / scale;
                sumsq += ratio * ratio;
            }
        }
    }

    if (!any_nonzero) return 0.0;
    const norm = scale * @sqrt(sumsq);
    if (!std.math.isFinite(norm)) return error.NumericOverflow;
    return norm;
}

inline fn cosineSimilarity(a: []const f32, b: []const f32, b_norm: f64) VectorIndexError!f64 {
    if (a.len != b.len) return error.VectorDimMismatch;
    const a_norm = try computeNorm(a, error.InvalidVector);
    if (a_norm <= 0.0 or b_norm <= 0.0) return error.InvalidVector;
    const dot = try innerProduct(a, b);
    var value = dot / a_norm / b_norm;
    if (!std.math.isFinite(value)) return error.NumericOverflow;
    if (value > 1.0) value = 1.0;
    if (value < -1.0) value = -1.0;
    return value;
}

inline fn innerProduct(a: []const f32, b: []const f32) VectorIndexError!f64 {
    if (a.len != b.len) return error.VectorDimMismatch;
    var sum: f64 = 0.0;
    var c: f64 = 0.0;

    for (a, 0..) |x32, i| {
        const product = @as(f64, @floatCast(x32)) * @as(f64, @floatCast(b[i]));
        const y = product - c;
        const t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }

    if (!std.math.isFinite(sum)) return error.NumericOverflow;
    return sum;
}

inline fn euclideanDistance(a: []const f32, b: []const f32) VectorIndexError!f64 {
    if (a.len != b.len) return error.VectorDimMismatch;
    var scale: f64 = 0.0;
    var sumsq: f64 = 1.0;
    var any_nonzero = false;

    for (a, 0..) |x32, i| {
        const diff = @as(f64, @floatCast(x32)) - @as(f64, @floatCast(b[i]));
        const ad = @abs(diff);
        if (ad != 0.0) {
            any_nonzero = true;
            if (scale < ad) {
                const ratio = if (scale == 0.0) 0.0 else scale / ad;
                sumsq = 1.0 + sumsq * ratio * ratio;
                scale = ad;
            } else {
                const ratio = ad / scale;
                sumsq += ratio * ratio;
            }
        }
    }

    if (!any_nonzero) return 0.0;
    const distance = scale * @sqrt(sumsq);
    if (!std.math.isFinite(distance)) return error.NumericOverflow;
    return distance;
}

inline fn manhattanDistance(a: []const f32, b: []const f32) VectorIndexError!f64 {
    if (a.len != b.len) return error.VectorDimMismatch;
    var sum: f64 = 0.0;
    var c: f64 = 0.0;

    for (a, 0..) |x32, i| {
        const value = @abs(@as(f64, @floatCast(x32)) - @as(f64, @floatCast(b[i])));
        const y = value - c;
        const t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }

    if (!std.math.isFinite(sum)) return error.NumericOverflow;
    return sum;
}

pub fn hashEmbed(allocator: std.mem.Allocator, text: []const u8, dim: usize) HashEmbedError![]f32 {
    try validateDimension(dim);
    if (@sizeOf(usize) > @sizeOf(u64)) {
        if (dim > std.math.maxInt(u64)) return error.InvalidDimension;
    }

    const counts = try allocator.alloc(f64, dim);
    defer allocator.free(counts);
    @memset(counts, 0.0);

    var token = std.ArrayList(u8).init(allocator);
    defer token.deinit();

    var i: usize = 0;
    var token_count: usize = 0;

    while (i < text.len) {
        const cp = try nextCodepoint(text, &i);
        if (isDelimiterCodepoint(cp)) {
            if (token.items.len > 0) {
                flushHashToken(counts, token.items, &token_count);
                token.clearRetainingCapacity();
            }
        } else {
            try appendUtf8(&token, foldCodepoint(cp));
        }
    }

    if (token.items.len > 0) {
        flushHashToken(counts, token.items, &token_count);
        token.clearRetainingCapacity();
    }

    if (token_count == 0) return error.EmptyEmbedding;

    const norm = try computeNormF64(counts);
    if (norm <= 0.0) return error.EmptyEmbedding;

    const out = try allocator.alloc(f32, dim);
    errdefer allocator.free(out);

    for (counts, 0..) |count, idx| {
        const normalized = count / norm;
        if (!std.math.isFinite(normalized)) return error.NumericOverflow;
        out[idx] = @as(f32, @floatCast(normalized));
    }

    return out;
}

fn flushHashToken(counts: []f64, token: []const u8, token_count: *usize) void {
    const dim_u64: u64 = @intCast(counts.len);
    const h1 = std.hash.Wyhash.hash(HASH_EMBED_SEED_INDEX, token);
    const h2 = std.hash.Wyhash.hash(HASH_EMBED_SEED_SIGN, token);
    const idx: usize = @intCast(h1 % dim_u64);
    const sign: f64 = if ((h2 & 1) == 0) 1.0 else -1.0;
    counts[idx] += sign;
    token_count.* += 1;
}

fn nextCodepoint(data: []const u8, index: *usize) VectorIndexError!u21 {
    if (index.* >= data.len) return error.InvalidUtf8;

    const b0 = data[index.*];
    if (b0 < 0x80) {
        index.* += 1;
        return @intCast(b0);
    }

    var cp: u32 = 0;
    var len: usize = 0;

    if (b0 >= 0xC2 and b0 <= 0xDF) {
        cp = @as(u32, b0 & 0x1F);
        len = 2;
    } else if (b0 >= 0xE0 and b0 <= 0xEF) {
        cp = @as(u32, b0 & 0x0F);
        len = 3;
    } else if (b0 >= 0xF0 and b0 <= 0xF4) {
        cp = @as(u32, b0 & 0x07);
        len = 4;
    } else {
        return error.InvalidUtf8;
    }

    if (index.* + len > data.len) return error.InvalidUtf8;

    var j: usize = 1;
    while (j < len) : (j += 1) {
        const bx = data[index.* + j];
        if ((bx & 0xC0) != 0x80) return error.InvalidUtf8;
        cp = (cp << 6) | @as(u32, bx & 0x3F);
    }

    if (len == 2 and cp < 0x80) return error.InvalidUtf8;
    if (len == 3 and cp < 0x800) return error.InvalidUtf8;
    if (len == 4 and cp < 0x10000) return error.InvalidUtf8;
    if (cp >= 0xD800 and cp <= 0xDFFF) return error.InvalidUtf8;
    if (cp > 0x10FFFF) return error.InvalidUtf8;

    index.* += len;
    return @intCast(cp);
}

fn appendUtf8(list: *std.ArrayList(u8), cp: u21) std.mem.Allocator.Error!void {
    if (cp <= 0x7F) {
        try list.append(@intCast(cp));
    } else if (cp <= 0x7FF) {
        try list.append(@intCast(0xC0 | (cp >> 6)));
        try list.append(@intCast(0x80 | (cp & 0x3F)));
    } else if (cp <= 0xFFFF) {
        try list.append(@intCast(0xE0 | (cp >> 12)));
        try list.append(@intCast(0x80 | ((cp >> 6) & 0x3F)));
        try list.append(@intCast(0x80 | (cp & 0x3F)));
    } else {
        try list.append(@intCast(0xF0 | (cp >> 18)));
        try list.append(@intCast(0x80 | ((cp >> 12) & 0x3F)));
        try list.append(@intCast(0x80 | ((cp >> 6) & 0x3F)));
        try list.append(@intCast(0x80 | (cp & 0x3F)));
    }
}

fn foldCodepoint(cp: u21) u21 {
    if (cp >= 'A' and cp <= 'Z') return cp + 32;
    if (cp >= 0x00C0 and cp <= 0x00D6) return cp + 32;
    if (cp >= 0x00D8 and cp <= 0x00DE) return cp + 32;
    if (cp == 0x0178) return 0x00FF;
    if (cp == 0x0386) return 0x03AC;
    if (cp == 0x0388) return 0x03AD;
    if (cp == 0x0389) return 0x03AE;
    if (cp == 0x038A) return 0x03AF;
    if (cp == 0x038C) return 0x03CC;
    if (cp == 0x038E) return 0x03CD;
    if (cp == 0x038F) return 0x03CE;
    if (cp >= 0x0391 and cp <= 0x03A1) return cp + 32;
    if (cp >= 0x03A3 and cp <= 0x03AB) return cp + 32;
    if (cp >= 0x0410 and cp <= 0x042F) return cp + 32;
    return cp;
}

fn isDelimiterCodepoint(cp: u21) bool {
    if (cp <= 0x2F) return true;
    if (cp >= 0x3A and cp <= 0x40) return true;
    if (cp >= 0x5B and cp <= 0x60) return true;
    if (cp >= 0x7B and cp <= 0x7F) return true;
    return switch (cp) {
        0x0085,
        0x00A0,
        0x1680,
        0x180E,
        0x2000...0x206F,
        0x2E00...0x2E7F,
        0x3000...0x303F,
        0xFE10...0xFE1F,
        0xFE30...0xFE4F,
        0xFF01...0xFF0F,
        0xFF1A...0xFF20,
        0xFF3B...0xFF40,
        0xFF5B...0xFF65,
        => true,
        else => false,
    };
}

fn checkedAdd(a: usize, b: usize) VectorIndexError!usize {
    return std.math.add(usize, a, b) catch error.SerializedSizeOverflow;
}

fn checkedMul(a: usize, b: usize) VectorIndexError!usize {
    return std.math.mul(usize, a, b) catch error.SerializedSizeOverflow;
}

fn checkedV2RecordPayloadSize(dim: usize) VectorIndexError!usize {
    const vector_bytes = try checkedMul(dim, @sizeOf(f32));
    return checkedAdd(@sizeOf(u64), vector_bytes);
}

fn checkedSerializedSize(dim: usize, count: usize) VectorIndexError!usize {
    const payload = try checkedV2RecordPayloadSize(dim);
    const record_total = try checkedAdd(@sizeOf(u64), payload);
    const records_total = try checkedMul(record_total, count);
    return checkedAdd(SERIALIZED_HEADER_SIZE, records_total);
}

fn checkedV1SerializedSize(dim: usize, count: usize) VectorIndexError!usize {
    const vector_bytes = try checkedMul(dim, @sizeOf(f32));
    const record_with_norm = try checkedAdd(try checkedAdd(@sizeOf(u64), @sizeOf(u32)), vector_bytes);
    const records_total = try checkedMul(record_with_norm, count);
    return checkedAdd(24, records_total);
}

fn usizeToU64(value: usize) VectorIndexError!u64 {
    if (@sizeOf(usize) > @sizeOf(u64)) {
        if (value > std.math.maxInt(u64)) return error.CountTooLarge;
    }
    return @intCast(value);
}

fn u64ToUsize(value: u64) VectorIndexError!usize {
    if (@sizeOf(usize) < @sizeOf(u64)) {
        if (value > @as(u64, std.math.maxInt(usize))) return error.CountTooLarge;
    }
    return @intCast(value);
}

fn checksumSerialized(data: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        if (i >= SERIALIZED_CHECKSUM_OFFSET and i < SERIALIZED_CHECKSUM_OFFSET + @sizeOf(u64)) continue;
        hash ^= data[i];
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn freeSnapshot(allocator: std.mem.Allocator, snapshot: []SnapshotEntry) void {
    for (snapshot) |entry| {
        allocator.free(entry.vector);
    }
    allocator.free(snapshot);
}

fn freeEntriesUnique(allocator: std.mem.Allocator, entries: []VectorEntry) void {
    for (entries, 0..) |*entry, i| {
        var seen = false;
        for (entries[0..i]) |previous| {
            if (previous.vector.ptr == entry.vector.ptr) {
                seen = true;
                break;
            }
        }
        if (!seen) allocator.free(entry.vector);
        entry.* = emptyEntry();
    }
}

fn emptyVectorSlice() []const f32 {
    return &[_]f32{};
}

fn emptySearchHitSlice() []SearchHit {
    return @constCast((&[_]SearchHit{})[0..]);
}

fn emptyEntry() VectorEntry {
    return .{
        .doc_id = 0,
        .vector = emptyVectorSlice(),
    };
}

test "vector cosine search" {
    const testing = std.testing;
    var idx = try VectorIndex.init(testing.allocator, 3, .cosine);
    defer idx.deinit();

    try idx.upsert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try idx.upsert(2, &[_]f32{ 0.0, 1.0, 0.0 });
    try idx.upsert(3, &[_]f32{ 0.7, 0.7, 0.0 });

    const hits = try idx.search(testing.allocator, &[_]f32{ 1.0, 0.1, 0.0 }, 3);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 3), hits.len);
    try testing.expectEqual(@as(u64, 1), hits[0].doc_id);
    try testing.expectEqual(@as(u64, 3), hits[1].doc_id);
    try testing.expectEqual(@as(u64, 2), hits[2].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 0.9950371902099893), hits[0].score, 0.000001);
}

test "vector serialize roundtrip" {
    const testing = std.testing;
    var idx = try VectorIndex.init(testing.allocator, 4, .inner_product);
    defer idx.deinit();

    try idx.upsert(10, &[_]f32{ 1, 2, 3, 4 });
    try idx.upsert(20, &[_]f32{ 0, 0, 1, 0 });

    const bytes = try idx.serialize(testing.allocator);
    defer testing.allocator.free(bytes);

    var idx2 = try VectorIndex.deserialize(testing.allocator, bytes);
    defer idx2.deinit();

    try testing.expectEqual(@as(usize, 2), idx2.vectorCount());
    try testing.expectEqual(@as(usize, 4), idx2.dimension());
    try testing.expectEqual(Distance.inner_product, idx2.distanceMetric());

    const vec = try idx2.get(testing.allocator, 10);
    defer if (vec) |owned| testing.allocator.free(owned);
    try testing.expect(vec != null);
    try testing.expectEqualSlices(f32, &[_]f32{ 1, 2, 3, 4 }, vec.?);

    const hits = try idx2.search(testing.allocator, &[_]f32{ 1, 0, 0, 0 }, 2);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 2), hits.len);
    try testing.expectEqual(@as(u64, 10), hits[0].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 1.0), hits[0].score, 0.000001);
}

test "top k boundaries and empty index" {
    const testing = std.testing;
    var idx = try VectorIndex.init(testing.allocator, 2, .inner_product);
    defer idx.deinit();

    const empty_hits = try idx.search(testing.allocator, &[_]f32{ 1, 0 }, 10);
    defer testing.allocator.free(empty_hits);
    try testing.expectEqual(@as(usize, 0), empty_hits.len);

    try idx.upsert(1, &[_]f32{ 1, 0 });
    try idx.upsert(2, &[_]f32{ 0, 1 });

    const zero_hits = try idx.search(testing.allocator, &[_]f32{ 1, 0 }, 0);
    defer testing.allocator.free(zero_hits);
    try testing.expectEqual(@as(usize, 0), zero_hits.len);

    const one_hit = try idx.search(testing.allocator, &[_]f32{ 1, 0 }, 1);
    defer testing.allocator.free(one_hit);
    try testing.expectEqual(@as(usize, 1), one_hit.len);
    try testing.expectEqual(@as(u64, 1), one_hit[0].doc_id);

    const many_hits = try idx.search(testing.allocator, &[_]f32{ 1, 0 }, 100);
    defer testing.allocator.free(many_hits);
    try testing.expectEqual(@as(usize, 2), many_hits.len);
}

test "remove update and map consistency" {
    const testing = std.testing;
    var idx = try VectorIndex.init(testing.allocator, 2, .inner_product);
    defer idx.deinit();

    try idx.upsert(1, &[_]f32{ 1, 0 });
    try idx.upsert(2, &[_]f32{ 0, 1 });
    try idx.upsert(3, &[_]f32{ 1, 1 });

    try testing.expect(idx.remove(1));
    try testing.expect(!idx.contains(1));
    try testing.expect(idx.contains(2));
    try testing.expect(idx.contains(3));
    try testing.expectEqual(@as(usize, 2), idx.vectorCount());

    try idx.upsert(2, &[_]f32{ 2, 0 });

    const hits = try idx.search(testing.allocator, &[_]f32{ 1, 0 }, 2);
    defer testing.allocator.free(hits);

    try testing.expectEqual(@as(usize, 2), hits.len);
    try testing.expectEqual(@as(u64, 2), hits[0].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 2.0), hits[0].score, 0.000001);

    try testing.expect(idx.remove(3));
    try testing.expect(idx.remove(2));
    try testing.expect(!idx.remove(2));
    try testing.expectEqual(@as(usize, 0), idx.vectorCount());
}

test "euclidean and manhattan return actual distances" {
    const testing = std.testing;

    var euclidean = try VectorIndex.init(testing.allocator, 2, .euclidean);
    defer euclidean.deinit();
    try euclidean.upsert(1, &[_]f32{ 1, 1 });
    try euclidean.upsert(2, &[_]f32{ 4, 5 });

    const euclidean_hits = try euclidean.search(testing.allocator, &[_]f32{ 1, 1 }, 2);
    defer testing.allocator.free(euclidean_hits);

    try testing.expectEqual(@as(u64, 1), euclidean_hits[0].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 0.0), euclidean_hits[0].score, 0.000001);
    try testing.expectEqual(@as(u64, 2), euclidean_hits[1].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 5.0), euclidean_hits[1].score, 0.000001);

    var manhattan = try VectorIndex.init(testing.allocator, 2, .manhattan);
    defer manhattan.deinit();
    try manhattan.upsert(1, &[_]f32{ 1, 1 });
    try manhattan.upsert(2, &[_]f32{ 4, 5 });

    const manhattan_hits = try manhattan.search(testing.allocator, &[_]f32{ 1, 1 }, 2);
    defer testing.allocator.free(manhattan_hits);

    try testing.expectEqual(@as(u64, 1), manhattan_hits[0].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 0.0), manhattan_hits[0].score, 0.000001);
    try testing.expectEqual(@as(u64, 2), manhattan_hits[1].doc_id);
    try testing.expectApproxEqAbs(@as(f64, 7.0), manhattan_hits[1].score, 0.000001);
}

test "validation errors" {
    const testing = std.testing;

    try testing.expectError(error.InvalidDimension, VectorIndex.init(testing.allocator, 0, .cosine));

    var idx = try VectorIndex.init(testing.allocator, 2, .cosine);
    defer idx.deinit();

    try testing.expectError(error.VectorDimMismatch, idx.upsert(1, &[_]f32{ 1 }));
    try testing.expectError(error.InvalidVector, idx.upsert(1, &[_]f32{ 0, 0 }));
    try testing.expectError(error.InvalidVector, idx.upsert(1, &[_]f32{ std.math.nan(f32), 1 }));
    try testing.expectError(error.InvalidVector, idx.upsert(1, &[_]f32{ std.math.inf(f32), 1 }));

    try idx.upsert(1, &[_]f32{ 1, 0 });
    try testing.expectError(error.InvalidQuery, idx.search(testing.allocator, &[_]f32{ 0, 0 }, 1));
    try testing.expectError(error.InvalidQuery, idx.search(testing.allocator, &[_]f32{ 1, std.math.nan(f32) }, 1));
}

test "deserialization errors" {
    const testing = std.testing;

    var invalid_magic = [_]u8{ 0, 0, 0, 0 };
    try testing.expectError(error.InvalidIndex, VectorIndex.deserialize(testing.allocator, &invalid_magic));

    var invalid_version = [_]u8{ 0x30, 0x43, 0x45, 0x56, 99, 0, 0, 0 };
    try testing.expectError(error.IncompatibleVersion, VectorIndex.deserialize(testing.allocator, &invalid_version));

    const invalid_distance = try makeV1Bytes(testing.allocator, 1, 99, 0, false, false);
    defer testing.allocator.free(invalid_distance);
    try testing.expectError(error.InvalidDistance, VectorIndex.deserialize(testing.allocator, invalid_distance));

    const trailing = try makeV1Bytes(testing.allocator, 1, 0, 0, false, false);
    defer testing.allocator.free(trailing);
    const trailing_copy = try testing.allocator.alloc(u8, trailing.len + 1);
    defer testing.allocator.free(trailing_copy);
    @memcpy(trailing_copy[0..trailing.len], trailing);
    trailing_copy[trailing.len] = 0;
    try testing.expectError(error.InvalidIndex, VectorIndex.deserialize(testing.allocator, trailing_copy));

    const duplicate = try makeV1Bytes(testing.allocator, 1, 0, 2, true, false);
    defer testing.allocator.free(duplicate);
    try testing.expectError(error.DuplicateDocId, VectorIndex.deserialize(testing.allocator, duplicate));

    const nonfinite = try makeV1Bytes(testing.allocator, 1, 0, 1, false, true);
    defer testing.allocator.free(nonfinite);
    try testing.expectError(error.InvalidVector, VectorIndex.deserialize(testing.allocator, nonfinite));
}

test "serialized output is deterministic after removal history" {
    const testing = std.testing;

    var a = try VectorIndex.init(testing.allocator, 2, .inner_product);
    defer a.deinit();
    try a.upsert(3, &[_]f32{ 3, 0 });
    try a.upsert(1, &[_]f32{ 1, 0 });
    try a.upsert(2, &[_]f32{ 2, 0 });
    try testing.expect(a.remove(1));
    try a.upsert(1, &[_]f32{ 1, 0 });

    var b = try VectorIndex.init(testing.allocator, 2, .inner_product);
    defer b.deinit();
    try b.upsert(1, &[_]f32{ 1, 0 });
    try b.upsert(2, &[_]f32{ 2, 0 });
    try b.upsert(3, &[_]f32{ 3, 0 });

    const bytes_a = try a.serialize(testing.allocator);
    defer testing.allocator.free(bytes_a);
    const bytes_b = try b.serialize(testing.allocator);
    defer testing.allocator.free(bytes_b);

    try testing.expect(std.mem.eql(u8, bytes_a, bytes_b));
}

test "hash embed" {
    const testing = std.testing;
    const emb = try hashEmbed(testing.allocator, "agdb is fast", 64);
    defer testing.allocator.free(emb);

    try testing.expectEqual(@as(usize, 64), emb.len);

    var any_nonzero = false;
    for (emb) |x| {
        if (x != 0) {
            any_nonzero = true;
            break;
        }
    }
    try testing.expect(any_nonzero);

    const norm = try computeNorm(emb, error.InvalidVector);
    try testing.expectApproxEqAbs(@as(f64, 1.0), norm, 0.000001);
}

test "hash embed tokenization and validation" {
    const testing = std.testing;

    const a = try hashEmbed(testing.allocator, "Foo-Bar/Baz", 32);
    defer testing.allocator.free(a);
    const b = try hashEmbed(testing.allocator, "foo bar baz", 32);
    defer testing.allocator.free(b);

    try testing.expectEqualSlices(f32, a, b);

    try testing.expectError(error.InvalidDimension, hashEmbed(testing.allocator, "x", 0));
    try testing.expectError(error.EmptyEmbedding, hashEmbed(testing.allocator, " \t\n.,;:!?()[]{}", 16));
    try testing.expectError(error.InvalidUtf8, hashEmbed(testing.allocator, &[_]u8{ 0xFF }, 16));
}

fn makeV1Bytes(allocator: std.mem.Allocator, dim: usize, dist: u32, count: usize, duplicate: bool, nonfinite: bool) ![]u8 {
    const size = try checkedV1SerializedSize(dim, count);
    const data = try allocator.alloc(u8, size);
    var writer = ByteWriter.init(data);
    writer.writeU32(SERIALIZED_MAGIC);
    writer.writeU32(1);
    writer.writeU32(@intCast(dim));
    writer.writeU32(dist);
    writer.writeU64(@intCast(count));

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const doc_id: u64 = if (duplicate) 7 else @intCast(i + 1);
        writer.writeU64(doc_id);
        writer.writeF32(std.math.nan(f32));
        var j: usize = 0;
        while (j < dim) : (j += 1) {
            if (nonfinite and i == 0 and j == 0) {
                writer.writeF32(std.math.inf(f32));
            } else {
                writer.writeF32(1.0);
            }
        }
    }

    return data;
}