const std = @import("std");
const build_options = @import("build_options");
const registry = @import("registry.zig");
const builtin = @import("builtin");

const linux = std.os.linux;
const E = linux.E;
const native_endian = builtin.cpu.arch.endian();

comptime {
    if (builtin.os.tag != .linux) @compileError("the tenant sandbox requires a Linux target");
    switch (builtin.cpu.arch) {
        .x86_64, .aarch64 => {},
        else => @compileError("the tenant sandbox supports x86_64 and aarch64 Linux targets"),
    }
}

pub const SandboxHandle = struct {
    tenant_id: u64,
    pid: i32,
    cgroup_fd: i32,
    ipc_fd: i32,
    last_activity_ns: i64,
    started_at_unix_ms: i64,
    stateless: bool = false,
    pidfd: i32 = -1,
    cgroup_serial: u64 = 0,
};

pub const SandboxError = error{
    InvalidTenantId,
    InvalidDataPath,
    DataPathOutsideRoot,
    InvalidWalEndpoint,
    WalEndpointTooLong,
    MissingWalEndpoint,
    WalEndpointUnreachable,
    TenantDataUnavailable,
    TenantDataOwnershipMismatch,
    TenantSandboxBusy,
    RunnerUnavailable,
    CapabilityQueryFailed,
    SupplementaryGroupsNotClearable,
    SubordinateIdRangeUnavailable,
    IdentityPoolExhausted,
    SandboxRegistryFailure,
    CgroupV2Unavailable,
    CgroupBaseUnavailable,
    CgroupControllersUnavailable,
    CgroupSelfUnknown,
    CgroupDelegationDenied,
    CgroupCreateFailed,
    CgroupOpenFailed,
    CgroupMemoryLimitFailed,
    CgroupSwapLimitFailed,
    CgroupPidsLimitFailed,
    CgroupCpuLimitFailed,
    CgroupOomGroupFailed,
    SocketCreationFailed,
    SignalMaskFailed,
    ProcessLimitReached,
    NamespaceLimitReached,
    NamespaceCreationDenied,
    CgroupNotEligible,
    SystemResources,
    CloneUnsupported,
    CloneRejected,
    PidfdUnavailable,
    CgroupMigrationFailed,
    CgroupMigrationUnverified,
    ChildProcessVanished,
    SetgroupsPolicyFailed,
    UidMapFailed,
    GidMapFailed,
    IdmappedMountFailed,
    ControlChannelFailed,
    HandshakeTimeout,
    ChildProtocolViolation,
    ReadinessTimeout,
    ReadinessProtocolViolation,
    SandboxExitedDuringStartup,
    ClockUnavailable,
    ChildSignalSetupFailed,
    ChildFdCleanupFailed,
    ChildStdioFailed,
    ChildHandshakeFailed,
    ChildSetgroupsFailed,
    ChildSetgidFailed,
    ChildSetuidFailed,
    ChildIdentityUnverified,
    ChildDeathSignalFailed,
    ChildCgroupNamespaceFailed,
    ChildSessionFailed,
    ChildMountPropagationFailed,
    ChildRootMountFailed,
    ChildRootLayoutFailed,
    ChildDeviceBindFailed,
    ChildRunnerBindFailed,
    ChildDataBindFailed,
    ChildProcMountFailed,
    ChildPivotRootFailed,
    ChildLoopbackFailed,
    ChildWalRelayFailed,
    ChildNoNewPrivsFailed,
    ChildSeccompFailed,
    ChildCapabilitiesFailed,
    ChildExecChannelFailed,
    ChildForkFailed,
    RunnerDeathSignalFailed,
    RunnerFdLayoutFailed,
    RunnerCapabilitiesFailed,
    RunnerSignalMaskFailed,
    RunnerExecFailed,
    RunnerExecTimeout,
    SandboxNotFound,
    SignalDeliveryFailed,
    WaitFailed,
    TerminationTimeout,
    CgroupKillFailed,
    CgroupDrainTimeout,
    CgroupRemoveFailed,
};

pub const Failure = struct {
    err: ?SandboxError = null,
    errno_value: u16 = 0,
    exit_status: ?u32 = null,
};

threadlocal var last_failure: Failure = .{};

pub fn lastFailure() Failure {
    return last_failure;
}

const cgroup_mount_path = "/sys/fs/cgroup";
const cgroup_base_name = "agdb";
const cgroup_base_path = cgroup_mount_path ++ "/" ++ cgroup_base_name;
const cgroup2_super_magic: u64 = 0x63677270;
const required_controllers = [_][]const u8{ "memory", "pids", "cpu" };

const CgroupLimit = struct {
    file: [:0]const u8,
    value: []const u8,
    optional: bool,
    err: SandboxError,
};

const cgroup_limits = [_]CgroupLimit{
    .{ .file = "memory.max", .value = "536870912", .optional = false, .err = error.CgroupMemoryLimitFailed },
    .{ .file = "memory.swap.max", .value = "0", .optional = true, .err = error.CgroupSwapLimitFailed },
    .{ .file = "pids.max", .value = "64", .optional = false, .err = error.CgroupPidsLimitFailed },
    .{ .file = "cpu.max", .value = "500000 1000000", .optional = false, .err = error.CgroupCpuLimitFailed },
    .{ .file = "memory.oom.group", .value = "1", .optional = true, .err = error.CgroupOomGroupFailed },
};

const handshake_timeout_ms: u32 = 5_000;
const exec_status_timeout_ms: u32 = 10_000;
const readiness_timeout_ms: u32 = 15_000;
const graceful_stop_timeout_ms: u32 = 3_000;
const forced_stop_timeout_ms: u32 = 5_000;
const startup_exit_grace_ms: u32 = 250;
const cgroup_drain_timeout_ms: u32 = 5_000;
const cgroup_remove_attempts: u32 = 50;
const cgroup_remove_backoff_ms: u32 = 20;
const cgroup_kill_rounds: u32 = 16;
const cgroup_kill_backoff_ms: u32 = 10;
const data_lock_timeout_ms: u32 = 10_000;
const data_lock_retry_ms: u32 = 50;
const wal_connect_timeout_ms: u32 = 5_000;
const default_wal_port: u16 = 7442;
const max_identity_slots: u32 = 65_536;
const max_nested_cgroup_depth: u32 = 16;
const relay_buffer_size: usize = 16 * 1024;
const root_tmpfs_options = "mode=0755,size=16m,nr_inodes=16384";
const device_nodes = [_][:0]const u8{ "null", "zero", "urandom" };
const staging_candidates = [_][:0]const u8{ "/tmp", "/mnt", "/run", "/var/tmp" };
const forwarded_signals = [_]u32{ linux.SIG.HUP, linux.SIG.INT, linux.SIG.QUIT, linux.SIG.USR1, linux.SIG.USR2, linux.SIG.ALRM, linux.SIG.TERM, linux.SIG.CONT, linux.SIG.WINCH };

const data_path_capacity = @typeInfo(@FieldType(registry.TenantRecord, "data_path")).array.len;
const wal_endpoint_capacity = @typeInfo(@FieldType(registry.TenantRecord, "wal_endpoint")).array.len;
const wal_environment_name = "AGDB_WAL_ENDPOINT=";
const relay_host = "127.0.0.1";
const wal_environment_capacity = wal_environment_name.len + @max(wal_endpoint_capacity, relay_host.len + 6) + 1;
const staging_path_capacity = 16;
const sandbox_path_capacity = staging_path_capacity + data_path_capacity + build_options.sandbox_runner_path.len + 8;
const cgroup_name_capacity = 64;
const proc_fd_path_capacity = 40;

const runner_ipc_fd: i32 = 3;
const runner_report_fd: i32 = 4;
const runner_ipc_fd_text = std.fmt.comptimePrint("{d}", .{runner_ipc_fd});
const descriptor_staging_floor: usize = 16;

const ipc_magic: u32 = 0x47444241;
const ipc_header_size: usize = 20;
const readiness_request_id: u64 = 0;
const readiness_message_type: u8 = 0;
const readiness_payload_limit: u32 = 4096;

const control_magic: u32 = 0x58424453;
const go_token: u32 = 1;

const ControlKind = enum(u32) {
    maps_ready = 1,
    armed = 2,
    go = 3,
    ready = 4,
    failure = 5,
};

const ControlMessage = extern struct {
    magic: u32,
    kind: u32,
    code: u32,
    errno_value: u32,
};

const CmsgHeader = extern struct {
    len: usize,
    level: i32,
    kind: i32,
};

const cmsg_data_offset = std.mem.alignForward(usize, @sizeOf(CmsgHeader), @alignOf(usize));
const cmsg_fd_len = cmsg_data_offset + @sizeOf(i32);
const cmsg_fd_space = std.mem.alignForward(usize, cmsg_fd_len, @alignOf(usize));

const clone_args = extern struct {
    flags: u64,
    pidfd: u64,
    child_tid: u64,
    parent_tid: u64,
    exit_signal: u64,
    stack: u64,
    stack_size: u64,
    tls: u64,
    set_tid: u64,
    set_tid_size: u64,
    cgroup: u64,
};

const clone_args_size_ver0: usize = 64;
const clone_namespace_flags: u64 = linux.CLONE.NEWUSER | linux.CLONE.NEWNS | linux.CLONE.NEWPID | linux.CLONE.NEWNET | linux.CLONE.NEWIPC | linux.CLONE.NEWUTS;

const CapHeader = extern struct {
    version: u32,
    pid: i32,
};

const CapData = extern struct {
    effective: u32,
    permitted: u32,
    inheritable: u32,
};

const KernelSigaction = extern struct {
    handler: usize,
    flags: c_ulong,
    restorer: usize,
    mask: [2]u32,
};

const StatFs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

const MountAttr = extern struct {
    attr_set: u64,
    attr_clr: u64,
    propagation: u64,
    userns_fd: u64,
};

const SockFilter = extern struct {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
};

const SockFprog = extern struct {
    len: u16,
    filter: [*]const SockFilter,
};

const linux_capability_version_3: u32 = 0x20080522;
const pr_cap_ambient_clear_all: usize = 4;
const f_dupfd_cloexec: i32 = 1030;
const at_eaccess: usize = 0x200;
const arch_get_fs: usize = 0x1003;
const open_tree_clone: u32 = 1;
const move_mount_f_empty_path: u32 = 0x4;
const mount_attr_nosuid: u64 = 0x2;
const mount_attr_nodev: u64 = 0x4;
const mount_attr_idmap: u64 = 0x00100000;
const st_rdonly: u64 = 0x1;
const st_nosuid: u64 = 0x2;
const st_nodev: u64 = 0x4;
const st_noexec: u64 = 0x8;
const st_noatime: u64 = 0x400;
const st_nodiratime: u64 = 0x800;
const st_relatime: u64 = 0x1000;
const cld_exited: i32 = 1;
const scm_rights: i32 = 1;
const x32_syscall_bit: u32 = 0x40000000;
const audit_arch_current: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 0xC000003E,
    .aarch64 => 0xC00000B7,
    else => @compileError("unsupported seccomp architecture"),
};
const close_range_max: u32 = std.math.maxInt(u32);
const empty_group_list = [_]u32{0};
const cloexec_flag_bits: u32 = @bitCast(linux.O{ .CLOEXEC = true });

const dir_flags: linux.O = .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true };
const read_flags: linux.O = .{ .ACCMODE = .RDONLY, .NOFOLLOW = true, .CLOEXEC = true };
const write_flags: linux.O = .{ .ACCMODE = .WRONLY, .NOFOLLOW = true, .CLOEXEC = true };
const mount_point_flags: linux.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true };

const data_root: []const u8 = blk: {
    var root: []const u8 = build_options.AGDB_DATA_ROOT;
    while (root.len > 1 and root[root.len - 1] == '/') root = root[0 .. root.len - 1];
    break :blk root;
};

const runner_path_z: [build_options.sandbox_runner_path.len:0]u8 = blk: {
    var buffer = [_:0]u8{0} ** build_options.sandbox_runner_path.len;
    @memcpy(buffer[0..build_options.sandbox_runner_path.len], build_options.sandbox_runner_path);
    break :blk buffer;
};

fn isSafeComponent(component: []const u8) bool {
    if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
    for (component) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn isCanonicalAbsolute(path: []const u8) bool {
    if (path.len < 2 or path[0] != '/' or path[path.len - 1] == '/') return false;
    var components = std.mem.splitScalar(u8, path[1..], '/');
    while (components.next()) |component| {
        if (!isSafeComponent(component)) return false;
    }
    return true;
}

fn isWithin(path: []const u8, root: []const u8) bool {
    return path.len > root.len and std.mem.startsWith(u8, path, root) and path[root.len] == '/';
}

comptime {
    @setEvalBranchQuota(100_000);
    if (!isCanonicalAbsolute(build_options.sandbox_runner_path)) @compileError("sandbox_runner_path must be a canonical absolute path");
    if (!isCanonicalAbsolute(data_root)) @compileError("AGDB_DATA_ROOT must be a canonical absolute path");
    if (isWithin(build_options.sandbox_runner_path, data_root)) @compileError("sandbox_runner_path must not be located inside AGDB_DATA_ROOT");
    for ([_][]const u8{ "/proc", "/dev", "/sys" }) |reserved| {
        if (std.mem.eql(u8, data_root, reserved) or isWithin(data_root, reserved)) @compileError("AGDB_DATA_ROOT must not be located inside /proc, /dev or /sys");
        if (isWithin(build_options.sandbox_runner_path, reserved)) @compileError("sandbox_runner_path must not be located inside /proc, /dev or /sys");
    }
}

fn fail(err: SandboxError, errno_value: E) SandboxError {
    last_failure = .{ .err = err, .errno_value = @intFromEnum(errno_value) };
    return err;
}

fn errorCode(err: SandboxError) u32 {
    return @intFromError(err);
}

fn sandboxErrorFromCode(code: u32) ?SandboxError {
    inline for (@typeInfo(SandboxError).error_set.?) |info| {
        const candidate = @field(SandboxError, info.name);
        if (@intFromError(candidate) == code) return candidate;
    }
    return null;
}

fn errnoFromCode(code: u32) E {
    const value = std.math.cast(u16, code) orelse return .IO;
    return @enumFromInt(value);
}

const SysResult = struct {
    value: usize,
    err: E,

    fn ok(self: SysResult) bool {
        return self.err == .SUCCESS;
    }

    fn fd(self: SysResult) i32 {
        return @intCast(self.value);
    }
};

fn sys(rc: usize) SysResult {
    const err = E.init(rc);
    return .{ .value = if (err == .SUCCESS) rc else 0, .err = err };
}

fn retry(comptime function: anytype, args: anytype) usize {
    while (true) {
        const rc = @call(.auto, function, args);
        if (E.init(rc) != .INTR) return rc;
    }
}

fn fdArg(fd: i32) usize {
    return @bitCast(@as(isize, fd));
}

fn closeFd(fd: *i32) void {
    if (fd.* >= 0) {
        _ = linux.close(fd.*);
        fd.* = -1;
    }
}

fn openAt(dir_fd: i32, path: [*:0]const u8, flags: linux.O) SysResult {
    return sys(retry(linux.openat, .{ dir_fd, path, flags, @as(linux.mode_t, 0) }));
}

fn writeOnce(fd: i32, data: []const u8) E {
    const rc = retry(linux.write, .{ fd, data.ptr, data.len });
    const err = E.init(rc);
    if (err != .SUCCESS) return err;
    if (rc != data.len) return .IO;
    return .SUCCESS;
}

fn writeFileAt(dir_fd: i32, name: [*:0]const u8, data: []const u8) E {
    const opened = openAt(dir_fd, name, write_flags);
    if (!opened.ok()) return opened.err;
    var fd = opened.fd();
    defer closeFd(&fd);
    return writeOnce(fd, data);
}

const ReadResult = struct {
    data: []u8,
    err: E,
};

fn readFileAt(dir_fd: i32, name: [*:0]const u8, buffer: []u8) ReadResult {
    const opened = openAt(dir_fd, name, read_flags);
    if (!opened.ok()) return .{ .data = buffer[0..0], .err = opened.err };
    var fd = opened.fd();
    defer closeFd(&fd);
    var length: usize = 0;
    while (length < buffer.len) {
        const result = sys(retry(linux.read, .{ fd, buffer[length..].ptr, buffer.len - length }));
        if (!result.ok()) return .{ .data = buffer[0..0], .err = result.err };
        if (result.value == 0) return .{ .data = buffer[0..length], .err = .SUCCESS };
        length += result.value;
    }
    return .{ .data = buffer[0..0], .err = .FBIG };
}

const LineReader = struct {
    fd: i32,
    buffer: []u8,
    start: usize = 0,
    end: usize = 0,
    eof: bool = false,

    fn next(self: *LineReader) error{ ReadFailed, LineTooLong }!?[]const u8 {
        while (true) {
            if (std.mem.indexOfScalarPos(u8, self.buffer[0..self.end], self.start, '\n')) |newline| {
                const line = self.buffer[self.start..newline];
                self.start = newline + 1;
                return line;
            }
            if (self.eof) {
                if (self.start == self.end) return null;
                const line = self.buffer[self.start..self.end];
                self.start = self.end;
                return line;
            }
            if (self.start > 0) {
                std.mem.copyForwards(u8, self.buffer[0 .. self.end - self.start], self.buffer[self.start..self.end]);
                self.end -= self.start;
                self.start = 0;
            }
            if (self.end == self.buffer.len) return error.LineTooLong;
            const result = sys(retry(linux.read, .{ self.fd, self.buffer[self.end..].ptr, self.buffer.len - self.end }));
            if (!result.ok()) return error.ReadFailed;
            if (result.value == 0) {
                self.eof = true;
            } else {
                self.end += result.value;
            }
        }
    }
};

const DirEntry = struct {
    name: [:0]const u8,
    kind: u8,
};

const DirReader = struct {
    fd: i32,
    buffer: [4096]u8 align(8) = undefined,
    length: usize = 0,
    offset: usize = 0,

    fn next(self: *DirReader) error{ReadFailed}!?DirEntry {
        while (true) {
            if (self.offset < self.length) {
                const record_length = std.mem.readInt(u16, self.buffer[self.offset + 16 ..][0..2], native_endian);
                if (record_length < 20 or self.offset + record_length > self.length) return error.ReadFailed;
                const kind = self.buffer[self.offset + 18];
                const region = self.buffer[self.offset + 19 .. self.offset + record_length];
                self.offset += record_length;
                const name_length = std.mem.indexOfScalar(u8, region, 0) orelse return error.ReadFailed;
                return .{ .name = region[0..name_length :0], .kind = kind };
            }
            const result = sys(retry(linux.getdents64, .{ self.fd, &self.buffer, self.buffer.len }));
            if (!result.ok()) return error.ReadFailed;
            if (result.value == 0) return null;
            self.length = result.value;
            self.offset = 0;
        }
    }

    fn rewind(self: *DirReader) bool {
        self.length = 0;
        self.offset = 0;
        return E.init(linux.lseek(self.fd, 0, linux.SEEK.SET)) == .SUCCESS;
    }
};

fn clockNs(clock: linux.clockid_t) ?i64 {
    var ts: linux.timespec = undefined;
    if (E.init(linux.clock_gettime(clock, &ts)) != .SUCCESS) return null;
    if (ts.sec < 0 or ts.nsec < 0 or ts.nsec >= std.time.ns_per_s) return null;
    const seconds = std.math.mul(i64, ts.sec, std.time.ns_per_s) catch return null;
    return std.math.add(i64, seconds, ts.nsec) catch null;
}

const Deadline = struct {
    end_ns: i64,

    fn after(timeout_ms: u32) ?Deadline {
        const now = clockNs(.MONOTONIC) orelse return null;
        return .{ .end_ns = now +| @as(i64, timeout_ms) * std.time.ns_per_ms };
    }

    fn remainingMs(self: Deadline) i32 {
        const now = clockNs(.MONOTONIC) orelse return 0;
        if (now >= self.end_ns) return 0;
        const left_ms = @divFloor(self.end_ns - now - 1, std.time.ns_per_ms) + 1;
        return @intCast(@min(left_ms, std.math.maxInt(i32)));
    }
};

fn sleepMs(milliseconds: u32) void {
    var request = linux.timespec{
        .sec = @intCast(milliseconds / 1000),
        .nsec = @intCast(@as(u64, milliseconds % 1000) * std.time.ns_per_ms),
    };
    while (true) {
        var remaining: linux.timespec = undefined;
        if (E.init(linux.nanosleep(&request, &remaining)) != .INTR) return;
        request = remaining;
    }
}

fn pollUntil(fds: []linux.pollfd, deadline: Deadline) SysResult {
    while (true) {
        for (fds) |*entry| entry.revents = 0;
        const timeout = deadline.remainingMs();
        const result = sys(linux.poll(fds.ptr, fds.len, timeout));
        if (result.err == .INTR) {
            if (timeout == 0) return .{ .value = 0, .err = .SUCCESS };
            continue;
        }
        return result;
    }
}

var activity_clock_mutex: std.Thread.Mutex = .{};
var activity_clock_base: ?[2]i64 = null;

fn activityTimestampNs() SandboxError!i64 {
    activity_clock_mutex.lock();
    defer activity_clock_mutex.unlock();
    const boot_now = clockNs(.BOOTTIME) orelse return fail(error.ClockUnavailable, .NOSYS);
    if (activity_clock_base == null) {
        const real_now = clockNs(.REALTIME) orelse return fail(error.ClockUnavailable, .NOSYS);
        activity_clock_base = .{ real_now, boot_now };
    }
    const base = activity_clock_base.?;
    return std.math.add(i64, base[0], boot_now - base[1]) catch fail(error.ClockUnavailable, .OVERFLOW);
}

fn unixMillis() SandboxError!i64 {
    const now = clockNs(.REALTIME) orelse return fail(error.ClockUnavailable, .NOSYS);
    return @divFloor(now, std.time.ns_per_ms);
}

const ValidatedTenant = struct {
    tenant_id: u64,
    data_path: [:0]const u8,
    data_dir: [data_path_capacity:0]u8,
    data_dir_len: usize,
    stateless: bool,
    wal_host: [wal_endpoint_capacity]u8,
    wal_host_len: usize,
    wal_port: u16,

    fn dataDir(self: *const ValidatedTenant) [:0]const u8 {
        return self.data_dir[0..self.data_dir_len :0];
    }

    fn dataDirRelative(self: *const ValidatedTenant) []const u8 {
        return self.data_dir[1..self.data_dir_len];
    }

    fn walHost(self: *const ValidatedTenant) []const u8 {
        return self.wal_host[0..self.wal_host_len];
    }
};

fn validateTenant(tenant: *const registry.TenantRecord, out: *ValidatedTenant) SandboxError!void {
    if (tenant.tenant_id == 0) return fail(error.InvalidTenantId, .INVAL);
    const path_len = std.mem.indexOfScalar(u8, &tenant.data_path, 0) orelse return fail(error.InvalidDataPath, .NAMETOOLONG);
    var trimmed: []const u8 = tenant.data_path[0..path_len];
    while (trimmed.len > 1 and trimmed[trimmed.len - 1] == '/') trimmed = trimmed[0 .. trimmed.len - 1];
    if (!isCanonicalAbsolute(trimmed)) return fail(error.InvalidDataPath, .INVAL);
    var expected_buffer: [data_path_capacity]u8 = undefined;
    const expected = std.fmt.bufPrint(&expected_buffer, "{s}/{d}", .{ data_root, tenant.tenant_id }) catch return fail(error.DataPathOutsideRoot, .NAMETOOLONG);
    if (!std.mem.eql(u8, trimmed, expected)) return fail(error.DataPathOutsideRoot, .PERM);
    out.* = .{
        .tenant_id = tenant.tenant_id,
        .data_path = tenant.data_path[0..path_len :0],
        .data_dir = [_:0]u8{0} ** data_path_capacity,
        .data_dir_len = trimmed.len,
        .stateless = tenant.stateless != 0,
        .wal_host = [_]u8{0} ** wal_endpoint_capacity,
        .wal_host_len = 0,
        .wal_port = default_wal_port,
    };
    @memcpy(out.data_dir[0..trimmed.len], trimmed);
    if (out.stateless) try validateWalEndpoint(tenant, out);
}

fn validateWalEndpoint(tenant: *const registry.TenantRecord, out: *ValidatedTenant) SandboxError!void {
    const length = std.mem.indexOfScalar(u8, &tenant.wal_endpoint, 0) orelse return fail(error.WalEndpointTooLong, .NAMETOOLONG);
    const endpoint = tenant.wal_endpoint[0..length];
    if (endpoint.len == 0) return fail(error.MissingWalEndpoint, .INVAL);
    for (endpoint) |byte| {
        if (byte <= 0x20 or byte >= 0x7f) return fail(error.InvalidWalEndpoint, .INVAL);
    }
    var host: []const u8 = endpoint;
    var port_text: ?[]const u8 = null;
    if (endpoint[0] == '[') {
        const close = std.mem.indexOfScalar(u8, endpoint, ']') orelse return fail(error.InvalidWalEndpoint, .INVAL);
        host = endpoint[1..close];
        const rest = endpoint[close + 1 ..];
        if (rest.len > 0) {
            if (rest[0] != ':') return fail(error.InvalidWalEndpoint, .INVAL);
            port_text = rest[1..];
        }
    } else if (std.mem.lastIndexOfScalar(u8, endpoint, ':')) |colon| {
        host = endpoint[0..colon];
        port_text = endpoint[colon + 1 ..];
    }
    if (host.len == 0) return fail(error.InvalidWalEndpoint, .INVAL);
    if (port_text) |text| {
        const port = std.fmt.parseInt(u16, text, 10) catch return fail(error.InvalidWalEndpoint, .INVAL);
        if (port == 0) return fail(error.InvalidWalEndpoint, .INVAL);
        out.wal_port = port;
    }
    @memcpy(out.wal_host[0..host.len], host);
    out.wal_host_len = host.len;
}

const IdentityPlan = struct {
    distinct: bool,
    host_uid: u32,
    host_gid: u32,
    allow_setgroups: bool,
    slot: ?u32,
};

const SubordinateEntry = struct {
    start: u32,
    count: u32,
};

const SubordinateRange = struct {
    uid_start: u32,
    gid_start: u32,
    count: u32,
};

fn capabilityBit(capability: u6) u64 {
    return @as(u64, 1) << capability;
}

fn effectiveCapabilities() SandboxError!u64 {
    var header = CapHeader{ .version = linux_capability_version_3, .pid = 0 };
    var data: [2]CapData = undefined;
    const result = sys(linux.syscall2(.capget, @intFromPtr(&header), @intFromPtr(&data)));
    if (!result.ok()) return fail(error.CapabilityQueryFailed, result.err);
    return @as(u64, data[0].effective) | (@as(u64, data[1].effective) << 32);
}

fn planIdentity() SandboxError!IdentityPlan {
    const euid = linux.geteuid();
    const egid = linux.getegid();
    const capabilities = try effectiveCapabilities();
    const can_setuid = (capabilities & capabilityBit(linux.CAP.SETUID)) != 0;
    const can_setgid = (capabilities & capabilityBit(linux.CAP.SETGID)) != 0;
    if (euid == 0) {
        if (!can_setuid or !can_setgid) return fail(error.CapabilityQueryFailed, .PERM);
        const range = try subordinateRange(euid);
        const slot = try reserveIdentitySlot(range.count);
        return .{ .distinct = true, .host_uid = range.uid_start + slot, .host_gid = range.gid_start + slot, .allow_setgroups = true, .slot = slot };
    }
    if (!can_setgid) try requireNoSupplementaryGroups(egid);
    return .{ .distinct = false, .host_uid = euid, .host_gid = egid, .allow_setgroups = can_setgid, .slot = null };
}

fn requireNoSupplementaryGroups(egid: u32) SandboxError!void {
    const counted = sys(linux.getgroups(0, null));
    if (!counted.ok()) return fail(error.SupplementaryGroupsNotClearable, counted.err);
    if (counted.value == 0) return;
    var groups: [64]u32 = undefined;
    if (counted.value > groups.len) return fail(error.SupplementaryGroupsNotClearable, .PERM);
    const listed = sys(linux.getgroups(groups.len, &groups[0]));
    if (!listed.ok()) return fail(error.SupplementaryGroupsNotClearable, listed.err);
    for (groups[0..listed.value]) |gid| {
        if (gid != egid) return fail(error.SupplementaryGroupsNotClearable, .PERM);
    }
}

fn subordinateRange(uid: u32) SandboxError!SubordinateRange {
    var name_buffer: [256]u8 = undefined;
    const name = accountName(uid, &name_buffer);
    const uids = try subordinateEntry("/etc/subuid", name, uid);
    const gids = try subordinateEntry("/etc/subgid", name, uid);
    return .{ .uid_start = uids.start, .gid_start = gids.start, .count = @min(uids.count, gids.count, max_identity_slots) };
}

fn accountName(uid: u32, buffer: []u8) ?[]const u8 {
    const opened = openAt(linux.AT.FDCWD, "/etc/passwd", read_flags);
    if (!opened.ok()) return null;
    var fd = opened.fd();
    defer closeFd(&fd);
    var line_buffer: [4096]u8 = undefined;
    var reader = LineReader{ .fd = fd, .buffer = &line_buffer };
    while (reader.next() catch return null) |line| {
        var fields = std.mem.splitScalar(u8, line, ':');
        const name = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const uid_text = fields.next() orelse continue;
        const parsed = std.fmt.parseInt(u32, uid_text, 10) catch continue;
        if (parsed != uid or name.len == 0 or name.len > buffer.len) continue;
        @memcpy(buffer[0..name.len], name);
        return buffer[0..name.len];
    }
    return null;
}

fn subordinateEntry(path: [*:0]const u8, name: ?[]const u8, uid: u32) SandboxError!SubordinateEntry {
    const opened = openAt(linux.AT.FDCWD, path, read_flags);
    if (!opened.ok()) return fail(error.SubordinateIdRangeUnavailable, opened.err);
    var fd = opened.fd();
    defer closeFd(&fd);
    var uid_buffer: [16]u8 = undefined;
    const uid_text = std.fmt.bufPrint(&uid_buffer, "{d}", .{uid}) catch return fail(error.SubordinateIdRangeUnavailable, .INVAL);
    var line_buffer: [4096]u8 = undefined;
    var reader = LineReader{ .fd = fd, .buffer = &line_buffer };
    while (reader.next() catch return fail(error.SubordinateIdRangeUnavailable, .IO)) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line, ':');
        const owner = fields.next() orelse continue;
        const start_text = fields.next() orelse continue;
        const count_text = fields.next() orelse continue;
        if (fields.next() != null) continue;
        const owner_matches = std.mem.eql(u8, owner, uid_text) or (if (name) |account| std.mem.eql(u8, owner, account) else false);
        if (!owner_matches) continue;
        const start = std.fmt.parseInt(u32, start_text, 10) catch continue;
        const count = std.fmt.parseInt(u32, count_text, 10) catch continue;
        if (start == 0 or count == 0) continue;
        if (@as(u64, start) + count > std.math.maxInt(u32)) continue;
        return .{ .start = start, .count = count };
    }
    return fail(error.SubordinateIdRangeUnavailable, .NOENT);
}

const LiveEntry = struct {
    serial: u64,
    tenant_id: u64,
    pid: i32,
    ipc_fd: i32,
    pidfd: i32,
    cgroup_fd: i32,
    lock_fd: i32,
    slot: ?u32,
    claimable: bool,
    cgroup_present: bool,
};

const LiveTable = struct {
    mutex: std.Thread.Mutex = .{},
    entries: std.ArrayListUnmanaged(LiveEntry) = .{},
    slots: std.DynamicBitSetUnmanaged = .{},
};

var live_table: LiveTable = .{};
const live_allocator = std.heap.page_allocator;

fn reserveIdentitySlot(count: u32) SandboxError!u32 {
    live_table.mutex.lock();
    defer live_table.mutex.unlock();
    if (live_table.slots.bit_length < count) {
        live_table.slots.resize(live_allocator, count, false) catch return fail(error.SandboxRegistryFailure, .NOMEM);
    }
    var iterator = live_table.slots.iterator(.{ .kind = .unset });
    const index = iterator.next() orelse return fail(error.IdentityPoolExhausted, .AGAIN);
    if (index >= count) return fail(error.IdentityPoolExhausted, .AGAIN);
    live_table.slots.set(index);
    return @intCast(index);
}

fn releaseIdentitySlotLocked(slot: u32) void {
    if (slot < live_table.slots.bit_length) live_table.slots.unset(slot);
}

fn releaseIdentitySlot(slot: u32) void {
    live_table.mutex.lock();
    defer live_table.mutex.unlock();
    releaseIdentitySlotLocked(slot);
}

fn registerLiveEntry(entry: LiveEntry) bool {
    live_table.mutex.lock();
    defer live_table.mutex.unlock();
    live_table.entries.append(live_allocator, entry) catch return false;
    return true;
}

fn claimLiveEntry(handle: SandboxHandle) ?LiveEntry {
    live_table.mutex.lock();
    defer live_table.mutex.unlock();
    for (live_table.entries.items, 0..) |entry, index| {
        if (entry.claimable and entry.serial == handle.cgroup_serial and entry.tenant_id == handle.tenant_id and entry.pid == handle.pid and entry.ipc_fd == handle.ipc_fd) {
            _ = live_table.entries.swapRemove(index);
            return entry;
        }
    }
    return null;
}

fn sweepAbandonedSandboxes() void {
    live_table.mutex.lock();
    defer live_table.mutex.unlock();
    var index: usize = 0;
    while (index < live_table.entries.items.len) {
        const entry = &live_table.entries.items[index];
        if (entry.pidfd >= 0 and pidfdHasExited(entry.pidfd)) {
            reapPidfdNonBlocking(entry.pidfd);
            closeFd(&entry.pidfd);
        }
        if (entry.pidfd < 0 and entry.cgroup_present and tryRemoveDrainedCgroup(entry)) {
            entry.cgroup_present = false;
            closeFd(&entry.cgroup_fd);
        }
        if (entry.pidfd < 0 and !entry.cgroup_present) {
            closeFd(&entry.lock_fd);
            if (entry.slot) |slot| releaseIdentitySlotLocked(slot);
            entry.slot = null;
            if (!entry.claimable) {
                _ = live_table.entries.swapRemove(index);
                continue;
            }
        }
        index += 1;
    }
}

fn tryRemoveDrainedCgroup(entry: *LiveEntry) bool {
    var owned_fd: i32 = -1;
    defer closeFd(&owned_fd);
    var cgroup_fd = entry.cgroup_fd;
    if (cgroup_fd < 0) {
        var base_fd: i32 = -1;
        defer closeFd(&base_fd);
        const base = openAt(linux.AT.FDCWD, cgroup_base_path, dir_flags);
        if (!base.ok()) return false;
        base_fd = base.fd();
        var name_buffer: [cgroup_name_capacity]u8 = undefined;
        const name = cgroupName(&name_buffer, entry.tenant_id, entry.serial) orelse return false;
        const opened = openAt(base_fd, name, dir_flags);
        if (opened.err == .NOENT) return true;
        if (!opened.ok()) return false;
        owned_fd = opened.fd();
        cgroup_fd = owned_fd;
    }
    const populated = cgroupPopulated(cgroup_fd) orelse return false;
    if (populated) {
        _ = killCgroup(cgroup_fd);
        return false;
    }
    return removeTenantCgroup(cgroup_fd, entry.tenant_id, entry.serial, 1) == .SUCCESS;
}

var serial_state = std.atomic.Value(u64).init(0);

fn nextCgroupSerial() u64 {
    while (true) {
        const current = serial_state.load(.monotonic);
        if (current == 0) {
            const seed = std.crypto.random.int(u64) | 1;
            _ = serial_state.cmpxchgStrong(0, seed, .monotonic, .monotonic);
            continue;
        }
        const serial = serial_state.fetchAdd(1, .monotonic) +% 1;
        if (serial != 0) return serial;
    }
}

fn cgroupName(buffer: *[cgroup_name_capacity]u8, tenant_id: u64, serial: u64) ?[:0]const u8 {
    return std.fmt.bufPrintZ(buffer, "tenant-{d}-{x:0>16}", .{ tenant_id, serial }) catch null;
}

fn isCgroup2(fd: i32) bool {
    var info: StatFs = undefined;
    if (E.init(linux.syscall2(.fstatfs, fdArg(fd), @intFromPtr(&info))) != .SUCCESS) return false;
    return @as(u64, @bitCast(info.f_type)) == cgroup2_super_magic;
}

fn containsToken(list: []const u8, token: []const u8) bool {
    var tokens = std.mem.tokenizeAny(u8, list, " \t\r\n");
    while (tokens.next()) |candidate| {
        if (std.mem.eql(u8, candidate, token)) return true;
    }
    return false;
}

fn prepareCgroupBase() SandboxError!i32 {
    const mount_opened = openAt(linux.AT.FDCWD, cgroup_mount_path, dir_flags);
    if (!mount_opened.ok()) return fail(error.CgroupV2Unavailable, mount_opened.err);
    var mount_fd = mount_opened.fd();
    defer closeFd(&mount_fd);
    if (!isCgroup2(mount_fd)) return fail(error.CgroupV2Unavailable, .NODEV);
    const made = sys(linux.mkdirat(mount_fd, cgroup_base_name, 0o755));
    if (!made.ok() and made.err != .EXIST) return fail(error.CgroupBaseUnavailable, made.err);
    const base_opened = openAt(mount_fd, cgroup_base_name, dir_flags);
    if (!base_opened.ok()) return fail(error.CgroupBaseUnavailable, base_opened.err);
    var base_fd = base_opened.fd();
    errdefer closeFd(&base_fd);
    if (!isCgroup2(base_fd)) return fail(error.CgroupBaseUnavailable, .NODEV);
    try enableSubtreeControllers(mount_fd);
    try enableSubtreeControllers(base_fd);
    try verifyCgroupDelegation(mount_fd);
    return base_fd;
}

fn enableSubtreeControllers(dir_fd: i32) SandboxError!void {
    var available_buffer: [512]u8 = undefined;
    const available = readFileAt(dir_fd, "cgroup.controllers", &available_buffer);
    if (available.err != .SUCCESS) return fail(error.CgroupControllersUnavailable, available.err);
    var enabled_buffer: [512]u8 = undefined;
    const enabled = readFileAt(dir_fd, "cgroup.subtree_control", &enabled_buffer);
    if (enabled.err != .SUCCESS) return fail(error.CgroupControllersUnavailable, enabled.err);
    var request_buffer: [64]u8 = undefined;
    var request_length: usize = 0;
    for (required_controllers) |controller| {
        if (containsToken(enabled.data, controller)) continue;
        if (!containsToken(available.data, controller)) return fail(error.CgroupControllersUnavailable, .NOENT);
        const separator: []const u8 = if (request_length == 0) "+" else " +";
        @memcpy(request_buffer[request_length..][0..separator.len], separator);
        request_length += separator.len;
        @memcpy(request_buffer[request_length..][0..controller.len], controller);
        request_length += controller.len;
    }
    if (request_length == 0) return;
    const written = writeFileAt(dir_fd, "cgroup.subtree_control", request_buffer[0..request_length]);
    if (written != .SUCCESS) return fail(error.CgroupControllersUnavailable, written);
}

fn verifyCgroupDelegation(mount_fd: i32) SandboxError!void {
    var cgroup_buffer: [4096]u8 = undefined;
    const membership = readFileAt(linux.AT.FDCWD, "/proc/self/cgroup", &cgroup_buffer);
    if (membership.err != .SUCCESS) return fail(error.CgroupSelfUnknown, membership.err);
    var own_path: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, membership.data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "0::")) {
            own_path = line[3..];
            break;
        }
    }
    const path = own_path orelse return fail(error.CgroupSelfUnknown, .NOENT);
    var ancestor_buffer: [4096 + 16]u8 = undefined;
    var ancestor_length: usize = 0;
    var own_components = std.mem.tokenizeScalar(u8, path, '/');
    var base_components = std.mem.tokenizeScalar(u8, cgroup_base_name, '/');
    while (true) {
        const own = own_components.next() orelse break;
        const base = base_components.next() orelse break;
        if (!std.mem.eql(u8, own, base)) break;
        if (ancestor_length + own.len + 1 > 4096) return fail(error.CgroupSelfUnknown, .NAMETOOLONG);
        @memcpy(ancestor_buffer[ancestor_length..][0..own.len], own);
        ancestor_length += own.len;
        ancestor_buffer[ancestor_length] = '/';
        ancestor_length += 1;
    }
    const procs_name = "cgroup.procs";
    @memcpy(ancestor_buffer[ancestor_length..][0..procs_name.len], procs_name);
    ancestor_length += procs_name.len;
    ancestor_buffer[ancestor_length] = 0;
    const target: [:0]const u8 = ancestor_buffer[0..ancestor_length :0];
    var checked = sys(linux.syscall4(.faccessat2, fdArg(mount_fd), @intFromPtr(target.ptr), linux.W_OK, at_eaccess));
    if (checked.err == .NOSYS) checked = sys(linux.syscall3(.faccessat, fdArg(mount_fd), @intFromPtr(target.ptr), linux.W_OK));
    if (!checked.ok()) return fail(error.CgroupDelegationDenied, checked.err);
}

const TenantCgroup = struct {
    fd: i32,
    serial: u64,
};

fn createTenantCgroup(base_fd: i32, tenant_id: u64) SandboxError!TenantCgroup {
    var name_buffer: [cgroup_name_capacity]u8 = undefined;
    var attempt: u32 = 0;
    while (attempt < 8) : (attempt += 1) {
        const serial = nextCgroupSerial();
        const name = cgroupName(&name_buffer, tenant_id, serial) orelse return fail(error.CgroupCreateFailed, .NAMETOOLONG);
        const made = sys(linux.mkdirat(base_fd, name, 0o755));
        if (made.err == .EXIST) continue;
        if (!made.ok()) return fail(error.CgroupCreateFailed, made.err);
        const opened = openAt(base_fd, name, dir_flags);
        if (!opened.ok()) {
            _ = removeCgroupEntry(base_fd, name, cgroup_remove_attempts);
            return fail(error.CgroupOpenFailed, opened.err);
        }
        var cgroup_fd = opened.fd();
        applyCgroupLimits(cgroup_fd) catch |err| {
            closeFd(&cgroup_fd);
            _ = removeCgroupEntry(base_fd, name, cgroup_remove_attempts);
            return err;
        };
        return .{ .fd = cgroup_fd, .serial = serial };
    }
    return fail(error.CgroupCreateFailed, .EXIST);
}

fn applyCgroupLimits(cgroup_fd: i32) SandboxError!void {
    for (cgroup_limits) |limit| {
        const written = writeFileAt(cgroup_fd, limit.file, limit.value);
        if (written == .SUCCESS) continue;
        if (limit.optional and written == .NOENT) continue;
        return fail(limit.err, written);
    }
}

fn removeCgroupEntry(dir_fd: i32, name: [*:0]const u8, attempts: u32) E {
    var attempt: u32 = 0;
    while (true) : (attempt += 1) {
        const err = E.init(retry(linux.unlinkat, .{ dir_fd, name, @as(u32, linux.AT.REMOVEDIR) }));
        switch (err) {
            .SUCCESS, .NOENT => return .SUCCESS,
            .BUSY => {
                if (attempt + 1 >= attempts) return err;
                sleepMs(cgroup_remove_backoff_ms);
            },
            else => return err,
        }
    }
}

fn removeNestedCgroups(dir_fd: i32, depth: u32, attempts: u32) E {
    if (depth >= max_nested_cgroup_depth) return .LOOP;
    const listing = openAt(dir_fd, ".", dir_flags);
    if (!listing.ok()) return listing.err;
    var reader = DirReader{ .fd = listing.fd() };
    defer closeFd(&reader.fd);
    while (true) {
        const entry = (reader.next() catch return .IO) orelse return .SUCCESS;
        if (entry.kind != linux.DT.DIR) continue;
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        const child = openAt(dir_fd, entry.name, dir_flags);
        if (!child.ok()) return child.err;
        var child_fd = child.fd();
        const nested = removeNestedCgroups(child_fd, depth + 1, attempts);
        closeFd(&child_fd);
        if (nested != .SUCCESS) return nested;
        const removed = removeCgroupEntry(dir_fd, entry.name, attempts);
        if (removed != .SUCCESS) return removed;
        if (!reader.rewind()) return .IO;
    }
}

fn removeTenantCgroup(cgroup_fd: i32, tenant_id: u64, serial: u64, attempts: u32) E {
    const nested = removeNestedCgroups(cgroup_fd, 0, attempts);
    if (nested != .SUCCESS) return nested;
    const base = openAt(linux.AT.FDCWD, cgroup_base_path, dir_flags);
    if (!base.ok()) return base.err;
    var base_fd = base.fd();
    defer closeFd(&base_fd);
    var name_buffer: [cgroup_name_capacity]u8 = undefined;
    const name = cgroupName(&name_buffer, tenant_id, serial) orelse return .NAMETOOLONG;
    var expected: linux.Stat = undefined;
    const described = E.init(linux.fstat(cgroup_fd, &expected));
    if (described != .SUCCESS) return described;
    var current: linux.Stat = undefined;
    const looked_up = E.init(linux.fstatat(base_fd, name, &current, linux.AT.SYMLINK_NOFOLLOW));
    if (looked_up == .NOENT) return .SUCCESS;
    if (looked_up != .SUCCESS) return looked_up;
    if (current.dev != expected.dev or current.ino != expected.ino) return .STALE;
    return removeCgroupEntry(base_fd, name, attempts);
}

fn parsePopulated(data: []const u8) ?bool {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "populated ")) {
            return !std.mem.eql(u8, std.mem.trim(u8, line["populated ".len..], " \t\r"), "0");
        }
    }
    return null;
}

fn cgroupPopulated(cgroup_fd: i32) ?bool {
    var buffer: [256]u8 = undefined;
    const events = readFileAt(cgroup_fd, "cgroup.events", &buffer);
    if (events.err != .SUCCESS) return null;
    return parsePopulated(events.data);
}

fn killCgroup(cgroup_fd: i32) E {
    const written = writeFileAt(cgroup_fd, "cgroup.kill", "1");
    if (written != .NOENT) return written;
    return signalCgroupMembers(cgroup_fd, linux.SIG.KILL);
}

fn signalCgroupMembers(cgroup_fd: i32, signal: i32) E {
    var round: u32 = 0;
    while (round < cgroup_kill_rounds) : (round += 1) {
        const opened = openAt(cgroup_fd, "cgroup.procs", read_flags);
        if (!opened.ok()) return opened.err;
        var fd = opened.fd();
        defer closeFd(&fd);
        var buffer: [256]u8 = undefined;
        var reader = LineReader{ .fd = fd, .buffer = &buffer };
        var signalled: usize = 0;
        while (reader.next() catch return .IO) |line| {
            const pid = std.fmt.parseInt(i32, std.mem.trim(u8, line, " \t\r"), 10) catch continue;
            if (pid <= 0) continue;
            const err = E.init(retry(linux.kill, .{ pid, signal }));
            if (err != .SUCCESS and err != .SRCH) return err;
            signalled += 1;
        }
        if (signalled == 0) return .SUCCESS;
        sleepMs(cgroup_kill_backoff_ms);
    }
    return .SUCCESS;
}

fn waitCgroupEmpty(cgroup_fd: i32, timeout_ms: u32) E {
    const deadline = Deadline.after(timeout_ms) orelse return .NOSYS;
    const opened = openAt(cgroup_fd, "cgroup.events", read_flags);
    if (!opened.ok()) return opened.err;
    var fd = opened.fd();
    defer closeFd(&fd);
    var buffer: [256]u8 = undefined;
    while (true) {
        const result = sys(retry(linux.pread, .{ fd, &buffer, buffer.len, @as(i64, 0) }));
        if (!result.ok()) return result.err;
        const populated = parsePopulated(buffer[0..result.value]) orelse return .IO;
        if (!populated) return .SUCCESS;
        const remaining = deadline.remainingMs();
        if (remaining == 0) return .TIMEDOUT;
        const slice = Deadline.after(@intCast(@min(remaining, 100))) orelse return .NOSYS;
        var fds = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.PRI, .revents = 0 }};
        const polled = pollUntil(&fds, slice);
        if (!polled.ok()) return polled.err;
    }
}

fn drainCgroup(cgroup_fd: i32) E {
    const populated = cgroupPopulated(cgroup_fd) orelse return .IO;
    if (!populated) return .SUCCESS;
    const killed = killCgroup(cgroup_fd);
    if (killed != .SUCCESS) return killed;
    return waitCgroupEmpty(cgroup_fd, cgroup_drain_timeout_ms);
}

fn migrateIntoCgroup(cgroup_fd: i32, pid: i32) SandboxError!void {
    var buffer: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{pid}) catch return fail(error.CgroupMigrationFailed, .INVAL);
    const written = writeFileAt(cgroup_fd, "cgroup.procs", text);
    if (written != .SUCCESS) return fail(error.CgroupMigrationFailed, written);
    const opened = openAt(cgroup_fd, "cgroup.procs", read_flags);
    if (!opened.ok()) return fail(error.CgroupMigrationUnverified, opened.err);
    var fd = opened.fd();
    defer closeFd(&fd);
    var line_buffer: [64]u8 = undefined;
    var reader = LineReader{ .fd = fd, .buffer = &line_buffer };
    while (reader.next() catch return fail(error.CgroupMigrationUnverified, .IO)) |line| {
        const member = std.fmt.parseInt(i32, std.mem.trim(u8, line, " \t\r"), 10) catch continue;
        if (member == pid) return;
    }
    return fail(error.CgroupMigrationUnverified, .SRCH);
}

const ExitWait = union(enum) {
    exited,
    timeout,
    failed: E,
};

fn waitPidfdExit(pidfd: i32, timeout_ms: u32) ExitWait {
    const deadline = Deadline.after(timeout_ms) orelse return .{ .failed = .NOSYS };
    while (true) {
        var fds = [1]linux.pollfd{.{ .fd = pidfd, .events = linux.POLL.IN, .revents = 0 }};
        const polled = pollUntil(&fds, deadline);
        if (!polled.ok()) return .{ .failed = polled.err };
        if (polled.value == 0) return .timeout;
        const events = fds[0].revents;
        if ((events & linux.POLL.NVAL) != 0) return .{ .failed = .BADF };
        if ((events & (linux.POLL.IN | linux.POLL.HUP)) != 0) return .exited;
        if ((events & linux.POLL.ERR) != 0) return .{ .failed = .IO };
    }
}

fn pidfdHasExited(pidfd: i32) bool {
    var fds = [1]linux.pollfd{.{ .fd = pidfd, .events = linux.POLL.IN, .revents = 0 }};
    const polled = sys(retry(linux.poll, .{ &fds, @as(usize, 1), @as(i32, 0) }));
    return polled.ok() and polled.value == 1 and (fds[0].revents & (linux.POLL.IN | linux.POLL.HUP)) != 0;
}

fn pidfdSignal(pidfd: i32, signal: i32) E {
    const err = E.init(retry(linux.pidfd_send_signal, .{ pidfd, signal, null, @as(u32, 0) }));
    if (err == .SRCH) return .SUCCESS;
    return err;
}

fn reapPidfd(pidfd: i32, status: *?u32) E {
    var info: linux.siginfo_t = undefined;
    const err = E.init(retry(linux.waitid, .{ linux.P.PIDFD, pidfd, &info, @as(u32, linux.W.EXITED) }));
    if (err == .CHILD) return .SUCCESS;
    if (err != .SUCCESS) return err;
    const value: u32 = @bitCast(info.fields.common.second.sigchld.status);
    status.* = if (info.code == cld_exited) value & 0xff else 128 + (value & 0x7f);
    return .SUCCESS;
}

fn reapPidfdNonBlocking(pidfd: i32) void {
    var info: linux.siginfo_t = undefined;
    _ = retry(linux.waitid, .{ linux.P.PIDFD, pidfd, &info, @as(u32, linux.W.EXITED | linux.W.NOHANG) });
}

const CloneOutcome = struct {
    pid: i32,
    pidfd: i32,
    in_cgroup: bool,
};

fn sys_clone3(args: *clone_args, size: usize) usize {
    return linux.syscall2(.clone3, @intFromPtr(args), size);
}

fn legacyClone(pidfd: *i32) usize {
    const flags: usize = @intCast(clone_namespace_flags | linux.CLONE.PIDFD | linux.SIG.CHLD);
    return linux.syscall5(.clone, flags, 0, @intFromPtr(pidfd), 0, 0);
}

fn cloneError(err: E) SandboxError {
    last_failure = .{ .err = null, .errno_value = @intFromEnum(err) };
    const mapped: SandboxError = switch (err) {
        .AGAIN => error.ProcessLimitReached,
        .NOSPC, .USERS => error.NamespaceLimitReached,
        .PERM => error.NamespaceCreationDenied,
        .ACCES => error.CgroupDelegationDenied,
        .NOMEM => error.SystemResources,
        .BUSY, .OPNOTSUPP => error.CgroupNotEligible,
        .INVAL => error.CloneUnsupported,
        else => error.CloneRejected,
    };
    last_failure.err = mapped;
    return mapped;
}

fn cloneSandboxProcess(cgroup_fd: i32, outcome: *CloneOutcome) SandboxError!bool {
    var previous_mask: linux.sigset_t = undefined;
    const masked = E.init(linux.sigprocmask(linux.SIG.SETMASK, &linux.all_mask, &previous_mask));
    if (masked != .SUCCESS) return fail(error.SignalMaskFailed, masked);
    var pidfd: i32 = -1;
    var args = std.mem.zeroes(clone_args);
    args.flags = clone_namespace_flags | linux.CLONE.PIDFD | linux.CLONE.INTO_CGROUP | linux.CLONE.CLEAR_SIGHAND;
    args.pidfd = @intFromPtr(&pidfd);
    args.exit_signal = linux.SIG.CHLD;
    args.cgroup = @intCast(cgroup_fd);
    var rc = sys_clone3(&args, @sizeOf(clone_args));
    var err = E.init(rc);
    var in_cgroup = true;
    if (err == .INVAL or err == .@"2BIG") {
        args = std.mem.zeroes(clone_args);
        args.flags = clone_namespace_flags | linux.CLONE.PIDFD;
        args.pidfd = @intFromPtr(&pidfd);
        args.exit_signal = linux.SIG.CHLD;
        rc = sys_clone3(&args, clone_args_size_ver0);
        err = E.init(rc);
        in_cgroup = false;
    }
    if (err == .NOSYS or err == .PERM) {
        rc = legacyClone(&pidfd);
        err = E.init(rc);
        in_cgroup = false;
    }
    if (err == .SUCCESS and rc == 0) return true;
    _ = linux.sigprocmask(linux.SIG.SETMASK, &previous_mask, null);
    if (err != .SUCCESS) return cloneError(err);
    const pid: i32 = @intCast(rc);
    if (pidfd < 0) {
        _ = linux.kill(pid, linux.SIG.KILL);
        var status: u32 = 0;
        _ = retry(linux.wait4, .{ pid, &status, @as(u32, 0), null });
        return fail(error.PidfdUnavailable, .NOSYS);
    }
    outcome.* = .{ .pid = pid, .pidfd = pidfd, .in_cgroup = in_cgroup };
    return false;
}

fn controlMessage(kind: ControlKind, code: u32, errno_value: u32) ControlMessage {
    return .{ .magic = control_magic, .kind = @intFromEnum(kind), .code = code, .errno_value = errno_value };
}

fn sendControl(fd: i32, message: ControlMessage, pass_fd: i32) E {
    var payload = message;
    var iov = [1]std.posix.iovec_const{.{ .base = std.mem.asBytes(&payload), .len = @sizeOf(ControlMessage) }};
    var control: [cmsg_fd_space]u8 align(@alignOf(CmsgHeader)) = [_]u8{0} ** cmsg_fd_space;
    var header = linux.msghdr_const{ .name = null, .namelen = 0, .iov = &iov, .iovlen = 1, .control = null, .controllen = 0, .flags = 0 };
    if (pass_fd >= 0) {
        const cmsg: *CmsgHeader = @ptrCast(&control);
        cmsg.* = .{ .len = cmsg_fd_len, .level = linux.SOL.SOCKET, .kind = scm_rights };
        std.mem.writeInt(i32, control[cmsg_data_offset..][0..4], pass_fd, native_endian);
        header.control = &control;
        header.controllen = cmsg_fd_space;
    }
    const sent = sys(retry(linux.sendmsg, .{ fd, &header, @as(u32, linux.MSG.NOSIGNAL) }));
    if (!sent.ok()) return sent.err;
    if (sent.value != @sizeOf(ControlMessage)) return .IO;
    return .SUCCESS;
}

const ControlReceipt = struct {
    status: E,
    message: ControlMessage,
    fd: i32,
};

fn recvControl(fd: i32, deadline: Deadline) ControlReceipt {
    var receipt = ControlReceipt{ .status = .SUCCESS, .message = std.mem.zeroes(ControlMessage), .fd = -1 };
    var fds = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const polled = pollUntil(&fds, deadline);
    if (!polled.ok()) {
        receipt.status = polled.err;
        return receipt;
    }
    if (polled.value == 0) {
        receipt.status = .TIMEDOUT;
        return receipt;
    }
    var iov = [1]std.posix.iovec{.{ .base = std.mem.asBytes(&receipt.message), .len = @sizeOf(ControlMessage) }};
    var control: [cmsg_fd_space]u8 align(@alignOf(CmsgHeader)) = [_]u8{0} ** cmsg_fd_space;
    var header = linux.msghdr{ .name = null, .namelen = 0, .iov = &iov, .iovlen = 1, .control = &control, .controllen = cmsg_fd_space, .flags = 0 };
    const received = sys(retry(linux.recvmsg, .{ fd, &header, @as(u32, linux.MSG.CMSG_CLOEXEC) }));
    if (!received.ok()) {
        receipt.status = received.err;
        return receipt;
    }
    if (header.controllen >= cmsg_fd_len) {
        const cmsg: *const CmsgHeader = @ptrCast(&control);
        if (cmsg.level == linux.SOL.SOCKET and cmsg.kind == scm_rights and cmsg.len >= cmsg_fd_len) {
            receipt.fd = std.mem.readInt(i32, control[cmsg_data_offset..][0..4], native_endian);
        }
    }
    if (received.value == 0) {
        receipt.status = .PIPE;
    } else if (received.value != @sizeOf(ControlMessage) or receipt.message.magic != control_magic or (header.flags & (linux.MSG.TRUNC | linux.MSG.CTRUNC)) != 0) {
        receipt.status = .PROTO;
    }
    if (receipt.status != .SUCCESS) closeFd(&receipt.fd);
    return receipt;
}

fn expectControl(fd: i32, timeout_ms: u32, kind: ControlKind) SandboxError!void {
    const deadline = Deadline.after(timeout_ms) orelse return fail(error.ClockUnavailable, .NOSYS);
    var receipt = recvControl(fd, deadline);
    closeFd(&receipt.fd);
    switch (receipt.status) {
        .SUCCESS => {},
        .TIMEDOUT => return fail(error.HandshakeTimeout, .TIMEDOUT),
        .PIPE, .CONNRESET => return fail(error.SandboxExitedDuringStartup, receipt.status),
        .PROTO => return fail(error.ChildProtocolViolation, .PROTO),
        else => return fail(error.ControlChannelFailed, receipt.status),
    }
    if (receipt.message.kind == @intFromEnum(ControlKind.failure)) {
        const reported = sandboxErrorFromCode(receipt.message.code) orelse return fail(error.ChildProtocolViolation, .PROTO);
        return fail(reported, errnoFromCode(receipt.message.errno_value));
    }
    if (receipt.message.kind != @intFromEnum(kind)) return fail(error.ChildProtocolViolation, .PROTO);
}

fn sendParentControl(fd: i32, kind: ControlKind, code: u32, pass_fd: i32) SandboxError!void {
    const sent = sendControl(fd, controlMessage(kind, code, 0), pass_fd);
    switch (sent) {
        .SUCCESS => {},
        .PIPE, .CONNRESET => return fail(error.SandboxExitedDuringStartup, sent),
        else => return fail(error.ControlChannelFailed, sent),
    }
}

fn createChannel(kind: u32, parent_fd: *i32, child_fd: *i32) SandboxError!void {
    var pair: [2]i32 = undefined;
    const created = sys(linux.socketpair(linux.AF.UNIX, @intCast(kind | linux.SOCK.CLOEXEC), 0, &pair));
    if (!created.ok()) return fail(error.SocketCreationFailed, created.err);
    parent_fd.* = pair[0];
    child_fd.* = pair[1];
}

fn openTenantData(validated: *const ValidatedTenant, plan: *const IdentityPlan) SandboxError!i32 {
    const opened = openAt(linux.AT.FDCWD, validated.dataDir(), dir_flags);
    if (!opened.ok()) return fail(error.TenantDataUnavailable, opened.err);
    var fd = opened.fd();
    errdefer closeFd(&fd);
    var info: linux.Stat = undefined;
    const described = sys(linux.fstat(fd, &info));
    if (!described.ok()) return fail(error.TenantDataUnavailable, described.err);
    const expected_uid: u32 = if (plan.distinct) 0 else plan.host_uid;
    if (info.uid != expected_uid or (plan.distinct and info.gid != 0)) return fail(error.TenantDataOwnershipMismatch, .PERM);
    const deadline = Deadline.after(data_lock_timeout_ms) orelse return fail(error.ClockUnavailable, .NOSYS);
    while (true) {
        const err = E.init(retry(linux.flock, .{ fd, @as(i32, std.posix.LOCK.EX | std.posix.LOCK.NB) }));
        if (err == .SUCCESS) return fd;
        if (err != .AGAIN or deadline.remainingMs() == 0) return fail(error.TenantSandboxBusy, err);
        sleepMs(data_lock_retry_ms);
    }
}

fn openRunner(plan: *const IdentityPlan) SandboxError!i32 {
    const opened = openAt(linux.AT.FDCWD, &runner_path_z, .{ .PATH = true, .CLOEXEC = true });
    if (!opened.ok()) return fail(error.RunnerUnavailable, opened.err);
    var fd = opened.fd();
    errdefer closeFd(&fd);
    var info: linux.Stat = undefined;
    const described = sys(linux.fstat(fd, &info));
    if (!described.ok()) return fail(error.RunnerUnavailable, described.err);
    if ((info.mode & linux.S.IFMT) != linux.S.IFREG) return fail(error.RunnerUnavailable, .NOEXEC);
    const executable = if (info.uid == plan.host_uid)
        (info.mode & 0o100) != 0
    else if (info.gid == plan.host_gid)
        (info.mode & 0o010) != 0
    else
        (info.mode & 0o001) != 0;
    if (!executable) return fail(error.RunnerUnavailable, .ACCES);
    return fd;
}

fn connectWalUpstream(host: []const u8, port: u16) SandboxError!i32 {
    if (std.net.Address.parseIp(host, port)) |address| {
        const connected = connectWithTimeout(address);
        if (!connected.ok()) return fail(error.WalEndpointUnreachable, connected.err);
        return connected.fd();
    } else |_| {}
    const list = std.net.getAddressList(std.heap.page_allocator, host, port) catch return fail(error.WalEndpointUnreachable, .HOSTUNREACH);
    defer list.deinit();
    var last_error: E = .HOSTUNREACH;
    for (list.addrs) |address| {
        const connected = connectWithTimeout(address);
        if (connected.ok()) return connected.fd();
        last_error = connected.err;
    }
    return fail(error.WalEndpointUnreachable, last_error);
}

fn connectWithTimeout(address: std.net.Address) SysResult {
    const created = sys(linux.socket(address.any.family, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, linux.IPPROTO.TCP));
    if (!created.ok()) return created;
    var fd = created.fd();
    const connected = E.init(linux.connect(fd, &address.any, address.getOsSockLen()));
    if (connected == .SUCCESS) return created;
    if (connected != .INPROGRESS) {
        closeFd(&fd);
        return .{ .value = 0, .err = connected };
    }
    const deadline = Deadline.after(wal_connect_timeout_ms) orelse {
        closeFd(&fd);
        return .{ .value = 0, .err = .NOSYS };
    };
    var fds = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.OUT, .revents = 0 }};
    const polled = pollUntil(&fds, deadline);
    if (!polled.ok() or polled.value == 0) {
        closeFd(&fd);
        return .{ .value = 0, .err = if (polled.ok()) .TIMEDOUT else polled.err };
    }
    var socket_error: i32 = 0;
    var length: linux.socklen_t = @sizeOf(i32);
    const queried = E.init(linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.ERROR, std.mem.asBytes(&socket_error), &length));
    if (queried != .SUCCESS or socket_error != 0) {
        closeFd(&fd);
        return .{ .value = 0, .err = if (queried != .SUCCESS) queried else errnoFromCode(@bitCast(socket_error)) };
    }
    return created;
}

fn configureUserNamespace(resources: *SpawnResources, plan: *const IdentityPlan) SandboxError!void {
    var path_buffer: [32]u8 = undefined;
    const proc_path = std.fmt.bufPrintZ(&path_buffer, "/proc/{d}", .{resources.pid}) catch return fail(error.ChildProcessVanished, .NAMETOOLONG);
    const opened = openAt(linux.AT.FDCWD, proc_path, dir_flags);
    if (!opened.ok()) return fail(error.ChildProcessVanished, opened.err);
    resources.proc_fd = opened.fd();
    if (pidfdHasExited(resources.pidfd)) return fail(error.ChildProcessVanished, .SRCH);
    const policy: []const u8 = if (plan.allow_setgroups) "allow\n" else "deny\n";
    var written = writeFileAt(resources.proc_fd, "setgroups", policy);
    if (written != .SUCCESS) return fail(error.SetgroupsPolicyFailed, written);
    var map_buffer: [64]u8 = undefined;
    const uid_map = std.fmt.bufPrint(&map_buffer, "0 {d} 1\n", .{plan.host_uid}) catch return fail(error.UidMapFailed, .NAMETOOLONG);
    written = writeFileAt(resources.proc_fd, "uid_map", uid_map);
    if (written != .SUCCESS) return fail(error.UidMapFailed, written);
    const gid_map = std.fmt.bufPrint(&map_buffer, "0 {d} 1\n", .{plan.host_gid}) catch return fail(error.GidMapFailed, .NAMETOOLONG);
    written = writeFileAt(resources.proc_fd, "gid_map", gid_map);
    if (written != .SUCCESS) return fail(error.GidMapFailed, written);
    if (plan.distinct) resources.tree_fd = try createIdmappedTree(resources.data_fd, resources.proc_fd);
    closeFd(&resources.proc_fd);
}

fn createIdmappedTree(data_fd: i32, proc_fd: i32) SandboxError!i32 {
    const namespace = openAt(proc_fd, "ns/user", .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (!namespace.ok()) return fail(error.IdmappedMountFailed, namespace.err);
    var namespace_fd = namespace.fd();
    defer closeFd(&namespace_fd);
    const tree = sys(linux.syscall3(.open_tree, fdArg(data_fd), @intFromPtr(""), open_tree_clone | cloexec_flag_bits | linux.AT.EMPTY_PATH));
    if (!tree.ok()) return fail(error.IdmappedMountFailed, tree.err);
    var tree_fd = tree.fd();
    errdefer closeFd(&tree_fd);
    var attributes = MountAttr{
        .attr_set = mount_attr_idmap | mount_attr_nosuid | mount_attr_nodev,
        .attr_clr = 0,
        .propagation = 0,
        .userns_fd = @intCast(namespace_fd),
    };
    const applied = sys(linux.syscall5(.mount_setattr, fdArg(tree_fd), @intFromPtr(""), linux.AT.EMPTY_PATH, @intFromPtr(&attributes), @sizeOf(MountAttr)));
    if (!applied.ok()) return fail(error.IdmappedMountFailed, applied.err);
    return tree_fd;
}

fn encodeIpcHeader(out: *[ipc_header_size]u8, request_id: u64, message_type: u8, payload_len: u32) void {
    std.mem.writeInt(u32, out[0..4], ipc_magic, .little);
    std.mem.writeInt(u64, out[4..12], request_id, .little);
    out[12] = message_type;
    out[13] = 0;
    out[14] = 0;
    out[15] = 0;
    std.mem.writeInt(u32, out[16..20], payload_len, .little);
}

fn receiveExact(ipc_fd: i32, pidfd: i32, buffer: []u8, deadline: Deadline) SandboxError!void {
    var received: usize = 0;
    while (received < buffer.len) {
        var fds = [2]linux.pollfd{
            .{ .fd = ipc_fd, .events = linux.POLL.IN, .revents = 0 },
            .{ .fd = pidfd, .events = linux.POLL.IN, .revents = 0 },
        };
        const polled = pollUntil(&fds, deadline);
        if (!polled.ok()) return fail(error.ReadinessProtocolViolation, polled.err);
        if (polled.value == 0) return fail(error.ReadinessTimeout, .TIMEDOUT);
        if ((fds[0].revents & linux.POLL.IN) == 0) {
            if ((fds[1].revents & (linux.POLL.IN | linux.POLL.HUP)) != 0 or (fds[0].revents & (linux.POLL.HUP | linux.POLL.ERR)) != 0) {
                return fail(error.SandboxExitedDuringStartup, .CHILD);
            }
            continue;
        }
        const result = sys(retry(linux.recvfrom, .{ ipc_fd, buffer[received..].ptr, buffer.len - received, @as(u32, 0), null, null }));
        if (!result.ok()) return fail(error.SandboxExitedDuringStartup, result.err);
        if (result.value == 0) return fail(error.SandboxExitedDuringStartup, .PIPE);
        received += result.value;
    }
}

fn awaitRunnerReadiness(ipc_fd: i32, pidfd: i32) SandboxError!void {
    const deadline = Deadline.after(readiness_timeout_ms) orelse return fail(error.ClockUnavailable, .NOSYS);
    var request: [ipc_header_size]u8 = undefined;
    encodeIpcHeader(&request, readiness_request_id, readiness_message_type, 0);
    var sent: usize = 0;
    while (sent < request.len) {
        const result = sys(retry(linux.sendto, .{ ipc_fd, request[sent..].ptr, request.len - sent, @as(u32, linux.MSG.NOSIGNAL), null, @as(linux.socklen_t, 0) }));
        if (!result.ok()) return fail(error.SandboxExitedDuringStartup, result.err);
        sent += result.value;
    }
    var response: [ipc_header_size]u8 = undefined;
    try receiveExact(ipc_fd, pidfd, &response, deadline);
    const magic = std.mem.readInt(u32, response[0..4], .little);
    const request_id = std.mem.readInt(u64, response[4..12], .little);
    const payload_len = std.mem.readInt(u32, response[16..20], .little);
    if (magic != ipc_magic or request_id != readiness_request_id or response[12] != readiness_message_type or response[13] != 0 or payload_len > readiness_payload_limit) {
        return fail(error.ReadinessProtocolViolation, .PROTO);
    }
    var discard: [readiness_payload_limit]u8 = undefined;
    try receiveExact(ipc_fd, pidfd, discard[0..payload_len], deadline);
}

const SpawnResources = struct {
    tenant_id: u64,
    slot: ?u32,
    data_fd: i32 = -1,
    runner_fd: i32 = -1,
    base_fd: i32 = -1,
    cgroup_fd: i32 = -1,
    cgroup_serial: u64 = 0,
    ipc_parent_fd: i32 = -1,
    ipc_child_fd: i32 = -1,
    control_parent_fd: i32 = -1,
    control_child_fd: i32 = -1,
    upstream_fd: i32 = -1,
    proc_fd: i32 = -1,
    tree_fd: i32 = -1,
    pid: i32 = 0,
    pidfd: i32 = -1,

    fn release(self: *SpawnResources) void {
        var processes_dead = true;
        if (self.pidfd >= 0) {
            const exiting = if (last_failure.err) |err| err == error.SandboxExitedDuringStartup else false;
            if (!(exiting and waitPidfdExit(self.pidfd, startup_exit_grace_ms) == .exited)) {
                _ = pidfdSignal(self.pidfd, linux.SIG.KILL);
            }
            if (self.cgroup_fd >= 0) _ = killCgroup(self.cgroup_fd);
            if (waitPidfdExit(self.pidfd, forced_stop_timeout_ms) == .exited) {
                var status: ?u32 = null;
                _ = reapPidfd(self.pidfd, &status);
                if (status != null) last_failure.exit_status = status;
            } else {
                processes_dead = false;
            }
        }
        closeFd(&self.pidfd);
        closeFd(&self.tree_fd);
        closeFd(&self.proc_fd);
        closeFd(&self.ipc_parent_fd);
        closeFd(&self.ipc_child_fd);
        closeFd(&self.control_parent_fd);
        closeFd(&self.control_child_fd);
        closeFd(&self.upstream_fd);
        closeFd(&self.runner_fd);
        var cgroup_present = self.cgroup_fd >= 0;
        if (cgroup_present and processes_dead) {
            if (drainCgroup(self.cgroup_fd) == .SUCCESS) {
                if (removeTenantCgroup(self.cgroup_fd, self.tenant_id, self.cgroup_serial, cgroup_remove_attempts) == .SUCCESS) cgroup_present = false;
            } else {
                processes_dead = false;
            }
        }
        closeFd(&self.cgroup_fd);
        closeFd(&self.base_fd);
        if (processes_dead) {
            closeFd(&self.data_fd);
            if (self.slot) |slot| releaseIdentitySlot(slot);
            self.slot = null;
        }
        if (!processes_dead or cgroup_present) {
            const orphan = LiveEntry{
                .serial = self.cgroup_serial,
                .tenant_id = self.tenant_id,
                .pid = self.pid,
                .ipc_fd = -1,
                .pidfd = -1,
                .cgroup_fd = -1,
                .lock_fd = self.data_fd,
                .slot = self.slot,
                .claimable = false,
                .cgroup_present = cgroup_present,
            };
            if (registerLiveEntry(orphan)) {
                self.data_fd = -1;
                self.slot = null;
            }
        }
    }
};

pub fn spawnTenantSandbox(tenant: registry.TenantRecord) SandboxError!SandboxHandle {
    last_failure = .{};
    sweepAbandonedSandboxes();
    var validated: ValidatedTenant = undefined;
    try validateTenant(&tenant, &validated);
    const plan = try planIdentity();
    var resources = SpawnResources{ .tenant_id = tenant.tenant_id, .slot = plan.slot };
    errdefer resources.release();
    resources.data_fd = try openTenantData(&validated, &plan);
    resources.runner_fd = try openRunner(&plan);
    resources.base_fd = try prepareCgroupBase();
    const cgroup = try createTenantCgroup(resources.base_fd, tenant.tenant_id);
    resources.cgroup_fd = cgroup.fd;
    resources.cgroup_serial = cgroup.serial;
    try createChannel(linux.SOCK.STREAM, &resources.ipc_parent_fd, &resources.ipc_child_fd);
    try createChannel(linux.SOCK.SEQPACKET, &resources.control_parent_fd, &resources.control_child_fd);
    if (validated.stateless) resources.upstream_fd = try connectWalUpstream(validated.walHost(), validated.wal_port);
    const context = ChildContext{
        .control_fd = resources.control_child_fd,
        .ipc_fd = resources.ipc_child_fd,
        .runner_fd = resources.runner_fd,
        .data_fd = resources.data_fd,
        .upstream_fd = resources.upstream_fd,
        .tenant_id = tenant.tenant_id,
        .data_path = validated.data_path,
        .data_dir = validated.dataDir(),
        .data_dir_relative = validated.dataDirRelative(),
        .stateless = validated.stateless,
        .wal_port = validated.wal_port,
        .allow_setgroups = plan.allow_setgroups,
        .distinct_ids = plan.distinct,
    };
    var outcome: CloneOutcome = undefined;
    if (try cloneSandboxProcess(resources.cgroup_fd, &outcome)) sandboxChildMain(&context);
    resources.pid = outcome.pid;
    resources.pidfd = outcome.pidfd;
    closeFd(&resources.ipc_child_fd);
    closeFd(&resources.control_child_fd);
    closeFd(&resources.runner_fd);
    closeFd(&resources.upstream_fd);
    if (!outcome.in_cgroup) try migrateIntoCgroup(resources.cgroup_fd, outcome.pid);
    try configureUserNamespace(&resources, &plan);
    try sendParentControl(resources.control_parent_fd, .maps_ready, 0, resources.tree_fd);
    closeFd(&resources.tree_fd);
    try expectControl(resources.control_parent_fd, handshake_timeout_ms, .armed);
    try sendParentControl(resources.control_parent_fd, .go, go_token, -1);
    try expectControl(resources.control_parent_fd, exec_status_timeout_ms, .ready);
    closeFd(&resources.control_parent_fd);
    try awaitRunnerReadiness(resources.ipc_parent_fd, resources.pidfd);
    const activity_ns = try activityTimestampNs();
    const started_ms = try unixMillis();
    const handle = SandboxHandle{
        .tenant_id = tenant.tenant_id,
        .pid = resources.pid,
        .cgroup_fd = resources.cgroup_fd,
        .ipc_fd = resources.ipc_parent_fd,
        .last_activity_ns = activity_ns,
        .started_at_unix_ms = started_ms,
        .stateless = validated.stateless,
        .pidfd = resources.pidfd,
        .cgroup_serial = resources.cgroup_serial,
    };
    const entry = LiveEntry{
        .serial = resources.cgroup_serial,
        .tenant_id = tenant.tenant_id,
        .pid = resources.pid,
        .ipc_fd = resources.ipc_parent_fd,
        .pidfd = resources.pidfd,
        .cgroup_fd = resources.cgroup_fd,
        .lock_fd = resources.data_fd,
        .slot = resources.slot,
        .claimable = true,
        .cgroup_present = true,
    };
    if (!registerLiveEntry(entry)) return fail(error.SandboxRegistryFailure, .NOMEM);
    closeFd(&resources.base_fd);
    return handle;
}

pub fn destroySandbox(handle: SandboxHandle) SandboxError!void {
    last_failure = .{};
    var entry = claimLiveEntry(handle) orelse return fail(error.SandboxNotFound, .SRCH);
    defer {
        closeFd(&entry.ipc_fd);
        closeFd(&entry.pidfd);
        closeFd(&entry.cgroup_fd);
    }
    var first_error: ?SandboxError = null;
    var processes_dead = entry.pidfd < 0;
    if (entry.pidfd >= 0) {
        const terminated = pidfdSignal(entry.pidfd, linux.SIG.TERM);
        if (terminated != .SUCCESS) first_error = first_error orelse fail(error.SignalDeliveryFailed, terminated);
        var waited = waitPidfdExit(entry.pidfd, graceful_stop_timeout_ms);
        if (waited != .exited) {
            if (entry.cgroup_fd >= 0) {
                const killed = killCgroup(entry.cgroup_fd);
                if (killed != .SUCCESS) first_error = first_error orelse fail(error.CgroupKillFailed, killed);
            }
            const forced = pidfdSignal(entry.pidfd, linux.SIG.KILL);
            if (forced != .SUCCESS) first_error = first_error orelse fail(error.SignalDeliveryFailed, forced);
            waited = waitPidfdExit(entry.pidfd, forced_stop_timeout_ms);
        }
        switch (waited) {
            .exited => {
                processes_dead = true;
                var status: ?u32 = null;
                const reaped = reapPidfd(entry.pidfd, &status);
                if (reaped != .SUCCESS) first_error = first_error orelse fail(error.WaitFailed, reaped);
            },
            .timeout => first_error = first_error orelse fail(error.TerminationTimeout, .TIMEDOUT),
            .failed => |err| first_error = first_error orelse fail(error.WaitFailed, err),
        }
    }
    if (entry.cgroup_present and entry.cgroup_fd >= 0 and processes_dead) {
        const drained = drainCgroup(entry.cgroup_fd);
        if (drained != .SUCCESS) {
            processes_dead = false;
            first_error = first_error orelse fail(error.CgroupDrainTimeout, drained);
        }
    }
    if (entry.cgroup_present and entry.cgroup_fd >= 0 and processes_dead) {
        const removed = removeTenantCgroup(entry.cgroup_fd, entry.tenant_id, entry.serial, cgroup_remove_attempts);
        if (removed == .SUCCESS) {
            entry.cgroup_present = false;
        } else {
            first_error = first_error orelse fail(error.CgroupRemoveFailed, removed);
        }
    }
    if (processes_dead) {
        closeFd(&entry.lock_fd);
        if (entry.slot) |slot| releaseIdentitySlot(slot);
        entry.slot = null;
    }
    if (!processes_dead or entry.cgroup_present) {
        var orphan = entry;
        orphan.claimable = false;
        orphan.ipc_fd = -1;
        orphan.pidfd = -1;
        orphan.cgroup_fd = -1;
        if (registerLiveEntry(orphan)) {
            entry.lock_fd = -1;
            entry.slot = null;
        }
    }
    if (first_error) |err| return err;
}

const ChildContext = struct {
    control_fd: i32,
    ipc_fd: i32,
    runner_fd: i32,
    data_fd: i32,
    upstream_fd: i32,
    tenant_id: u64,
    data_path: [:0]const u8,
    data_dir: [:0]const u8,
    data_dir_relative: []const u8,
    stateless: bool,
    wal_port: u16,
    allow_setgroups: bool,
    distinct_ids: bool,
};

const ChildState = struct {
    control_fd: i32,
    ipc_fd: i32,
    runner_fd: i32,
    data_fd: i32,
    upstream_fd: i32,
    tree_fd: i32 = -1,
    listen_fd: i32 = -1,
};

fn childFail(control_fd: i32, err: SandboxError, errno_value: E) noreturn {
    if (control_fd >= 0) _ = sendControl(control_fd, controlMessage(.failure, errorCode(err), @intFromEnum(errno_value)), -1);
    linux.exit_group(1);
}

fn childCheck(control_fd: i32, rc: usize, err: SandboxError) usize {
    const result = sys(rc);
    if (!result.ok()) childFail(control_fd, err, result.err);
    return result.value;
}

fn resetSignalDispositions() E {
    var signal: usize = 1;
    while (signal < linux.NSIG) : (signal += 1) {
        if (signal == linux.SIG.KILL or signal == linux.SIG.STOP) continue;
        const action = KernelSigaction{ .handler = 0, .flags = 0, .restorer = 0, .mask = .{ 0, 0 } };
        const err = E.init(linux.syscall4(.rt_sigaction, signal, @intFromPtr(&action), 0, @sizeOf([2]u32)));
        if (err != .SUCCESS) return err;
    }
    return .SUCCESS;
}

fn closeRange(first: u32, last: u32) E {
    return E.init(linux.syscall3(.close_range, first, last, 0));
}

fn closeAllExcept(keep: []const i32) E {
    var sorted: [8]i32 = undefined;
    var count: usize = 0;
    for (keep) |fd| {
        if (fd < 0 or std.mem.indexOfScalar(i32, sorted[0..count], fd) != null) continue;
        if (count == sorted.len) return .INVAL;
        sorted[count] = fd;
        count += 1;
    }
    std.mem.sort(i32, sorted[0..count], {}, std.sort.asc(i32));
    var next: u32 = 0;
    for (sorted[0..count]) |fd| {
        const value: u32 = @intCast(fd);
        if (value > next) {
            const err = closeRange(next, value - 1);
            if (err == .NOSYS) return closeAllExceptSlow(sorted[0..count]);
            if (err != .SUCCESS) return err;
        }
        next = value + 1;
    }
    const err = closeRange(next, close_range_max);
    if (err == .NOSYS) return closeAllExceptSlow(sorted[0..count]);
    return err;
}

fn closeAllExceptSlow(keep: []const i32) E {
    const opened = openAt(linux.AT.FDCWD, "/proc/self/fd", dir_flags);
    if (!opened.ok()) return opened.err;
    var reader = DirReader{ .fd = opened.fd() };
    defer closeFd(&reader.fd);
    while (true) {
        const entry = (reader.next() catch return .IO) orelse return .SUCCESS;
        const fd = std.fmt.parseInt(i32, entry.name, 10) catch continue;
        if (fd == reader.fd or std.mem.indexOfScalar(i32, keep, fd) != null) continue;
        _ = linux.close(fd);
    }
}

fn relocateDescriptor(control_fd: i32, fd: *i32) void {
    if (fd.* < 0 or fd.* > 2) return;
    const moved: i32 = @intCast(childCheck(control_fd, linux.fcntl(fd.*, f_dupfd_cloexec, 3), error.ChildFdCleanupFailed));
    _ = linux.close(fd.*);
    fd.* = moved;
}

fn prepareChildDescriptors(state: *ChildState) void {
    relocateDescriptor(state.control_fd, &state.control_fd);
    relocateDescriptor(state.control_fd, &state.ipc_fd);
    relocateDescriptor(state.control_fd, &state.runner_fd);
    relocateDescriptor(state.control_fd, &state.data_fd);
    relocateDescriptor(state.control_fd, &state.upstream_fd);
    var null_fd: i32 = @intCast(childCheck(state.control_fd, retry(linux.openat, .{ linux.AT.FDCWD, "/dev/null", linux.O{ .ACCMODE = .RDWR, .CLOEXEC = true }, @as(linux.mode_t, 0) }), error.ChildStdioFailed));
    relocateDescriptor(state.control_fd, &null_fd);
    const keep = [_]i32{ null_fd, state.control_fd, state.ipc_fd, state.runner_fd, state.data_fd, state.upstream_fd };
    const closed = closeAllExcept(&keep);
    if (closed != .SUCCESS) childFail(state.control_fd, error.ChildFdCleanupFailed, closed);
    var target: i32 = 0;
    while (target <= 2) : (target += 1) {
        _ = childCheck(state.control_fd, retry(linux.dup3, .{ null_fd, target, @as(u32, 0) }), error.ChildStdioFailed);
    }
    closeFd(&null_fd);
}

fn childHandshake(context: *const ChildContext, state: *ChildState) void {
    const control_fd = state.control_fd;
    const deadline = Deadline.after(handshake_timeout_ms) orelse childFail(control_fd, error.ChildHandshakeFailed, .NOSYS);
    const maps = recvControl(control_fd, deadline);
    if (maps.status != .SUCCESS) childFail(control_fd, error.ChildHandshakeFailed, maps.status);
    state.tree_fd = maps.fd;
    if (maps.message.kind != @intFromEnum(ControlKind.maps_ready)) childFail(control_fd, error.ChildHandshakeFailed, .PROTO);
    if (context.distinct_ids != (state.tree_fd >= 0)) childFail(control_fd, error.ChildHandshakeFailed, .PROTO);
    if (context.allow_setgroups) {
        _ = childCheck(control_fd, linux.setgroups(0, &empty_group_list), error.ChildSetgroupsFailed);
        const remaining = childCheck(control_fd, linux.getgroups(0, null), error.ChildIdentityUnverified);
        if (remaining != 0) childFail(control_fd, error.ChildIdentityUnverified, .PERM);
    }
    _ = childCheck(control_fd, linux.setresgid(0, 0, 0), error.ChildSetgidFailed);
    _ = childCheck(control_fd, linux.setresuid(0, 0, 0), error.ChildSetuidFailed);
    var real_uid: u32 = 1;
    var effective_uid: u32 = 1;
    var saved_uid: u32 = 1;
    var real_gid: u32 = 1;
    var effective_gid: u32 = 1;
    var saved_gid: u32 = 1;
    _ = childCheck(control_fd, linux.getresuid(&real_uid, &effective_uid, &saved_uid), error.ChildIdentityUnverified);
    _ = childCheck(control_fd, linux.getresgid(&real_gid, &effective_gid, &saved_gid), error.ChildIdentityUnverified);
    if ((real_uid | effective_uid | saved_uid | real_gid | effective_gid | saved_gid) != 0) childFail(control_fd, error.ChildIdentityUnverified, .PERM);
    _ = childCheck(control_fd, linux.prctl(@intFromEnum(linux.PR.SET_PDEATHSIG), linux.SIG.KILL, 0, 0, 0), error.ChildDeathSignalFailed);
    const armed = sendControl(control_fd, controlMessage(.armed, 0, 0), -1);
    if (armed != .SUCCESS) childFail(control_fd, error.ChildHandshakeFailed, armed);
    var go = recvControl(control_fd, deadline);
    if (go.status != .SUCCESS) childFail(control_fd, error.ChildHandshakeFailed, go.status);
    if (go.fd >= 0) {
        closeFd(&go.fd);
        childFail(control_fd, error.ChildHandshakeFailed, .PROTO);
    }
    if (go.message.kind != @intFromEnum(ControlKind.go) or go.message.code != go_token) childFail(control_fd, error.ChildHandshakeFailed, .PROTO);
}

fn childEnterNamespaces(control_fd: i32) void {
    _ = childCheck(control_fd, linux.unshare(linux.CLONE.NEWCGROUP), error.ChildCgroupNamespaceFailed);
    _ = childCheck(control_fd, linux.syscall0(.setsid), error.ChildSessionFailed);
}

fn selectStagingDirectory() ?[:0]const u8 {
    for (staging_candidates) |candidate| {
        var info: linux.Stat = undefined;
        if (E.init(linux.fstatat(linux.AT.FDCWD, candidate, &info, 0)) == .SUCCESS and (info.mode & linux.S.IFMT) == linux.S.IFDIR) return candidate;
    }
    return null;
}

fn createDirectories(control_fd: i32, root_fd: i32, relative: []const u8, include_last: bool, err: SandboxError) void {
    var buffer: [sandbox_path_capacity]u8 = undefined;
    var index: usize = 0;
    while (index < relative.len) {
        const slash = std.mem.indexOfScalarPos(u8, relative, index, '/');
        if (slash == null and !include_last) return;
        const end = slash orelse relative.len;
        if (end + 1 > buffer.len) childFail(control_fd, err, .NAMETOOLONG);
        @memcpy(buffer[0..end], relative[0..end]);
        buffer[end] = 0;
        const made = sys(linux.mkdirat(root_fd, buffer[0..end :0], 0o700));
        if (!made.ok() and made.err != .EXIST) childFail(control_fd, err, made.err);
        index = end + 1;
    }
}

fn createMountPoint(control_fd: i32, root_fd: i32, relative: [*:0]const u8, err: SandboxError) void {
    var fd: i32 = @intCast(childCheck(control_fd, retry(linux.openat, .{ root_fd, relative, mount_point_flags, @as(linux.mode_t, 0o600) }), err));
    closeFd(&fd);
}

fn preservedMountFlags(statfs_flags: u64) u32 {
    var flags: u32 = 0;
    if ((statfs_flags & st_rdonly) != 0) flags |= linux.MS.RDONLY;
    if ((statfs_flags & st_nosuid) != 0) flags |= linux.MS.NOSUID;
    if ((statfs_flags & st_nodev) != 0) flags |= linux.MS.NODEV;
    if ((statfs_flags & st_noexec) != 0) flags |= linux.MS.NOEXEC;
    if ((statfs_flags & st_noatime) != 0) flags |= linux.MS.NOATIME;
    if ((statfs_flags & st_nodiratime) != 0) flags |= linux.MS.NODIRATIME;
    if ((statfs_flags & st_relatime) != 0) flags |= linux.MS.RELATIME;
    if ((statfs_flags & (st_noatime | st_relatime)) == 0) flags |= linux.MS.STRICTATIME;
    return flags;
}

fn remountWithFlags(control_fd: i32, target: [*:0]const u8, extra_flags: u32, err: SandboxError) void {
    var info: StatFs = undefined;
    _ = childCheck(control_fd, linux.syscall2(.statfs, @intFromPtr(target), @intFromPtr(&info)), err);
    const flags = linux.MS.BIND | linux.MS.REMOUNT | extra_flags | preservedMountFlags(@bitCast(info.f_flags));
    _ = childCheck(control_fd, linux.mount("none", target, null, flags, 0), err);
}

fn bindMount(control_fd: i32, source: [*:0]const u8, target: [*:0]const u8, recursive: bool, extra_flags: u32, err: SandboxError) void {
    const bind_flags: u32 = if (recursive) linux.MS.BIND | linux.MS.REC else linux.MS.BIND;
    _ = childCheck(control_fd, linux.mount(source, target, null, bind_flags, 0), err);
    remountWithFlags(control_fd, target, extra_flags, err);
}

fn reopenInNamespace(control_fd: i32, inherited_fd: *i32, path: [*:0]const u8, flags: linux.O, err: SandboxError) void {
    var expected: linux.Stat = undefined;
    _ = childCheck(control_fd, linux.fstat(inherited_fd.*, &expected), err);
    var reopened: i32 = @intCast(childCheck(control_fd, retry(linux.openat, .{ linux.AT.FDCWD, path, flags, @as(linux.mode_t, 0) }), err));
    var current: linux.Stat = undefined;
    const described = sys(linux.fstat(reopened, &current));
    if (!described.ok()) childFail(control_fd, err, described.err);
    if (current.dev != expected.dev or current.ino != expected.ino) {
        closeFd(&reopened);
        childFail(control_fd, err, .STALE);
    }
    closeFd(inherited_fd);
    inherited_fd.* = reopened;
}

fn childBuildRoot(context: *const ChildContext, state: *ChildState) void {
    const control_fd = state.control_fd;
    _ = childCheck(control_fd, linux.mount("none", "/", null, linux.MS.REC | linux.MS.PRIVATE, 0), error.ChildMountPropagationFailed);
    reopenInNamespace(control_fd, &state.runner_fd, &runner_path_z, .{ .PATH = true, .CLOEXEC = true }, error.ChildRunnerBindFailed);
    if (state.tree_fd < 0) reopenInNamespace(control_fd, &state.data_fd, context.data_dir.ptr, .{ .PATH = true, .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, error.ChildDataBindFailed);
    const staging = selectStagingDirectory() orelse childFail(control_fd, error.ChildRootMountFailed, .NOENT);
    _ = childCheck(control_fd, linux.mount("tmpfs", staging, "tmpfs", linux.MS.NOSUID | linux.MS.NODEV, @intFromPtr(root_tmpfs_options)), error.ChildRootMountFailed);
    var root_fd: i32 = @intCast(childCheck(control_fd, retry(linux.openat, .{ linux.AT.FDCWD, staging, dir_flags, @as(linux.mode_t, 0) }), error.ChildRootLayoutFailed));
    for ([_][:0]const u8{ "proc", "dev", "tmp" }) |name| {
        _ = childCheck(control_fd, linux.mkdirat(root_fd, name, 0o700), error.ChildRootLayoutFailed);
    }
    var target_buffer: [sandbox_path_capacity]u8 = undefined;
    var source_buffer: [proc_fd_path_capacity]u8 = undefined;
    for (device_nodes) |device| {
        var relative_buffer: [32]u8 = undefined;
        const relative = std.fmt.bufPrintZ(&relative_buffer, "dev/{s}", .{device}) catch childFail(control_fd, error.ChildRootLayoutFailed, .NAMETOOLONG);
        createMountPoint(control_fd, root_fd, relative, error.ChildRootLayoutFailed);
        const source = std.fmt.bufPrintZ(&source_buffer, "/dev/{s}", .{device}) catch childFail(control_fd, error.ChildDeviceBindFailed, .NAMETOOLONG);
        const target = std.fmt.bufPrintZ(&target_buffer, "{s}/{s}", .{ staging, relative }) catch childFail(control_fd, error.ChildDeviceBindFailed, .NAMETOOLONG);
        bindMount(control_fd, source, target, false, linux.MS.NOSUID | linux.MS.NOEXEC, error.ChildDeviceBindFailed);
    }
    const runner_relative: [:0]const u8 = runner_path_z[1..];
    createDirectories(control_fd, root_fd, runner_relative, false, error.ChildRootLayoutFailed);
    createMountPoint(control_fd, root_fd, runner_relative, error.ChildRootLayoutFailed);
    {
        const source = std.fmt.bufPrintZ(&source_buffer, "/proc/self/fd/{d}", .{state.runner_fd}) catch childFail(control_fd, error.ChildRunnerBindFailed, .NAMETOOLONG);
        const target = std.fmt.bufPrintZ(&target_buffer, "{s}/{s}", .{ staging, runner_relative }) catch childFail(control_fd, error.ChildRunnerBindFailed, .NAMETOOLONG);
        bindMount(control_fd, source, target, false, linux.MS.RDONLY | linux.MS.NOSUID | linux.MS.NODEV, error.ChildRunnerBindFailed);
    }
    createDirectories(control_fd, root_fd, context.data_dir_relative, true, error.ChildRootLayoutFailed);
    {
        const target = std.fmt.bufPrintZ(&target_buffer, "{s}/{s}", .{ staging, context.data_dir_relative }) catch childFail(control_fd, error.ChildDataBindFailed, .NAMETOOLONG);
        if (state.tree_fd >= 0) {
            _ = childCheck(control_fd, linux.syscall5(.move_mount, fdArg(state.tree_fd), @intFromPtr(""), fdArg(linux.AT.FDCWD), @intFromPtr(target.ptr), move_mount_f_empty_path), error.ChildDataBindFailed);
        } else {
            const source = std.fmt.bufPrintZ(&source_buffer, "/proc/self/fd/{d}", .{state.data_fd}) catch childFail(control_fd, error.ChildDataBindFailed, .NAMETOOLONG);
            bindMount(control_fd, source, target, true, linux.MS.NOSUID | linux.MS.NODEV, error.ChildDataBindFailed);
        }
    }
    {
        const target = std.fmt.bufPrintZ(&target_buffer, "{s}/proc", .{staging}) catch childFail(control_fd, error.ChildProcMountFailed, .NAMETOOLONG);
        _ = childCheck(control_fd, linux.mount("proc", target, "proc", linux.MS.NOSUID | linux.MS.NODEV | linux.MS.NOEXEC, 0), error.ChildProcMountFailed);
    }
    _ = childCheck(control_fd, linux.fchdir(root_fd), error.ChildPivotRootFailed);
    _ = childCheck(control_fd, linux.syscall2(.pivot_root, @intFromPtr("."), @intFromPtr(".")), error.ChildPivotRootFailed);
    _ = childCheck(control_fd, linux.umount2(".", linux.MNT.DETACH), error.ChildPivotRootFailed);
    _ = childCheck(control_fd, linux.chdir("/"), error.ChildPivotRootFailed);
    closeFd(&root_fd);
    closeFd(&state.runner_fd);
    closeFd(&state.data_fd);
    closeFd(&state.tree_fd);
}

fn childLoopbackUp(control_fd: i32) void {
    var fd: i32 = @intCast(childCheck(control_fd, linux.socket(linux.AF.INET, linux.SOCK.DGRAM | linux.SOCK.CLOEXEC, 0), error.ChildLoopbackFailed));
    defer closeFd(&fd);
    var request = std.mem.zeroes(linux.ifreq);
    @memcpy(request.ifrn.name[0..2], "lo");
    _ = childCheck(control_fd, linux.ioctl(fd, linux.SIOCGIFFLAGS, @intFromPtr(&request)), error.ChildLoopbackFailed);
    request.ifru.flags.UP = true;
    _ = childCheck(control_fd, linux.ioctl(fd, linux.SIOCSIFFLAGS, @intFromPtr(&request)), error.ChildLoopbackFailed);
}

fn childWalListener(control_fd: i32, port: u16) i32 {
    var fd: i32 = @intCast(childCheck(control_fd, linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK, linux.IPPROTO.TCP), error.ChildWalRelayFailed));
    errdefer closeFd(&fd);
    const address = linux.sockaddr.in{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f000001) };
    _ = childCheck(control_fd, linux.bind(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.in)), error.ChildWalRelayFailed);
    _ = childCheck(control_fd, linux.listen(fd, 4), error.ChildWalRelayFailed);
    return fd;
}

const bpf_ld_w_abs: u16 = 0x00 | 0x00 | 0x20;
const bpf_jmp_jeq_k: u16 = 0x05 | 0x10 | 0x00;
const bpf_jmp_jge_k: u16 = 0x05 | 0x30 | 0x00;
const bpf_jmp_jset_k: u16 = 0x05 | 0x40 | 0x00;
const bpf_ret_k: u16 = 0x06 | 0x00;
const seccomp_ret_errno_eperm: u32 = linux.SECCOMP.RET.ERRNO | @as(u32, @intFromEnum(E.PERM));
const seccomp_ret_errno_enosys: u32 = linux.SECCOMP.RET.ERRNO | @as(u32, @intFromEnum(E.NOSYS));
const seccomp_clone_flags_offset: u32 = @offsetOf(linux.SECCOMP.data, "arg0") + (if (native_endian == .big) 4 else 0);
const seccomp_clone_namespace_mask: u32 = linux.CLONE.NEWNS | linux.CLONE.NEWUTS | linux.CLONE.NEWIPC | linux.CLONE.NEWUSER | linux.CLONE.NEWPID | linux.CLONE.NEWNET | linux.CLONE.NEWCGROUP;

const seccomp_denied_syscall_names = [_][]const u8{
    "kexec_load",        "kexec_file_load",   "init_module",     "finit_module",
    "delete_module",     "reboot",            "swapon",          "swapoff",
    "acct",              "settimeofday",      "clock_settime",   "clock_settime64",
    "clock_adjtime",     "clock_adjtime64",   "adjtimex",        "iopl",
    "ioperm",            "quotactl",          "quotactl_fd",     "lookup_dcookie",
    "perf_event_open",   "bpf",               "userfaultfd",     "keyctl",
    "add_key",           "request_key",       "ptrace",          "process_vm_readv",
    "process_vm_writev", "process_madvise",   "kcmp",            "pidfd_getfd",
    "open_by_handle_at", "name_to_handle_at", "setns",           "unshare",
    "fsopen",            "fsconfig",          "fsmount",         "fspick",
    "open_tree",         "move_mount",        "mount_setattr",   "chroot",
    "uselib",            "ustat",             "sysfs",           "vhangup",
    "nfsservctl",        "syslog",            "personality",     "mbind",
    "set_mempolicy",     "migrate_pages",     "move_pages",      "set_mempolicy_home_node",
    "_sysctl",           "create_module",     "get_kernel_syms", "query_module",
    "afs_syscall",       "tuxcall",           "security",        "vserver",
};

const seccomp_denied_syscalls = blk: {
    var numbers: [seccomp_denied_syscall_names.len]u32 = undefined;
    var count: usize = 0;
    for (seccomp_denied_syscall_names) |name| {
        if (@hasField(linux.SYS, name)) {
            numbers[count] = @intCast(@intFromEnum(@field(linux.SYS, name)));
            count += 1;
        }
    }
    var result: [count]u32 = undefined;
    @memcpy(&result, numbers[0..count]);
    break :blk result;
};

fn bpfStatement(code: u16, k: u32) SockFilter {
    return .{ .code = code, .jt = 0, .jf = 0, .k = k };
}

fn bpfJump(code: u16, k: u32, jt: usize, jf: usize) SockFilter {
    return .{ .code = code, .jt = @intCast(jt), .jf = @intCast(jf), .k = k };
}

const seccomp_filter = blk: {
    const check_x32 = builtin.cpu.arch == .x86_64;
    const prologue_length: usize = 4 + @as(usize, if (check_x32) 1 else 0) + 2;
    const allow_index = prologue_length + seccomp_denied_syscalls.len;
    const clone_check_index = allow_index + 1;
    const deny_index = clone_check_index + 3;
    const enosys_index = deny_index + 1;
    var program: [enosys_index + 1]SockFilter = undefined;
    var index: usize = 0;
    program[index] = bpfStatement(bpf_ld_w_abs, @offsetOf(linux.SECCOMP.data, "arch"));
    index += 1;
    program[index] = bpfJump(bpf_jmp_jeq_k, audit_arch_current, 1, 0);
    index += 1;
    program[index] = bpfStatement(bpf_ret_k, linux.SECCOMP.RET.KILL_PROCESS);
    index += 1;
    program[index] = bpfStatement(bpf_ld_w_abs, @offsetOf(linux.SECCOMP.data, "nr"));
    index += 1;
    if (check_x32) {
        program[index] = bpfJump(bpf_jmp_jge_k, x32_syscall_bit, deny_index - index - 1, 0);
        index += 1;
    }
    program[index] = bpfJump(bpf_jmp_jeq_k, @intFromEnum(linux.SYS.clone3), enosys_index - index - 1, 0);
    index += 1;
    program[index] = bpfJump(bpf_jmp_jeq_k, @intFromEnum(linux.SYS.clone), clone_check_index - index - 1, 0);
    index += 1;
    for (seccomp_denied_syscalls) |number| {
        program[index] = bpfJump(bpf_jmp_jeq_k, number, deny_index - index - 1, 0);
        index += 1;
    }
    program[index] = bpfStatement(bpf_ret_k, linux.SECCOMP.RET.ALLOW);
    index += 1;
    program[index] = bpfStatement(bpf_ld_w_abs, seccomp_clone_flags_offset);
    index += 1;
    program[index] = bpfJump(bpf_jmp_jset_k, seccomp_clone_namespace_mask, deny_index - index - 1, 0);
    index += 1;
    program[index] = bpfStatement(bpf_ret_k, linux.SECCOMP.RET.ALLOW);
    index += 1;
    program[index] = bpfStatement(bpf_ret_k, seccomp_ret_errno_eperm);
    index += 1;
    program[index] = bpfStatement(bpf_ret_k, seccomp_ret_errno_enosys);
    break :blk program;
};

fn installSeccompFilter(control_fd: i32) void {
    const program = SockFprog{ .len = seccomp_filter.len, .filter = &seccomp_filter };
    var installed = sys(linux.seccomp(linux.SECCOMP.SET_MODE_FILTER, 0, &program));
    if (installed.err == .NOSYS) installed = sys(linux.prctl(@intFromEnum(linux.PR.SET_SECCOMP), linux.SECCOMP.MODE.FILTER, @intFromPtr(&program), 0, 0));
    if (!installed.ok()) childFail(control_fd, error.ChildSeccompFailed, installed.err);
}

fn dropBoundingSet(keep: u64) E {
    var capability: u32 = 0;
    while (capability < 64) : (capability += 1) {
        const present = sys(linux.prctl(@intFromEnum(linux.PR.CAPBSET_READ), capability, 0, 0, 0));
        if (present.err == .INVAL) return .SUCCESS;
        if (!present.ok()) return present.err;
        if (present.value == 0 or (keep & (@as(u64, 1) << @as(u6, @intCast(capability)))) != 0) continue;
        const dropped = E.init(linux.prctl(@intFromEnum(linux.PR.CAPBSET_DROP), capability, 0, 0, 0));
        if (dropped != .SUCCESS) return dropped;
    }
    return .SUCCESS;
}

fn restrictCapabilities(keep: u64) E {
    const bounded = dropBoundingSet(keep);
    if (bounded != .SUCCESS) return bounded;
    var header = CapHeader{ .version = linux_capability_version_3, .pid = 0 };
    const low: u32 = @truncate(keep);
    const high: u32 = @truncate(keep >> 32);
    const data = [2]CapData{
        .{ .effective = low, .permitted = low, .inheritable = 0 },
        .{ .effective = high, .permitted = high, .inheritable = 0 },
    };
    const applied = E.init(linux.syscall2(.capset, @intFromPtr(&header), @intFromPtr(&data)));
    if (applied != .SUCCESS) return applied;
    const ambient = E.init(linux.prctl(@intFromEnum(linux.PR.CAP_AMBIENT), pr_cap_ambient_clear_all, 0, 0, 0));
    if (ambient != .SUCCESS and ambient != .INVAL) return ambient;
    return .SUCCESS;
}

fn runnerFail(report_fd: i32, err: SandboxError, errno_value: E) noreturn {
    const record = [2]u32{ errorCode(err), @intFromEnum(errno_value) };
    const bytes = std.mem.asBytes(&record);
    _ = retry(linux.write, .{ report_fd, bytes, bytes.len });
    linux.exit_group(127);
}

fn arrangeRunnerDescriptors(ipc_fd: i32, report_fd: i32) void {
    const staged_ipc = sys(linux.fcntl(ipc_fd, f_dupfd_cloexec, descriptor_staging_floor));
    if (!staged_ipc.ok()) runnerFail(report_fd, error.RunnerFdLayoutFailed, staged_ipc.err);
    const staged_report = sys(linux.fcntl(report_fd, f_dupfd_cloexec, descriptor_staging_floor));
    if (!staged_report.ok()) runnerFail(report_fd, error.RunnerFdLayoutFailed, staged_report.err);
    var ipc_staged = staged_ipc.fd();
    var report_staged = staged_report.fd();
    var original_ipc = ipc_fd;
    var original_report = report_fd;
    closeFd(&original_ipc);
    closeFd(&original_report);
    const placed_ipc = sys(retry(linux.dup3, .{ ipc_staged, runner_ipc_fd, @as(u32, 0) }));
    if (!placed_ipc.ok()) runnerFail(report_staged, error.RunnerFdLayoutFailed, placed_ipc.err);
    const placed_report = sys(retry(linux.dup3, .{ report_staged, runner_report_fd, cloexec_flag_bits }));
    if (!placed_report.ok()) runnerFail(report_staged, error.RunnerFdLayoutFailed, placed_report.err);
    closeFd(&ipc_staged);
    closeFd(&report_staged);
    const cleared = sys(linux.fcntl(runner_ipc_fd, linux.F.SETFD, 0));
    if (!cleared.ok()) runnerFail(runner_report_fd, error.RunnerFdLayoutFailed, cleared.err);
    const flags = sys(linux.fcntl(runner_ipc_fd, linux.F.GETFD, 0));
    if (!flags.ok()) runnerFail(runner_report_fd, error.RunnerFdLayoutFailed, flags.err);
    if ((flags.value & linux.FD_CLOEXEC) != 0) runnerFail(runner_report_fd, error.RunnerFdLayoutFailed, .INVAL);
    const closed = closeAllExcept(&[_]i32{ 0, 1, 2, runner_ipc_fd, runner_report_fd });
    if (closed != .SUCCESS) runnerFail(runner_report_fd, error.RunnerFdLayoutFailed, closed);
}

fn runnerProcessMain(state: *ChildState, exec_pipe: [2]i32, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) noreturn {
    const report_fd = exec_pipe[1];
    const armed = E.init(linux.prctl(@intFromEnum(linux.PR.SET_PDEATHSIG), linux.SIG.KILL, 0, 0, 0));
    if (armed != .SUCCESS) runnerFail(report_fd, error.RunnerDeathSignalFailed, armed);
    if (linux.getppid() != 1) runnerFail(report_fd, error.RunnerDeathSignalFailed, .SRCH);
    var read_end = exec_pipe[0];
    closeFd(&read_end);
    closeFd(&state.control_fd);
    closeFd(&state.listen_fd);
    closeFd(&state.upstream_fd);
    arrangeRunnerDescriptors(state.ipc_fd, report_fd);
    const restricted = restrictCapabilities(capabilityBit(linux.CAP.SYS_ADMIN) | capabilityBit(linux.CAP.SETPCAP));
    if (restricted != .SUCCESS) runnerFail(runner_report_fd, error.RunnerCapabilitiesFailed, restricted);
    const unmasked = E.init(linux.sigprocmask(linux.SIG.SETMASK, &linux.empty_sigset, null));
    if (unmasked != .SUCCESS) runnerFail(runner_report_fd, error.RunnerSignalMaskFailed, unmasked);
    const executed = E.init(linux.execve(&runner_path_z, argv, envp));
    runnerFail(runner_report_fd, error.RunnerExecFailed, executed);
}

const ExecReport = union(enum) {
    success,
    failure: struct { err: SandboxError, errno_value: E },
    timeout,
    channel_error: E,
};

fn readExecReport(fd: i32) ExecReport {
    const deadline = Deadline.after(exec_status_timeout_ms) orelse return .{ .channel_error = .NOSYS };
    var record: [2]u32 = undefined;
    const bytes = std.mem.asBytes(&record);
    var received: usize = 0;
    while (received < bytes.len) {
        var fds = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
        const polled = pollUntil(&fds, deadline);
        if (!polled.ok()) return .{ .channel_error = polled.err };
        if (polled.value == 0) return .timeout;
        const result = sys(retry(linux.read, .{ fd, bytes[received..].ptr, bytes.len - received }));
        if (!result.ok()) return .{ .channel_error = result.err };
        if (result.value == 0) {
            if (received == 0) return .success;
            return .{ .channel_error = .PROTO };
        }
        received += result.value;
    }
    const err = sandboxErrorFromCode(record[0]) orelse return .{ .channel_error = .PROTO };
    return .{ .failure = .{ .err = err, .errno_value = errnoFromCode(record[1]) } };
}

fn childLaunchRunner(context: *const ChildContext, state: *ChildState) noreturn {
    const control_fd = state.control_fd;
    var tenant_id_buffer: [24]u8 = undefined;
    const tenant_id_text = std.fmt.bufPrintZ(&tenant_id_buffer, "{d}", .{context.tenant_id}) catch childFail(control_fd, error.ChildExecChannelFailed, .NAMETOOLONG);
    var environment_buffer: [wal_environment_capacity]u8 = undefined;
    const wal_environment = std.fmt.bufPrintZ(&environment_buffer, "{s}{s}:{d}", .{ wal_environment_name, relay_host, context.wal_port }) catch childFail(control_fd, error.ChildExecChannelFailed, .NAMETOOLONG);
    const argv = [_:null]?[*:0]const u8{ &runner_path_z, tenant_id_text.ptr, runner_ipc_fd_text, context.data_path.ptr };
    const stateless_environment = [_:null]?[*:0]const u8{wal_environment.ptr};
    const empty_environment = [_:null]?[*:0]const u8{};
    const envp: [*:null]const ?[*:0]const u8 = if (context.stateless) &stateless_environment else &empty_environment;
    _ = childCheck(control_fd, linux.prctl(@intFromEnum(linux.PR.SET_NO_NEW_PRIVS), 1, 0, 0, 0), error.ChildNoNewPrivsFailed);
    installSeccompFilter(control_fd);
    var exec_pipe: [2]i32 = undefined;
    _ = childCheck(control_fd, linux.pipe2(&exec_pipe, .{ .CLOEXEC = true }), error.ChildExecChannelFailed);
    const forked = childCheck(control_fd, linux.fork(), error.ChildForkFailed);
    if (forked == 0) runnerProcessMain(state, exec_pipe, &argv, envp);
    const runner_pid: i32 = @intCast(forked);
    var exec_read_fd = exec_pipe[0];
    var exec_write_fd = exec_pipe[1];
    closeFd(&exec_write_fd);
    closeFd(&state.ipc_fd);
    const report = readExecReport(exec_read_fd);
    closeFd(&exec_read_fd);
    switch (report) {
        .success => {},
        .failure => |failure| {
            _ = linux.kill(runner_pid, linux.SIG.KILL);
            childFail(control_fd, failure.err, failure.errno_value);
        },
        .timeout => {
            _ = linux.kill(runner_pid, linux.SIG.KILL);
            childFail(control_fd, error.RunnerExecTimeout, .TIMEDOUT);
        },
        .channel_error => |err| {
            _ = linux.kill(runner_pid, linux.SIG.KILL);
            childFail(control_fd, error.ChildExecChannelFailed, err);
        },
    }
    const restricted = restrictCapabilities(0);
    if (restricted != .SUCCESS) {
        _ = linux.kill(runner_pid, linux.SIG.KILL);
        childFail(control_fd, error.ChildCapabilitiesFailed, restricted);
    }
    const undumpable = E.init(linux.prctl(@intFromEnum(linux.PR.SET_DUMPABLE), 0, 0, 0, 0));
    if (undumpable != .SUCCESS) {
        _ = linux.kill(runner_pid, linux.SIG.KILL);
        childFail(control_fd, error.ChildCapabilitiesFailed, undumpable);
    }
    const signal_fd_result = sys(linux.signalfd(-1, &linux.all_mask, linux.SFD.CLOEXEC | linux.SFD.NONBLOCK));
    if (!signal_fd_result.ok()) {
        _ = linux.kill(runner_pid, linux.SIG.KILL);
        childFail(control_fd, error.ChildSignalSetupFailed, signal_fd_result.err);
    }
    releaseInheritedMemory();
    const ready = sendControl(control_fd, controlMessage(.ready, 0, 0), -1);
    if (ready != .SUCCESS) {
        _ = linux.kill(runner_pid, linux.SIG.KILL);
        linux.exit_group(1);
    }
    closeFd(&state.control_fd);
    superviseSandbox(runner_pid, signal_fd_result.fd(), state.listen_fd, state.upstream_fd);
}

fn threadPointer() usize {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            var value: usize = 0;
            if (E.init(linux.syscall2(.arch_prctl, arch_get_fs, @intFromPtr(&value))) != .SUCCESS) return 0;
            return value;
        },
        .aarch64 => return asm volatile ("mrs %[value], tpidr_el0"
            : [value] "=r" (-> usize),
        ),
        else => return 0,
    }
}

fn releaseInheritedMemory() void {
    const stack_address = @frameAddress();
    const tls_address = threadPointer();
    if (tls_address == 0) return;
    const opened = openAt(linux.AT.FDCWD, "/proc/self/maps", read_flags);
    if (!opened.ok()) return;
    var fd = opened.fd();
    defer closeFd(&fd);
    var buffer: [8192]u8 = undefined;
    var reader = LineReader{ .fd = fd, .buffer = &buffer };
    while (reader.next() catch null) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const range = fields.next() orelse continue;
        const permissions = fields.next() orelse continue;
        if (permissions.len < 4 or permissions[1] != 'w' or permissions[3] != 'p') continue;
        const dash = std.mem.indexOfScalar(u8, range, '-') orelse continue;
        const start = std.fmt.parseInt(usize, range[0..dash], 16) catch continue;
        const end = std.fmt.parseInt(usize, range[dash + 1 ..], 16) catch continue;
        if (start == 0 or end <= start) continue;
        if (stack_address >= start and stack_address < end) continue;
        if (tls_address >= start and tls_address < end) continue;
        _ = linux.madvise(@ptrFromInt(start), end - start, linux.MADV.DONTNEED);
    }
}

const RelayDirection = struct {
    buffer: [relay_buffer_size]u8 = undefined,
    start: usize = 0,
    end: usize = 0,
    source_closed: bool = false,
    sink_shut: bool = false,

    fn hasData(self: *const RelayDirection) bool {
        return self.end > self.start;
    }

    fn hasSpace(self: *const RelayDirection) bool {
        return !self.source_closed and self.end < self.buffer.len;
    }

    fn finished(self: *const RelayDirection) bool {
        return self.source_closed and !self.hasData();
    }

    fn pump(self: *RelayDirection, source_fd: i32, sink_fd: i32, readable: bool) bool {
        if (readable and self.hasSpace()) {
            const received = sys(retry(linux.recvfrom, .{ source_fd, self.buffer[self.end..].ptr, self.buffer.len - self.end, @as(u32, 0), null, null }));
            if (received.ok()) {
                if (received.value == 0) {
                    self.source_closed = true;
                } else {
                    self.end += received.value;
                }
            } else if (received.err != .AGAIN) {
                return false;
            }
        }
        if (self.hasData()) {
            const sent = sys(retry(linux.sendto, .{ sink_fd, self.buffer[self.start..self.end].ptr, self.end - self.start, @as(u32, linux.MSG.NOSIGNAL), null, @as(linux.socklen_t, 0) }));
            if (sent.ok()) {
                self.start += sent.value;
                if (self.start == self.end) {
                    self.start = 0;
                    self.end = 0;
                }
            } else if (sent.err != .AGAIN) {
                return false;
            }
        }
        if (self.finished() and !self.sink_shut) {
            _ = linux.shutdown(sink_fd, linux.SHUT.WR);
            self.sink_shut = true;
        }
        return true;
    }

    fn interest(inbound: *const RelayDirection, outbound: *const RelayDirection) i16 {
        var events: i16 = 0;
        if (inbound.hasSpace()) events |= linux.POLL.IN;
        if (outbound.hasData()) events |= linux.POLL.OUT;
        return events;
    }
};

const WalRelay = struct {
    listen_fd: i32,
    upstream_fd: i32,
    client_fd: i32 = -1,
    to_upstream: RelayDirection = .{},
    to_client: RelayDirection = .{},

    fn active(self: *const WalRelay) bool {
        return self.client_fd >= 0 and self.upstream_fd >= 0;
    }

    fn shutdownAll(self: *WalRelay) void {
        closeFd(&self.listen_fd);
        closeFd(&self.client_fd);
        closeFd(&self.upstream_fd);
    }

    fn acceptClient(self: *WalRelay) void {
        const accepted = sys(retry(linux.accept4, .{ self.listen_fd, null, null, @as(u32, linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK) }));
        if (accepted.err == .AGAIN) return;
        if (!accepted.ok()) {
            self.shutdownAll();
            return;
        }
        self.client_fd = accepted.fd();
        closeFd(&self.listen_fd);
    }

    fn service(self: *WalRelay, client_events: i16, upstream_events: i16) void {
        if (((client_events | upstream_events) & (linux.POLL.ERR | linux.POLL.NVAL)) != 0) {
            self.shutdownAll();
            return;
        }
        const client_readable = (client_events & (linux.POLL.IN | linux.POLL.HUP)) != 0;
        const upstream_readable = (upstream_events & (linux.POLL.IN | linux.POLL.HUP)) != 0;
        if (!self.to_upstream.pump(self.client_fd, self.upstream_fd, client_readable) or !self.to_client.pump(self.upstream_fd, self.client_fd, upstream_readable)) {
            self.shutdownAll();
            return;
        }
        if (self.to_upstream.finished() and self.to_client.finished()) self.shutdownAll();
    }
};

fn exitCodeFromStatus(status: u32) u8 {
    if (linux.W.IFEXITED(status)) return linux.W.EXITSTATUS(status);
    if (linux.W.IFSIGNALED(status)) return @intCast(128 + (linux.W.TERMSIG(status) & 0x7f));
    return 1;
}

fn reapSandboxChildren(runner_pid: i32) void {
    while (true) {
        var status: u32 = 0;
        const result = sys(retry(linux.wait4, .{ @as(i32, -1), &status, @as(u32, linux.W.NOHANG), null }));
        if (!result.ok() or result.value == 0) return;
        const pid: i32 = @intCast(result.value);
        if (pid == runner_pid) linux.exit_group(exitCodeFromStatus(status));
    }
}

fn handleSupervisorSignals(runner_pid: i32, signal_fd: i32) void {
    while (true) {
        var info: linux.signalfd_siginfo = undefined;
        const bytes = std.mem.asBytes(&info);
        const result = sys(retry(linux.read, .{ signal_fd, bytes, bytes.len }));
        if (!result.ok() or result.value != bytes.len) return;
        if (info.signo == linux.SIG.CHLD) {
            reapSandboxChildren(runner_pid);
            continue;
        }
        if (std.mem.indexOfScalar(u32, &forwarded_signals, info.signo) != null) {
            _ = linux.kill(runner_pid, @intCast(info.signo));
        }
    }
}

fn superviseSandbox(runner_pid: i32, signal_fd: i32, listen_fd: i32, upstream_fd: i32) noreturn {
    var relay = WalRelay{ .listen_fd = listen_fd, .upstream_fd = upstream_fd };
    if (relay.listen_fd < 0 or relay.upstream_fd < 0) relay.shutdownAll();
    reapSandboxChildren(runner_pid);
    while (true) {
        var fds: [4]linux.pollfd = undefined;
        fds[0] = .{ .fd = signal_fd, .events = linux.POLL.IN, .revents = 0 };
        var count: usize = 1;
        var listen_slot: ?usize = null;
        var client_slot: ?usize = null;
        if (relay.listen_fd >= 0) {
            fds[count] = .{ .fd = relay.listen_fd, .events = linux.POLL.IN, .revents = 0 };
            listen_slot = count;
            count += 1;
        }
        if (relay.active()) {
            fds[count] = .{ .fd = relay.client_fd, .events = RelayDirection.interest(&relay.to_upstream, &relay.to_client), .revents = 0 };
            client_slot = count;
            count += 1;
            fds[count] = .{ .fd = relay.upstream_fd, .events = RelayDirection.interest(&relay.to_client, &relay.to_upstream), .revents = 0 };
            count += 1;
        }
        const polled = E.init(linux.poll(&fds, count, -1));
        if (polled == .INTR) continue;
        if (polled != .SUCCESS) {
            _ = linux.kill(runner_pid, linux.SIG.KILL);
            linux.exit_group(1);
        }
        if ((fds[0].revents & linux.POLL.IN) != 0) handleSupervisorSignals(runner_pid, signal_fd);
        if (listen_slot) |slot| {
            if (fds[slot].revents != 0) relay.acceptClient();
        }
        if (client_slot) |slot| {
            if (relay.active()) relay.service(fds[slot].revents, fds[slot + 1].revents);
        }
    }
}

fn sandboxChildMain(context: *const ChildContext) noreturn {
    var state = ChildState{
        .control_fd = context.control_fd,
        .ipc_fd = context.ipc_fd,
        .runner_fd = context.runner_fd,
        .data_fd = context.data_fd,
        .upstream_fd = context.upstream_fd,
    };
    const reset = resetSignalDispositions();
    if (reset != .SUCCESS) childFail(state.control_fd, error.ChildSignalSetupFailed, reset);
    _ = linux.syscall1(.umask, 0o077);
    prepareChildDescriptors(&state);
    childHandshake(context, &state);
    childEnterNamespaces(state.control_fd);
    childBuildRoot(context, &state);
    childLoopbackUp(state.control_fd);
    if (context.stateless and state.upstream_fd >= 0) state.listen_fd = childWalListener(state.control_fd, context.wal_port);
    childLaunchRunner(context, &state);
}
