const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub const is_linux = builtin.os.tag == .linux;

pub const MPOL_DEFAULT: u32 = 0;
pub const MPOL_PREFERRED: u32 = 1;
pub const MPOL_BIND: u32 = 2;
pub const MPOL_INTERLEAVE: u32 = 3;
pub const MPOL_LOCAL: u32 = 4;

pub const MPOL_F_NODE: u32 = 1 << 0;
pub const MPOL_F_ADDR: u32 = 1 << 1;
pub const MPOL_F_MEMS_ALLOWED: u32 = 1 << 2;

pub const MPOL_MF_STRICT: u32 = 1 << 0;
pub const MPOL_MF_MOVE: u32 = 1 << 1;
pub const MPOL_MF_MOVE_ALL: u32 = 1 << 2;

pub const MAX_NUMA_NODES: usize = 1024;
pub const MAX_CPUS: usize = 8192;

pub const CpuWord = c_ulong;
pub const WORD_BITS: usize = @bitSizeOf(CpuWord);
pub const NODEMASK_BITS: usize = MAX_NUMA_NODES + 1;
pub const NODEMASK_WORDS: usize = (NODEMASK_BITS + WORD_BITS - 1) / WORD_BITS;

pub const LOCAL_DISTANCE: u8 = 10;
pub const UNREACHABLE_DISTANCE: u8 = 255;
pub const HBM_MIN_READ_BANDWIDTH_MBPS: u64 = 400_000;
pub const MAX_SYSFS_FILE_BYTES: usize = 1024 * 1024;

const NODE_ONLINE_PATH = "/sys/devices/system/node/online";
const CPU_ONLINE_PATH = "/sys/devices/system/cpu/online";
const PROC_MEMINFO_PATH = "/proc/meminfo";

pub const NumaError = error{
    Unsupported,
    InvalidArgument,
    AccessDenied,
    OutOfMemory,
    BadAddress,
    IoFailure,
    NoSuchProcess,
    Unexpected,
    NodeOutOfRange,
    CpuOutOfRange,
    UnalignedAddress,
    UnalignedLength,
    InvalidSize,
    UnknownNode,
    NodeHasNoCpus,
    EmptyTopology,
    DistanceUnavailable,
};

pub const PageSlice = []align(std.heap.page_size_min) u8;

fn mapErrno(err: std.os.linux.E) NumaError {
    return switch (err) {
        .INVAL => error.InvalidArgument,
        .PERM, .ACCES => error.AccessDenied,
        .NOMEM => error.OutOfMemory,
        .FAULT => error.BadAddress,
        .IO => error.IoFailure,
        .SRCH => error.NoSuchProcess,
        .NOSYS => error.Unsupported,
        else => error.Unexpected,
    };
}

fn parseListId(text: []const u8) error{MalformedList}!u32 {
    return std.fmt.parseInt(u32, text, 10) catch return error.MalformedList;
}

pub const CpuSet = extern struct {
    bits: [MAX_CPUS / WORD_BITS]CpuWord,

    pub fn init() CpuSet {
        return .{ .bits = [_]CpuWord{0} ** (MAX_CPUS / WORD_BITS) };
    }

    pub fn set(self: *CpuSet, cpu: u32) error{CpuOutOfRange}!void {
        if (cpu >= MAX_CPUS) return error.CpuOutOfRange;
        const word = cpu / WORD_BITS;
        const bit: std.math.Log2Int(CpuWord) = @intCast(cpu % WORD_BITS);
        self.bits[word] |= @as(CpuWord, 1) << bit;
    }

    pub fn clear(self: *CpuSet, cpu: u32) error{CpuOutOfRange}!void {
        if (cpu >= MAX_CPUS) return error.CpuOutOfRange;
        const word = cpu / WORD_BITS;
        const bit: std.math.Log2Int(CpuWord) = @intCast(cpu % WORD_BITS);
        self.bits[word] &= ~(@as(CpuWord, 1) << bit);
    }

    pub fn isSet(self: *const CpuSet, cpu: u32) bool {
        if (cpu >= MAX_CPUS) return false;
        const word = cpu / WORD_BITS;
        const bit: std.math.Log2Int(CpuWord) = @intCast(cpu % WORD_BITS);
        return (self.bits[word] >> bit) & 1 != 0;
    }

    pub fn count(self: *const CpuSet) u32 {
        var n: u32 = 0;
        for (self.bits) |w| n += @popCount(w);
        return n;
    }

    pub fn highestSet(self: *const CpuSet) ?u32 {
        var i: usize = self.bits.len;
        while (i > 0) {
            i -= 1;
            const w = self.bits[i];
            if (w != 0) {
                const top: usize = WORD_BITS - 1 - @clz(w);
                return @intCast(i * WORD_BITS + top);
            }
        }
        return null;
    }

    pub fn parseList(self: *CpuSet, text: []const u8) error{ MalformedList, CpuOutOfRange }!void {
        const content = std.mem.trim(u8, text, " \t\r\n");
        if (content.len == 0) return;
        var parts = std.mem.splitScalar(u8, content, ',');
        while (parts.next()) |raw| {
            const token = std.mem.trim(u8, raw, " \t");
            if (token.len == 0) return error.MalformedList;
            const dash = std.mem.indexOfScalar(u8, token, '-');
            const first = try parseListId(if (dash) |d| token[0..d] else token);
            const last = if (dash) |d| try parseListId(token[d + 1 ..]) else first;
            if (first > last) return error.MalformedList;
            if (last >= MAX_CPUS) return error.CpuOutOfRange;
            var cpu = first;
            while (true) {
                try self.set(cpu);
                if (cpu == last) break;
                cpu += 1;
            }
        }
    }
};

pub const NodeMask = extern struct {
    words: [NODEMASK_WORDS]CpuWord,

    pub fn init() NodeMask {
        return .{ .words = [_]CpuWord{0} ** NODEMASK_WORDS };
    }

    pub fn setNode(self: *NodeMask, node: u32) error{NodeOutOfRange}!void {
        if (node >= MAX_NUMA_NODES) return error.NodeOutOfRange;
        const word = node / WORD_BITS;
        const bit: std.math.Log2Int(CpuWord) = @intCast(node % WORD_BITS);
        self.words[word] |= @as(CpuWord, 1) << bit;
    }
};

fn isHighBandwidth(total_mem_bytes: u64, read_bandwidth_mbps: ?u64) bool {
    const bandwidth = read_bandwidth_mbps orelse return false;
    return total_mem_bytes > 0 and bandwidth >= HBM_MIN_READ_BANDWIDTH_MBPS;
}

pub const NumaNode = struct {
    node_id: u32,
    cpu_set: CpuSet,
    total_mem_bytes: u64,
    free_mem_bytes: u64,
    read_bandwidth_mbps: ?u64,
    is_hbm: bool,

    pub fn init(
        id: u32,
        cpu_set: CpuSet,
        total_mem_bytes: u64,
        free_mem_bytes: u64,
        read_bandwidth_mbps: ?u64,
    ) NumaNode {
        return .{
            .node_id = id,
            .cpu_set = cpu_set,
            .total_mem_bytes = total_mem_bytes,
            .free_mem_bytes = free_mem_bytes,
            .read_bandwidth_mbps = read_bandwidth_mbps,
            .is_hbm = isHighBandwidth(total_mem_bytes, read_bandwidth_mbps),
        };
    }
};

fn readSmallFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, MAX_SYSFS_FILE_BYTES);
}

fn nodeFilePath(buf: []u8, node: u32, name: []const u8) std.fmt.BufPrintError![]const u8 {
    return std.fmt.bufPrint(buf, "/sys/devices/system/node/node{d}/{s}", .{ node, name });
}

fn parseKbField(content: []const u8, key: []const u8) error{ MalformedMeminfo, MeminfoFieldMissing, MemoryValueOverflow }!u64 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const head = std.mem.trim(u8, line[0..colon], " \t");
        const name = if (std.mem.lastIndexOfScalar(u8, head, ' ')) |sp| head[sp + 1 ..] else head;
        if (!std.mem.eql(u8, name, key)) continue;
        var tokens = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t\r");
        const number = tokens.next() orelse return error.MalformedMeminfo;
        const kb = std.fmt.parseInt(u64, number, 10) catch return error.MalformedMeminfo;
        const unit = tokens.next() orelse return error.MalformedMeminfo;
        if (!std.mem.eql(u8, unit, "kB")) return error.MalformedMeminfo;
        if (tokens.next() != null) return error.MalformedMeminfo;
        return std.math.mul(u64, kb, 1024) catch return error.MemoryValueOverflow;
    }
    return error.MeminfoFieldMissing;
}

fn loadReadBandwidth(allocator: std.mem.Allocator, id: u32) !?u64 {
    var path_buf: [192]u8 = undefined;
    const path = try nodeFilePath(&path_buf, id, "access0/initiators/read_bandwidth");
    const text = readSmallFile(allocator, path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(text);
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return std.fmt.parseInt(u64, trimmed, 10) catch return error.MalformedBandwidth;
}

fn loadNode(allocator: std.mem.Allocator, id: u32) !NumaNode {
    var path_buf: [192]u8 = undefined;

    const meminfo_path = try nodeFilePath(&path_buf, id, "meminfo");
    const meminfo_text = try readSmallFile(allocator, meminfo_path);
    defer allocator.free(meminfo_text);
    const total = try parseKbField(meminfo_text, "MemTotal");
    const free_bytes = try parseKbField(meminfo_text, "MemFree");

    const cpulist_path = try nodeFilePath(&path_buf, id, "cpulist");
    const cpulist_text = try readSmallFile(allocator, cpulist_path);
    defer allocator.free(cpulist_text);
    var cpus = CpuSet.init();
    try cpus.parseList(cpulist_text);

    const bandwidth = try loadReadBandwidth(allocator, id);

    return NumaNode.init(id, cpus, total, free_bytes, bandwidth);
}

fn loadDistances(allocator: std.mem.Allocator, id: u32, count: usize, out: []?u8) !void {
    var path_buf: [192]u8 = undefined;
    const path = try nodeFilePath(&path_buf, id, "distance");
    const text = try readSmallFile(allocator, path);
    defer allocator.free(text);
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var i: usize = 0;
    while (tokens.next()) |token| {
        if (i >= count) return error.InconsistentDistances;
        const value = std.fmt.parseInt(u8, token, 10) catch return error.MalformedDistance;
        out[i] = if (value == UNREACHABLE_DISTANCE) null else value;
        i += 1;
    }
    if (i != count) return error.InconsistentDistances;
}

pub const NumaTopology = struct {
    allocator: std.mem.Allocator,
    nodes: []NumaNode,
    distances: []?u8,
    hbm_nodes: []u32,

    const Self = @This();

    pub fn detect(allocator: std.mem.Allocator) !NumaTopology {
        if (comptime !is_linux) return error.Unsupported;
        return detectLinux(allocator);
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.nodes);
        self.allocator.free(self.distances);
        self.allocator.free(self.hbm_nodes);
        self.nodes = &.{};
        self.distances = &.{};
        self.hbm_nodes = &.{};
    }

    fn detectLinux(allocator: std.mem.Allocator) !NumaTopology {
        const online_text = readSmallFile(allocator, NODE_ONLINE_PATH) catch |err| switch (err) {
            error.FileNotFound => return detectSingleNode(allocator),
            else => return err,
        };
        defer allocator.free(online_text);

        var online = CpuSet.init();
        try online.parseList(online_text);
        if (online.highestSet()) |highest| {
            if (highest >= MAX_NUMA_NODES) return error.NodeIdOutOfRange;
        }
        const count: usize = online.count();
        if (count == 0) return error.NoNumaNodes;

        const nodes = try allocator.alloc(NumaNode, count);
        errdefer allocator.free(nodes);

        var index: usize = 0;
        var id: u32 = 0;
        while (id < MAX_NUMA_NODES) : (id += 1) {
            if (!online.isSet(id)) continue;
            nodes[index] = try loadNode(allocator, id);
            index += 1;
        }

        const distances = try allocator.alloc(?u8, count * count);
        errdefer allocator.free(distances);

        for (0..count) |row| {
            try loadDistances(allocator, nodes[row].node_id, count, distances[row * count ..][0..count]);
        }

        var hbm_count: usize = 0;
        for (nodes) |*node| {
            if (node.is_hbm) hbm_count += 1;
        }

        const hbm_nodes = try allocator.alloc(u32, hbm_count);
        var h: usize = 0;
        for (nodes) |*node| {
            if (node.is_hbm) {
                hbm_nodes[h] = node.node_id;
                h += 1;
            }
        }

        return .{
            .allocator = allocator,
            .nodes = nodes,
            .distances = distances,
            .hbm_nodes = hbm_nodes,
        };
    }

    fn detectSingleNode(allocator: std.mem.Allocator) !NumaTopology {
        const meminfo_text = try readSmallFile(allocator, PROC_MEMINFO_PATH);
        defer allocator.free(meminfo_text);
        const total = try parseKbField(meminfo_text, "MemTotal");
        const free_bytes = try parseKbField(meminfo_text, "MemFree");

        const cpu_text = try readSmallFile(allocator, CPU_ONLINE_PATH);
        defer allocator.free(cpu_text);
        var cpus = CpuSet.init();
        try cpus.parseList(cpu_text);
        if (cpus.count() == 0) return error.NoOnlineCpus;

        const nodes = try allocator.alloc(NumaNode, 1);
        errdefer allocator.free(nodes);
        nodes[0] = NumaNode.init(0, cpus, total, free_bytes, null);

        const distances = try allocator.alloc(?u8, 1);
        errdefer allocator.free(distances);
        distances[0] = LOCAL_DISTANCE;

        const hbm_nodes = try allocator.alloc(u32, 0);

        return .{
            .allocator = allocator,
            .nodes = nodes,
            .distances = distances,
            .hbm_nodes = hbm_nodes,
        };
    }

    pub fn indexOfNode(self: *const Self, id: u32) ?usize {
        for (self.nodes, 0..) |node, i| {
            if (node.node_id == id) return i;
        }
        return null;
    }

    pub fn findNode(self: *const Self, id: u32) ?*const NumaNode {
        const index = self.indexOfNode(id) orelse return null;
        return &self.nodes[index];
    }

    pub fn distanceBetween(self: *const Self, from: u32, to: u32) NumaError!?u8 {
        const from_index = self.indexOfNode(from) orelse return error.UnknownNode;
        const to_index = self.indexOfNode(to) orelse return error.UnknownNode;
        return self.distances[from_index * self.nodes.len + to_index];
    }

    pub fn localNode(self: *const Self) NumaError!u32 {
        if (self.nodes.len == 0) return error.EmptyTopology;
        const node = try getCurrentNumaNode();
        if (self.indexOfNode(node) == null) return error.UnknownNode;
        return node;
    }

    pub fn nearestHBMNode(self: *const Self) NumaError!?u32 {
        if (self.hbm_nodes.len == 0) return null;
        const local = try self.localNode();
        var best: ?u32 = null;
        var best_distance: u8 = 0;
        for (self.hbm_nodes) |hbm| {
            const distance = (try self.distanceBetween(local, hbm)) orelse continue;
            if (best == null or distance < best_distance) {
                best = hbm;
                best_distance = distance;
            }
        }
        if (best == null) return error.DistanceUnavailable;
        return best;
    }

    pub fn nodeCount(self: *const Self) u32 {
        return @intCast(self.nodes.len);
    }

    pub fn hbmNodeCount(self: *const Self) u32 {
        return @intCast(self.hbm_nodes.len);
    }
};

pub fn getCurrentNumaNode() NumaError!u32 {
    if (comptime !is_linux) return error.Unsupported;
    var cpu: u32 = 0;
    var node: u32 = 0;
    const ret = std.os.linux.syscall3(
        .getcpu,
        @intFromPtr(&cpu),
        @intFromPtr(&node),
        0,
    );
    const err = std.os.linux.E.init(ret);
    if (err != .SUCCESS) return mapErrno(err);
    return node;
}

pub fn nodeOfAddress(addr: *const u8) NumaError!u32 {
    if (comptime !is_linux) return error.Unsupported;
    var node: i32 = 0;
    const ret = std.os.linux.syscall5(
        .get_mempolicy,
        @intFromPtr(&node),
        0,
        0,
        @intFromPtr(addr),
        MPOL_F_NODE | MPOL_F_ADDR,
    );
    const err = std.os.linux.E.init(ret);
    if (err != .SUCCESS) return mapErrno(err);
    return std.math.cast(u32, node) orelse error.Unexpected;
}

pub fn mbind(
    addr: [*]u8,
    len: usize,
    mode: u32,
    nodemask: ?[*]const CpuWord,
    maxnode: usize,
    flags: u32,
) NumaError!void {
    if (comptime !is_linux) return error.Unsupported;
    const nm_ptr: usize = if (nodemask) |nm| @intFromPtr(nm) else 0;
    const ret = std.os.linux.syscall6(
        .mbind,
        @intFromPtr(addr),
        len,
        @as(usize, mode),
        nm_ptr,
        maxnode,
        @as(usize, flags),
    );
    const err = std.os.linux.E.init(ret);
    if (err != .SUCCESS) return mapErrno(err);
}

pub fn bindMemoryToNode(ptr: []u8, node: u32) NumaError!void {
    if (comptime !is_linux) return error.Unsupported;
    if (node >= MAX_NUMA_NODES) return error.NodeOutOfRange;
    if (ptr.len == 0) return error.InvalidSize;
    const page = std.heap.pageSize();
    if (@intFromPtr(ptr.ptr) % page != 0) return error.UnalignedAddress;
    if (ptr.len % page != 0) return error.UnalignedLength;
    var mask = NodeMask.init();
    try mask.setNode(node);
    const mask_ptr: [*]const CpuWord = &mask.words;
    try mbind(ptr.ptr, ptr.len, MPOL_BIND, mask_ptr, NODEMASK_BITS, MPOL_MF_MOVE | MPOL_MF_STRICT);
}

pub fn migrateMemoryToNode(ptr: []u8, dst_node: u32) NumaError!void {
    try bindMemoryToNode(ptr, dst_node);
}

fn applyAffinity(cpuset: *const CpuSet) NumaError!void {
    if (comptime !is_linux) return error.Unsupported;
    const ret = std.os.linux.syscall3(
        .sched_setaffinity,
        0,
        @sizeOf(CpuSet),
        @intFromPtr(cpuset),
    );
    const err = std.os.linux.E.init(ret);
    if (err != .SUCCESS) return mapErrno(err);
}

pub fn setThreadAffinity(cpu: u32) NumaError!void {
    if (comptime !is_linux) return error.Unsupported;
    var cpuset = CpuSet.init();
    try cpuset.set(cpu);
    try applyAffinity(&cpuset);
}

pub fn setThreadAffinityNode(topo: *const NumaTopology, node: u32) NumaError!void {
    if (comptime !is_linux) return error.Unsupported;
    const found = topo.findNode(node) orelse return error.UnknownNode;
    if (found.cpu_set.count() == 0) return error.NodeHasNoCpus;
    try applyAffinity(&found.cpu_set);
}

fn paddedLength(size: usize) NumaError!usize {
    const page = std.heap.pageSize();
    const padded = std.math.add(usize, size, page - 1) catch return error.OutOfMemory;
    return padded & ~(page - 1);
}

fn mapOnNode(size: usize, node: u32) NumaError!PageSlice {
    if (comptime !is_linux) return error.Unsupported;
    if (size == 0) return error.InvalidSize;
    if (node >= MAX_NUMA_NODES) return error.NodeOutOfRange;
    const length = try paddedLength(size);
    const memory = posix.mmap(
        null,
        length,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Unexpected,
    };
    errdefer posix.munmap(memory);
    try bindMemoryToNode(memory, node);
    return memory;
}

fn unmapPages(memory: PageSlice) void {
    if (comptime !is_linux) return;
    posix.munmap(memory);
}

pub const NumaBuffer = struct {
    memory: PageSlice,
    size: usize,
    node: u32,

    pub fn bytes(self: NumaBuffer) []u8 {
        return self.memory[0..self.size];
    }

    pub fn deinit(self: NumaBuffer) void {
        unmapPages(self.memory);
    }
};

pub fn allocOnNode(size: usize, node: u32) NumaError!NumaBuffer {
    const memory = try mapOnNode(size, node);
    return .{ .memory = memory, .size = size, .node = node };
}

pub const NumaAwareAllocator = struct {
    preferred_node: u32,
    topo: *const NumaTopology,

    const Self = @This();

    const allocator_vtable = std.mem.Allocator.VTable{
        .alloc = vtableAlloc,
        .resize = vtableResize,
        .remap = vtableRemap,
        .free = vtableFree,
    };

    pub fn init(topo: *const NumaTopology, node: u32) NumaError!Self {
        if (topo.findNode(node) == null) return error.UnknownNode;
        return .{ .preferred_node = node, .topo = topo };
    }

    pub fn alloc(self: *const Self, size: usize) NumaError!NumaBuffer {
        return allocOnNode(size, self.preferred_node);
    }

    pub fn free(_: *const Self, buf: NumaBuffer) void {
        buf.deinit();
    }

    pub fn migrate(self: *const Self, buf: *NumaBuffer, new_node: u32) NumaError!void {
        if (self.topo.findNode(new_node) == null) return error.UnknownNode;
        if (buf.node == new_node) return;
        try migrateMemoryToNode(buf.memory, new_node);
        buf.node = new_node;
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &allocator_vtable };
    }

    fn vtableAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (len == 0) return null;
        if (alignment.toByteUnits() > std.heap.pageSize()) return null;
        const memory = mapOnNode(len, self.preferred_node) catch return null;
        return memory.ptr;
    }

    fn vtableResize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
        if (new_len == 0) return false;
        const old_length = paddedLength(memory.len) catch return false;
        const new_length = paddedLength(new_len) catch return false;
        return old_length == new_length;
    }

    fn vtableRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        if (vtableResize(ctx, memory, alignment, new_len, ret_addr)) return memory.ptr;
        return null;
    }

    fn vtableFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
        if (comptime !is_linux) return;
        const length = paddedLength(memory.len) catch return;
        const base: [*]align(std.heap.page_size_min) u8 = @alignCast(memory.ptr);
        posix.munmap(base[0..length]);
    }
};

test "cpuset operations" {
    const testing = std.testing;
    var cs = CpuSet.init();
    try cs.set(0);
    try cs.set(63);
    try cs.set(127);
    try cs.set(8191);
    try testing.expect(cs.isSet(0));
    try testing.expect(cs.isSet(63));
    try testing.expect(cs.isSet(127));
    try testing.expect(cs.isSet(8191));
    try testing.expect(!cs.isSet(1));
    try testing.expectEqual(@as(u32, 4), cs.count());
    try testing.expectEqual(@as(?u32, 8191), cs.highestSet());
    try cs.clear(63);
    try testing.expect(!cs.isSet(63));
    try testing.expectEqual(@as(u32, 3), cs.count());
    try testing.expectError(error.CpuOutOfRange, cs.set(MAX_CPUS));
    try testing.expectError(error.CpuOutOfRange, cs.clear(MAX_CPUS));
    try testing.expect(!cs.isSet(MAX_CPUS));
}

test "cpuset list parsing" {
    const testing = std.testing;
    var cs = CpuSet.init();
    try cs.parseList("0-3,8,10-11\n");
    try testing.expectEqual(@as(u32, 7), cs.count());
    try testing.expect(cs.isSet(3));
    try testing.expect(!cs.isSet(4));
    try testing.expect(cs.isSet(11));

    var empty = CpuSet.init();
    try empty.parseList("\n");
    try testing.expectEqual(@as(u32, 0), empty.count());

    var bad = CpuSet.init();
    try testing.expectError(error.MalformedList, bad.parseList("3-1"));
    try testing.expectError(error.MalformedList, bad.parseList("a"));
    try testing.expectError(error.MalformedList, bad.parseList("1,,2"));
    try testing.expectError(error.CpuOutOfRange, bad.parseList("0-4294967295"));
}

test "meminfo parsing" {
    const testing = std.testing;
    const content = "Node 0 MemTotal:       16384 kB\nNode 0 MemFree:         1024 kB\n";
    try testing.expectEqual(@as(u64, 16384 * 1024), try parseKbField(content, "MemTotal"));
    try testing.expectEqual(@as(u64, 1024 * 1024), try parseKbField(content, "MemFree"));
    try testing.expectError(error.MeminfoFieldMissing, parseKbField(content, "MemAvailable"));
    try testing.expectError(
        error.MemoryValueOverflow,
        parseKbField("Node 0 MemTotal: 18446744073709551615 kB\n", "MemTotal"),
    );
    try testing.expectError(error.MalformedMeminfo, parseKbField("MemTotal: abc kB\n", "MemTotal"));
}

test "numa topology detect" {
    if (comptime !is_linux) return error.SkipZigTest;
    const testing = std.testing;
    var topo = try NumaTopology.detect(testing.allocator);
    defer topo.deinit();
    try testing.expect(topo.nodeCount() >= 1);
    try testing.expectEqual(topo.nodes.len * topo.nodes.len, topo.distances.len);
    var i: usize = 1;
    while (i < topo.nodes.len) : (i += 1) {
        try testing.expect(topo.nodes[i - 1].node_id < topo.nodes[i].node_id);
    }
}

test "numa current node" {
    if (comptime !is_linux) return error.SkipZigTest;
    const testing = std.testing;
    var topo = try NumaTopology.detect(testing.allocator);
    defer topo.deinit();
    const node = try getCurrentNumaNode();
    try testing.expect(node < MAX_NUMA_NODES);
    try testing.expect(topo.findNode(node) != null);
}

test "numa memory placement" {
    if (comptime !is_linux) return error.SkipZigTest;
    const testing = std.testing;
    var topo = try NumaTopology.detect(testing.allocator);
    defer topo.deinit();
    const node = try topo.localNode();
    var numa_allocator = try NumaAwareAllocator.init(&topo, node);

    const buf = allocOnNode(4 * std.heap.pageSize(), node) catch |err| switch (err) {
        error.AccessDenied, error.Unsupported => return error.SkipZigTest,
        else => return err,
    };
    defer buf.deinit();

    buf.bytes()[0] = 1;
    const placed = try nodeOfAddress(&buf.bytes()[0]);
    try testing.expectEqual(node, placed);

    const a = numa_allocator.allocator();
    const mem = try a.alloc(u8, 10000);
    defer a.free(mem);
    @memset(mem, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), mem[9999]);
}
