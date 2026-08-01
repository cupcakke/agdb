const std = @import("std");
const builtin = @import("builtin");
const header = @import("header.zig");
const pointer = @import("pointer.zig");
const security = @import("security.zig");
const tsc = @import("tsc.zig");

const posix = std.posix;
const page_size_min = std.heap.page_size_min;

pub const PERSISTENT_FORMAT_VERSION: u32 = 1;
pub const PERSISTENT_ENDIAN_MAGIC: u32 = 0x01020304;

pub const VfsFaultKind = enum(u8) {
    none,
    torn_write,
    corruption,
    power_off,
};

pub const VfsFaultSpec = struct {
    kind: VfsFaultKind = .none,
    trigger_offset: u64 = 0,
    trigger_size: u64 = 0,
    partial_bytes: u64 = 0,
    flip_bit_offset: u64 = 0,
    armed: bool = false,
};

pub const SimSector = struct {
    data: [512]u8,
    written: bool,
    synced: bool,
};

const SIM_BUF_ALIGN: u29 = @intCast(@max(page_size_min, @alignOf(header.HeapHeader)));

pub const SimVfsBackend = struct {
    buf: []align(SIM_BUF_ALIGN) u8,
    size: u64,
    allocator: std.mem.Allocator,
    fault: VfsFaultSpec,
    sector_written: []bool,
    sector_synced: []bool,
    sector_count: usize,

    pub fn init(allocator: std.mem.Allocator, initial_size: u64) !SimVfsBackend {
        if (initial_size == 0) return error.InvalidHeapSize;
        const aligned_sz = try alignForwardChecked(initial_size, 512);
        const usize_sz = try u64ToUsize(aligned_sz);

        const buf = try allocator.alignedAlloc(u8, SIM_BUF_ALIGN, usize_sz);
        errdefer allocator.free(buf);
        @memset(buf, 0);

        const sector_count: usize = @intCast(aligned_sz / 512);

        const sector_written = try allocator.alloc(bool, sector_count);
        errdefer allocator.free(sector_written);
        @memset(sector_written, false);

        const sector_synced = try allocator.alloc(bool, sector_count);
        errdefer allocator.free(sector_synced);
        @memset(sector_synced, false);

        return SimVfsBackend{
            .buf = buf,
            .size = aligned_sz,
            .allocator = allocator,
            .fault = .{},
            .sector_written = sector_written,
            .sector_synced = sector_synced,
            .sector_count = sector_count,
        };
    }

    pub fn deinit(self: *SimVfsBackend) void {
        self.allocator.free(self.buf);
        self.allocator.free(self.sector_written);
        self.allocator.free(self.sector_synced);
    }

    pub fn armFault(self: *SimVfsBackend, spec: VfsFaultSpec) void {
        self.fault = spec;
        self.fault.armed = true;
    }

    pub fn disarmFault(self: *SimVfsBackend) void {
        self.fault.armed = false;
        self.fault.kind = .none;
    }

    pub fn writeAt(self: *SimVfsBackend, offset: u64, data: []const u8) !void {
        const data_len = try usizeToU64(data.len);
        try checkRange(self.size, offset, data_len);

        if (data.len == 0) return;

        if (self.fault.armed and self.fault.kind != .none) {
            const fault_start = self.fault.trigger_offset;
            const fault_end = try checkedAddU64(fault_start, self.fault.trigger_size);
            const write_end = try checkedAddU64(offset, data_len);
            const overlaps = offset < fault_end and write_end > fault_start;

            if (overlaps) {
                switch (self.fault.kind) {
                    .torn_write => {
                        const overlap_start = @max(offset, fault_start);
                        const overlap_end = @min(write_end, fault_end);
                        const overlap_len = overlap_end - overlap_start;
                        const partial = @min(self.fault.partial_bytes, overlap_len);

                        const pre_overlap_start = offset;
                        const pre_overlap_end = overlap_start;
                        if (pre_overlap_end > pre_overlap_start) {
                            const pre_len = pre_overlap_end - pre_overlap_start;
                            const pre_off_usize = try u64ToUsize(pre_overlap_start);
                            const pre_len_usize = try u64ToUsize(pre_len);
                            @memcpy(self.buf[pre_off_usize..][0..pre_len_usize], data[0..pre_len_usize]);
                            try self.markSectors(pre_overlap_start, pre_len);
                        }

                        if (partial > 0) {
                            const partial_usize = try u64ToUsize(partial);
                            const data_start_off = overlap_start - offset;
                            const data_start_usize = try u64ToUsize(data_start_off);
                            const dst_start_usize = try u64ToUsize(overlap_start);
                            @memcpy(self.buf[dst_start_usize..][0..partial_usize], data[data_start_usize..][0..partial_usize]);
                            try self.markSectors(overlap_start, partial);
                        }
                        self.fault.armed = false;
                        return error.SimulatedTornWrite;
                    },
                    .corruption => {
                        const off_usize = try u64ToUsize(offset);
                        @memcpy(self.buf[off_usize..][0..data.len], data);
                        try self.markSectors(offset, data_len);

                        if (self.fault.flip_bit_offset < self.fault.trigger_size) {
                            const target_abs = try checkedAddU64(fault_start, self.fault.flip_bit_offset);
                            if (target_abs >= offset and target_abs < write_end) {
                                const byte_idx = try u64ToUsize(target_abs);
                                self.buf[byte_idx] ^= 0xFF;
                            }
                        }
                        self.fault.armed = false;
                        return;
                    },
                    .power_off => {
                        const overlap_start = @max(offset, fault_start);
                        const pre_len = overlap_start - offset;
                        if (pre_len > 0) {
                            const pre_off_usize = try u64ToUsize(offset);
                            const pre_len_usize = try u64ToUsize(pre_len);
                            @memcpy(self.buf[pre_off_usize..][0..pre_len_usize], data[0..pre_len_usize]);
                            try self.markSectors(offset, pre_len);
                        }
                        if (self.fault.partial_bytes > 0) {
                            const overlap_len = @min(write_end, fault_end) - overlap_start;
                            const partial = @min(self.fault.partial_bytes, overlap_len);
                            if (partial > 0) {
                                const partial_usize = try u64ToUsize(partial);
                                const data_start_off = overlap_start - offset;
                                const data_start_usize = try u64ToUsize(data_start_off);
                                const dst_start_usize = try u64ToUsize(overlap_start);
                                @memcpy(self.buf[dst_start_usize..][0..partial_usize], data[data_start_usize..][0..partial_usize]);
                                try self.markSectors(overlap_start, partial);
                            }
                        }
                        self.fault.armed = false;
                        return error.SimulatedPowerOff;
                    },
                    .none => {},
                }
            }
        }

        const off_usize = try u64ToUsize(offset);
        @memcpy(self.buf[off_usize..][0..data.len], data);
        try self.markSectors(offset, data_len);
    }

    pub fn readAt(self: *const SimVfsBackend, offset: u64, buf: []u8) !void {
        const buf_len = try usizeToU64(buf.len);
        try checkRange(self.size, offset, buf_len);
        if (buf.len == 0) return;
        const off_usize = try u64ToUsize(offset);
        @memcpy(buf, self.buf[off_usize..][0..buf.len]);
    }

    pub fn syncRange(self: *SimVfsBackend, offset: u64, len: u64) !void {
        try checkRange(self.size, offset, len);
        if (len == 0) return;
        const start_sector = offset / 512;
        const end_sector = try alignForwardChecked(try checkedAddU64(offset, len), 512);
        const end = end_sector / 512;
        var s = start_sector;
        while (s < end and s < @as(u64, @intCast(self.sector_count))) : (s += 1) {
            const idx: usize = @intCast(s);
            if (self.sector_written[idx]) {
                self.sector_synced[idx] = true;
            }
        }
    }

    pub fn fsync(self: *SimVfsBackend) !void {
        var i: usize = 0;
        while (i < self.sector_count) : (i += 1) {
            if (self.sector_written[i]) {
                self.sector_synced[i] = true;
            }
        }
    }

    pub fn grow(self: *SimVfsBackend, new_size: u64) !void {
        if (new_size <= self.size) return;
        const aligned = try alignForwardChecked(new_size, 512);
        if (aligned <= self.size) return;
        const aligned_usize = try u64ToUsize(aligned);
        const new_sector_count: usize = @intCast(aligned / 512);

        const old_buf = self.buf;
        const old_size = self.size;
        const old_size_usize = try u64ToUsize(old_size);
        const old_sector_written = self.sector_written;
        const old_sector_synced = self.sector_synced;
        const old_sector_count = self.sector_count;

        const new_buf = try self.allocator.alignedAlloc(u8, SIM_BUF_ALIGN, aligned_usize);
        errdefer self.allocator.free(new_buf);

        const new_sector_written = try self.allocator.alloc(bool, new_sector_count);
        errdefer self.allocator.free(new_sector_written);

        const new_sector_synced = try self.allocator.alloc(bool, new_sector_count);
        errdefer self.allocator.free(new_sector_synced);

        @memcpy(new_buf[0..old_size_usize], old_buf[0..old_size_usize]);
        @memset(new_buf[old_size_usize..], 0);

        @memcpy(new_sector_written[0..old_sector_count], old_sector_written[0..old_sector_count]);
        @memset(new_sector_written[old_sector_count..], false);

        @memcpy(new_sector_synced[0..old_sector_count], old_sector_synced[0..old_sector_count]);
        @memset(new_sector_synced[old_sector_count..], false);

        self.buf = new_buf;
        self.sector_written = new_sector_written;
        self.sector_synced = new_sector_synced;
        self.sector_count = new_sector_count;
        self.size = aligned;

        self.allocator.free(old_buf);
        self.allocator.free(old_sector_written);
        self.allocator.free(old_sector_synced);
    }

    fn markSectors(self: *SimVfsBackend, offset: u64, len: u64) !void {
        if (len == 0) return;
        const start_sector = offset / 512;
        const end_byte = try checkedAddU64(offset, len);
        const end_byte_rounded = try checkedAddU64(end_byte, 511);
        const end_sector = end_byte_rounded / 512;
        var s = start_sector;
        while (s < end_sector and s < @as(u64, @intCast(self.sector_count))) : (s += 1) {
            self.sector_written[@intCast(s)] = true;
            self.sector_synced[@intCast(s)] = false;
        }
    }
};

pub const VfsKind = enum { prod, sim };

pub const VfsHandle = struct {
    kind: VfsKind,
    prod_base: []align(page_size_min) u8,
    prod_size: u64,
    prod_file: std.fs.File,
    sim: ?*SimVfsBackend,

    pub fn writeRange(self: *VfsHandle, offset: u64, data: []const u8) !void {
        const data_len = try usizeToU64(data.len);
        switch (self.kind) {
            .prod => {
                try checkRange(self.prod_size, offset, data_len);
                const idx = try u64ToUsize(offset);
                if (data.len == 0) return;
                @memcpy(self.prod_base[idx..][0..data.len], data);
            },
            .sim => {
                try self.sim.?.writeAt(offset, data);
            },
        }
    }

    pub fn readRange(self: *const VfsHandle, offset: u64, buf: []u8) !void {
        const buf_len = try usizeToU64(buf.len);
        switch (self.kind) {
            .prod => {
                try checkRange(self.prod_size, offset, buf_len);
                if (buf.len == 0) return;
                const idx = try u64ToUsize(offset);
                @memcpy(buf, self.prod_base[idx..][0..buf.len]);
            },
            .sim => {
                try self.sim.?.readAt(offset, buf);
            },
        }
    }

    pub fn syncRange(self: *VfsHandle, offset: u64, len: u64) !void {
        switch (self.kind) {
            .prod => try flushRangeRaw(self.prod_base, offset, len),
            .sim => try self.sim.?.syncRange(offset, len),
        }
    }

    pub fn fsync(self: *VfsHandle) !void {
        switch (self.kind) {
            .prod => try posix.fsync(self.prod_file.handle),
            .sim => try self.sim.?.fsync(),
        }
    }

    pub fn basePtrConst(self: *const VfsHandle) [*]const u8 {
        switch (self.kind) {
            .prod => return self.prod_base.ptr,
            .sim => return self.sim.?.buf.ptr,
        }
    }

    pub fn basePtrMut(self: *VfsHandle) [*]u8 {
        switch (self.kind) {
            .prod => return self.prod_base.ptr,
            .sim => return self.sim.?.buf.ptr,
        }
    }

    pub fn currentSize(self: *const VfsHandle) u64 {
        switch (self.kind) {
            .prod => return self.prod_size,
            .sim => return self.sim.?.size,
        }
    }

    pub fn grow(self: *VfsHandle, new_size: u64) !void {
        switch (self.kind) {
            .prod => {
                const ps = pageSize();
                if (new_size == 0) return error.InvalidHeapSize;
                if (new_size % ps != 0) return error.HeapSizeNotPageAligned;
                if (new_size <= self.prod_size) return;

                const old_size = self.prod_size;
                const old_base = self.prod_base;
                try posix.msync(old_base, posix.MSF.SYNC);
                try posix.fsync(self.prod_file.handle);

                self.prod_file.setEndPos(new_size) catch |err| return err;

                const new_len = try u64ToUsize(new_size);
                const new_map = posix.mmap(
                    null,
                    new_len,
                    posix.PROT.READ | posix.PROT.WRITE,
                    .{ .TYPE = .SHARED },
                    self.prod_file.handle,
                    0,
                ) catch |err| {
                    self.prod_file.setEndPos(old_size) catch {};
                    posix.fsync(self.prod_file.handle) catch {};
                    return err;
                };

                posix.munmap(old_base);
                self.prod_base = new_map;
                self.prod_size = new_size;

                posix.fsync(self.prod_file.handle) catch |err| {
                    posix.munmap(new_map);
                    self.prod_base = &[_]u8{};
                    self.prod_size = 0;

                    const old_len = u64ToUsize(old_size) catch {
                        return err;
                    };

                    self.prod_file.setEndPos(old_size) catch {};
                    posix.fsync(self.prod_file.handle) catch {};

                    const restored = posix.mmap(
                        null,
                        old_len,
                        posix.PROT.READ | posix.PROT.WRITE,
                        .{ .TYPE = .SHARED },
                        self.prod_file.handle,
                        0,
                    ) catch {
                        self.prod_base = &[_]u8{};
                        self.prod_size = 0;
                        return err;
                    };

                    self.prod_base = restored;
                    self.prod_size = old_size;
                    return err;
                };
            },
            .sim => try self.sim.?.grow(new_size),
        }
    }
};

pub const ReadObjectResult = struct {
    header: header.ObjectHeader,
    data: []u8,
    owned: bool,
    allocator: ?std.mem.Allocator,

    pub fn deinit(self: *ReadObjectResult) void {
        if (self.owned) {
            if (self.allocator) |a| a.free(self.data);
        }
    }
};

const OpenResult = struct {
    file: std.fs.File,
    needs_init: bool,
    is_new_file: bool,
    map_size: u64,
};

pub const PersistentHeap = struct {
    vfs: VfsHandle,
    size: u64,
    mapped_size: u64,
    file_path: []u8,
    pool_uuid: u128,
    security_mgr: ?*security.SecurityManager,
    allocator: std.mem.Allocator,
    dirty_pages: []bool,
    dirty_page_count: u64,
    is_dirty: bool,
    active_transaction: bool,
    file_lock_held: bool,
    journal_path: ?[]u8,

    const MMAP_PROT: u32 = posix.PROT.READ | posix.PROT.WRITE;
    const MMAP_FLAGS: posix.MAP = .{ .TYPE = .SHARED };

    pub fn init(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        size: u64,
        security_mgr: ?*security.SecurityManager,
    ) !*PersistentHeap {
        const min_size = minimumHeapSize();
        const requested_size = try normalizeHeapSize(@max(size, min_size));

        const self = try allocator.create(PersistentHeap);
        errdefer allocator.destroy(self);

        const path_copy = try allocator.dupe(u8, file_path);
        errdefer allocator.free(path_copy);

        if (tsc.is_simulation) {
            const sim_backend = try allocator.create(SimVfsBackend);
            errdefer allocator.destroy(sim_backend);

            sim_backend.* = try SimVfsBackend.init(allocator, requested_size);
            errdefer sim_backend.deinit();

            const page_count = try pageCountForSize(requested_size);
            const dirty_pages = try allocator.alloc(bool, page_count);
            errdefer allocator.free(dirty_pages);
            @memset(dirty_pages, false);

            const empty_aligned: []align(page_size_min) u8 = &[_]u8{};
            const vfs = VfsHandle{
                .kind = .sim,
                .prod_base = empty_aligned,
                .prod_size = 0,
                .prod_file = undefined,
                .sim = sim_backend,
            };

            self.* = PersistentHeap{
                .vfs = vfs,
                .size = requested_size,
                .mapped_size = requested_size,
                .file_path = path_copy,
                .pool_uuid = 0,
                .security_mgr = security_mgr,
                .allocator = allocator,
                .dirty_pages = dirty_pages,
                .dirty_page_count = 0,
                .is_dirty = false,
                .active_transaction = false,
                .file_lock_held = false,
                .journal_path = null,
            };

            const mapped_len = try u64ToUsize(requested_size);
            @memset(sim_backend.buf[0..mapped_len], 0);
            const hh = self.heapHeaderMut();
            hh.* = header.HeapHeader.init(requested_size);
            hh.setDirty(false);
            hh.updateChecksum();
            try writeFooterMagic(self);
            try self.vfs.syncRange(0, requested_size);
            self.pool_uuid = hh.getPoolUUID();
            if (self.pool_uuid == 0) return error.InvalidPoolUUID;

            if (security_mgr) |sm| {
                try sm.attach(self.pool_uuid);
            }

            return self;
        }

        const open_result = try openOrCreateFile(file_path, requested_size);
        var file = open_result.file;
        errdefer file.close();
        const needs_init_initial = open_result.needs_init;
        const is_new_file = open_result.is_new_file;
        const mapped_size = open_result.map_size;

        if (mapped_size < min_size) {
            return error.InvalidHeapSize;
        }

        try acquireFileLock(file.handle);
        var lock_held = true;
        errdefer if (lock_held) releaseFileLock(file.handle);

        const base_addr = try mapFile(file.handle, mapped_size);
        errdefer unmapFile(base_addr);

        const heap_hdr: *header.HeapHeader = @ptrCast(@alignCast(base_addr.ptr));
        var heap_size: u64 = mapped_size;
        var needs_init = needs_init_initial;
        var was_dirty_on_open = false;

        if (!needs_init) {
            const header_valid: bool = if (heap_hdr.validate()) |_| true else |_| false;
            if (header_valid) {
                if (heap_hdr.version != PERSISTENT_FORMAT_VERSION) {
                    return error.IncompatibleFormatVersion;
                }
                if (heap_hdr.endianness != (if (builtin.cpu.arch.endian() == .little) header.Endianness.little else header.Endianness.big)) {
                    return error.EndianMismatch;
                }
                heap_size = heap_hdr.heap_size;
                if (heap_size < min_size) return error.InvalidHeapSize;
                if (heap_size > mapped_size) return error.InvalidHeapSize;
                if (heap_size % pageSize() != 0) return error.InvalidHeapSize;
                was_dirty_on_open = heap_hdr.isDirty();
                if (was_dirty_on_open) {
                    return error.HeapDirtyRecoveryRequired;
                }
            } else {
                if (is_new_file) {
                    needs_init = true;
                } else {
                    return error.HeapHeaderCorrupt;
                }
            }
        }

        if (needs_init) {
            const mapped_len = try u64ToUsize(mapped_size);
            @memset(base_addr[0..mapped_len], 0);
            heap_hdr.* = header.HeapHeader.init(mapped_size);
            heap_hdr.version = PERSISTENT_FORMAT_VERSION;
            heap_hdr.endianness = if (builtin.cpu.arch.endian() == .little) header.Endianness.little else header.Endianness.big;
            heap_hdr.setDirty(false);
            heap_hdr.updateChecksum();
            try flushRangeRaw(base_addr, 0, mapped_size);
            try posix.fsync(file.handle);
            heap_size = mapped_size;
        }

        const pool_uuid = heap_hdr.getPoolUUID();
        if (pool_uuid == 0) return error.InvalidPoolUUID;

        const page_count = try pageCountForSize(mapped_size);
        const dirty_pages = try allocator.alloc(bool, page_count);
        errdefer allocator.free(dirty_pages);
        @memset(dirty_pages, false);

        const vfs = VfsHandle{
            .kind = .prod,
            .prod_base = base_addr,
            .prod_size = mapped_size,
            .prod_file = file,
            .sim = null,
        };

        self.* = PersistentHeap{
            .vfs = vfs,
            .size = heap_size,
            .mapped_size = mapped_size,
            .file_path = path_copy,
            .pool_uuid = pool_uuid,
            .security_mgr = security_mgr,
            .allocator = allocator,
            .dirty_pages = dirty_pages,
            .dirty_page_count = 0,
            .is_dirty = false,
            .active_transaction = false,
            .file_lock_held = true,
            .journal_path = null,
        };
        lock_held = false;

        if (security_mgr) |sm| {
            try sm.attach(self.pool_uuid);
        }

        return self;
    }

    pub fn deinit(self: *PersistentHeap) !void {
        const alloc = self.allocator;
        var flush_err: ?anyerror = null;
        self.flush() catch |e| {
            flush_err = e;
        };
        self.vfs.fsync() catch |e| {
            if (flush_err == null) flush_err = e;
        };

        if (self.security_mgr) |sm| {
            sm.detach(self.pool_uuid) catch {};
        }

        switch (self.vfs.kind) {
            .prod => {
                unmapFile(self.vfs.prod_base);
                if (self.file_lock_held) {
                    releaseFileLock(self.vfs.prod_file.handle);
                }
                self.vfs.prod_file.close();
            },
            .sim => {
                if (self.vfs.sim) |sim| {
                    sim.deinit();
                    alloc.destroy(sim);
                }
            },
        }
        alloc.free(self.dirty_pages);
        alloc.free(self.file_path);
        if (self.journal_path) |jp| alloc.free(jp);
        alloc.destroy(self);

        if (flush_err) |e| return e;
    }

    pub fn heapHeader(self: *const PersistentHeap) *const header.HeapHeader {
        const base = self.vfs.basePtrConst();
        return @ptrCast(@alignCast(base));
    }

    pub fn heapHeaderMut(self: *PersistentHeap) *header.HeapHeader {
        const base = self.vfs.basePtrMut();
        return @ptrCast(@alignCast(base));
    }

    pub fn getSimBackend(self: *PersistentHeap) ?*SimVfsBackend {
        if (self.vfs.kind == .sim) return self.vfs.sim;
        return null;
    }

    pub fn getSize(self: *const PersistentHeap) u64 {
        return self.size;
    }

    pub fn getUsedSize(self: *const PersistentHeap) u64 {
        return self.heapHeader().used_size;
    }

    pub fn getBaseAddress(self: *PersistentHeap) [*]u8 {
        return self.vfs.basePtrMut();
    }

    pub fn getPoolUUID(self: *const PersistentHeap) u128 {
        return self.pool_uuid;
    }

    pub fn getRoot(self: *const PersistentHeap) !?pointer.PersistentPtr {
        const hh = self.heapHeader();
        const root = hh.getRootPtr();
        if (root) |r| {
            if (r.uuid != self.pool_uuid) return error.UUIDMismatch;
            if (r.offset >= self.size) return error.OutOfBounds;
            const oh_size = objectHeaderSize();
            if (r.offset < freeListRegionEnd() + oh_size) return error.InvalidRootPointer;
            return pointer.PersistentPtr{
                .pool_uuid = r.uuid,
                .offset = r.offset,
            };
        }
        return null;
    }

    pub fn setRoot(self: *PersistentHeap, tx: anytype, ptr: pointer.PersistentPtr) !void {
        try self.requireTransaction(tx);
        try self.checkSecurity(.set_root);

        if (ptr.pool_uuid != self.pool_uuid) return error.UUIDMismatch;
        if (ptr.offset >= self.size) return error.OutOfBounds;
        const oh_size = objectHeaderSize();
        if (ptr.offset < freeListRegionEnd() + oh_size) return error.InvalidRootPointer;

        const payload_off = ptr.offset;
        const hdr_off = payload_off - oh_size;
        try self.validateAllocatedObject(hdr_off);

        try self.vfs.syncRange(hdr_off, oh_size);
        try self.vfs.fsync();

        const hh = self.heapHeaderMut();
        hh.setRootPtr(ptr.offset, ptr.pool_uuid);
        hh.updateChecksum();
        try self.persistHeaderRange();
        try self.vfs.fsync();
    }

    pub fn resolvePtr(self: *const PersistentHeap, ptr: pointer.PersistentPtr) !?*anyopaque {
        if (ptr.isNull()) return null;
        if (ptr.pool_uuid != self.pool_uuid) return error.UUIDMismatch;
        if (ptr.offset >= self.size) return error.OutOfBounds;

        const oh_size = objectHeaderSize();
        if (ptr.offset < freeListRegionEnd() + oh_size) return error.PointerInReservedRegion;

        const hdr_off = ptr.offset - oh_size;
        const base = self.vfs.basePtrConst();
        const hdr_idx = try u64ToUsize(hdr_off);
        const obj_hdr: *const header.ObjectHeader = @ptrCast(@alignCast(base + hdr_idx));
        obj_hdr.validate() catch return error.InvalidObjectHeader;
        if (obj_hdr.isFreed()) return error.UseAfterFree;

        const payload_idx = try u64ToUsize(ptr.offset);
        const mut_base = @as([*]u8, @ptrFromInt(@intFromPtr(base)));
        return @ptrCast(mut_base + payload_idx);
    }

    pub fn getNativePtr(
        self: *const PersistentHeap,
        comptime T: type,
        ptr: pointer.PersistentPtr,
    ) !?*T {
        const oh_size = objectHeaderSize();
        if (ptr.isNull()) return null;
        if (ptr.pool_uuid != self.pool_uuid) return error.UUIDMismatch;
        if (ptr.offset >= self.size) return error.OutOfBounds;
        if (ptr.offset < freeListRegionEnd() + oh_size) return error.PointerInReservedRegion;

        if (@alignOf(T) > 1) {
            const req_align: u64 = @intCast(@alignOf(T));
            if (ptr.offset % req_align != 0) return error.InvalidAlignment;
        }

        const hdr_off = ptr.offset - oh_size;
        const base = self.vfs.basePtrConst();
        const hdr_idx = try u64ToUsize(hdr_off);
        const obj_hdr: *const header.ObjectHeader = @ptrCast(@alignCast(base + hdr_idx));
        try obj_hdr.validate();
        if (obj_hdr.isFreed()) return error.UseAfterFree;

        const type_size: u64 = @intCast(@sizeOf(T));
        const payload_size: u64 = @intCast(obj_hdr.size);
        if (type_size > payload_size) return error.SizeMismatch;

        try checkRange(self.size, ptr.offset, type_size);

        const payload_idx = try u64ToUsize(ptr.offset);
        const mut_base = @as([*]u8, @ptrFromInt(@intFromPtr(base)));
        const typed: *T = @ptrCast(@alignCast(mut_base + payload_idx));
        return typed;
    }

    pub fn allocate(
        self: *PersistentHeap,
        tx: anytype,
        size: u64,
        alignment: u64,
    ) !pointer.PersistentPtr {
        try self.requireTransaction(tx);
        try self.checkSecurity(.allocate);

        if (size == 0) return error.InvalidSize;
        if (!isPowerOfTwo(alignment)) return error.InvalidAlignment;

        const oh_size = objectHeaderSize();
        const want = @max(size, header.MIN_BLOCK_SIZE);

        if (want <= header.MAX_SMALL_SIZE and alignment <= header.MIN_ALIGNMENT) {
            const class_idx = header.sizeClassIndex(want);
            if (class_idx < header.NUM_SIZE_CLASSES) {
                const class_size = header.SIZE_CLASSES[class_idx];
                const storage = self.freeListStorageMut();
                const hd = storage[class_idx];
                if (hd != 0) {
                    try self.validateFreeListNode(hd);
                    const next = self.freeListNodeNext(hd);
                    storage[class_idx] = next;
                    try self.writeObjectHeaderAt(hd, class_size);
                    try self.vfs.syncRange(hd, oh_size);
                    try self.vfs.fsync();
                    try self.persistFreeListMetadata();
                    try self.vfs.fsync();
                    const payload_off = try checkedAddU64(hd, oh_size);
                    return pointer.PersistentPtr{
                        .pool_uuid = self.pool_uuid,
                        .offset = payload_off,
                    };
                }
                return self.bumpBlock(class_size, alignment);
            }
        }

        const large_off = try self.tryReuseLarge(want, alignment);
        if (large_off) |off| {
            const payload_off = try checkedAddU64(off, oh_size);
            return pointer.PersistentPtr{
                .pool_uuid = self.pool_uuid,
                .offset = payload_off,
            };
        }

        return self.bumpBlock(want, alignment);
    }

    fn tryReuseLarge(self: *PersistentHeap, size: u64, alignment: u64) !?u64 {
        const oh_size = objectHeaderSize();
        var prev: u64 = 0;
        var cur = self.heapHeaderMut().allocator_offset;
        var iterations: u32 = 0;
        const max_iter: u32 = 65536;
        const base_mut = self.vfs.basePtrMut();
        while (cur != 0 and iterations < max_iter) : (iterations += 1) {
            try self.validateFreeListNode(cur);
            const node = header.freeListNodeAtConst(self.vfs.basePtrConst(), cur);
            const payload_off = try checkedAddU64(cur, oh_size);
            const aligned_ok = if (alignment <= 1) true else (payload_off % alignment == 0);
            if (node.size >= size and aligned_ok) {
                if (prev == 0) {
                    self.heapHeaderMut().allocator_offset = node.next;
                } else {
                    const prev_node = header.freeListNodeAtMut(base_mut, prev);
                    prev_node.next = node.next;
                }
                try self.writeObjectHeaderAt(cur, node.size);
                try self.vfs.syncRange(cur, oh_size);
                try self.vfs.fsync();
                try self.persistFreeListMetadata();
                try self.vfs.fsync();
                return cur;
            }
            prev = cur;
            cur = node.next;
        }
        if (iterations >= max_iter) return error.FreeListCycle;
        return null;
    }

    fn bumpBlock(self: *PersistentHeap, block_size: u64, alignment: u64) !pointer.PersistentPtr {
        const oh_size = objectHeaderSize();
        const actual_alignment = @max(alignment, header.MIN_ALIGNMENT);
        const free_list_end = freeListRegionEnd();
        const aligned_floor = try alignTo(free_list_end, @alignOf(header.ObjectHeader));
        const hh = self.heapHeaderMut();
        const current_used = @max(hh.used_size, aligned_floor);

        const header_align = @max(@as(u64, @intCast(@alignOf(header.ObjectHeader))), actual_alignment);
        var hdr_offset = try alignTo(current_used, header_align);

        var payload_offset = try checkedAddU64(hdr_offset, oh_size);
        if (payload_offset % actual_alignment != 0) {
            const adj = actual_alignment - (payload_offset % actual_alignment);
            hdr_offset = try checkedAddU64(hdr_offset, adj);
            hdr_offset = try alignTo(hdr_offset, @alignOf(header.ObjectHeader));
            payload_offset = try checkedAddU64(hdr_offset, oh_size);
        }

        const end_offset = try checkedAddU64(payload_offset, block_size);
        if (end_offset > self.size) return error.OutOfMemory;

        try self.writeObjectHeaderAt(hdr_offset, block_size);
        try self.vfs.syncRange(hdr_offset, oh_size);
        try self.vfs.fsync();

        const hh2 = self.heapHeaderMut();
        hh2.used_size = end_offset;
        hh2.updateChecksum();
        try self.persistHeaderRange();
        try self.vfs.fsync();

        return pointer.PersistentPtr{
            .pool_uuid = self.pool_uuid,
            .offset = payload_offset,
        };
    }

    fn writeObjectHeaderAt(self: *PersistentHeap, offset: u64, block_size: u64) !void {
        const oh_size = objectHeaderSize();
        try checkRange(self.size, offset, oh_size);
        const oh_align: u64 = @intCast(@alignOf(header.ObjectHeader));
        if (offset % oh_align != 0) return error.InvalidAlignment;
        if (offset < freeListRegionEnd()) return error.OffsetInReservedRegion;

        var oh = header.ObjectHeader.init(block_size, 0);
        oh.updateChecksum();
        const bytes = std.mem.asBytes(&oh);
        try self.vfs.writeRange(offset, bytes[0..@sizeOf(header.ObjectHeader)]);
        try self.markDirty(offset, oh_size);
    }

    pub fn deallocate(
        self: *PersistentHeap,
        tx: anytype,
        ptr: pointer.PersistentPtr,
    ) !void {
        try self.requireTransaction(tx);
        try self.checkSecurity(.deallocate);

        if (ptr.isNull()) return;
        if (ptr.pool_uuid != self.pool_uuid) return error.UUIDMismatch;

        const oh_size = objectHeaderSize();
        if (ptr.offset >= self.size) return error.OutOfBounds;
        if (ptr.offset < freeListRegionEnd() + oh_size) return error.PointerInReservedRegion;

        const payload_off = ptr.offset;
        const hdr_off = payload_off - oh_size;
        try checkRange(self.size, hdr_off, oh_size);

        const base = self.vfs.basePtrConst();
        const hdr_idx = try u64ToUsize(hdr_off);
        const obj_hdr_ro: *const header.ObjectHeader = @ptrCast(@alignCast(base + hdr_idx));
        try obj_hdr_ro.validate();
        if (obj_hdr_ro.isFreed()) return error.DoubleFree;

        const block_size: u64 = @intCast(obj_hdr_ro.size);
        const total_block = try checkedAddU64(oh_size, block_size);
        if (block_size < @sizeOf(header.FreeListNode)) return error.BlockTooSmallForFreeList;
        try checkRange(self.size, hdr_off, total_block);

        try self.freeListInsert(hdr_off, block_size);
        try self.persistFreeListNode(hdr_off);
        try self.vfs.fsync();

        var freed = obj_hdr_ro.*;
        freed.setFreed(true);
        freed.updateChecksum();
        const fr_bytes = std.mem.asBytes(&freed);
        try self.vfs.writeRange(hdr_off, fr_bytes[0..@sizeOf(header.ObjectHeader)]);
        try self.markDirty(hdr_off, oh_size);
        try self.vfs.syncRange(hdr_off, oh_size);
        try self.vfs.fsync();

        try self.persistFreeListMetadata();
        try self.vfs.fsync();
    }

    pub fn write(self: *PersistentHeap, offset: u64, data: []const u8) !void {
        try self.checkSecurity(.write);
        const len = try usizeToU64(data.len);
        try checkRange(self.size, offset, len);
        if (data.len == 0) return;

        const hh = self.heapHeaderMut();
        if (!hh.isDirty()) {
            hh.setDirty(true);
            hh.updateChecksum();
            try self.persistHeaderRange();
            try self.vfs.fsync();
        }

        try self.vfs.writeRange(offset, data);
        try self.markDirty(offset, len);
    }

    pub fn read(self: *const PersistentHeap, offset: u64, buffer: []u8) !void {
        try self.checkSecurityConst(.read);
        const len = try usizeToU64(buffer.len);
        try checkRange(self.size, offset, len);
        if (buffer.len == 0) return;
        try self.vfs.readRange(offset, buffer);
    }

    pub fn writeObject(
        self: *PersistentHeap,
        tx: anytype,
        payload_offset: u64,
        data: []const u8,
    ) !void {
        try self.requireTransaction(tx);
        try self.checkSecurity(.write);

        const oh_size = objectHeaderSize();
        if (payload_offset < freeListRegionEnd() + oh_size) return error.PointerInReservedRegion;
        const hdr_off = payload_offset - oh_size;
        try checkRange(self.size, hdr_off, oh_size);

        const base = self.vfs.basePtrConst();
        const hdr_idx = try u64ToUsize(hdr_off);
        const obj_hdr: *const header.ObjectHeader = @ptrCast(@alignCast(base + hdr_idx));
        try obj_hdr.validate();
        if (obj_hdr.isFreed()) return error.UseAfterFree;

        const payload_capacity: u64 = @intCast(obj_hdr.size);
        const data_len = try usizeToU64(data.len);
        if (data_len > payload_capacity) return error.SizeMismatch;

        try checkRange(self.size, payload_offset, data_len);

        try self.vfs.writeRange(payload_offset, data);
        try self.markDirty(payload_offset, data_len);
        try self.vfs.syncRange(payload_offset, data_len);
        try self.vfs.fsync();

        var nh = obj_hdr.*;
        nh.payload_checksum = computePayloadChecksum(data);
        nh.updateChecksum();
        const nh_bytes = std.mem.asBytes(&nh);
        try self.vfs.writeRange(hdr_off, nh_bytes[0..@sizeOf(header.ObjectHeader)]);
        try self.markDirty(hdr_off, oh_size);
        try self.vfs.syncRange(hdr_off, oh_size);
        try self.vfs.fsync();
    }

    pub fn readObject(self: *const PersistentHeap, payload_offset: u64) !?ReadObjectResult {
        try self.checkSecurityConst(.read);
        const oh_size = objectHeaderSize();
        if (payload_offset < freeListRegionEnd() + oh_size) return null;
        if (payload_offset >= self.size) return null;
        const hdr_off = payload_offset - oh_size;
        if (oh_size > self.size - hdr_off) return null;

        var obj_header: header.ObjectHeader = undefined;
        const hdr_bytes = std.mem.asBytes(&obj_header);
        try self.vfs.readRange(hdr_off, hdr_bytes[0..@sizeOf(header.ObjectHeader)]);

        obj_header.validate() catch return null;
        if (obj_header.isFreed()) return null;

        const data_size: u64 = @intCast(obj_header.size);
        try checkRange(self.size, payload_offset, data_size);
        const data_len = try u64ToUsize(data_size);

        const copy = try self.allocator.alloc(u8, data_len);
        errdefer self.allocator.free(copy);
        try self.vfs.readRange(payload_offset, copy);

        const computed = computePayloadChecksum(copy);
        if (obj_header.payload_checksum != 0 and obj_header.payload_checksum != computed) {
            return error.PayloadChecksumMismatch;
        }

        return ReadObjectResult{
            .header = obj_header,
            .data = copy,
            .owned = true,
            .allocator = self.allocator,
        };
    }

    pub fn markDirty(self: *PersistentHeap, offset: u64, len: u64) !void {
        if (len == 0) return;
        if (offset >= self.size) return error.OutOfBounds;
        if (len > self.size - offset) return error.OutOfBounds;

        const ps = pageSize();
        const start_page = offset / ps;
        const last_byte = offset + len - 1;
        const end_page = last_byte / ps;

        const start_idx = try u64ToUsize(start_page);
        const end_idx = try u64ToUsize(end_page);

        var i = start_idx;
        while (i <= end_idx and i < self.dirty_pages.len) : (i += 1) {
            if (!self.dirty_pages[i]) {
                self.dirty_pages[i] = true;
                self.dirty_page_count = try checkedAddU64(self.dirty_page_count, 1);
            }
        }
        self.is_dirty = true;
    }

    pub fn flush(self: *PersistentHeap) !void {
        if (!self.is_dirty and self.dirty_page_count == 0) {
            const hh = self.heapHeaderMut();
            if (hh.isDirty()) {
                hh.setDirty(false);
                hh.updateChecksum();
                try self.persistHeaderRange();
                try self.vfs.fsync();
            }
            return;
        }

        try self.flushDirtyPagesInternal();
        try self.vfs.fsync();

        const hh = self.heapHeaderMut();
        hh.setDirty(false);
        hh.updateChecksum();
        try self.persistHeaderRange();
        try self.vfs.fsync();

        self.is_dirty = false;
        @memset(self.dirty_pages, false);
        self.dirty_page_count = 0;
    }

    pub fn flushRange(self: *PersistentHeap, len: u64) !void {
        try self.flushRangeAt(0, len);
    }

    pub fn flushRangeAt(self: *PersistentHeap, offset: u64, len: u64) !void {
        if (len == 0) return;
        if (offset >= self.size) return error.OutOfBounds;
        if (len > self.size - offset) return error.OutOfBounds;

        try self.vfs.syncRange(offset, len);

        const ps = pageSize();
        const start_page = offset / ps;
        const last_byte = offset + len - 1;
        const end_page = last_byte / ps;

        var p = start_page;
        while (p <= end_page) : (p += 1) {
            const idx = try u64ToUsize(p);
            if (idx < self.dirty_pages.len and self.dirty_pages[idx]) {
                self.dirty_pages[idx] = false;
                if (self.dirty_page_count > 0) self.dirty_page_count -= 1;
            }
        }
        if (self.dirty_page_count == 0) self.is_dirty = false;
    }

    fn flushDirtyPagesInternal(self: *PersistentHeap) !void {
        const ps = pageSize();
        var i: usize = 0;
        while (i < self.dirty_pages.len) {
            while (i < self.dirty_pages.len and !self.dirty_pages[i]) : (i += 1) {}
            if (i >= self.dirty_pages.len) break;
            const start_page = i;
            while (i < self.dirty_pages.len and self.dirty_pages[i]) : (i += 1) {}
            const start_offset = try checkedMulU64(try usizeToU64(start_page), ps);
            const end_page_offset = try checkedMulU64(try usizeToU64(i), ps);
            const end_offset = @min(end_page_offset, self.size);
            if (end_offset > start_offset) {
                try self.vfs.syncRange(start_offset, end_offset - start_offset);
            }
        }
    }

    pub fn sync(self: *PersistentHeap) !void {
        try self.flush();
        try self.vfs.fsync();
    }

    fn persistHeaderRange(self: *PersistentHeap) !void {
        const end = freeListRegionEnd();
        try self.markDirty(0, end);
        try self.vfs.syncRange(0, end);
    }

    fn persistFreeListMetadata(self: *PersistentHeap) !void {
        const end = freeListRegionEnd();
        try self.markDirty(0, end);
        try self.vfs.syncRange(0, end);
    }

    fn persistFreeListNode(self: *PersistentHeap, offset: u64) !void {
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        try self.markDirty(offset, node_size);
        try self.vfs.syncRange(offset, node_size);
    }

    fn expandCopy(self: *PersistentHeap, tx: anytype, new_size: u64) !void {
        try self.requireTransaction(tx);
        if (new_size <= self.size) return;
        const aligned_new_size = try normalizeHeapSize(new_size);
        if (aligned_new_size <= self.size) return;

        const old_size = self.size;
        try self.flush();
        try self.vfs.fsync();

        const new_page_count = try pageCountForSize(aligned_new_size);
        const new_dirty_pages = try self.allocator.alloc(bool, new_page_count);
        errdefer self.allocator.free(new_dirty_pages);
        @memset(new_dirty_pages, false);

        const old_dirty = self.dirty_pages;

        try self.vfs.grow(aligned_new_size);

        const old_size_usize = try u64ToUsize(old_size);
        const new_size_usize = try u64ToUsize(aligned_new_size);
        if (new_size_usize > old_size_usize) {
            const base = self.vfs.basePtrMut();
            @memset(base[old_size_usize..new_size_usize], 0);
        }

        const new_header = self.heapHeaderMut();
        new_header.heap_size = aligned_new_size;
        new_header.updateChecksum();

        const end = freeListRegionEnd();
        try self.vfs.syncRange(0, end);
        try self.vfs.fsync();

        self.mapped_size = aligned_new_size;
        self.size = aligned_new_size;

        self.allocator.free(old_dirty);
        self.dirty_pages = new_dirty_pages;
        self.dirty_page_count = 0;
        self.is_dirty = false;
    }

    pub fn getDirtyPages(self: *const PersistentHeap, allocator: std.mem.Allocator) ![]bool {
        const copy = try allocator.alloc(bool, self.dirty_pages.len);
        @memcpy(copy, self.dirty_pages);
        return copy;
    }

    pub fn getDirtyPageCount(self: *const PersistentHeap) u64 {
        return self.dirty_page_count;
    }

    pub fn clearDirty(self: *PersistentHeap) !void {
        try self.flush();
        try self.vfs.fsync();
        @memset(self.dirty_pages, false);
        self.dirty_page_count = 0;
        self.is_dirty = false;
        const hh = self.heapHeaderMut();
        if (hh.isDirty()) {
            hh.setDirty(false);
            hh.updateChecksum();
            try self.persistHeaderRange();
            try self.vfs.fsync();
        }
    }

    pub fn beginTransaction(self: *PersistentHeap) !void {
        if (self.active_transaction) return error.TransactionAlreadyActive;
        const hh = self.heapHeaderMut();
        const ov = @addWithOverflow(hh.transaction_id, 1);
        if (ov[1] != 0) return error.TransactionIdOverflow;
        hh.transaction_id = ov[0];
        hh.setDirty(true);
        hh.updateChecksum();
        try self.persistHeaderRange();
        try self.vfs.fsync();
        self.active_transaction = true;
    }

    pub fn endTransaction(self: *PersistentHeap) !void {
        if (!self.active_transaction) return error.NoActiveTransaction;
        try self.flush();
        try self.vfs.fsync();
        const hh = self.heapHeaderMut();
        hh.setDirty(false);
        hh.updateChecksum();
        try self.persistHeaderRange();
        try self.vfs.fsync();
        self.active_transaction = false;
    }

    pub fn getTransactionId(self: *const PersistentHeap) u64 {
        return self.heapHeader().transaction_id;
    }

    fn requireTransaction(self: *PersistentHeap, tx: anytype) !void {
        const T = @TypeOf(tx);
        if (T == void) {
            if (!self.active_transaction) return error.TransactionRequired;
            return;
        }
        if (@typeInfo(T) == .optional) {
            if (tx == null) {
                if (!self.active_transaction) return error.TransactionRequired;
                return;
            }
        }
        if (!self.active_transaction) return error.TransactionRequired;
    }

    const SecurityOp = enum { read, write, allocate, deallocate, set_root };

    fn checkSecurity(self: *PersistentHeap, op: SecurityOp) !void {
        if (self.security_mgr) |sm| {
            try sm.check(self.pool_uuid, switch (op) {
                .read => .read,
                .write => .write,
                .allocate => .allocate,
                .deallocate => .deallocate,
                .set_root => .set_root,
            });
        }
    }

    fn checkSecurityConst(self: *const PersistentHeap, op: SecurityOp) !void {
        if (self.security_mgr) |sm| {
            try sm.check(self.pool_uuid, switch (op) {
                .read => .read,
                .write => .write,
                .allocate => .allocate,
                .deallocate => .deallocate,
                .set_root => .set_root,
            });
        }
    }

    fn validateAllocatedObject(self: *const PersistentHeap, hdr_off: u64) !void {
        const oh_size = objectHeaderSize();
        try checkRange(self.size, hdr_off, oh_size);
        const base = self.vfs.basePtrConst();
        const idx = try u64ToUsize(hdr_off);
        const oh: *const header.ObjectHeader = @ptrCast(@alignCast(base + idx));
        try oh.validate();
        if (oh.isFreed()) return error.UseAfterFree;
    }

    fn validateFreeListNode(self: *const PersistentHeap, offset: u64) !void {
        const oh_size = objectHeaderSize();
        if (offset < freeListRegionEnd()) return error.InvalidFreeListNode;
        if (offset % @as(u64, @intCast(@alignOf(header.ObjectHeader))) != 0) return error.InvalidFreeListNode;
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        try checkRange(self.size, offset, @max(oh_size, node_size));
        const base = self.vfs.basePtrConst();
        const idx = try u64ToUsize(offset);
        const node: *const header.FreeListNode = @ptrCast(@alignCast(base + idx));
        if (!header.freeListNodeValid(node)) return error.InvalidFreeListNode;
    }

    fn freeListNodeNext(self: *const PersistentHeap, offset: u64) u64 {
        const base = self.vfs.basePtrConst();
        const node = header.freeListNodeAtConst(base, offset);
        return node.next;
    }

    fn freeListStorageMut(self: *PersistentHeap) *[header.NUM_SIZE_CLASSES]u64 {
        const storage_off = header.FREE_LIST_STORAGE_OFFSET;
        const align_u64: u64 = @intCast(@alignOf(u64));
        std.debug.assert(storage_off % align_u64 == 0);
        const base = self.vfs.basePtrMut();
        const idx: usize = @intCast(storage_off);
        return @ptrCast(@alignCast(base + idx));
    }

    fn freeListStorageConst(self: *const PersistentHeap) *const [header.NUM_SIZE_CLASSES]u64 {
        const storage_off = header.FREE_LIST_STORAGE_OFFSET;
        const align_u64: u64 = @intCast(@alignOf(u64));
        std.debug.assert(storage_off % align_u64 == 0);
        const base = self.vfs.basePtrConst();
        const idx: usize = @intCast(storage_off);
        return @ptrCast(@alignCast(base + idx));
    }

    fn freeListHeadFor(self: *PersistentHeap, size: u64) *u64 {
        if (size <= header.MAX_SMALL_SIZE) {
            const class_idx = header.sizeClassIndex(size);
            if (class_idx < header.NUM_SIZE_CLASSES) {
                const storage = self.freeListStorageMut();
                return &storage[class_idx];
            }
        }
        return &self.heapHeaderMut().allocator_offset;
    }

    fn freeListHeadValue(self: *const PersistentHeap, size: u64) u64 {
        if (size <= header.MAX_SMALL_SIZE) {
            const class_idx = header.sizeClassIndex(size);
            if (class_idx < header.NUM_SIZE_CLASSES) {
                const storage = self.freeListStorageConst();
                return storage[class_idx];
            }
        }
        return self.heapHeader().allocator_offset;
    }

    pub fn markAllocated(self: *PersistentHeap, offset: u64, size: u64) !void {
        try self.reconcileWatermark(offset, size);
    }

    pub fn markFreed(self: *PersistentHeap, offset: u64, size: u64) !void {
        _ = self;
        _ = offset;
        _ = size;
    }

    fn reconcileWatermark(self: *PersistentHeap, offset: u64, size: u64) !void {
        const oh_size = objectHeaderSize();
        const with_hdr = try checkedAddU64(offset, oh_size);
        const block_end = try checkedAddU64(with_hdr, size);
        if (block_end > self.size) return error.OutOfBounds;

        const md_off = header.HEADER_SIZE;
        if (md_off + @as(u64, @intCast(@sizeOf(header.AllocatorMetadata))) > self.size) {
            return error.OutOfBounds;
        }
        const md_align: u64 = @intCast(@alignOf(header.AllocatorMetadata));
        if (md_off % md_align != 0) return error.InvalidAlignment;

        const base = self.vfs.basePtrMut();
        const md_idx = try u64ToUsize(md_off);
        const md: *header.AllocatorMetadata = @ptrCast(@alignCast(base + md_idx));

        var changed = false;
        if (md.magic == header.AllocatorMetadata.ALLOCATOR_MAGIC and block_end > md.free_heap_offset) {
            md.free_heap_offset = block_end;
            md.updateChecksum();
            changed = true;
        }

        const hh = self.heapHeaderMut();
        if (block_end > hh.used_size) {
            hh.used_size = block_end;
            hh.updateChecksum();
            changed = true;
        }

        if (changed) {
            const end = freeListRegionEnd();
            try self.markDirty(0, end);
            try self.vfs.syncRange(0, end);
            try self.vfs.fsync();
        }
    }

    pub fn freeListInsert(self: *PersistentHeap, offset: u64, size: u64) !void {
        if (offset == 0) return;
        try self.validateFreeListOffset(offset);
        const hd = self.freeListHeadFor(size);
        header.freeListPush(self.vfs.basePtrMut(), hd, offset, size);
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        try self.markDirty(offset, node_size);
        try self.markDirty(0, freeListRegionEnd());
    }

    pub fn freeListRemove(self: *PersistentHeap, offset: u64, size: u64) !void {
        if (offset == 0) return;
        try self.validateFreeListOffset(offset);
        const hd = self.freeListHeadFor(size);
        header.freeListUnlink(self.vfs.basePtrMut(), hd, offset);
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        try self.markDirty(offset, node_size);
        try self.markDirty(0, freeListRegionEnd());
    }

    fn validateFreeListOffset(self: *const PersistentHeap, offset: u64) !void {
        const oh_align: u64 = @intCast(@alignOf(header.ObjectHeader));
        if (offset % oh_align != 0) return error.InvalidAlignment;
        if (offset < freeListRegionEnd()) return error.OffsetInReservedRegion;
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        try checkRange(self.size, offset, node_size);
    }

    pub fn flushFreeListMetadata(self: *PersistentHeap) !void {
        const end = freeListRegionEnd();
        try self.markDirty(0, end);
        try self.vfs.syncRange(0, end);
        try self.vfs.fsync();
    }

    pub fn expand(self: *PersistentHeap, tx: anytype, target_size: u64) !void {
        try self.expandCopy(tx, target_size);
    }

    pub fn shrink(self: *PersistentHeap, tx: anytype, new_size: u64) !void {
        try self.requireTransaction(tx);
        if (new_size >= self.size) return;
        const min = minimumHeapSize();
        if (new_size < min) return error.InvalidHeapSize;
        const aligned = try normalizeHeapSize(new_size);
        if (aligned >= self.size) return;

        const hh = self.heapHeaderMut();
        if (hh.used_size > aligned) return error.HeapInUseAboveShrinkBoundary;

        var cls: usize = 0;
        while (cls < header.NUM_SIZE_CLASSES) : (cls += 1) {
            const storage = self.freeListStorageMut();
            var prev_ptr: *u64 = &storage[cls];
            var cur = storage[cls];
            var iters: u32 = 0;
            while (cur != 0 and iters < 65536) : (iters += 1) {
                const node = header.freeListNodeAtConst(self.vfs.basePtrConst(), cur);
                if (cur >= aligned) {
                    prev_ptr.* = node.next;
                    cur = node.next;
                } else {
                    prev_ptr = &(header.freeListNodeAtMut(self.vfs.basePtrMut(), cur)).next;
                    cur = node.next;
                }
            }
        }

        var prev_large: *u64 = &self.heapHeaderMut().allocator_offset;
        var cur_large = self.heapHeaderMut().allocator_offset;
        var li: u32 = 0;
        while (cur_large != 0 and li < 65536) : (li += 1) {
            const node = header.freeListNodeAtConst(self.vfs.basePtrConst(), cur_large);
            if (cur_large >= aligned) {
                prev_large.* = node.next;
                cur_large = node.next;
            } else {
                prev_large = &(header.freeListNodeAtMut(self.vfs.basePtrMut(), cur_large)).next;
                cur_large = node.next;
            }
        }

        const new_page_count = try pageCountForSize(aligned);
        const new_dirty = try self.allocator.alloc(bool, new_page_count);
        errdefer self.allocator.free(new_dirty);
        @memset(new_dirty, false);

        switch (self.vfs.kind) {
            .prod => {
                try posix.msync(self.vfs.prod_base, posix.MSF.SYNC);
                try posix.fsync(self.vfs.prod_file.handle);
                try self.vfs.prod_file.setEndPos(aligned);
                self.vfs.prod_size = aligned;
            },
            .sim => {
                self.vfs.sim.?.size = aligned;
            },
        }

        const hh2 = self.heapHeaderMut();
        hh2.heap_size = aligned;
        hh2.updateChecksum();
        self.size = aligned;
        self.mapped_size = aligned;

        self.allocator.free(self.dirty_pages);
        self.dirty_pages = new_dirty;
        self.dirty_page_count = 0;
        self.is_dirty = false;

        try self.persistHeaderRange();
        try self.vfs.fsync();
    }

    pub fn findObjectHeaderOffset(self: *PersistentHeap, payload_offset: u64) !u64 {
        const oh_size = objectHeaderSize();
        if (payload_offset < freeListRegionEnd() + oh_size) return error.OutOfBounds;
        const sub = @subWithOverflow(payload_offset, oh_size);
        if (sub[1] != 0) return error.OutOfBounds;
        const hdr_offset = sub[0];
        const add = @addWithOverflow(hdr_offset, oh_size);
        if (add[1] != 0) return error.OutOfBounds;
        if (add[0] > self.size) return error.OutOfBounds;
        const base = self.vfs.basePtrConst();
        const idx = try u64ToUsize(hdr_offset);
        const obj_hdr: *const header.ObjectHeader = @ptrCast(@alignCast(base + idx));
        if (!obj_hdr.hasValidMagic()) return error.InvalidRecord;
        try obj_hdr.validate();
        return hdr_offset;
    }

    pub fn isInFreeList(self: *const PersistentHeap, offset: u64, size: u64) !bool {
        if (offset == 0) return false;
        const node_size: u64 = @intCast(@sizeOf(header.FreeListNode));
        const oh_align: u64 = @intCast(@alignOf(header.ObjectHeader));
        if (offset % oh_align != 0) return false;

        const base = self.vfs.basePtrConst();
        const max_iter: u32 = 1 << 20;

        if (size <= header.MAX_SMALL_SIZE) {
            const class_idx = header.sizeClassIndex(size);
            if (class_idx < header.NUM_SIZE_CLASSES) {
                const storage = self.freeListStorageConst();
                var cur = storage[class_idx];
                var visited = std.AutoHashMap(u64, void).init(self.allocator);
                defer visited.deinit();
                var iter: u32 = 0;
                while (cur != 0 and iter < max_iter) : (iter += 1) {
                    if (visited.contains(cur)) return error.FreeListCycle;
                    try visited.put(cur, {});
                    if (cur == offset) return true;
                    const end = @addWithOverflow(cur, node_size);
                    if (end[1] != 0) return error.OutOfBounds;
                    if (end[0] > self.size) return error.OutOfBounds;
                    const node = header.freeListNodeAtConst(base, cur);
                    cur = node.next;
                }
                if (iter >= max_iter) return error.FreeListCycle;
                return false;
            }
        }

        var cur = self.heapHeader().allocator_offset;
        var visited2 = std.AutoHashMap(u64, void).init(self.allocator);
        defer visited2.deinit();
        var iter2: u32 = 0;
        while (cur != 0 and iter2 < max_iter) : (iter2 += 1) {
            if (visited2.contains(cur)) return error.FreeListCycle;
            try visited2.put(cur, {});
            if (cur == offset) return true;
            const end = @addWithOverflow(cur, node_size);
            if (end[1] != 0) return error.OutOfBounds;
            if (end[0] > self.size) return error.OutOfBounds;
            const node = header.freeListNodeAtConst(base, cur);
            cur = node.next;
        }
        if (iter2 >= max_iter) return error.FreeListCycle;
        return false;
    }
};

fn writeFooterMagic(self: *PersistentHeap) !void {
    const hh = self.heapHeaderMut();
    hh.version = PERSISTENT_FORMAT_VERSION;
    hh.endianness = if (builtin.cpu.arch.endian() == .little) header.Endianness.little else header.Endianness.big;
    hh.updateChecksum();
}

fn computePayloadChecksum(data: []const u8) u32 {
    var crc = std.hash.Crc32.init();
    crc.update(data);
    return crc.final();
}

fn declaredHeaderSize() u64 {
    return freeListRegionEnd();
}

fn heapHeaderSize() u64 {
    return @as(u64, @intCast(@sizeOf(header.HeapHeader)));
}

fn objectHeaderSize() u64 {
    return @as(u64, @intCast(@sizeOf(header.ObjectHeader)));
}

fn pageSize() u64 {
    return @as(u64, @intCast(std.heap.pageSize()));
}

fn minimumHeapSize() u64 {
    const ps = pageSize();
    const fl_end = freeListRegionEnd();
    const min_alloc_area = @as(u64, 4096);
    const total = @max(fl_end + min_alloc_area, ps * 2);
    const aligned = std.mem.alignForward(u64, total, ps);
    return aligned;
}

fn freeListRegionEnd() u64 {
    const u64_size: u64 = @intCast(@sizeOf(u64));
    const storage_off = header.FREE_LIST_STORAGE_OFFSET;
    const slots: u64 = @intCast(header.NUM_SIZE_CLASSES);
    const ov1 = @mulWithOverflow(slots, u64_size);
    std.debug.assert(ov1[1] == 0);
    const ov2 = @addWithOverflow(storage_off, ov1[0]);
    std.debug.assert(ov2[1] == 0);
    const u64_align: u64 = @intCast(@alignOf(u64));
    return std.mem.alignForward(u64, ov2[0], u64_align);
}

fn normalizeHeapSize(size: u64) !u64 {
    const ps = pageSize();
    if (size == 0) return error.InvalidHeapSize;
    const min = minimumHeapSize();
    const adj = @max(size, min);
    const ov = @addWithOverflow(adj, ps - 1);
    if (ov[1] != 0) return error.IntegerOverflow;
    const aligned = (ov[0] / ps) * ps;
    return aligned;
}

fn pageCountForSize(size: u64) !usize {
    const ps = pageSize();
    if (ps == 0) return error.InvalidPageSize;
    if (size == 0) return 0;
    const ov = @addWithOverflow(size, ps - 1);
    if (ov[1] != 0) return error.IntegerOverflow;
    const count = ov[0] / ps;
    return try u64ToUsize(count);
}

fn alignTo(value: u64, alignment: u64) !u64 {
    if (alignment == 0 or (alignment & (alignment - 1)) != 0) return error.InvalidAlignment;
    const mask = alignment - 1;
    const ov = @addWithOverflow(value, mask);
    if (ov[1] != 0) return error.IntegerOverflow;
    return ov[0] & ~mask;
}

fn alignForwardChecked(value: u64, alignment: u64) !u64 {
    return alignTo(value, alignment);
}

fn isPowerOfTwo(value: u64) bool {
    if (value == 0) return false;
    return (value & (value - 1)) == 0;
}

fn checkedAddU64(a: u64, b: u64) !u64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return error.IntegerOverflow;
    return result[0];
}

fn checkedMulU64(a: u64, b: u64) !u64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return error.IntegerOverflow;
    return result[0];
}

fn u64ToUsize(value: u64) !usize {
    if (@bitSizeOf(usize) < 64) {
        if (value > std.math.maxInt(usize)) return error.ValueTooLarge;
    }
    return @intCast(value);
}

fn usizeToU64(value: usize) !u64 {
    if (@bitSizeOf(usize) > 64) {
        if (value > std.math.maxInt(u64)) return error.ValueTooLarge;
    }
    return @intCast(value);
}

fn checkRange(total: u64, offset: u64, len: u64) !void {
    if (offset > total) return error.OutOfBounds;
    if (len > total - offset) return error.OutOfBounds;
}

fn acquireFileLock(fd: posix.fd_t) !void {
    const flock = posix.Flock{
        .type = posix.F.WRLCK,
        .whence = posix.SEEK.SET,
        .start = 0,
        .len = 0,
        .pid = 0,
    };
    _ = posix.fcntl(fd, posix.F.SETLK, @intFromPtr(&flock)) catch |err| switch (err) {
        error.Locked => return error.HeapAlreadyLocked,
        else => return err,
    };
}

fn releaseFileLock(fd: posix.fd_t) void {
    const flock = posix.Flock{
        .type = posix.F.UNLCK,
        .whence = posix.SEEK.SET,
        .start = 0,
        .len = 0,
        .pid = 0,
    };
    _ = posix.fcntl(fd, posix.F.SETLK, @intFromPtr(&flock)) catch {};
}

fn openOrCreateFile(path: []const u8, size: u64) !OpenResult {
    var attempts: u32 = 0;
    while (attempts < 8) : (attempts += 1) {
        if (std.fs.cwd().openFile(path, .{ .mode = .read_write })) |existing| {
            errdefer existing.close();
            const stat = try existing.stat();
            const min = minimumHeapSize();
            if (stat.size > 0 and stat.size < min) {
                return error.ExistingFileTooSmall;
            }
            const desired = @max(size, min);
            const target_size = try normalizeHeapSize(@max(stat.size, desired));
            if (stat.size != target_size) {
                try existing.setEndPos(target_size);
                try posix.fsync(existing.handle);
            }
            return .{
                .file = existing,
                .needs_init = stat.size == 0,
                .is_new_file = false,
                .map_size = target_size,
            };
        } else |open_err| switch (open_err) {
            error.FileNotFound => {
                if (std.fs.cwd().createFile(path, .{ .read = true, .truncate = false, .exclusive = true })) |file| {
                    errdefer file.close();
                    const min = minimumHeapSize();
                    const target_size = try normalizeHeapSize(@max(size, min));
                    try file.setEndPos(target_size);
                    try posix.fsync(file.handle);
                    return .{
                        .file = file,
                        .needs_init = true,
                        .is_new_file = true,
                        .map_size = target_size,
                    };
                } else |create_err| switch (create_err) {
                    error.PathAlreadyExists => continue,
                    else => return create_err,
                }
            },
            else => return open_err,
        }
    }
    return error.OpenRetryExhausted;
}

fn mapFile(fd: posix.fd_t, size: u64) ![]align(page_size_min) u8 {
    const ps = pageSize();
    if (size == 0) return error.InvalidHeapSize;
    if (size % ps != 0) return error.HeapSizeNotPageAligned;
    const len = try u64ToUsize(size);
    const slice = try posix.mmap(
        null,
        len,
        PersistentHeap.MMAP_PROT,
        PersistentHeap.MMAP_FLAGS,
        fd,
        0,
    );
    return slice;
}

fn unmapFile(base_addr: []align(page_size_min) u8) void {
    if (base_addr.len == 0) return;
    posix.munmap(base_addr);
}

fn flushRangeRaw(base_addr: []align(page_size_min) u8, offset: u64, len: u64) !void {
    if (len == 0) return;
    const total_len_u64 = try usizeToU64(base_addr.len);
    try checkRange(total_len_u64, offset, len);

    const ps = std.heap.pageSize();
    if (ps == 0 or (ps & (ps - 1)) != 0) return error.InvalidPageSize;

    const offset_usize = try u64ToUsize(offset);
    const len_usize = try u64ToUsize(len);

    const base_addr_int = @intFromPtr(base_addr.ptr);
    const start_int_ov = @addWithOverflow(base_addr_int, offset_usize);
    if (start_int_ov[1] != 0) return error.IntegerOverflow;
    const start_int = start_int_ov[0];

    const page_aligned = start_int & ~(ps - 1);
    const offset_into_page = start_int - page_aligned;

    const total_ov = @addWithOverflow(len_usize, offset_into_page);
    if (total_ov[1] != 0) return error.IntegerOverflow;
    const total_len = total_ov[0];

    const aligned_len_unbounded = try alignForwardUsize(total_len, ps);
    const remaining_in_mapping = base_addr.len - offset_usize + offset_into_page;
    const aligned_len = @min(aligned_len_unbounded, remaining_in_mapping);
    const final_len = @min(aligned_len, base_addr.len - (offset_usize - offset_into_page));

    const aligned_ptr: [*]align(page_size_min) u8 = @ptrFromInt(page_aligned);
    try posix.msync(aligned_ptr[0..final_len], posix.MSF.SYNC);
}

fn alignForwardUsize(value: usize, alignment: usize) !usize {
    if (alignment == 0 or (alignment & (alignment - 1)) != 0) return error.InvalidAlignment;
    const mask = alignment - 1;
    const ov = @addWithOverflow(value, mask);
    if (ov[1] != 0) return error.IntegerOverflow;
    return ov[0] & ~mask;
}

test "heap initialization" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_init.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    try testing.expect(heap.size >= 1024 * 1024);
    try testing.expect(heap.pool_uuid != 0);
    try heap.deinit();
}

test "heap allocation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_alloc.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    try heap.beginTransaction();
    const ptr = try heap.allocate({}, 256, 64);
    try testing.expect(!ptr.isNull());
    try testing.expect(ptr.offset >= freeListRegionEnd() + objectHeaderSize());
    try testing.expect(ptr.offset % 64 == 0);

    const native = try heap.getNativePtr(u8, ptr);
    try testing.expect(native != null);

    try heap.endTransaction();
    try heap.deinit();
}

test "heap read/write" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_path = "test_heap_rw.dat";
    std.fs.cwd().deleteFile(test_path) catch {};
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const heap = try PersistentHeap.init(alloc, test_path, 1024 * 1024, null);
    try heap.beginTransaction();
    const ptr = try heap.allocate({}, 256, 8);
    try heap.endTransaction();

    const test_data: []const u8 = "Hello, Persistent World!";
    try heap.beginTransaction();
    try heap.writeObject({}, ptr.offset, test_data);
    try heap.endTransaction();

    const result_opt = try heap.readObject(ptr.offset);
    try testing.expect(result_opt != null);
    var result = result_opt.?;
    defer result.deinit();
    try testing.expectEqualSlices(u8, test_data, result.data[0..test_data.len]);

    try heap.deinit();
}

test "sim vfs torn write fault" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const prev_sim = tsc.is_simulation;
    tsc.initSimulation(42);
    defer {
        tsc.is_simulation = prev_sim;
    }

    const heap = try PersistentHeap.init(alloc, "sim_heap_torn.dat", 1024 * 1024, null);
    defer {
        heap.deinit() catch {};
    }

    try heap.beginTransaction();
    const ptr = try heap.allocate({}, 256, 8);
    try heap.endTransaction();

    const sim = heap.getSimBackend().?;
    sim.armFault(.{
        .kind = .torn_write,
        .trigger_offset = ptr.offset,
        .trigger_size = 256,
        .partial_bytes = 8,
        .armed = true,
    });

    const data = "0123456789ABCDEF0123456789ABCDEF";
    try heap.beginTransaction();
    const write_result = heap.writeObject({}, ptr.offset, data);
    try testing.expectError(error.SimulatedTornWrite, write_result);
    heap.endTransaction() catch {};

    const payload_idx: usize = @intCast(ptr.offset);
    const partial_check = sim.buf[payload_idx .. payload_idx + 8];
    try testing.expectEqualSlices(u8, data[0..8], partial_check);

    sim.disarmFault();
}