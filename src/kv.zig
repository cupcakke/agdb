const std = @import("std");
const tsc = @import("tsc.zig");
const concurrency = @import("concurrency.zig");

pub const KvError = error{
    Corrupted,
    NotFound,
    IoError,
    KeyTooLong,
    ValueTooLong,
    AlreadyOpen,
    NotOpen,
};

const MAGIC: u32 = 0x4147_4442;
const VERSION: u16 = 1;
const HEADER_SIZE: u64 = 64;
const MAX_KEY_LEN: usize = 64 * 1024;
const MAX_VALUE_LEN: usize = 64 * 1024 * 1024;

const Op = enum(u8) {
    put = 1,
    delete = 2,
};

const RecordHeader = extern struct {
    magic: u32,
    op: u8,
    reserved: u8,
    key_len: u16,
    value_len: u32,
    timestamp_us: u64,
    crc32: u32,
    pad: u32,
};

const FileHeader = extern struct {
    magic: u32,
    version: u16,
    reserved: u16,
    created_at: u64,
    schema_id: u64,
    last_offset: u64,
    record_count: u64,
    flags: u64,
    pad: [16]u8,
};

pub const Entry = struct {
    offset: u64,
    value_offset: u64,
    value_len: u32,
    key_len: u16,
};

pub const KvFaultKind = enum(u8) {
    none,
    drop_write,
    corrupt_on_write,
    power_off,
};

pub const KvFaultSpec = struct {
    kind: KvFaultKind = .none,
    trigger_key: ?[]const u8 = null,
    armed: bool = false,
};

pub const SimKvBackend = struct {
    data: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    fault: KvFaultSpec,

    pub fn init(allocator: std.mem.Allocator) SimKvBackend {
        return .{
            .data = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .fault = .{},
        };
    }

    pub fn deinit(self: *SimKvBackend) void {
        self.data.deinit();
    }

    pub fn armFault(self: *SimKvBackend, spec: KvFaultSpec) void {
        self.fault = spec;
        self.fault.armed = true;
    }

    pub fn disarmFault(self: *SimKvBackend) void {
        self.fault.armed = false;
        self.fault.kind = .none;
    }

    pub fn size(self: *const SimKvBackend) u64 {
        return @intCast(self.data.items.len);
    }

    pub fn seekAndWrite(self: *SimKvBackend, offset: u64, buf: []const u8) !void {
        const end: usize = @intCast(offset + @as(u64, @intCast(buf.len)));
        if (end > self.data.items.len) {
            const needed = end - self.data.items.len;
            try self.data.appendNTimes(0, needed);
        }
        @memcpy(self.data.items[@intCast(offset)..end], buf);
    }

    pub fn seekAndRead(self: *const SimKvBackend, offset: u64, out: []u8) !usize {
        const start: usize = @intCast(offset);
        if (start >= self.data.items.len) return 0;
        const available = self.data.items.len - start;
        const to_copy = @min(available, out.len);
        @memcpy(out[0..to_copy], self.data.items[start .. start + to_copy]);
        return to_copy;
    }

    pub fn truncate(self: *SimKvBackend, new_size: u64) void {
        const sz: usize = @intCast(new_size);
        if (sz < self.data.items.len) {
            self.data.shrinkAndFree(sz);
        }
    }

    pub fn sync(self: *SimKvBackend) !void {
        _ = self;
    }
};

const IoBackend = union(enum) {
    file: std.fs.File,
    sim: *SimKvBackend,

    pub fn write(self: *IoBackend, offset: u64, buf: []const u8) !void {
        switch (self.*) {
            .file => |f| {
                try f.seekTo(offset);
                try f.writeAll(buf);
            },
            .sim => |s| try s.seekAndWrite(offset, buf),
        }
    }

    pub fn read(self: *IoBackend, offset: u64, buf: []u8) !usize {
        switch (self.*) {
            .file => |f| {
                try f.seekTo(offset);
                return try f.readAll(buf);
            },
            .sim => |s| return try s.seekAndRead(offset, buf),
        }
    }

    pub fn sync(self: *IoBackend) !void {
        switch (self.*) {
            .file => |f| try f.sync(),
            .sim => |s| try s.sync(),
        }
    }

    pub fn currentSize(self: *const IoBackend) u64 {
        switch (self.*) {
            .file => |f| {
                const stat = f.stat() catch return 0;
                return stat.size;
            },
            .sim => |s| return s.size(),
        }
    }

    pub fn truncateTo(self: *IoBackend, new_size: u64) !void {
        switch (self.*) {
            .file => |f| try f.setEndPos(new_size),
            .sim => |s| s.truncate(new_size),
        }
    }
};

pub const KvStore = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    io: IoBackend,
    file_size: u64,
    header: FileHeader,
    index: std.StringHashMapUnmanaged(Entry),
    keys_arena: std.heap.ArenaAllocator,
    mutex: std.Thread.Mutex,
    schema_id: u64,
    record_count: u64,
    dead_bytes: u64,

    const Self = @This();

    pub fn open(allocator: std.mem.Allocator, path: []const u8, schema_id: u64) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const path_dup = try allocator.dupe(u8, path);
        errdefer allocator.free(path_dup);

        var keys_arena = std.heap.ArenaAllocator.init(allocator);
        errdefer keys_arena.deinit();

        if (tsc.is_simulation) {
            const sim = try allocator.create(SimKvBackend);
            errdefer allocator.destroy(sim);
            sim.* = SimKvBackend.init(allocator);
            errdefer sim.deinit();

            self.* = .{
                .allocator = allocator,
                .path = path_dup,
                .io = .{ .sim = sim },
                .file_size = 0,
                .header = undefined,
                .index = .{},
                .keys_arena = keys_arena,
                .mutex = .{},
                .schema_id = schema_id,
                .record_count = 0,
                .dead_bytes = 0,
            };

            try self.writeNewHeader();
            return self;
        }

        const file_existed = blk: {
            std.fs.cwd().access(path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        const file = std.fs.cwd().createFile(path, .{ .read = true, .truncate = false }) catch |err| switch (err) {
            error.PathAlreadyExists => try std.fs.cwd().openFile(path, .{ .mode = .read_write }),
            else => return err,
        };
        errdefer file.close();

        self.* = .{
            .allocator = allocator,
            .path = path_dup,
            .io = .{ .file = file },
            .file_size = 0,
            .header = undefined,
            .index = .{},
            .keys_arena = keys_arena,
            .mutex = .{},
            .schema_id = schema_id,
            .record_count = 0,
            .dead_bytes = 0,
        };

        const stat = try file.stat();
        self.file_size = stat.size;

        if (!file_existed or self.file_size == 0) {
            try self.writeNewHeader();
        } else {
            try self.readAndRepairHeader();
            try self.replayLog();
        }

        return self;
    }

    pub fn close(self: *Self) void {
        switch (self.io) {
            .file => |f| f.close(),
            .sim => |s| {
                s.deinit();
                self.allocator.destroy(s);
            },
        }
        self.index.deinit(self.allocator);
        self.keys_arena.deinit();
        self.allocator.free(self.path);
        const a = self.allocator;
        a.destroy(self);
    }

    pub fn getSimBackend(self: *Self) ?*SimKvBackend {
        if (self.io == .sim) return self.io.sim;
        return null;
    }

    fn writeNewHeader(self: *Self) !void {
        var hdr = FileHeader{
            .magic = MAGIC,
            .version = VERSION,
            .reserved = 0,
            .created_at = @intCast(std.time.microTimestamp()),
            .schema_id = self.schema_id,
            .last_offset = HEADER_SIZE,
            .record_count = 0,
            .flags = 0,
            .pad = [_]u8{0} ** 16,
        };
        self.header = hdr;
        const buf: *[@sizeOf(FileHeader)]u8 = @ptrCast(&hdr);
        try self.io.write(0, buf[0..@sizeOf(FileHeader)]);
        const pad_count = HEADER_SIZE - @sizeOf(FileHeader);
        if (pad_count > 0) {
            const pad_bytes = try self.allocator.alloc(u8, pad_count);
            defer self.allocator.free(pad_bytes);
            @memset(pad_bytes, 0);
            try self.io.write(@sizeOf(FileHeader), pad_bytes);
        }
        try self.io.sync();
        self.file_size = HEADER_SIZE;
    }

    fn readAndRepairHeader(self: *Self) !void {
        var hdr: FileHeader = undefined;
        const hdr_buf: *[@sizeOf(FileHeader)]u8 = @ptrCast(&hdr);
        const n = try self.io.read(0, hdr_buf);
        if (n < @sizeOf(FileHeader)) return KvError.Corrupted;
        if (hdr.magic != MAGIC) return KvError.Corrupted;
        if (hdr.version != VERSION) return KvError.Corrupted;
        if (self.schema_id != 0 and hdr.schema_id != 0 and hdr.schema_id != self.schema_id) return KvError.Corrupted;
        if (hdr.schema_id == 0 and self.schema_id != 0) {
            hdr.schema_id = self.schema_id;
            try self.flushHeader(&hdr);
        }
        self.header = hdr;
        if (self.header.last_offset > self.file_size) {
            self.header.last_offset = self.file_size;
            try self.flushHeader(&self.header);
        }
    }

    fn flushHeader(self: *Self, hdr: *FileHeader) !void {
        const buf: *[@sizeOf(FileHeader)]u8 = @ptrCast(hdr);
        try self.io.write(0, buf[0..@sizeOf(FileHeader)]);
    }

    fn replayLog(self: *Self) !void {
        var pos: u64 = HEADER_SIZE;
        const max_pos = self.header.last_offset;
        while (pos + @sizeOf(RecordHeader) <= max_pos) {
            var rec: RecordHeader = undefined;
            const rec_buf: *[@sizeOf(RecordHeader)]u8 = @ptrCast(&rec);
            const read_n = try self.io.read(pos, rec_buf);
            if (read_n < @sizeOf(RecordHeader)) break;
            if (rec.magic != MAGIC) {
                pos += 1;
                continue;
            }
            const key_len: usize = rec.key_len;
            const value_len: usize = rec.value_len;
            const record_body_size: u64 = @as(u64, key_len) + @as(u64, value_len);
            const total_size: u64 = @sizeOf(RecordHeader) + record_body_size;
            if (pos + total_size > max_pos) break;
            if (key_len > MAX_KEY_LEN or value_len > MAX_VALUE_LEN) {
                pos += 1;
                continue;
            }

            const key_bytes = try self.allocator.alloc(u8, key_len);
            defer self.allocator.free(key_bytes);
            const got_k = try self.io.read(pos + @sizeOf(RecordHeader), key_bytes);
            if (got_k < key_len) break;

            const value_buf = try self.allocator.alloc(u8, value_len);
            defer self.allocator.free(value_buf);
            const got_v: usize = if (value_len == 0) 0 else try self.io.read(pos + @sizeOf(RecordHeader) + key_len, value_buf);
            if (got_v < value_len) break;

            const expected_crc = computeCrc(rec.op, key_bytes, value_buf, rec.timestamp_us);
            if (expected_crc != rec.crc32) {
                pos += 1;
                continue;
            }

            const value_offset = pos + @sizeOf(RecordHeader) + key_len;
            switch (@as(Op, @enumFromInt(rec.op))) {
                .put => {
                    const gop = try self.index.getOrPut(self.allocator, key_bytes);
                    if (gop.found_existing) {
                        self.dead_bytes += gop.value_ptr.value_len + @sizeOf(RecordHeader) + gop.value_ptr.key_len;
                    } else {
                        const interned_key = try self.keys_arena.allocator().dupe(u8, key_bytes);
                        gop.key_ptr.* = interned_key;
                        self.record_count += 1;
                    }
                    gop.value_ptr.* = Entry{
                        .offset = pos,
                        .value_offset = value_offset,
                        .value_len = rec.value_len,
                        .key_len = rec.key_len,
                    };
                },
                .delete => {
                    if (self.index.fetchRemove(key_bytes)) |kv| {
                        self.dead_bytes += kv.value.value_len + @sizeOf(RecordHeader) + kv.value.key_len;
                        if (self.record_count > 0) self.record_count -= 1;
                    }
                    self.dead_bytes += @sizeOf(RecordHeader) + key_len;
                },
            }
            pos += total_size;
        }
        if (pos != self.header.last_offset) {
            self.header.last_offset = pos;
            try self.flushHeader(&self.header);
            try self.io.truncateTo(pos);
            self.file_size = pos;
        }
    }

    fn computeCrc(op: u8, key: []const u8, value: []const u8, ts: u64) u32 {
        var crc = std.hash.Crc32.init();
        crc.update(&[_]u8{op});
        var ts_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &ts_bytes, ts, .little);
        crc.update(&ts_bytes);
        crc.update(key);
        crc.update(value);
        return crc.final();
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        if (key.len > MAX_KEY_LEN) return KvError.KeyTooLong;
        if (value.len > MAX_VALUE_LEN) return KvError.ValueTooLong;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (tsc.is_simulation) {
            if (self.io == .sim) {
                if (self.io.sim.fault.armed) {
                    const fault_key = self.io.sim.fault.trigger_key;
                    const matches = if (fault_key) |fk| std.mem.eql(u8, fk, key) else true;
                    if (matches) {
                        switch (self.io.sim.fault.kind) {
                            .drop_write => {
                                self.io.sim.fault.armed = false;
                                return;
                            },
                            .power_off => {
                                self.io.sim.fault.armed = false;
                                return error.SimulatedPowerOff;
                            },
                            .corrupt_on_write => {
                                self.io.sim.fault.armed = false;
                            },
                            .none => {},
                        }
                    }
                }
            }
            concurrency.FiberScheduler.yield();
        }

        const ts: u64 = @intCast(tsc.virtualTimestampUs());
        var rec = RecordHeader{
            .magic = MAGIC,
            .op = @intFromEnum(Op.put),
            .reserved = 0,
            .key_len = @intCast(key.len),
            .value_len = @intCast(value.len),
            .timestamp_us = ts,
            .crc32 = 0,
            .pad = 0,
        };
        rec.crc32 = computeCrc(rec.op, key, value, ts);

        const offset = self.header.last_offset;
        const hdr_bytes: *[@sizeOf(RecordHeader)]u8 = @ptrCast(&rec);
        try self.io.write(offset, hdr_bytes);
        try self.io.write(offset + @sizeOf(RecordHeader), key);
        if (value.len > 0) try self.io.write(offset + @sizeOf(RecordHeader) + key.len, value);
        try self.io.sync();

        const total: u64 = @sizeOf(RecordHeader) + key.len + value.len;
        const value_offset = offset + @sizeOf(RecordHeader) + key.len;

        const gop = try self.index.getOrPut(self.allocator, key);
        if (gop.found_existing) {
            self.dead_bytes += gop.value_ptr.value_len + @sizeOf(RecordHeader) + gop.value_ptr.key_len;
        } else {
            const interned_key = try self.keys_arena.allocator().dupe(u8, key);
            gop.key_ptr.* = interned_key;
            self.record_count += 1;
        }
        gop.value_ptr.* = Entry{
            .offset = offset,
            .value_offset = value_offset,
            .value_len = rec.value_len,
            .key_len = rec.key_len,
        };

        self.header.last_offset = offset + total;
        self.header.record_count = self.record_count;
        try self.flushHeader(&self.header);
        try self.io.sync();
        self.file_size = self.header.last_offset;
    }

    pub fn get(self: *Self, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.index.get(key) orelse return null;
        if (entry.value_len == 0) {
            const out = try allocator.alloc(u8, 0);
            return out;
        }
        const buf = try allocator.alloc(u8, entry.value_len);
        errdefer allocator.free(buf);
        const n = try self.io.read(entry.value_offset, buf);
        if (n < entry.value_len) return KvError.Corrupted;
        return buf;
    }

    pub fn contains(self: *Self, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.index.contains(key);
    }

    pub fn delete(self: *Self, key: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const existed = self.index.contains(key);
        if (!existed) return false;

        if (tsc.is_simulation) {
            concurrency.FiberScheduler.yield();
        }

        const ts: u64 = @intCast(tsc.virtualTimestampUs());
        var rec = RecordHeader{
            .magic = MAGIC,
            .op = @intFromEnum(Op.delete),
            .reserved = 0,
            .key_len = @intCast(key.len),
            .value_len = 0,
            .timestamp_us = ts,
            .crc32 = 0,
            .pad = 0,
        };
        rec.crc32 = computeCrc(rec.op, key, &[_]u8{}, ts);

        const offset = self.header.last_offset;
        const hdr_bytes: *[@sizeOf(RecordHeader)]u8 = @ptrCast(&rec);
        try self.io.write(offset, hdr_bytes);
        try self.io.write(offset + @sizeOf(RecordHeader), key);
        try self.io.sync();

        if (self.index.fetchRemove(key)) |kv| {
            self.dead_bytes += kv.value.value_len + @sizeOf(RecordHeader) + kv.value.key_len;
            if (self.record_count > 0) self.record_count -= 1;
        }
        self.dead_bytes += @sizeOf(RecordHeader) + key.len;

        self.header.last_offset = offset + @sizeOf(RecordHeader) + key.len;
        self.header.record_count = self.record_count;
        try self.flushHeader(&self.header);
        try self.io.sync();
        self.file_size = self.header.last_offset;
        return true;
    }

    pub fn count(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.record_count;
    }

    pub fn diskSize(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.file_size;
    }

    pub fn countWithPrefix(self: *Self, prefix: []const u8) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        var matched_count: u64 = 0;
        var it = self.index.iterator();
        while (it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) matched_count += 1;
        }
        return matched_count;
    }

    pub fn keysWithPrefix(self: *Self, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var keys = std.ArrayList([]u8).init(allocator);
        errdefer {
            for (keys.items) |key| allocator.free(key);
            keys.deinit();
        }

        var it = self.index.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (!std.mem.startsWith(u8, key, prefix)) continue;
            const key_copy = try allocator.dupe(u8, key);
            keys.append(key_copy) catch |err| {
                allocator.free(key_copy);
                return err;
            };
        }
        return keys.toOwnedSlice();
    }

    pub fn deadBytes(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.dead_bytes;
    }

    pub fn flush(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.io.sync();
    }

    pub const KeyValue = struct {
        key: []const u8,
        value: []u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *KeyValue) void {
            self.allocator.free(self.key);
            self.allocator.free(self.value);
        }
    };

    pub const Iterator = struct {
        items: []KeyValue,
        index: usize,
        allocator: std.mem.Allocator,

        pub fn next(self: *Iterator) !?KeyValue {
            if (self.index >= self.items.len) return null;
            const item = self.items[self.index];
            self.index += 1;
            return item;
        }

        pub fn deinit(self: *Iterator) void {
            var i: usize = self.index;
            while (i < self.items.len) : (i += 1) {
                self.allocator.free(self.items[i].key);
                self.allocator.free(self.items[i].value);
            }
            self.allocator.free(self.items);
            self.items = &[_]KeyValue{};
            self.index = 0;
        }
    };

    pub fn iterator(self: *Self) !Iterator {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry_count = self.index.count();
        const items = try self.allocator.alloc(KeyValue, entry_count);
        var produced: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < produced) : (i += 1) {
                self.allocator.free(items[i].key);
                self.allocator.free(items[i].value);
            }
            self.allocator.free(items);
        }

        var it = self.index.iterator();
        while (it.next()) |entry| {
            const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key_copy);
            const value_buf = try self.allocator.alloc(u8, entry.value_ptr.value_len);
            errdefer self.allocator.free(value_buf);
            if (entry.value_ptr.value_len > 0) {
                const n = try self.io.read(entry.value_ptr.value_offset, value_buf);
                if (n < entry.value_ptr.value_len) return KvError.Corrupted;
            }
            items[produced] = KeyValue{
                .key = key_copy,
                .value = value_buf,
                .allocator = self.allocator,
            };
            produced += 1;
        }

        return Iterator{
            .items = items,
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn compact(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.io == .sim) {
            var new_sim = SimKvBackend.init(self.allocator);
            errdefer new_sim.deinit();

            var new_header = FileHeader{
                .magic = MAGIC,
                .version = VERSION,
                .reserved = 0,
                .created_at = self.header.created_at,
                .schema_id = self.schema_id,
                .last_offset = HEADER_SIZE,
                .record_count = 0,
                .flags = 0,
                .pad = [_]u8{0} ** 16,
            };
            const hdr_bytes: *[@sizeOf(FileHeader)]u8 = @ptrCast(&new_header);
            try new_sim.seekAndWrite(0, hdr_bytes);
            const pad_count = HEADER_SIZE - @sizeOf(FileHeader);
            if (pad_count > 0) {
                const zeros = try self.allocator.alloc(u8, pad_count);
                defer self.allocator.free(zeros);
                @memset(zeros, 0);
                try new_sim.seekAndWrite(@sizeOf(FileHeader), zeros);
            }

            var offset: u64 = HEADER_SIZE;
            var count_after: u64 = 0;

            var new_keys_arena = std.heap.ArenaAllocator.init(self.allocator);
            errdefer new_keys_arena.deinit();
            var new_index: std.StringHashMapUnmanaged(Entry) = .{};
            errdefer new_index.deinit(self.allocator);

            var it = self.index.iterator();
            while (it.next()) |kv_entry| {
                const key = kv_entry.key_ptr.*;
                const ventry = kv_entry.value_ptr.*;
                const value_buf = try self.allocator.alloc(u8, ventry.value_len);
                defer self.allocator.free(value_buf);
                if (ventry.value_len > 0) {
                    const got = try self.io.read(ventry.value_offset, value_buf);
                    if (got < ventry.value_len) return KvError.Corrupted;
                }
                const ts: u64 = @intCast(tsc.virtualTimestampUs());
                var rec = RecordHeader{
                    .magic = MAGIC,
                    .op = @intFromEnum(Op.put),
                    .reserved = 0,
                    .key_len = @intCast(key.len),
                    .value_len = ventry.value_len,
                    .timestamp_us = ts,
                    .crc32 = 0,
                    .pad = 0,
                };
                rec.crc32 = computeCrc(rec.op, key, value_buf, ts);
                const rec_bytes: *[@sizeOf(RecordHeader)]u8 = @ptrCast(&rec);
                try new_sim.seekAndWrite(offset, rec_bytes);
                try new_sim.seekAndWrite(offset + @sizeOf(RecordHeader), key);
                if (ventry.value_len > 0) try new_sim.seekAndWrite(offset + @sizeOf(RecordHeader) + key.len, value_buf);

                const new_value_offset = offset + @sizeOf(RecordHeader) + key.len;
                const interned_key = try new_keys_arena.allocator().dupe(u8, key);
                try new_index.put(self.allocator, interned_key, Entry{
                    .offset = offset,
                    .value_offset = new_value_offset,
                    .value_len = ventry.value_len,
                    .key_len = @intCast(key.len),
                });
                offset += @sizeOf(RecordHeader) + key.len + ventry.value_len;
                count_after += 1;
            }

            new_header.last_offset = offset;
            new_header.record_count = count_after;
            const new_hdr_bytes: *[@sizeOf(FileHeader)]u8 = @ptrCast(&new_header);
            try new_sim.seekAndWrite(0, new_hdr_bytes);

            self.io.sim.deinit();
            self.allocator.destroy(self.io.sim);
            const new_sim_ptr = try self.allocator.create(SimKvBackend);
            new_sim_ptr.* = new_sim;
            self.io = .{ .sim = new_sim_ptr };
            self.file_size = offset;
            self.header = new_header;
            self.index.deinit(self.allocator);
            self.keys_arena.deinit();
            self.index = new_index;
            self.keys_arena = new_keys_arena;
            self.record_count = count_after;
            self.dead_bytes = 0;
            return;
        }

        const tmp_path = try std.fmt.allocPrint(self.allocator, "{s}.compact", .{self.path});
        defer self.allocator.free(tmp_path);
        std.fs.cwd().deleteFile(tmp_path) catch {};

        var tmp = try std.fs.cwd().createFile(tmp_path, .{ .read = true });
        var tmp_open = true;
        errdefer {
            if (tmp_open) tmp.close();
            std.fs.cwd().deleteFile(tmp_path) catch {};
        }

        var new_header = FileHeader{
            .magic = MAGIC,
            .version = VERSION,
            .reserved = 0,
            .created_at = self.header.created_at,
            .schema_id = self.schema_id,
            .last_offset = HEADER_SIZE,
            .record_count = 0,
            .flags = 0,
            .pad = [_]u8{0} ** 16,
        };
        const hdr_bytes: *[@sizeOf(FileHeader)]u8 = @ptrCast(&new_header);
        try tmp.writeAll(hdr_bytes);
        const pad_count = HEADER_SIZE - @sizeOf(FileHeader);
        if (pad_count > 0) {
            const pad_bytes = try self.allocator.alloc(u8, pad_count);
            defer self.allocator.free(pad_bytes);
            @memset(pad_bytes, 0);
            try tmp.writeAll(pad_bytes);
        }

        var offset: u64 = HEADER_SIZE;
        var count_after: u64 = 0;

        var new_keys_arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer new_keys_arena.deinit();
        var new_index: std.StringHashMapUnmanaged(Entry) = .{};
        errdefer new_index.deinit(self.allocator);

        var it = self.index.iterator();
        while (it.next()) |kv_entry| {
            const key = kv_entry.key_ptr.*;
            const ventry = kv_entry.value_ptr.*;
            const value_buf = try self.allocator.alloc(u8, ventry.value_len);
            defer self.allocator.free(value_buf);
            if (ventry.value_len > 0) {
                const got = try self.io.read(ventry.value_offset, value_buf);
                if (got < ventry.value_len) return KvError.Corrupted;
            }
            const ts: u64 = @intCast(std.time.microTimestamp());
            var rec = RecordHeader{
                .magic = MAGIC,
                .op = @intFromEnum(Op.put),
                .reserved = 0,
                .key_len = @intCast(key.len),
                .value_len = ventry.value_len,
                .timestamp_us = ts,
                .crc32 = 0,
                .pad = 0,
            };
            rec.crc32 = computeCrc(rec.op, key, value_buf, ts);

            const rec_bytes: *[@sizeOf(RecordHeader)]u8 = @ptrCast(&rec);
            try tmp.writeAll(rec_bytes);
            try tmp.writeAll(key);
            if (ventry.value_len > 0) try tmp.writeAll(value_buf);

            const new_value_offset = offset + @sizeOf(RecordHeader) + key.len;
            const interned_key = try new_keys_arena.allocator().dupe(u8, key);
            try new_index.put(self.allocator, interned_key, Entry{
                .offset = offset,
                .value_offset = new_value_offset,
                .value_len = ventry.value_len,
                .key_len = @intCast(key.len),
            });
            offset += @sizeOf(RecordHeader) + key.len + ventry.value_len;
            count_after += 1;
        }

        new_header.last_offset = offset;
        new_header.record_count = count_after;
        try tmp.seekTo(0);
        try tmp.writeAll(hdr_bytes);
        try tmp.sync();
        tmp.close();
        tmp_open = false;

        try std.fs.cwd().rename(tmp_path, self.path);
        const new_file = try std.fs.cwd().openFile(self.path, .{ .mode = .read_write });
        self.io.file.close();
        self.io = .{ .file = new_file };
        self.file_size = offset;
        self.header = new_header;

        self.index.deinit(self.allocator);
        self.keys_arena.deinit();
        self.index = new_index;
        self.keys_arena = new_keys_arena;
        self.record_count = count_after;
        self.dead_bytes = 0;
    }
};

test "kv put get delete" {
    const testing = std.testing;
    const tmp_dir = "agdb-test-kv";
    std.fs.cwd().deleteTree(tmp_dir) catch {};
    try std.fs.cwd().makePath(tmp_dir);
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const path = try std.fmt.allocPrint(testing.allocator, "{s}/store.kv", .{tmp_dir});
    defer testing.allocator.free(path);

    var kv = try KvStore.open(testing.allocator, path, 0);
    try kv.put("foo", "bar");
    try kv.put("name", "agdb");
    try testing.expect(kv.contains("foo"));

    const got = try kv.get(testing.allocator, "foo");
    defer if (got) |g| testing.allocator.free(g);
    try testing.expectEqualStrings("bar", got.?);

    _ = try kv.delete("foo");
    try testing.expect(!kv.contains("foo"));
    try testing.expectEqual(@as(u64, 1), kv.count());

    const path_dup = try testing.allocator.dupe(u8, path);
    defer testing.allocator.free(path_dup);
    kv.close();

    var kv2 = try KvStore.open(testing.allocator, path_dup, 0);
    defer kv2.close();
    try testing.expect(!kv2.contains("foo"));
    try testing.expect(kv2.contains("name"));
    try testing.expectEqual(@as(u64, 1), kv2.count());

    try kv2.compact();
    try testing.expect(kv2.contains("name"));
    try testing.expectEqual(@as(u64, 1), kv2.count());
}

test "sim kv drop write fault" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    tsc.initSimulation(9999);
    defer {
        tsc.is_simulation = false;
    }

    var kv = try KvStore.open(alloc, "/tmp/sim_kv_drop.kv", 0);
    defer kv.close();

    try kv.put("before", "ok");
    kv.getSimBackend().?.armFault(.{
        .kind = .drop_write,
        .trigger_key = "dropped",
        .armed = true,
    });
    try kv.put("dropped", "never");
    try testing.expect(!kv.contains("dropped"));
    try testing.expect(kv.contains("before"));
}
