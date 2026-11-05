const std = @import("std");

pub const ANS_SCALE_BITS: u32 = 12;
pub const ANS_SCALE: u32 = 1 << ANS_SCALE_BITS;
pub const ANS_SCALE_MASK: u64 = ANS_SCALE - 1;
pub const ANS_LOWER_BOUND: u64 = 1 << 23;
pub const ANS_UPPER_BOUND: u64 = ANS_LOWER_BOUND << 8;
pub const MAX_SYMBOLS: usize = 256;
pub const STATE_BYTES: usize = 4;
pub const LENGTH_FIELD_SIZE: usize = 4;
pub const TABLE_SIZE: usize = MAX_SYMBOLS * 2;
pub const HEADER_SIZE: usize = LENGTH_FIELD_SIZE + TABLE_SIZE;

pub const SymbolStats = struct {
    freq: [MAX_SYMBOLS]u32,
    cum_freq: [MAX_SYMBOLS + 1]u32,
    symbol_count: u32,

    pub fn init() SymbolStats {
        return std.mem.zeroes(SymbolStats);
    }

    pub fn countFrequencies(self: *SymbolStats, data: []const u8) void {
        var raw = [_]u64{0} ** MAX_SYMBOLS;
        for (data) |b| raw[b] += 1;

        const total: u64 = data.len;
        @memset(&self.freq, 0);
        if (total == 0) {
            @memset(&self.cum_freq, 0);
            self.symbol_count = 0;
            return;
        }

        var sum: u32 = 0;
        var active: u32 = 0;
        for (0..MAX_SYMBOLS) |i| {
            const r = raw[i];
            if (r == 0) continue;
            const scaled: u32 = @intCast((@as(u128, r) * ANS_SCALE) / total);
            const value: u32 = @max(scaled, 1);
            self.freq[i] = value;
            sum += value;
            active += 1;
        }
        self.symbol_count = active;

        while (sum < ANS_SCALE) {
            var best: usize = 0;
            var found = false;
            for (0..MAX_SYMBOLS) |i| {
                if (raw[i] == 0) continue;
                if (!found) {
                    best = i;
                    found = true;
                    continue;
                }
                const lhs = @as(u128, raw[i]) * self.freq[best];
                const rhs = @as(u128, raw[best]) * self.freq[i];
                if (lhs > rhs) best = i;
            }
            self.freq[best] += 1;
            sum += 1;
        }

        while (sum > ANS_SCALE) {
            var best: usize = 0;
            var found = false;
            for (0..MAX_SYMBOLS) |i| {
                if (self.freq[i] <= 1) continue;
                if (!found) {
                    best = i;
                    found = true;
                    continue;
                }
                const lhs = @as(u128, raw[i]) * (self.freq[best] - 1);
                const rhs = @as(u128, raw[best]) * (self.freq[i] - 1);
                if (lhs < rhs) best = i;
            }
            self.freq[best] -= 1;
            sum -= 1;
        }

        self.buildCumFreq();
    }

    pub fn buildCumFreq(self: *SymbolStats) void {
        self.cum_freq[0] = 0;
        for (0..MAX_SYMBOLS) |i| {
            self.cum_freq[i + 1] = self.cum_freq[i] + self.freq[i];
        }
    }

    pub fn validate(self: *const SymbolStats) bool {
        var sum: u32 = 0;
        for (0..MAX_SYMBOLS) |i| {
            const f = self.freq[i];
            if (f > ANS_SCALE) return false;
            if (self.cum_freq[i] != sum) return false;
            sum += f;
            if (sum > ANS_SCALE) return false;
        }
        return sum == ANS_SCALE and self.cum_freq[MAX_SYMBOLS] == sum;
    }

    pub fn serialize(self: *const SymbolStats, out: []u8) !usize {
        if (out.len < TABLE_SIZE) return error.BufferTooSmall;
        for (0..MAX_SYMBOLS) |i| {
            const v = std.math.cast(u16, self.freq[i]) orelse return error.InvalidFrequencyTable;
            std.mem.writeInt(u16, out[i * 2 ..][0..2], v, .little);
        }
        return TABLE_SIZE;
    }

    pub fn deserialize(self: *SymbolStats, data: []const u8) !void {
        if (data.len < TABLE_SIZE) return error.InvalidCompressedData;

        var parsed: [MAX_SYMBOLS]u32 = undefined;
        var sum: u32 = 0;
        var active: u32 = 0;
        for (0..MAX_SYMBOLS) |i| {
            const f: u32 = std.mem.readInt(u16, data[i * 2 ..][0..2], .little);
            if (f > ANS_SCALE) return error.InvalidFrequencyTable;
            sum += f;
            if (f > 0) active += 1;
            parsed[i] = f;
        }
        if (sum != ANS_SCALE) return error.InvalidFrequencyTable;

        self.freq = parsed;
        self.symbol_count = active;
        self.buildCumFreq();
    }
};

pub const SymbolLookup = struct {
    table: [ANS_SCALE]u8,

    pub fn build(self: *SymbolLookup, stats: *const SymbolStats) !void {
        if (!stats.validate()) return error.InvalidFrequencyTable;
        for (0..MAX_SYMBOLS) |i| {
            const f = stats.freq[i];
            if (f == 0) continue;
            const s: u8 = @intCast(i);
            const start: usize = stats.cum_freq[i];
            const end: usize = start + @as(usize, f);
            @memset(self.table[start..end], s);
        }
    }

    pub fn lookup(self: *const SymbolLookup, slot: u32) u8 {
        return self.table[slot];
    }
};

const ByteList = struct {
    items: []u8,
    len: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) ByteList {
        return .{
            .items = &.{},
            .len = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *ByteList) void {
        self.allocator.free(self.items);
        self.items = &.{};
        self.len = 0;
    }

    fn ensureUnused(self: *ByteList, extra: usize) !void {
        const needed = std.math.add(usize, self.len, extra) catch return error.OutOfMemory;
        if (needed <= self.items.len) return;
        var new_cap: usize = if (self.items.len == 0) 64 else self.items.len;
        while (new_cap < needed) {
            new_cap = std.math.mul(usize, new_cap, 2) catch needed;
        }
        self.items = try self.allocator.realloc(self.items, new_cap);
    }

    fn pushAssumeCapacity(self: *ByteList, byte: u8) void {
        self.items[self.len] = byte;
        self.len += 1;
    }
};

pub const RansEncoder = struct {
    state: u64,
    bytes: ByteList,
    allocator: std.mem.Allocator,
    stats: *const SymbolStats,

    pub fn init(allocator: std.mem.Allocator, stats: *const SymbolStats) RansEncoder {
        return .{
            .state = ANS_LOWER_BOUND,
            .bytes = ByteList.init(allocator),
            .allocator = allocator,
            .stats = stats,
        };
    }

    pub fn deinit(self: *RansEncoder) void {
        self.bytes.deinit();
    }

    pub fn encode(self: *RansEncoder, sym: u8) !void {
        const freq = self.stats.freq[sym];
        const cum = self.stats.cum_freq[sym];
        if (freq == 0) return error.SymbolNotInAlphabet;
        if (freq > ANS_SCALE) return error.InvalidFrequencyTable;

        try self.bytes.ensureUnused(4);

        const f: u64 = freq;
        const upper: u64 = (ANS_UPPER_BOUND >> ANS_SCALE_BITS) * f;
        var state = self.state;
        while (state >= upper) {
            self.bytes.pushAssumeCapacity(@intCast(state & 0xFF));
            state >>= 8;
        }
        self.state = (state / f) * ANS_SCALE + cum + (state % f);
    }

    pub fn encodedSize(self: *const RansEncoder) !usize {
        return std.math.add(usize, self.bytes.len, STATE_BYTES) catch return error.OutputTooLarge;
    }

    pub fn writeTo(self: *const RansEncoder, dest: []u8) !void {
        const total = try self.encodedSize();
        if (dest.len != total) return error.BufferSizeMismatch;
        if (self.state < ANS_LOWER_BOUND or self.state >= ANS_UPPER_BOUND) return error.CorruptStream;

        const state32: u32 = @intCast(self.state);
        std.mem.writeInt(u32, dest[0..STATE_BYTES], state32, .big);

        const n = self.bytes.len;
        for (0..n) |k| {
            dest[STATE_BYTES + k] = self.bytes.items[n - 1 - k];
        }
    }

    pub fn reset(self: *RansEncoder) void {
        self.bytes.len = 0;
        self.state = ANS_LOWER_BOUND;
    }

    pub fn flush(self: *RansEncoder) ![]u8 {
        const total = try self.encodedSize();
        const result = try self.allocator.alloc(u8, total);
        errdefer self.allocator.free(result);
        try self.writeTo(result);
        self.reset();
        return result;
    }
};

pub const RansDecoder = struct {
    state: u64,
    input: []const u8,
    pos: usize,
    stats: *const SymbolStats,
    table: SymbolLookup,

    pub fn init(encoded: []const u8, stats: *const SymbolStats) !RansDecoder {
        if (encoded.len < STATE_BYTES) return error.InvalidCompressedData;

        var self = RansDecoder{
            .state = 0,
            .input = encoded,
            .pos = STATE_BYTES,
            .stats = stats,
            .table = undefined,
        };
        try self.table.build(stats);

        const state: u64 = std.mem.readInt(u32, encoded[0..STATE_BYTES], .big);
        if (state < ANS_LOWER_BOUND or state >= ANS_UPPER_BOUND) return error.InvalidInitialState;
        self.state = state;
        return self;
    }

    pub fn decode(self: *RansDecoder) !u8 {
        if (self.state < ANS_LOWER_BOUND or self.state >= ANS_UPPER_BOUND) return error.CorruptStream;

        const slot: u32 = @intCast(self.state & ANS_SCALE_MASK);
        const sym = self.table.lookup(slot);
        const freq: u64 = self.stats.freq[sym];
        const cum: u64 = self.stats.cum_freq[sym];
        if (freq == 0 or slot < cum) return error.CorruptStream;

        var state: u64 = freq * (self.state >> ANS_SCALE_BITS) + slot - cum;
        while (state < ANS_LOWER_BOUND) {
            if (self.pos >= self.input.len) return error.TruncatedInput;
            state = (state << 8) | self.input[self.pos];
            self.pos += 1;
        }

        self.state = state;
        return sym;
    }

    pub fn isFinished(self: *const RansDecoder) bool {
        return self.state == ANS_LOWER_BOUND and self.pos == self.input.len;
    }
};

pub fn compress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const length = std.math.cast(u32, data.len) orelse return error.InputTooLarge;

    if (length == 0) {
        const empty_out = try allocator.alloc(u8, LENGTH_FIELD_SIZE);
        std.mem.writeInt(u32, empty_out[0..LENGTH_FIELD_SIZE], 0, .little);
        return empty_out;
    }

    var stats = SymbolStats.init();
    stats.countFrequencies(data);
    if (!stats.validate()) return error.InvalidFrequencyTable;

    var header_buf: [HEADER_SIZE]u8 = undefined;
    std.mem.writeInt(u32, header_buf[0..LENGTH_FIELD_SIZE], length, .little);
    _ = try stats.serialize(header_buf[LENGTH_FIELD_SIZE..]);

    var encoder = RansEncoder.init(allocator, &stats);
    defer encoder.deinit();

    var i: usize = data.len;
    while (i > 0) {
        i -= 1;
        try encoder.encode(data[i]);
    }

    const payload = try encoder.encodedSize();
    const total = std.math.add(usize, HEADER_SIZE, payload) catch return error.OutputTooLarge;
    const out = try allocator.alloc(u8, total);
    errdefer allocator.free(out);

    @memcpy(out[0..HEADER_SIZE], &header_buf);
    try encoder.writeTo(out[HEADER_SIZE..]);
    return out;
}

pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len < LENGTH_FIELD_SIZE) return error.InvalidCompressedData;

    const orig_len = std.mem.readInt(u32, data[0..LENGTH_FIELD_SIZE], .little);
    if (orig_len == 0) {
        if (data.len != LENGTH_FIELD_SIZE) return error.InvalidCompressedData;
        return try allocator.alloc(u8, 0);
    }

    const out_len = std.math.cast(usize, orig_len) orelse return error.OutputTooLarge;
    if (data.len < HEADER_SIZE) return error.InvalidCompressedData;

    var stats = SymbolStats.init();
    try stats.deserialize(data[LENGTH_FIELD_SIZE..HEADER_SIZE]);

    const encoded = data[HEADER_SIZE..];
    var decoder = try RansDecoder.init(encoded, &stats);

    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    var j: usize = 0;
    while (j < out_len) : (j += 1) {
        out[j] = try decoder.decode();
    }

    if (!decoder.isFinished()) return error.CorruptStream;
    return out;
}

fn slicesOverlap(a: []const u8, b: []const u8) bool {
    if (a.len == 0 or b.len == 0) return false;
    const a_start = @intFromPtr(a.ptr);
    const b_start = @intFromPtr(b.ptr);
    return a_start < b_start + b.len and b_start < a_start + a.len;
}

pub const WCBuffer = struct {
    buf: []align(64) u8,
    pos: usize,
    allocator: std.mem.Allocator,
    flush_target: ?[]u8,
    flush_offset: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, requested_capacity: usize) !WCBuffer {
        const requested = @max(requested_capacity, 1);
        const padded = std.math.add(usize, requested, 63) catch return error.CapacityOverflow;
        const aligned_cap = padded & ~@as(usize, 63);
        const buf = try allocator.alignedAlloc(u8, .@"64", aligned_cap);

        return Self{
            .buf = buf,
            .pos = 0,
            .allocator = allocator,
            .flush_target = null,
            .flush_offset = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buf);
        self.buf = self.buf[0..0];
        self.pos = 0;
        self.flush_target = null;
        self.flush_offset = 0;
    }

    pub fn capacity(self: *const Self) usize {
        return self.buf.len;
    }

    pub fn setTarget(self: *Self, target: []u8) !void {
        if (slicesOverlap(target, self.buf)) return error.OverlappingMemory;
        self.flush_target = target;
        self.flush_offset = 0;
    }

    pub fn clearTarget(self: *Self) void {
        self.flush_target = null;
        self.flush_offset = 0;
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.buf.len == 0) return error.BufferClosed;
        if (slicesOverlap(data, self.buf)) return error.OverlappingMemory;

        var written: usize = 0;
        while (written < data.len) {
            if (self.pos == self.buf.len) {
                self.flushToTarget() catch |err| {
                    if (written == 0) return err;
                    return written;
                };
            }
            const n = @min(data.len - written, self.buf.len - self.pos);
            @memcpy(self.buf[self.pos..][0..n], data[written..][0..n]);
            self.pos += n;
            written += n;
        }
        return written;
    }

    pub fn flushToTarget(self: *Self) !void {
        if (self.pos == 0) return;
        const target = self.flush_target orelse return error.NoFlushTarget;
        if (slicesOverlap(target, self.buf)) return error.OverlappingMemory;
        if (self.flush_offset > target.len or target.len - self.flush_offset < self.pos) {
            return error.FlushTargetFull;
        }
        @memcpy(target[self.flush_offset..][0..self.pos], self.buf[0..self.pos]);
        self.flush_offset += self.pos;
        self.pos = 0;
    }

    pub fn bytesBuffered(self: *const Self) usize {
        return self.pos;
    }

    pub fn bytesFlushed(self: *const Self) usize {
        return self.flush_offset;
    }
};
