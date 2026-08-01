const std = @import("std");
const sandbox = @import("sandbox.zig");
const ipc = @import("ipc.zig");

pub const SandboxHandle = sandbox.SandboxHandle;

pub const WaitingRequest = struct {
    response_buf: []u8,
    response_len: usize,
    status: u8,
    sem: std.Thread.Semaphore,
    completed: std.atomic.Value(bool),
    tenant_id: u64 = 0,
};

const seccomp_notif = extern struct {
    id: u64,
    pid: u32,
    flags: u32,
    data: extern struct {
        op: i32,
        arch: u32,
        instruction_pointer: u64,
        args: [6]u64,
    },
};

const seccomp_notif_resp = extern struct {
    id: u64,
    val: i64,
    error_code: i32,
    flags: u32,
};

const SECCOMP_IOC_NOTIF_RECV: u32 = 0xC0502100;
const SECCOMP_IOC_NOTIF_RESP: u32 = 0xC0182101;
const SECCOMP_USER_NOTIF_FLAG_CONTINUE: u32 = 0x00000001;

const SECCOMP_ALLOWED_SYSCALLS = [_]i32{
    1,
    3,
    4,
    5,
    8,
    9,
    10,
    11,
    12,
    13,
    17,
    21,
    25,
    28,
    39,
    41,
    42,
    43,
    44,
    45,
    46,
    48,
    72,
    73,
    74,
    75,
    76,
    78,
    79,
    82,
    83,
    89,
    90,
    96,
    97,
    99,
    102,
    107,
    108,
    131,
    158,
    202,
    218,
    228,
    229,
    232,
    233,
    257,
    262,
    293,
    318,
};

const ProcMemCtx = struct {
    mem_fd: i32,
    pid: u32,
};

fn openProcMem(pid: u32, allocator: std.mem.Allocator) !ProcMemCtx {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&path_buf, "/proc/{d}/mem", .{pid});
    _ = allocator;
    const fd_rc = std.os.linux.open(path.ptr, @as(std.os.linux.O, .{ .ACCMODE = .RDONLY, .LARGEFILE = true }), 0);
    if (std.posix.errno(fd_rc) != .SUCCESS) return error.ProcMemOpenFailed;
    return ProcMemCtx{ .mem_fd = @intCast(fd_rc), .pid = pid };
}

fn closeProcMem(ctx: ProcMemCtx) void {
    _ = std.os.linux.close(ctx.mem_fd);
}

fn preadProcMem(ctx: ProcMemCtx, addr: u64, buf: []u8) !usize {
    const rc = std.os.linux.pread(ctx.mem_fd, buf.ptr, buf.len, @intCast(addr));
    const err = std.posix.errno(rc);
    if (err != .SUCCESS) return error.ProcMemReadFailed;
    return @intCast(rc);
}

fn isSyscallAllowed(op: i32) bool {
    for (SECCOMP_ALLOWED_SYSCALLS) |allowed| {
        if (op == allowed) return true;
    }
    return false;
}

fn validateOpenatArgs(ctx: ProcMemCtx, args: [6]u64, allocator: std.mem.Allocator) bool {
    const path_ptr = args[1];
    if (path_ptr == 0) return false;
    var path_buf: [4096]u8 = undefined;
    const n = preadProcMem(ctx, path_ptr, &path_buf) catch return false;
    _ = n;
    const path_str = std.mem.sliceTo(&path_buf, 0);
    _ = allocator;
    if (std.mem.startsWith(u8, path_str, "/proc")) {
        if (!std.mem.startsWith(u8, path_str, "/proc/self")) return false;
    }
    if (std.mem.startsWith(u8, path_str, "/sys")) return false;
    if (std.mem.startsWith(u8, path_str, "/dev") and
        !std.mem.eql(u8, path_str, "/dev/null") and
        !std.mem.eql(u8, path_str, "/dev/zero") and
        !std.mem.eql(u8, path_str, "/dev/urandom")) return false;
    return true;
}

fn dispatchSyscallOnBehalf(notif: *const seccomp_notif, allocator: std.mem.Allocator) seccomp_notif_resp {
    var resp = seccomp_notif_resp{
        .id = notif.id,
        .val = 0,
        .error_code = 0,
        .flags = 0,
    };

    if (!isSyscallAllowed(notif.data.op)) {
        resp.error_code = @intFromEnum(std.os.linux.E.PERM);
        resp.val = -1;
        return resp;
    }

    const proc_ctx = openProcMem(notif.pid, allocator) catch {
        resp.error_code = @intFromEnum(std.os.linux.E.PERM);
        resp.val = -1;
        return resp;
    };
    defer closeProcMem(proc_ctx);

    const SYS_openat: i32 = 257;
    const SYS_open: i32 = 2;

    if (notif.data.op == SYS_openat or notif.data.op == SYS_open) {
        const valid = validateOpenatArgs(proc_ctx, notif.data.args, allocator);
        if (!valid) {
            resp.error_code = @intFromEnum(std.os.linux.E.ACCES);
            resp.val = -1;
            return resp;
        }
    }

    resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE;
    return resp;
}

const SeccompSupervisorCtx = struct {
    seccomp_fd: i32,
    pid: u32,
    tenant_id: u64,
    allocator: std.mem.Allocator,
    shutdown: *std.atomic.Value(bool),
};

fn seccompSupervisorThread(ctx: SeccompSupervisorCtx) void {
    var notif: seccomp_notif = undefined;

    while (!ctx.shutdown.load(.acquire)) {
        @memset(std.mem.asBytes(&notif), 0);

        const recv_rc = std.os.linux.ioctl(
            ctx.seccomp_fd,
            SECCOMP_IOC_NOTIF_RECV,
            @intFromPtr(&notif),
        );

        if (std.posix.errno(recv_rc) != .SUCCESS) {
            const e = std.posix.errno(recv_rc);
            if (e == .INTR) continue;
            break;
        }

        const resp = dispatchSyscallOnBehalf(&notif, ctx.allocator);

        const resp_rc = std.os.linux.ioctl(
            ctx.seccomp_fd,
            SECCOMP_IOC_NOTIF_RESP,
            @intFromPtr(&resp),
        );

        if (std.posix.errno(resp_rc) != .SUCCESS) {
            const e = std.posix.errno(resp_rc);
            if (e == .NOENT) continue;
            break;
        }
    }

    _ = std.os.linux.close(ctx.seccomp_fd);
}

const SupervisorEntry = struct {
    tenant_id: u64,
    thread: std.Thread,
    shutdown: *std.atomic.Value(bool),
    allocator: std.mem.Allocator,
};

pub const ProcessTable = struct {
    slots: []?SandboxHandle,
    epoll_fd: i32,
    mu: std.Thread.Mutex,
    pending_requests: std.AutoHashMap(u64, *WaitingRequest),
    pending_mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    supervisors: std.ArrayList(SupervisorEntry),
    supervisors_mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) !*ProcessTable {
        const self = try allocator.create(ProcessTable);
        errdefer allocator.destroy(self);

        const slots = try allocator.alloc(?SandboxHandle, 4096);
        errdefer allocator.free(slots);
        @memset(slots, null);

        const epoll_fd_rc = std.os.linux.epoll_create1(0);
        if (std.posix.errno(epoll_fd_rc) != .SUCCESS) return error.EpollCreateFailed;

        self.* = ProcessTable{
            .slots = slots,
            .epoll_fd = @intCast(epoll_fd_rc),
            .mu = .{},
            .pending_requests = std.AutoHashMap(u64, *WaitingRequest).init(allocator),
            .pending_mutex = .{},
            .allocator = allocator,
            .supervisors = std.ArrayList(SupervisorEntry).init(allocator),
            .supervisors_mu = .{},
        };
        return self;
    }

    pub fn deinit(self: *ProcessTable) void {
        self.stopAllSupervisors();

        var handles_to_destroy = std.ArrayList(SandboxHandle).init(self.allocator);
        defer handles_to_destroy.deinit();
        {
            self.mu.lock();
            defer self.mu.unlock();
            for (self.slots, 0..) |maybe_handle, i| {
                if (maybe_handle) |handle| {
                    handles_to_destroy.append(handle) catch {
                        sandbox.destroySandbox(handle) catch {};
                    };
                    self.slots[i] = null;
                }
            }
        }
        for (handles_to_destroy.items) |h| {
            sandbox.destroySandbox(h) catch {};
        }
        self.allocator.free(self.slots);
        _ = std.os.linux.close(self.epoll_fd);
        self.pending_requests.deinit();
        self.supervisors.deinit();
        self.allocator.destroy(self);
    }

    fn stopAllSupervisors(self: *ProcessTable) void {
        self.supervisors_mu.lock();
        for (self.supervisors.items) |*sv| {
            sv.shutdown.store(true, .release);
        }
        var to_join = std.ArrayList(SupervisorEntry).init(self.allocator);
        for (self.supervisors.items) |sv| {
            to_join.append(sv) catch {
                var sv_copy = sv;
                sv_copy.thread.join();
                self.allocator.destroy(sv_copy.shutdown);
            };
        }
        self.supervisors.clearRetainingCapacity();
        self.supervisors_mu.unlock();

        for (to_join.items) |*sv| {
            sv.thread.join();
            self.allocator.destroy(sv.shutdown);
        }
        to_join.deinit();
    }

    pub fn spawnSeccompSupervisor(self: *ProcessTable, seccomp_fd: i32, pid: u32, tenant_id: u64) !void {
        const shutdown_flag = try self.allocator.create(std.atomic.Value(bool));
        errdefer self.allocator.destroy(shutdown_flag);
        shutdown_flag.* = std.atomic.Value(bool).init(false);

        const ctx = SeccompSupervisorCtx{
            .seccomp_fd = seccomp_fd,
            .pid = pid,
            .tenant_id = tenant_id,
            .allocator = self.allocator,
            .shutdown = shutdown_flag,
        };

        const thread = try std.Thread.spawn(.{}, seccompSupervisorThread, .{ctx});
        errdefer {
            shutdown_flag.store(true, .release);
            thread.join();
        }

        self.supervisors_mu.lock();
        defer self.supervisors_mu.unlock();
        try self.supervisors.append(SupervisorEntry{
            .tenant_id = tenant_id,
            .thread = thread,
            .shutdown = shutdown_flag,
            .allocator = self.allocator,
        });
    }

    pub fn stopSeccompSupervisor(self: *ProcessTable, tenant_id: u64) void {
        self.supervisors_mu.lock();
        defer self.supervisors_mu.unlock();

        var i: usize = 0;
        while (i < self.supervisors.items.len) {
            if (self.supervisors.items[i].tenant_id == tenant_id) {
                const sv = self.supervisors.orderedRemove(i);
                sv.shutdown.store(true, .release);
                sv.thread.join();
                self.allocator.destroy(sv.shutdown);
            } else {
                i += 1;
            }
        }
    }

    pub fn insertLocked(self: *ProcessTable, handle: SandboxHandle) !void {
        var free_slot: ?usize = null;
        for (self.slots, 0..) |maybe_handle, i| {
            if (maybe_handle == null) {
                free_slot = i;
                break;
            }
        }

        const idx = free_slot orelse return error.ProcessTableFull;
        self.slots[idx] = handle;

        var event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP,
            .data = .{ .u64 = handle.tenant_id },
        };
        const rc = std.os.linux.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, handle.ipc_fd, &event);
        if (std.posix.errno(rc) != .SUCCESS) {
            self.slots[idx] = null;
            return error.EpollCtlFailed;
        }
    }

    pub fn insert(self: *ProcessTable, handle: SandboxHandle) !void {
        self.mu.lock();
        defer self.mu.unlock();
        try self.insertLocked(handle);
    }

    pub fn insertWithSeccomp(self: *ProcessTable, handle: SandboxHandle, seccomp_fd: i32) !void {
        self.mu.lock();
        defer self.mu.unlock();
        try self.insertLocked(handle);
        try self.spawnSeccompSupervisor(seccomp_fd, @intCast(handle.pid), handle.tenant_id);
    }

    pub fn lookupLocked(self: *ProcessTable, tenant_id: u64) ?*SandboxHandle {
        for (self.slots) |*maybe_handle| {
            if (maybe_handle.*) |*handle| {
                if (handle.tenant_id == tenant_id) return handle;
            }
        }
        return null;
    }

    pub fn getHandle(self: *ProcessTable, tenant_id: u64) ?SandboxHandle {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.lookupLocked(tenant_id)) |h| return h.*;
        return null;
    }

    pub fn updateActivity(self: *ProcessTable, tenant_id: u64) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.lookupLocked(tenant_id)) |h| {
            h.last_activity_ns = @intCast(std.time.nanoTimestamp());
        }
    }

    pub fn removeLocked(self: *ProcessTable, tenant_id: u64) void {
        for (self.slots, 0..) |maybe_handle, i| {
            if (maybe_handle) |handle| {
                if (handle.tenant_id == tenant_id) {
                    _ = std.os.linux.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, handle.ipc_fd, null);
                    self.slots[i] = null;
                    return;
                }
            }
        }
    }

    pub fn remove(self: *ProcessTable, tenant_id: u64) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.removeLocked(tenant_id);
        self.stopSeccompSupervisor(tenant_id);
    }

    fn failPendingForTenant(self: *ProcessTable, tenant_id: u64) void {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();
        var to_fail = std.ArrayList(u64).init(self.allocator);
        defer to_fail.deinit();
        var it = self.pending_requests.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*.tenant_id == tenant_id) {
                to_fail.append(entry.key_ptr.*) catch {
                    const wr = entry.value_ptr.*;
                    if (!wr.completed.load(.acquire)) {
                        wr.status = 0xFF;
                        wr.response_len = 0;
                        wr.completed.store(true, .release);
                        wr.sem.post();
                    }
                };
            }
        }
        for (to_fail.items) |req_id| {
            if (self.pending_requests.get(req_id)) |wr| {
                if (!wr.completed.load(.acquire)) {
                    wr.status = 0xFF;
                    wr.response_len = 0;
                    wr.completed.store(true, .release);
                    wr.sem.post();
                }
            }
        }
    }

    fn reapZombies(self: *ProcessTable) void {
        var status: u32 = 0;
        while (true) {
            const pid_rc = std.os.linux.wait4(-1, &status, std.os.linux.W.NOHANG, null);
            const err = std.posix.errno(pid_rc);
            if (err != .SUCCESS) break;
            if (pid_rc <= 0) break;

            const pid: i32 = @intCast(pid_rc);
            var found_tenant: ?u64 = null;
            {
                self.mu.lock();
                defer self.mu.unlock();
                for (self.slots) |maybe_handle| {
                    if (maybe_handle) |h| {
                        if (h.pid == pid) {
                            found_tenant = h.tenant_id;
                            break;
                        }
                    }
                }
                if (found_tenant) |tid| {
                    self.removeLocked(tid);
                }
            }

            if (found_tenant) |tid| {
                self.failPendingForTenant(tid);
                self.stopSeccompSupervisor(tid);
            }
        }
    }

    fn reapIdleSandboxes(self: *ProcessTable, now: i64) void {
        var to_destroy = std.ArrayList(SandboxHandle).init(self.allocator);
        defer to_destroy.deinit();

        const idle_limit_ns = 10 * 60 * std.time.ns_per_s;

        self.mu.lock();
        for (self.slots, 0..) |maybe_handle, i| {
            if (maybe_handle) |h| {
                if (now - h.last_activity_ns > idle_limit_ns) {
                    _ = std.os.linux.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, h.ipc_fd, null);
                    self.slots[i] = null;
                    to_destroy.append(h) catch {
                        self.stopSeccompSupervisor(h.tenant_id);
                        sandbox.destroySandbox(h) catch {};
                    };
                }
            }
        }
        self.mu.unlock();

        for (to_destroy.items) |h| {
            self.stopSeccompSupervisor(h.tenant_id);
            sandbox.destroySandbox(h) catch {};
        }
    }

    pub fn runDispatchLoop(self: *ProcessTable) !void {
        var events: [64]std.os.linux.epoll_event = undefined;
        var last_sweep_ns: i64 = @intCast(std.time.nanoTimestamp());

        while (true) {
            const rc = std.os.linux.epoll_wait(self.epoll_fd, &events, 64, 5000);
            const err = std.posix.errno(rc);

            const now: i64 = @intCast(std.time.nanoTimestamp());
            if (now - last_sweep_ns > 5 * std.time.ns_per_s) {
                self.reapZombies();
                self.reapIdleSandboxes(now);
                last_sweep_ns = now;
            }

            if (err != .SUCCESS) {
                if (err == .INTR) continue;
                if (err == .BADF or err == .INVAL) return error.EpollWaitFailed;
                std.log.err("epoll_wait transient error: {}", .{err});
                continue;
            }
            const n: usize = @intCast(rc);
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const tenant_id = events[i].data.u64;

                var ipc_fd: i32 = -1;
                {
                    self.mu.lock();
                    if (self.lookupLocked(tenant_id)) |h| {
                        ipc_fd = h.ipc_fd;
                    }
                    self.mu.unlock();
                }
                if (ipc_fd < 0) continue;

                const ev_flags = events[i].events;
                if ((ev_flags & (std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP)) != 0 and (ev_flags & std.os.linux.EPOLL.IN) == 0) {
                    self.remove(tenant_id);
                    self.failPendingForTenant(tenant_id);
                    continue;
                }

                var msg = ipc.recvMessage(self.allocator, ipc_fd) catch |rerr| {
                    if (rerr == error.ConnectionClosed) {
                        self.remove(tenant_id);
                        self.failPendingForTenant(tenant_id);
                    }
                    continue;
                };
                defer msg.deinit(self.allocator);

                self.pending_mutex.lock();
                const wait_opt = self.pending_requests.get(msg.header.request_id);
                if (wait_opt) |wait_req| {
                    _ = self.pending_requests.remove(msg.header.request_id);
                    self.pending_mutex.unlock();

                    const copy_len = @min(wait_req.response_buf.len, msg.payload.len);
                    if (copy_len > 0) {
                        @memcpy(wait_req.response_buf[0..copy_len], msg.payload[0..copy_len]);
                    }
                    wait_req.response_len = copy_len;
                    wait_req.status = msg.header.status;
                    wait_req.completed.store(true, .release);
                    wait_req.sem.post();
                } else {
                    self.pending_mutex.unlock();
                }
            }
        }
    }
};
