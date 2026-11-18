const std = @import("std");
const builtin = @import("builtin");

pub const CACHE_LINE_SIZE: usize = 64;
pub const L1_SIZE: usize = 32 * 1024;
pub const L2_SIZE: usize = 256 * 1024;
pub const L3_SIZE: usize = 8 * 1024 * 1024;
pub const PAGE_SIZE: usize = std.heap.page_size_min;
pub const HBM_BANDWIDTH_GBPS: u32 = 900;
pub const DRAM_BANDWIDTH_GBPS: u32 = 50;
pub const NVM_LATENCY_NS: u32 = 300;
pub const DRAM_LATENCY_NS: u32 = 80;

fn maxUsize(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

fn readSysfs(path: []const u8) ?[]u8 {
    return std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 4096) catch null;
}

fn parsedSize(text: []const u8) ?usize {
    var end: usize = 0;
    while (end < text.len and text[end] >= '0' and text[end] <= '9') : (end += 1) {}
    if (end == 0) return null;
    const value = std.fmt.parseInt(usize, text[0..end], 10) catch return null;
    if (end < text.len) {
        return switch (text[end]) {
            'K', 'k' => std.math.mul(usize, value, 1024) catch null,
            'M', 'm' => std.math.mul(usize, value, 1024 * 1024) catch null,
            else => value,
        };
    }
    return value;
}

fn listedCpuCount(text: []const u8) usize {
    var count: usize = 0;
    var iterator = std.mem.splitScalar(u8, std.mem.trim(u8, text, " \t\r\n"), ',');
    while (iterator.next()) |part| {
        const range = std.mem.indexOfScalar(u8, part, '-') orelse {
            if (std.fmt.parseInt(usize, part, 10)) |_| {
                count += 1;
            } else |_| {}
            continue;
        };
        const first = std.fmt.parseInt(usize, part[0..range], 10) catch continue;
        const last = std.fmt.parseInt(usize, part[range + 1 ..], 10) catch continue;
        if (last >= first) count += last - first + 1;
    }
    return count;
}

fn runtimePageSize() usize {
    return maxUsize(std.heap.page_size_min, PAGE_SIZE);
}

pub fn CacheLinePadded(comptime T: type) type {
    const alignment = maxUsize(CACHE_LINE_SIZE, @alignOf(T));
    const data_size = @sizeOf(T);
    const total_size = maxUsize(CACHE_LINE_SIZE, std.mem.alignForward(usize, data_size, CACHE_LINE_SIZE));
    const padding_size = total_size - data_size;
    return struct {
        data: T align(alignment),
        padding: [padding_size]u8,

        pub fn init(value: T) @This() {
            return .{ .data = value, .padding = [_]u8{0} ** padding_size };
        }

        pub fn get(self: *@This()) *T {
            return &self.data;
        }

        pub fn getConst(self: *const @This()) *const T {
            return &self.data;
        }
    };
}

pub fn cacheLineCount(comptime T: type) usize {
    const size = @sizeOf(T);
    if (size == 0) return 0;
    if (@alignOf(T) >= CACHE_LINE_SIZE) return size / CACHE_LINE_SIZE + @as(usize, @intFromBool(size % CACHE_LINE_SIZE != 0));
    const quotient = size / CACHE_LINE_SIZE;
    const remainder = size % CACHE_LINE_SIZE;
    const alignment = @alignOf(T);
    const offset_span = CACHE_LINE_SIZE - alignment;
    const tail_span = remainder + offset_span;
    return quotient + tail_span / CACHE_LINE_SIZE + @as(usize, @intFromBool(tail_span % CACHE_LINE_SIZE != 0));
}

pub fn optimalSlabSize(comptime T: type, objects_per_slab: usize) usize {
    const obj_size = @sizeOf(T);
    const page_size = runtimePageSize();
    if (objects_per_slab == 0 or obj_size == 0) return 0;
    const raw = @mulWithOverflow(obj_size, objects_per_slab);
    if (raw[1] != 0) return 0;
    const rounded = @addWithOverflow(raw[0], page_size - 1);
    if (rounded[1] != 0) return 0;
    return rounded[0] / page_size * page_size;
}

pub fn fieldPackingAnalysis(comptime T: type) type {
    const ti = @typeInfo(T);
    const struct_info: ?std.builtin.Type.Struct = if (ti == .@"struct") ti.@"struct" else null;
    const packed_layout = if (struct_info) |info| info.layout == .@"packed" else false;
    const used_bits: u128 = if (struct_info) |info| blk: {
        var sum: u128 = 0;
        for (info.fields) |field| {
            if (field.is_comptime) continue;
            sum += if (packed_layout) @bitSizeOf(field.type) else @as(u128, @sizeOf(field.type)) * 8;
        }
        break :blk sum;
    } else @as(u128, @sizeOf(T)) * 8;
    const type_size = @sizeOf(T);
    const used_bytes: usize = @intCast(@min(used_bits / 8 + @as(u128, @intFromBool(used_bits % 8 != 0)), type_size));
    const eff: usize = if (type_size == 0) 100 else @intCast(@min(@as(u128, 100), used_bits * 100 / (@as(u128, type_size) * 8)));
    return struct {
        pub const total_size = @sizeOf(T);
        pub const alignment = @alignOf(T);
        pub const cache_lines = cacheLineCount(T);
        pub const minimum_cache_lines = if (total_size == 0) 0 else total_size / CACHE_LINE_SIZE + @as(usize, @intFromBool(total_size % CACHE_LINE_SIZE != 0));
        pub const wasted_bytes = total_size - used_bytes;
        pub const packing_efficiency_pct = eff;
        pub const fits_in_cache_line = total_size == 0 or total_size <= @min(CACHE_LINE_SIZE, @alignOf(T));
        pub const fits_in_two_cache_lines = total_size == 0 or total_size <= CACHE_LINE_SIZE + @min(CACHE_LINE_SIZE, @alignOf(T));
        pub const optimal_batch_size: usize = blk: {
            if (total_size == 0) break :blk 64;
            const fit = L1_SIZE / total_size;
            break :blk if (fit > 64) 64 else if (fit > 0) fit else 1;
        };
    };
}

pub fn PackedSlab(comptime T: type, comptime slab_objects: usize) type {
    const analysis = fieldPackingAnalysis(T);
    const object_alignment = maxUsize(runtimePageSize(), @alignOf(T));
    const word_count = slab_objects / 64 + @as(usize, @intFromBool(slab_objects % 64 != 0));
    const BitmapWord = std.atomic.Value(u64);
    return struct {
        data: [slab_objects]T align(object_alignment),
        bitmap: [word_count]BitmapWord,
        count: std.atomic.Value(usize),
        cursor: std.atomic.Value(usize),

        pub const capacity = slab_objects;
        pub const size_of_slab = @sizeOf(Self);
        pub const Analysis = analysis;

        const Self = @This();

        pub fn init() Self {
            var self: Self = undefined;
            for (&self.bitmap) |*word| word.* = BitmapWord.init(0);
            self.count = std.atomic.Value(usize).init(0);
            self.cursor = std.atomic.Value(usize).init(0);
            return self;
        }

        pub fn initPtr(self: *Self) void {
            for (&self.bitmap) |*word| word.* = BitmapWord.init(0);
            self.count = std.atomic.Value(usize).init(0);
            self.cursor = std.atomic.Value(usize).init(0);
        }

        pub fn alloc(self: *Self) ?*T {
            if (capacity == 0) return null;
            const initial = self.cursor.fetchAdd(1, .monotonic) % capacity;
            const start_word = initial / 64;
            const start_bit: u6 = @intCast(initial % 64);
            var step: usize = 0;
            while (step <= word_count) : (step += 1) {
                const word_index = (start_word + step) % word_count;
                var candidates = ~self.bitmap[word_index].load(.acquire);
                if (word_index == word_count - 1 and capacity % 64 != 0) {
                    candidates &= (@as(u64, 1) << @as(u6, @intCast(capacity % 64))) - 1;
                }
                if (step == 0) candidates &= (~@as(u64, 0)) << start_bit;
                if (step == word_count and start_bit != 0) candidates &= (@as(u64, 1) << start_bit) - 1;
                if (candidates == 0) continue;
                const bit: u6 = @intCast(@ctz(candidates));
                const index = word_index * 64 + bit;
                const mask = @as(u64, 1) << bit;
                const previous = self.bitmap[word_index].fetchOr(mask, .acq_rel);
                if (previous & mask == 0) {
                    _ = self.count.fetchAdd(1, .monotonic);
                    return &self.data[index];
                }
                step = 0;
            }
            return null;
        }

        pub fn free(self: *Self, ptr: *T) bool {
            if (capacity == 0) return false;
            const base = @intFromPtr(&self.data[0]);
            const addr = @intFromPtr(ptr);
            if (addr < base) return false;
            const delta = addr - base;
            const object_size = @sizeOf(T);
            var index: usize = undefined;
            if (object_size == 0) {
                if (delta != 0) return false;
                index = 0;
                while (index < capacity) : (index += 1) {
                    const mask = @as(u64, 1) << @as(u6, @intCast(index % 64));
                    const old = self.bitmap[index / 64].fetchAnd(~mask, .acq_rel);
                    if (old & mask != 0) {
                        _ = self.count.fetchSub(1, .monotonic);
                        return true;
                    }
                }
                return false;
            }
            if (delta % object_size != 0) return false;
            index = delta / object_size;
            if (index >= capacity) return false;
            const mask = @as(u64, 1) << @as(u6, @intCast(index % 64));
            const old = self.bitmap[index / 64].fetchAnd(~mask, .acq_rel);
            if (old & mask == 0) return false;
            _ = self.count.fetchSub(1, .monotonic);
            return true;
        }

        pub fn available(self: *const Self) usize {
            const used = self.count.load(.acquire);
            return if (used >= capacity) 0 else capacity - used;
        }
    };
}

pub fn WorkStealDeque(comptime T: type) type {
    const item_size = @sizeOf(T);
    const stride = maxUsize(1, item_size);
    const Slot = std.atomic.Value(u8);
    const PaddedIndex = struct {
        value: std.atomic.Value(i64) align(CACHE_LINE_SIZE),
    };
    return struct {
        slots: []Slot align(CACHE_LINE_SIZE),
        top: PaddedIndex,
        bottom: PaddedIndex,
        fence_token: std.atomic.Value(u8) align(CACHE_LINE_SIZE),
        owner_id: std.atomic.Value(std.Thread.Id) align(CACHE_LINE_SIZE),
        allocator: std.mem.Allocator,
        capacity: usize align(CACHE_LINE_SIZE),

        const Self = @This();

        pub const StealResult = union(enum) {
            stolen: T,
            empty: void,
            contended: void,
        };

        pub fn init(allocator: std.mem.Allocator, cap: usize) !Self {
            const requested = @max(cap, 1);
            const actual_cap = try std.math.ceilPowerOfTwo(usize, requested);
            if (actual_cap > @as(usize, @intCast(std.math.maxInt(i64))) or actual_cap > std.math.maxInt(usize) / stride) return error.InvalidCapacity;
            const slots = try allocator.alloc(Slot, actual_cap * stride);
            for (slots) |*slot| slot.* = Slot.init(0);
            return .{
                .slots = slots,
                .top = .{ .value = std.atomic.Value(i64).init(0) },
                .bottom = .{ .value = std.atomic.Value(i64).init(0) },
                .fence_token = std.atomic.Value(u8).init(0),
                .owner_id = std.atomic.Value(std.Thread.Id).init(0),
                .allocator = allocator,
                .capacity = actual_cap,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.slots);
            self.slots = self.slots[0..0];
            self.capacity = 0;
            self.top.value.store(0, .monotonic);
            self.bottom.value.store(0, .monotonic);
            self.fence_token.store(0, .monotonic);
            self.owner_id.store(0, .monotonic);
        }

        fn isOwner(self: *Self) bool {
            const current = std.Thread.getCurrentId();
            const owner = self.owner_id.load(.acquire);
            if (owner == current) return true;
            if (owner != 0) return false;
            return self.owner_id.cmpxchgStrong(0, current, .acq_rel, .acquire) == null;
        }

        fn encodeItem(item: T) [item_size]u8 {
            if (comptime item_size == 0) return .{};
            return @bitCast(item);
        }

        fn storeBytes(self: *Self, index: usize, bytes: [item_size]u8) void {
            if (comptime item_size == 0) return;
            const offset = index * stride;
            for (bytes, 0..) |byte, i| self.slots[offset + i].store(byte, .monotonic);
        }

        fn loadBytes(self: *Self, index: usize) [item_size]u8 {
            var bytes: [item_size]u8 = undefined;
            if (comptime item_size == 0) return bytes;
            const offset = index * stride;
            for (&bytes, 0..) |*byte, i| byte.* = self.slots[offset + i].load(.monotonic);
            return bytes;
        }

        fn decodeItem(bytes: [item_size]u8) T {
            if (comptime item_size == 0) return;
            return @bitCast(bytes);
        }

        pub fn push(self: *Self, item: T) bool {
            if (self.capacity == 0 or !self.isOwner()) return false;
            const b = self.bottom.value.load(.monotonic);
            if (b >= std.math.maxInt(i64) - 1) return false;
            const t = self.top.value.load(.acquire);
            if (b < t or b - t >= @as(i64, @intCast(self.capacity))) return false;
            const index: usize = @intCast(@as(u64, @bitCast(b)) & (self.capacity - 1));
            self.storeBytes(index, encodeItem(item));
            self.bottom.value.store(b + 1, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            if (self.capacity == 0 or !self.isOwner()) return null;
            const b = self.bottom.value.load(.monotonic) - 1;
            self.bottom.value.store(b, .seq_cst);
            const t = self.top.value.load(.seq_cst);
            if (t > b) {
                self.bottom.value.store(b + 1, .seq_cst);
                return null;
            }
            const index: usize = @intCast(@as(u64, @bitCast(b)) & (self.capacity - 1));
            const bytes = self.loadBytes(index);
            if (t == b) {
                if (self.top.value.cmpxchgStrong(t, t + 1, .seq_cst, .seq_cst) != null) {
                    self.bottom.value.store(b + 1, .seq_cst);
                    return null;
                }
                self.bottom.value.store(b + 1, .seq_cst);
            }
            return decodeItem(bytes);
        }

        pub fn trySteal(self: *Self) StealResult {
            if (self.capacity == 0) return .empty;
            const t = self.top.value.load(.seq_cst);
            _ = self.fence_token.fetchAdd(1, .seq_cst);
            const b = self.bottom.value.load(.seq_cst);
            if (t >= b) return .empty;
            const index: usize = @intCast(@as(u64, @bitCast(t)) & (self.capacity - 1));
            const bytes = self.loadBytes(index);
            if (self.top.value.cmpxchgStrong(t, t + 1, .seq_cst, .seq_cst) != null) return .contended;
            return .{ .stolen = decodeItem(bytes) };
        }

        pub fn steal(self: *Self) ?T {
            return switch (self.trySteal()) {
                .stolen => |item| item,
                .empty, .contended => null,
            };
        }

        pub fn size(self: *const Self) usize {
            const b = self.bottom.value.load(.acquire);
            const t = self.top.value.load(.acquire);
            if (b <= t) return 0;
            return @intCast(b - t);
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size() == 0;
        }
    };
}

pub fn computeOptimalThreadCount(work_items: usize, item_cost_ns: u64, sync_overhead_ns: u64) u32 {
    if (work_items <= 1 or item_cost_ns == 0) return 1;
    const cpu_size = std.Thread.getCpuCount() catch 1;
    const cpu_count: u32 = @intCast(@min(cpu_size, std.math.maxInt(u32)));
    const n: u128 = work_items;
    const cost: u128 = item_cost_ns;
    const overhead: u128 = sync_overhead_ns;
    const serial_time = n * cost;
    if (cpu_count <= 1 or serial_time == 0) return 1;
    var best_threads: u32 = 1;
    var best_time = serial_time;
    var p: u32 = 2;
    while (p <= cpu_count) : (p += 1) {
        const count: u128 = p;
        const chunks = (n + count - 1) / count;
        const elapsed = chunks * cost + (count - 1) * overhead;
        if (elapsed < best_time) {
            best_time = elapsed;
            best_threads = p;
        }
    }
    return best_threads;
}

pub const MicroarchProfile = struct {
    l1_cache_size: usize,
    l2_cache_size: usize,
    l3_cache_size: usize,
    cache_line_size: usize,
    cpu_count: u32,
    has_hyperthreading: bool,
    numa_nodes: u32,

    pub fn detect() MicroarchProfile {
        var profile = MicroarchProfile{
            .l1_cache_size = 0,
            .l2_cache_size = 0,
            .l3_cache_size = 0,
            .cache_line_size = CACHE_LINE_SIZE,
            .cpu_count = @intCast(@min(std.Thread.getCpuCount() catch 1, std.math.maxInt(u32))),
            .has_hyperthreading = false,
            .numa_nodes = 1,
        };
        if (builtin.os.tag == .linux) {
            var index: usize = 0;
            while (index < 32) : (index += 1) {
                const base = std.fmt.allocPrint(std.heap.page_allocator, "/sys/devices/system/cpu/cpu0/cache/index{d}/", .{index}) catch continue;
                defer std.heap.page_allocator.free(base);
                const size_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}size", .{base}) catch continue;
                defer std.heap.page_allocator.free(size_path);
                const type_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}type", .{base}) catch continue;
                defer std.heap.page_allocator.free(type_path);
                const level_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}level", .{base}) catch continue;
                defer std.heap.page_allocator.free(level_path);
                const line_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}coherency_line_size", .{base}) catch continue;
                defer std.heap.page_allocator.free(line_path);
                const size_data = readSysfs(size_path) orelse continue;
                defer std.heap.page_allocator.free(size_data);
                const type_data = readSysfs(type_path) orelse continue;
                defer std.heap.page_allocator.free(type_data);
                const level_data = readSysfs(level_path) orelse continue;
                defer std.heap.page_allocator.free(level_data);
                const cache_size = parsedSize(size_data) orelse continue;
                const level = std.fmt.parseInt(u8, std.mem.trim(u8, level_data, " \t\r\n"), 10) catch continue;
                if (std.mem.startsWith(u8, type_data, "Data") or std.mem.startsWith(u8, type_data, "Unified")) {
                    switch (level) {
                        1 => profile.l1_cache_size = @max(profile.l1_cache_size, cache_size),
                        2 => profile.l2_cache_size = @max(profile.l2_cache_size, cache_size),
                        3 => profile.l3_cache_size = @max(profile.l3_cache_size, cache_size),
                        else => {},
                    }
                }
                if (readSysfs(line_path)) |line_data| {
                    defer std.heap.page_allocator.free(line_data);
                    if (std.fmt.parseInt(usize, std.mem.trim(u8, line_data, " \t\r\n"), 10)) |line| {
                        if (line != 0) profile.cache_line_size = line;
                    } else |_| {}
                }
            }
            if (readSysfs("/sys/devices/system/cpu/cpu0/topology/thread_siblings_list")) |siblings| {
                defer std.heap.page_allocator.free(siblings);
                profile.has_hyperthreading = listedCpuCount(siblings) > 1;
            }
            if (readSysfs("/sys/devices/system/cpu/smt/active")) |active| {
                defer std.heap.page_allocator.free(active);
                const trimmed = std.mem.trim(u8, active, " \t\r\n");
                profile.has_hyperthreading = trimmed.len != 0 and trimmed[0] == '1';
            }
            if (readSysfs("/sys/devices/system/node/online")) |nodes| {
                defer std.heap.page_allocator.free(nodes);
                profile.numa_nodes = @intCast(@min(listedCpuCount(nodes), std.math.maxInt(u32)));
                if (profile.numa_nodes == 0) profile.numa_nodes = 1;
            }
        }
        if (profile.l1_cache_size == 0) profile.l1_cache_size = L1_SIZE;
        if (profile.l2_cache_size == 0) profile.l2_cache_size = L2_SIZE;
        if (profile.l3_cache_size == 0) profile.l3_cache_size = L3_SIZE;
        return profile;
    }

    pub fn optimalBatchSize(self: *const MicroarchProfile, comptime T: type) usize {
        const size = @sizeOf(T);
        if (size == 0) return 64;
        return @max(1, @min(64, self.l1_cache_size / size));
    }

    pub fn optimalSlabObjects(self: *const MicroarchProfile, comptime T: type) usize {
        const size = @sizeOf(T);
        if (size == 0) return 1;
        const fit = self.l2_cache_size / size;
        if (fit == 0) return 1;
        const rounded = fit - fit % 8;
        return if (rounded == 0) fit else rounded;
    }
};

pub fn MPSCQueue(comptime T: type) type {
    return struct {
        const Node = struct {
            value: ?T,
            next: std.atomic.Value(?*Node),
        };

        const PaddedPointer = struct {
            value: std.atomic.Value(?*Node) align(CACHE_LINE_SIZE),
        };

        tail: PaddedPointer,
        head: PaddedPointer,
        allocator: std.mem.Allocator,
        allocator_lock: std.Thread.Mutex,
        initialized: bool,

        const Self = @This();

        fn createStub(allocator: std.mem.Allocator) *Node {
            const node = allocator.create(Node) catch @panic("queue initialization allocation failed");
            node.* = .{ .value = null, .next = std.atomic.Value(?*Node).init(null) };
            return node;
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            const stub = createStub(allocator);
            return .{
                .tail = .{ .value = std.atomic.Value(?*Node).init(stub) },
                .head = .{ .value = std.atomic.Value(?*Node).init(stub) },
                .allocator = allocator,
                .allocator_lock = .{},
                .initialized = true,
            };
        }

        pub fn initPtr(self: *Self, allocator: std.mem.Allocator) void {
            const stub = createStub(allocator);
            self.* = .{
                .tail = .{ .value = std.atomic.Value(?*Node).init(stub) },
                .head = .{ .value = std.atomic.Value(?*Node).init(stub) },
                .allocator = allocator,
                .allocator_lock = .{},
                .initialized = true,
            };
        }

        pub fn deinit(self: *Self) void {
            while (self.dequeue()) |_| {}
            const last = self.head.value.load(.acquire) orelse return;
            self.allocator_lock.lock();
            self.allocator.destroy(last);
            self.allocator_lock.unlock();
            self.head.value.store(null, .release);
            self.tail.value.store(null, .release);
            self.initialized = false;
        }

        pub fn enqueue(self: *Self, value: T) !void {
            if (!self.initialized) return error.NotInitialized;
            self.allocator_lock.lock();
            const node = self.allocator.create(Node) catch |err| {
                self.allocator_lock.unlock();
                return err;
            };
            node.* = .{ .value = value, .next = std.atomic.Value(?*Node).init(null) };
            self.allocator_lock.unlock();
            const previous = self.tail.value.swap(node, .acq_rel) orelse unreachable;
            previous.next.store(node, .release);
        }

        pub fn dequeue(self: *Self) ?T {
            if (!self.initialized) return null;
            const head = self.head.value.load(.acquire) orelse return null;
            const next = head.next.load(.acquire) orelse return null;
            const value = next.value orelse return null;
            self.head.value.store(next, .release);
            self.allocator_lock.lock();
            self.allocator.destroy(head);
            self.allocator_lock.unlock();
            return value;
        }

        pub fn isEmpty(self: *const Self) bool {
            if (!self.initialized) return true;
            const head = self.head.value.load(.acquire) orelse return true;
            return head.next.load(.acquire) == null;
        }
    };
}
