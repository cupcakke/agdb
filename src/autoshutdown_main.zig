const std = @import("std");

pub const ConfigError = error{
    InvalidInteger,
    InvalidBoolean,
    InvalidPort,
};

pub const Config = struct {
    activity_host: []const u8,
    activity_port: u16,
    activity_path: []const u8,
    idle_seconds: i64,
    check_interval_seconds: u64,
    request_timeout_ms: u32,
    consecutive_idle_checks: u32,
    inhibit_file: []const u8,
    access_log_path: []const u8,
    use_access_log: bool,
    dry_run: bool,
    drain_timeout_seconds: u64,
    shutdown_command: []const u8,
    drain_unit: []const u8,
    drain_command: []const u8,

    pub fn fromEnvironment() ConfigError!Config {
        return Config{
            .activity_host = envOr("AGDB_ACTIVITY_HOST", "127.0.0.1"),
            .activity_port = try parsePort(envOr("AGDB_CLOUD_PORT", "7070")),
            .activity_path = envOr("AGDB_ACTIVITY_PATH", "/v1/activity"),
            .idle_seconds = try parseI64(envOr("AGDB_IDLE_SHUTDOWN_SECONDS", "900")),
            .check_interval_seconds = try parseU64(envOr("AGDB_IDLE_CHECK_INTERVAL_SECONDS", "60")),
            .request_timeout_ms = try parseU32(envOr("AGDB_ACTIVITY_TIMEOUT_MS", "3000")),
            .consecutive_idle_checks = try parseU32(envOr("AGDB_IDLE_CONFIRMATIONS", "3")),
            .inhibit_file = envOr("AGDB_SHUTDOWN_INHIBIT_FILE", "/run/agdb/shutdown.inhibit"),
            .access_log_path = envOr("AGDB_ACCESS_LOG_PATH", "/var/log/nginx/access.log"),
            .use_access_log = try parseBool(envOr("AGDB_USE_ACCESS_LOG", "0")),
            .dry_run = try parseBool(envOr("AGDB_SHUTDOWN_DRY_RUN", "1")),
            .drain_timeout_seconds = try parseU64(envOr("AGDB_DRAIN_TIMEOUT_SECONDS", "120")),
            .shutdown_command = envOr("AGDB_SHUTDOWN_COMMAND", "systemctl poweroff"),
            .drain_unit = envOr("AGDB_DRAIN_UNIT", "agdb-cloud.service"),
            .drain_command = envOr("AGDB_DRAIN_COMMAND", "systemctl stop agdb-cloud.service"),
        };
    }
};

fn envOr(name: []const u8, fallback: []const u8) []const u8 {
    const value = std.posix.getenv(name) orelse return fallback;
    if (value.len == 0) return fallback;
    return value;
}

fn parsePort(text: []const u8) ConfigError!u16 {
    return std.fmt.parseInt(u16, text, 10) catch return ConfigError.InvalidPort;
}

fn parseI64(text: []const u8) ConfigError!i64 {
    return std.fmt.parseInt(i64, text, 10) catch return ConfigError.InvalidInteger;
}

fn parseU64(text: []const u8) ConfigError!u64 {
    return std.fmt.parseInt(u64, text, 10) catch return ConfigError.InvalidInteger;
}

fn parseU32(text: []const u8) ConfigError!u32 {
    return std.fmt.parseInt(u32, text, 10) catch return ConfigError.InvalidInteger;
}

fn parseBool(text: []const u8) ConfigError!bool {
    if (std.ascii.eqlIgnoreCase(text, "1") or
        std.ascii.eqlIgnoreCase(text, "true") or
        std.ascii.eqlIgnoreCase(text, "yes") or
        std.ascii.eqlIgnoreCase(text, "on")) return true;
    if (std.ascii.eqlIgnoreCase(text, "0") or
        std.ascii.eqlIgnoreCase(text, "false") or
        std.ascii.eqlIgnoreCase(text, "no") or
        std.ascii.eqlIgnoreCase(text, "off")) return false;
    return ConfigError.InvalidBoolean;
}

pub const MAX_ACTIVITY_RESPONSE_BYTES: usize = 64 * 1024;

pub fn extractHttpBody(response: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, response, "HTTP/1.")) return error.NotHttpResponse;
    const status_end = std.mem.indexOf(u8, response, "\r\n") orelse return error.MalformedResponse;
    const status_line = response[0..status_end];
    var fields = std.mem.tokenizeScalar(u8, status_line, ' ');
    _ = fields.next() orelse return error.MalformedResponse;
    const code_text = fields.next() orelse return error.MalformedResponse;
    const code = std.fmt.parseInt(u16, code_text, 10) catch return error.MalformedResponse;
    if (code != 200) return error.ActivityEndpointStatus;

    const separator = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return error.MalformedResponse;
    const headers = response[status_end + 2 .. separator];
    const body = response[separator + 4 ..];

    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) return error.UnsupportedTransferEncoding;
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            const declared = std.fmt.parseInt(usize, value, 10) catch return error.MalformedResponse;
            if (declared > body.len) return error.TruncatedResponse;
            return body[0..declared];
        }
    }
    return body;
}

pub fn connectWithTimeout(allocator: std.mem.Allocator, host: []const u8, port: u16, timeout_ms: u32) !std.net.Stream {
    const list = try std.net.getAddressList(allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;

    var last_error: anyerror = error.ConnectionRefused;
    for (list.addrs) |address| {
        const sock_flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC;
        const fd = std.posix.socket(address.any.family, sock_flags, std.posix.IPPROTO.TCP) catch |err| {
            last_error = err;
            continue;
        };
        applyTimeout(fd, timeout_ms);
        std.posix.connect(fd, &address.any, address.getOsSockLen()) catch |err| {
            std.posix.close(fd);
            last_error = err;
            continue;
        };
        return std.net.Stream{ .handle = fd };
    }
    return last_error;
}

fn applyTimeout(fd: std.posix.socket_t, timeout_ms: u32) void {
    const seconds: isize = @intCast(timeout_ms / 1000);
    const micros: isize = @intCast((timeout_ms % 1000) * 1000);
    const tv = std.os.linux.timeval{ .sec = seconds, .usec = micros };
    const bytes = std.mem.asBytes(&tv);
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.RCVTIMEO, bytes.ptr, @intCast(bytes.len));
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.SNDTIMEO, bytes.ptr, @intCast(bytes.len));
}

pub const Activity = struct {
    last_request_ms: i64,
    idle_ms: i64,
    active_connections: u64,
    queued_connections: u64,
    in_flight_requests: u64,
    active_sandboxes: u64,
    pending_sandbox_requests: u64,

    pub fn isIdle(self: Activity, idle_seconds: i64) bool {
        if (self.active_connections != 0) return false;
        if (self.queued_connections != 0) return false;
        if (self.in_flight_requests != 0) return false;
        if (self.active_sandboxes != 0) return false;
        if (self.pending_sandbox_requests != 0) return false;
        return @divTrunc(self.idle_ms, 1000) >= idle_seconds;
    }
};

pub const Decision = enum {
    shutdown,
    busy,
    inhibited,
    unknown,
};

pub fn parseActivityJson(body: []const u8) !Activity {
    return Activity{
        .last_request_ms = try readJsonInt(body, "last_request_ms"),
        .idle_ms = try readJsonInt(body, "idle_ms"),
        .active_connections = @intCast(@max(0, try readJsonInt(body, "active_connections"))),
        .queued_connections = @intCast(@max(0, try readJsonInt(body, "queued_connections"))),
        .in_flight_requests = @intCast(@max(0, try readJsonInt(body, "in_flight_requests"))),
        .active_sandboxes = @intCast(@max(0, try readJsonInt(body, "active_sandboxes"))),
        .pending_sandbox_requests = @intCast(@max(0, try readJsonInt(body, "pending_sandbox_requests"))),
    };
}

fn readJsonInt(body: []const u8, field: []const u8) !i64 {
    var needle_buffer: [128]u8 = undefined;
    const needle = try std.fmt.bufPrint(&needle_buffer, "\"{s}\":", .{field});
    const start = std.mem.indexOf(u8, body, needle) orelse return error.FieldMissing;
    var cursor = start + needle.len;
    while (cursor < body.len and (body[cursor] == ' ' or body[cursor] == '\t')) cursor += 1;
    var end = cursor;
    if (end < body.len and (body[end] == '-' or body[end] == '+')) end += 1;
    while (end < body.len and body[end] >= '0' and body[end] <= '9') end += 1;
    if (end == cursor) return error.FieldNotNumeric;
    return std.fmt.parseInt(i64, body[cursor..end], 10) catch error.FieldNotNumeric;
}

pub const AccessLogWatcher = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    file: ?std.fs.File,
    inode: std.posix.ino_t,
    size: u64,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) AccessLogWatcher {
        return AccessLogWatcher{
            .allocator = allocator,
            .path = path,
            .file = null,
            .inode = 0,
            .size = 0,
        };
    }

    pub fn deinit(self: *AccessLogWatcher) void {
        if (self.file) |file| file.close();
        self.file = null;
    }

    pub fn lastAccessTimestamp(self: *AccessLogWatcher) !i64 {
        try self.ensureOpen();
        const file = self.file.?;
        const stat = try file.stat();
        if (stat.inode != self.inode or stat.size < self.size) {
            self.reopen() catch |err| return err;
            return self.lastAccessTimestampLocked();
        }
        self.size = stat.size;
        return self.lastAccessTimestampLocked();
    }

    fn lastAccessTimestampLocked(self: *AccessLogWatcher) !i64 {
        const file = self.file.?;
        const stat = try file.stat();
        if (stat.size == 0) return error.EmptyLog;

        const window: u64 = @min(stat.size, 8192);
        try file.seekTo(stat.size - window);
        const buffer = try self.allocator.alloc(u8, window);
        defer self.allocator.free(buffer);
        const read_len = try file.readAll(buffer);
        const data = std.mem.trimRight(u8, buffer[0..read_len], "\r\n");
        if (data.len == 0) return error.EmptyLog;

        var cursor = data.len;
        var scanned: usize = 0;
        while (cursor > 0 and scanned < 64) : (scanned += 1) {
            const line_start = if (std.mem.lastIndexOfScalar(u8, data[0..cursor], '\n')) |index| index + 1 else 0;
            const line = std.mem.trimRight(u8, data[line_start..cursor], "\r");
            if (parseAccessLogTimestamp(line)) |timestamp| return timestamp else |_| {}
            if (line_start == 0) break;
            cursor = line_start - 1;
        }
        return error.NoParsableLine;
    }

    fn ensureOpen(self: *AccessLogWatcher) !void {
        if (self.file != null) return;
        try self.reopen();
    }

    fn reopen(self: *AccessLogWatcher) !void {
        if (self.file) |file| file.close();
        self.file = null;
        const file = try std.fs.openFileAbsolute(self.path, .{});
        const stat = try file.stat();
        self.file = file;
        self.inode = stat.inode;
        self.size = stat.size;
    }
};

const MONTHS = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub fn parseAccessLogTimestamp(line: []const u8) !i64 {
    const open_index = std.mem.indexOfScalar(u8, line, '[') orelse return error.NoTimestamp;
    const close_offset = std.mem.indexOfScalar(u8, line[open_index..], ']') orelse return error.NoTimestamp;
    const stamp = line[open_index + 1 .. open_index + close_offset];
    if (stamp.len < 20) return error.ShortTimestamp;

    const day = std.fmt.parseInt(u32, stamp[0..2], 10) catch return error.BadDay;
    const month_text = stamp[3..6];
    const year = std.fmt.parseInt(u32, stamp[7..11], 10) catch return error.BadYear;
    const hour = std.fmt.parseInt(u32, stamp[12..14], 10) catch return error.BadHour;
    const minute = std.fmt.parseInt(u32, stamp[15..17], 10) catch return error.BadMinute;
    const second = std.fmt.parseInt(u32, stamp[18..20], 10) catch return error.BadSecond;

    var month: u32 = 0;
    for (MONTHS, 0..) |candidate, index| {
        if (std.mem.eql(u8, month_text, candidate)) {
            month = @intCast(index + 1);
            break;
        }
    }
    if (month == 0) return error.BadMonth;
    if (day == 0 or day > 31 or hour > 23 or minute > 59 or second > 60) return error.OutOfRange;

    var offset_seconds: i64 = 0;
    if (stamp.len >= 26) {
        const sign = stamp[21];
        if (sign == '+' or sign == '-') {
            const offset_hours = std.fmt.parseInt(i64, stamp[22..24], 10) catch 0;
            const offset_minutes = std.fmt.parseInt(i64, stamp[24..26], 10) catch 0;
            offset_seconds = offset_hours * 3600 + offset_minutes * 60;
            if (sign == '-') offset_seconds = -offset_seconds;
        }
    }

    const days = daysFromCivil(year, month, day);
    const local_epoch = days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
    return local_epoch - offset_seconds;
}

fn daysFromCivil(year_in: u32, month_in: u32, day_in: u32) i64 {
    var year: i64 = @intCast(year_in);
    const month: i64 = @intCast(month_in);
    const day: i64 = @intCast(day_in);
    year -= if (month <= 2) @as(i64, 1) else @as(i64, 0);
    const era = @divFloor(year, 400);
    const year_of_era = year - era * 400;
    const shifted_month = if (month > 2) month - 3 else month + 9;
    const day_of_year = @divTrunc(153 * shifted_month + 2, 5) + day - 1;
    const day_of_era = year_of_era * 365 + @divTrunc(year_of_era, 4) - @divTrunc(year_of_era, 100) + day_of_year;
    return era * 146097 + day_of_era - 719468;
}

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    config: Config,
    watcher: AccessLogWatcher,
    idle_streak: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .watcher = AccessLogWatcher.init(allocator, config.access_log_path),
            .idle_streak = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.watcher.deinit();
    }

    pub fn run(self: *Self) !void {
        std.log.info(
            "idle shutdown supervisor started: endpoint http://{s}:{d}{s}, idle limit {d}s, confirmations {d}, dry_run {}",
            .{
                self.config.activity_host,
                self.config.activity_port,
                self.config.activity_path,
                self.config.idle_seconds,
                self.config.consecutive_idle_checks,
                self.config.dry_run,
            },
        );

        while (true) {
            std.time.sleep(self.config.check_interval_seconds * std.time.ns_per_s);
            const decision = self.evaluate();
            switch (decision) {
                .shutdown => {
                    self.drainAndShutdown() catch |err| {
                        std.log.err("shutdown sequence failed: {s}", .{@errorName(err)});
                        self.idle_streak = 0;
                        continue;
                    };
                    if (!self.config.dry_run) return;
                },
                .busy, .inhibited, .unknown => {},
            }
        }
    }

    pub fn evaluate(self: *Self) Decision {
        if (self.isInhibited()) {
            self.idle_streak = 0;
            std.log.info("shutdown inhibited by {s}", .{self.config.inhibit_file});
            return .inhibited;
        }

        const activity = self.fetchActivity() catch |err| {
            self.idle_streak = 0;
            std.log.warn("activity endpoint unavailable: {s}", .{@errorName(err)});
            return .unknown;
        };

        if (!activity.isIdle(self.config.idle_seconds)) {
            self.idle_streak = 0;
            std.log.info(
                "server busy: idle_ms {d}, connections {d}, in_flight {d}, sandboxes {d}, pending {d}",
                .{
                    activity.idle_ms,
                    activity.active_connections,
                    activity.in_flight_requests,
                    activity.active_sandboxes,
                    activity.pending_sandbox_requests,
                },
            );
            return .busy;
        }

        if (self.config.use_access_log) {
            const now = std.time.timestamp();
            const last_access = self.watcher.lastAccessTimestamp() catch |err| {
                self.idle_streak = 0;
                std.log.warn("access log unreadable, deferring shutdown: {s}", .{@errorName(err)});
                return .unknown;
            };
            const log_idle = now - last_access;
            if (log_idle < self.config.idle_seconds) {
                self.idle_streak = 0;
                std.log.info("access log reports traffic {d}s ago", .{log_idle});
                return .busy;
            }
        }

        self.idle_streak += 1;
        std.log.info(
            "idle confirmation {d} of {d} (idle_ms {d})",
            .{ self.idle_streak, self.config.consecutive_idle_checks, activity.idle_ms },
        );
        if (self.idle_streak < self.config.consecutive_idle_checks) return .busy;
        return .shutdown;
    }

    fn isInhibited(self: *Self) bool {
        std.fs.accessAbsolute(self.config.inhibit_file, .{}) catch return false;
        return true;
    }

    fn fetchActivity(self: *Self) !Activity {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const stream = try connectWithTimeout(
            allocator,
            self.config.activity_host,
            self.config.activity_port,
            self.config.request_timeout_ms,
        );
        defer stream.close();

        const request = try std.fmt.allocPrint(
            allocator,
            "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nUser-Agent: agdb-autoshutdown\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
            .{ self.config.activity_path, self.config.activity_host, self.config.activity_port },
        );
        try stream.writeAll(request);

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        var chunk: [4096]u8 = undefined;
        while (response.items.len < MAX_ACTIVITY_RESPONSE_BYTES) {
            const read_len = stream.read(&chunk) catch |err| {
                if (err == error.WouldBlock) return error.ActivityTimeout;
                return err;
            };
            if (read_len == 0) break;
            try response.appendSlice(chunk[0..read_len]);
        }
        if (response.items.len >= MAX_ACTIVITY_RESPONSE_BYTES) return error.ActivityResponseTooLarge;

        const body = try extractHttpBody(response.items);
        return parseActivityJson(body);
    }

    fn drainAndShutdown(self: *Self) !void {
        std.log.info("idle threshold reached, starting drain of {s}", .{self.config.drain_unit});

        if (self.config.dry_run) {
            std.log.info("dry run enabled, skipping drain and poweroff", .{});
            self.idle_streak = 0;
            return;
        }

        try self.runShellWords(self.config.drain_command);

        const deadline = std.time.timestamp() + @as(i64, @intCast(self.config.drain_timeout_seconds));
        while (std.time.timestamp() < deadline) {
            const activity = self.fetchActivity() catch break;
            if (activity.in_flight_requests == 0 and activity.active_sandboxes == 0) break;
            std.time.sleep(std.time.ns_per_s);
        }

        std.log.info("executing shutdown command: {s}", .{self.config.shutdown_command});
        try self.runShellWords(self.config.shutdown_command);
    }

    fn runShellWords(self: *Self, command: []const u8) !void {
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();
        var parts = std.mem.tokenizeAny(u8, command, " \t");
        while (parts.next()) |part| try argv.append(part);
        if (argv.items.len == 0) return error.EmptyCommand;
        try self.runCommand(argv.items);
    }

    fn runCommand(self: *Self, argv: []const []const u8) !void {
        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    std.log.err("command {s} exited with code {d}", .{ argv[0], code });
                    return error.CommandFailed;
                }
            },
            else => {
                std.log.err("command {s} terminated abnormally", .{argv[0]});
                return error.CommandFailed;
            },
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = Config.fromEnvironment() catch |err| {
        std.log.err("configuration error: {s}", .{@errorName(err)});
        std.process.exit(2);
    };

    if (std.os.linux.geteuid() == 0) {
        std.log.warn("running as root is not required and not recommended for the idle shutdown supervisor", .{});
    }

    var supervisor = Supervisor.init(allocator, config);
    defer supervisor.deinit();

    try supervisor.run();
}

test "activity json parsing extracts every field" {
    const testing = std.testing;
    const body =
        "{\"last_request_ms\":1735689600000,\"idle_ms\":930000,\"active_connections\":0," ++
        "\"queued_connections\":0,\"in_flight_requests\":0,\"active_sandboxes\":0," ++
        "\"pending_sandbox_requests\":0,\"shed_connections\":4,\"worker_threads\":8}";
    const activity = try parseActivityJson(body);
    try testing.expectEqual(@as(i64, 1735689600000), activity.last_request_ms);
    try testing.expectEqual(@as(i64, 930000), activity.idle_ms);
    try testing.expectEqual(@as(u64, 0), activity.active_connections);
    try testing.expect(activity.isIdle(900));
}

test "activity with live work is never idle" {
    const testing = std.testing;
    const body =
        "{\"last_request_ms\":1,\"idle_ms\":99999999,\"active_connections\":0," ++
        "\"queued_connections\":0,\"in_flight_requests\":0,\"active_sandboxes\":2," ++
        "\"pending_sandbox_requests\":0}";
    const activity = try parseActivityJson(body);
    try testing.expect(!activity.isIdle(900));
}

test "activity below idle threshold is not idle" {
    const testing = std.testing;
    const body =
        "{\"last_request_ms\":1,\"idle_ms\":60000,\"active_connections\":0," ++
        "\"queued_connections\":0,\"in_flight_requests\":0,\"active_sandboxes\":0," ++
        "\"pending_sandbox_requests\":0}";
    const activity = try parseActivityJson(body);
    try testing.expect(!activity.isIdle(900));
}

test "missing activity field is an error" {
    const testing = std.testing;
    try testing.expectError(error.FieldMissing, parseActivityJson("{\"idle_ms\":1}"));
}

test "access log timestamp honours timezone offset" {
    const testing = std.testing;
    const line = "203.0.113.7 - - [05/Jun/2026:14:32:01 +0200] \"GET / HTTP/1.1\" 200 194607";
    const parsed = try parseAccessLogTimestamp(line);
    try testing.expectEqual(@as(i64, 1780662721), parsed);
}

test "access log timestamp rejects malformed lines" {
    const testing = std.testing;
    try testing.expectError(error.NoTimestamp, parseAccessLogTimestamp("no brackets here"));
    try testing.expectError(error.ShortTimestamp, parseAccessLogTimestamp("[05/Jun]"));
    try testing.expectError(error.BadMonth, parseAccessLogTimestamp("[05/Xxx/2026:14:32:01 +0000]"));
}

test "civil date conversion matches known epochs" {
    const testing = std.testing;
    try testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    try testing.expectEqual(@as(i64, 19723), daysFromCivil(2024, 1, 1));
    try testing.expectEqual(@as(i64, 11688), daysFromCivil(2002, 1, 1));
}

test "boolean and integer environment parsing" {
    const testing = std.testing;
    try testing.expect(try parseBool("yes"));
    try testing.expect(!try parseBool("off"));
    try testing.expectError(ConfigError.InvalidBoolean, parseBool("maybe"));
    try testing.expectEqual(@as(i64, -5), try parseI64("-5"));
    try testing.expectError(ConfigError.InvalidInteger, parseU64("x"));
}

test "access log watcher reads the newest parsable line" {
    const testing = std.testing;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(path);
    const log_path = try std.fs.path.join(testing.allocator, &[_][]const u8{ path, "access.log" });
    defer testing.allocator.free(log_path);

    {
        const file = try std.fs.createFileAbsolute(log_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll("203.0.113.1 - - [05/Jun/2026:14:00:00 +0000] \"GET /a HTTP/1.1\" 200 1\n");
        try file.writeAll("corrupted line without timestamp\n");
    }

    var watcher = AccessLogWatcher.init(testing.allocator, log_path);
    defer watcher.deinit();

    const first = try watcher.lastAccessTimestamp();
    try testing.expectEqual(@as(i64, 1780668000), first);

    {
        const file = try std.fs.createFileAbsolute(log_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll("203.0.113.2 - - [05/Jun/2026:15:00:00 +0000] \"GET /b HTTP/1.1\" 200 1\n");
    }

    const second = try watcher.lastAccessTimestamp();
    try testing.expectEqual(@as(i64, 1780671600), second);
}

test "http body extraction honours content length" {
    const testing = std.testing;
    const response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 13\r\nConnection: close\r\n\r\n" ++
        "{\"idle_ms\":1}trailing";
    const body = try extractHttpBody(response);
    try testing.expectEqualStrings("{\"idle_ms\":1}", body);
}

test "http body extraction rejects non success and malformed responses" {
    const testing = std.testing;
    try testing.expectError(error.ActivityEndpointStatus, extractHttpBody("HTTP/1.1 503 Busy\r\nContent-Length: 0\r\n\r\n"));
    try testing.expectError(error.NotHttpResponse, extractHttpBody("garbage"));
    try testing.expectError(error.MalformedResponse, extractHttpBody("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n"));
    try testing.expectError(error.TruncatedResponse, extractHttpBody("HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\nshort"));
    try testing.expectError(error.UnsupportedTransferEncoding, extractHttpBody("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\na\r\n0\r\n\r\n"));
}

test "activity fetch over a real socket enforces the response contract" {
    const testing = std.testing;
    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();
    const bound_port = server.listen_address.getPort();

    const Responder = struct {
        fn serve(listener: *std.net.Server) void {
            const conn = listener.accept() catch return;
            defer conn.stream.close();
            var scratch: [1024]u8 = undefined;
            _ = conn.stream.read(&scratch) catch {};
            const payload =
                "{\"last_request_ms\":10,\"idle_ms\":1000000,\"active_connections\":0," ++
                "\"queued_connections\":0,\"in_flight_requests\":0,\"active_sandboxes\":0," ++
                "\"pending_sandbox_requests\":0,\"shed_connections\":0,\"worker_threads\":4}";
            var head: [256]u8 = undefined;
            const header = std.fmt.bufPrint(
                &head,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
                .{payload.len},
            ) catch return;
            conn.stream.writeAll(header) catch return;
            conn.stream.writeAll(payload) catch return;
        }
    };

    const thread = try std.Thread.spawn(.{}, Responder.serve, .{&server});
    defer thread.join();

    var config = Config{
        .activity_host = "127.0.0.1",
        .activity_port = bound_port,
        .activity_path = "/v1/activity",
        .idle_seconds = 900,
        .check_interval_seconds = 60,
        .request_timeout_ms = 2000,
        .consecutive_idle_checks = 1,
        .inhibit_file = "/nonexistent/agdb-inhibit",
        .access_log_path = "/nonexistent/access.log",
        .use_access_log = false,
        .dry_run = true,
        .drain_timeout_seconds = 5,
        .shutdown_command = "true",
        .drain_unit = "agdb-cloud.service",
        .drain_command = "true",
    };

    var supervisor = Supervisor.init(testing.allocator, config);
    defer supervisor.deinit();

    const activity = try supervisor.fetchActivity();
    try testing.expectEqual(@as(u64, 0), activity.active_connections);
    try testing.expect(activity.isIdle(900));

    config.activity_port = bound_port;
}

test "connect with timeout fails fast on a closed port" {
    const testing = std.testing;
    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    var probe = try address.listen(.{ .reuse_address = true });
    const closed_port = probe.listen_address.getPort();
    probe.deinit();

    const result = connectWithTimeout(testing.allocator, "127.0.0.1", closed_port, 500);
    try testing.expectError(error.ConnectionRefused, result);
}
