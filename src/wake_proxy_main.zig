const std = @import("std");
const agdb = @import("agdb");
const http_parser = agdb.cloud.http_parser;

const WAITING_PAGE =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head><meta charset="UTF-8">
    \\<meta http-equiv="refresh" content="8">
    \\<title>Starting</title>
    \\<style>
    \\body{font-family:system-ui,sans-serif;display:flex;align-items:center;
    \\     justify-content:center;min-height:100vh;margin:0;background:#0f172a;color:#e2e8f0}
    \\.card{text-align:center;padding:3rem;max-width:420px}
    \\.spinner{width:48px;height:48px;border:4px solid #334155;border-top-color:#60a5fa;
    \\         border-radius:50%;animation:spin 1s linear infinite;margin:0 auto 2rem}
    \\@keyframes spin{to{transform:rotate(360deg)}}
    \\h1{font-size:1.5rem;margin:0 0 .5rem}p{color:#94a3b8;margin:0 0 1.5rem}
    \\small{color:#64748b}
    \\</style></head>
    \\<body><div class="card">
    \\<div class="spinner"></div>
    \\<h1>Backend is starting</h1>
    \\<p>The backend instance is being powered on. This usually takes 30 to 60 seconds.</p>
    \\<small>This page refreshes automatically.</small>
    \\</div></body></html>
;

pub const ConfigError = error{
    MissingTargetHost,
    MissingOvhEndpoint,
    MissingOvhProjectId,
    MissingOvhInstanceId,
    MissingOvhApplicationKey,
    MissingOvhApplicationSecret,
    MissingOvhConsumerKey,
    MissingExecCommand,
    InvalidProvider,
    InvalidPort,
    InvalidInteger,
};

pub const ProviderKind = enum {
    none,
    ovh,
    exec,

    pub fn fromSlice(text: []const u8) ?ProviderKind {
        if (std.ascii.eqlIgnoreCase(text, "none")) return .none;
        if (std.ascii.eqlIgnoreCase(text, "ovh")) return .ovh;
        if (std.ascii.eqlIgnoreCase(text, "exec")) return .exec;
        return null;
    }
};

pub const OvhConfig = struct {
    endpoint: []const u8,
    project_id: []const u8,
    instance_id: []const u8,
    application_key: []const u8,
    application_secret: []const u8,
    consumer_key: []const u8,
};

pub const Config = struct {
    listen_address: []const u8,
    listen_port: u16,
    target_host: []const u8,
    target_port: u16,
    health_path: []const u8,
    provider: ProviderKind,
    ovh: ?OvhConfig,
    exec_command: ?[]const u8,
    worker_threads: usize,
    queue_capacity: usize,
    connect_timeout_ms: u32,
    io_timeout_ms: u32,
    wake_poll_interval_ms: u64,
    wake_poll_attempts: u32,
    upstream_body_limit: usize,
    request_header_limit: usize,

    pub fn fromEnvironment() (ConfigError || error{OutOfMemory})!Config {
        const provider_text = envOr("AGDB_CLOUD_PROVIDER", "none");
        const provider = ProviderKind.fromSlice(provider_text) orelse return ConfigError.InvalidProvider;

        const target_host = std.posix.getenv("AGDB_TARGET_HOST") orelse return ConfigError.MissingTargetHost;
        if (target_host.len == 0) return ConfigError.MissingTargetHost;

        var ovh: ?OvhConfig = null;
        if (provider == .ovh) {
            ovh = OvhConfig{
                .endpoint = std.posix.getenv("AGDB_OVH_ENDPOINT") orelse return ConfigError.MissingOvhEndpoint,
                .project_id = std.posix.getenv("AGDB_OVH_PROJECT_ID") orelse return ConfigError.MissingOvhProjectId,
                .instance_id = std.posix.getenv("AGDB_OVH_INSTANCE_ID") orelse return ConfigError.MissingOvhInstanceId,
                .application_key = std.posix.getenv("OVH_APP_KEY") orelse return ConfigError.MissingOvhApplicationKey,
                .application_secret = std.posix.getenv("OVH_APP_SECRET") orelse return ConfigError.MissingOvhApplicationSecret,
                .consumer_key = std.posix.getenv("OVH_CONSUMER_KEY") orelse return ConfigError.MissingOvhConsumerKey,
            };
        }

        var exec_command: ?[]const u8 = null;
        if (provider == .exec) {
            const command = std.posix.getenv("AGDB_WAKE_EXEC_COMMAND") orelse return ConfigError.MissingExecCommand;
            if (command.len == 0) return ConfigError.MissingExecCommand;
            exec_command = command;
        }

        return Config{
            .listen_address = envOr("AGDB_WAKE_LISTEN_ADDR", "0.0.0.0"),
            .listen_port = try parsePort(envOr("AGDB_WAKE_LISTEN_PORT", envOr("PORT", "5000"))),
            .target_host = target_host,
            .target_port = try parsePort(envOr("AGDB_TARGET_PORT", "80")),
            .health_path = envOr("AGDB_WAKE_HEALTH_PATH", "/v1/health"),
            .provider = provider,
            .ovh = ovh,
            .exec_command = exec_command,
            .worker_threads = try parseUsize(envOr("AGDB_WAKE_WORKER_THREADS", "8")),
            .queue_capacity = try parseUsize(envOr("AGDB_WAKE_QUEUE_CAPACITY", "256")),
            .connect_timeout_ms = try parseU32(envOr("AGDB_WAKE_CONNECT_TIMEOUT_MS", "3000")),
            .io_timeout_ms = try parseU32(envOr("AGDB_WAKE_IO_TIMEOUT_MS", "15000")),
            .wake_poll_interval_ms = try parseU64(envOr("AGDB_WAKE_POLL_INTERVAL_MS", "5000")),
            .wake_poll_attempts = try parseU32(envOr("AGDB_WAKE_POLL_ATTEMPTS", "60")),
            .upstream_body_limit = try parseUsize(envOr("AGDB_WAKE_UPSTREAM_BODY_LIMIT", "67108864")),
            .request_header_limit = try parseUsize(envOr("AGDB_WAKE_REQUEST_HEADER_LIMIT", "65536")),
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

fn parseUsize(text: []const u8) ConfigError!usize {
    return std.fmt.parseInt(usize, text, 10) catch return ConfigError.InvalidInteger;
}

fn parseU32(text: []const u8) ConfigError!u32 {
    return std.fmt.parseInt(u32, text, 10) catch return ConfigError.InvalidInteger;
}

fn parseU64(text: []const u8) ConfigError!u64 {
    return std.fmt.parseInt(u64, text, 10) catch return ConfigError.InvalidInteger;
}

pub const ConnectionQueue = struct {
    allocator: std.mem.Allocator,
    items: []std.net.Server.Connection,
    head: usize,
    tail: usize,
    len: usize,
    mutex: std.Thread.Mutex,
    not_empty: std.Thread.Condition,
    not_full: std.Thread.Condition,
    closed: bool,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ConnectionQueue {
        const effective = if (capacity == 0) 1 else capacity;
        return ConnectionQueue{
            .allocator = allocator,
            .items = try allocator.alloc(std.net.Server.Connection, effective),
            .head = 0,
            .tail = 0,
            .len = 0,
            .mutex = .{},
            .not_empty = .{},
            .not_full = .{},
            .closed = false,
        };
    }

    pub fn deinit(self: *ConnectionQueue) void {
        self.allocator.free(self.items);
    }

    pub fn tryPush(self: *ConnectionQueue, conn: std.net.Server.Connection) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.closed) return false;
        if (self.len == self.items.len) return false;
        self.items[self.tail] = conn;
        self.tail = (self.tail + 1) % self.items.len;
        self.len += 1;
        self.not_empty.signal();
        return true;
    }

    pub fn pop(self: *ConnectionQueue) ?std.net.Server.Connection {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.len == 0 and !self.closed) {
            self.not_empty.wait(&self.mutex);
        }
        if (self.len == 0) return null;
        const conn = self.items[self.head];
        self.head = (self.head + 1) % self.items.len;
        self.len -= 1;
        self.not_full.signal();
        return conn;
    }

    pub fn close(self: *ConnectionQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        self.not_empty.broadcast();
        self.not_full.broadcast();
    }

    pub fn count(self: *ConnectionQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.len;
    }
};

pub const Proxy = struct {
    allocator: std.mem.Allocator,
    config: Config,
    queue: ConnectionQueue,
    workers: []std.Thread,
    waking: std.atomic.Value(bool),
    running: std.atomic.Value(bool),
    upstream_up: std.atomic.Value(bool),
    last_probe_ms: std.atomic.Value(i64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const worker_count = if (config.worker_threads == 0) 1 else config.worker_threads;

        self.* = Self{
            .allocator = allocator,
            .config = config,
            .queue = try ConnectionQueue.init(allocator, config.queue_capacity),
            .workers = try allocator.alloc(std.Thread, worker_count),
            .waking = std.atomic.Value(bool).init(false),
            .running = std.atomic.Value(bool).init(true),
            .upstream_up = std.atomic.Value(bool).init(false),
            .last_probe_ms = std.atomic.Value(i64).init(0),
        };
        errdefer {
            self.queue.deinit();
            allocator.free(self.workers);
        }

        var started: usize = 0;
        errdefer {
            self.running.store(false, .release);
            self.queue.close();
            var i: usize = 0;
            while (i < started) : (i += 1) self.workers[i].join();
        }
        while (started < worker_count) : (started += 1) {
            self.workers[started] = try std.Thread.spawn(.{}, workerMain, .{self});
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.running.store(false, .release);
        self.queue.close();
        for (self.workers) |worker| worker.join();
        self.allocator.free(self.workers);
        self.queue.deinit();
        self.allocator.destroy(self);
    }

    pub fn serve(self: *Self) !void {
        const address = try std.net.Address.parseIp(self.config.listen_address, self.config.listen_port);
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();

        std.log.info("wake proxy listening on {s}:{d}, upstream {s}:{d}, provider {s}", .{
            self.config.listen_address,
            self.config.listen_port,
            self.config.target_host,
            self.config.target_port,
            @tagName(self.config.provider),
        });

        while (self.running.load(.acquire)) {
            const conn = server.accept() catch |err| {
                std.log.err("accept failed: {s}", .{@errorName(err)});
                continue;
            };
            if (!self.queue.tryPush(conn)) {
                sendStatus(conn.stream, 503, "text/plain; charset=utf-8", "proxy queue is full");
                conn.stream.close();
            }
        }
    }

    fn workerMain(self: *Self) void {
        while (true) {
            const conn = self.queue.pop() orelse break;
            self.handleConnection(conn);
        }
    }

    fn handleConnection(self: *Self, conn: std.net.Server.Connection) void {
        defer conn.stream.close();

        setSocketTimeout(conn.stream.handle, self.config.io_timeout_ms);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var parser = http_parser.Parser.init(allocator, .{
            .max_header_bytes = self.config.request_header_limit,
            .max_body_bytes = self.config.upstream_body_limit,
        });
        defer parser.deinit();

        var buffer: [16 * 1024]u8 = undefined;
        while (!parser.isComplete()) {
            const read_len = conn.stream.read(&buffer) catch |err| {
                std.log.debug("connection read failed: {s}", .{@errorName(err)});
                return;
            };
            if (read_len == 0) return;
            var offset: usize = 0;
            while (offset < read_len) {
                const result = parser.feed(buffer[offset..read_len]) catch |err| {
                    const status = if (@as(?http_parser.ParseError, castParseError(err))) |perr|
                        http_parser.statusForError(perr)
                    else
                        500;
                    sendStatus(conn.stream, status, "text/plain; charset=utf-8", http_parser.reasonPhrase(status));
                    return;
                };
                offset += result.consumed;
                if (result.expect_continue) {
                    _ = conn.stream.writeAll("HTTP/1.1 100 Continue\r\n\r\n") catch return;
                }
                if (result.complete) break;
                if (result.consumed == 0) break;
            }
        }

        if (!self.isUpstreamReachable()) {
            self.triggerWake();
            sendWaitingPage(conn.stream);
            return;
        }

        self.proxyRequest(allocator, &parser.request, conn.stream);
    }

    fn proxyRequest(self: *Self, allocator: std.mem.Allocator, request: *const http_parser.Request, stream: std.net.Stream) void {
        const url = std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{
            self.config.target_host,
            self.config.target_port,
            request.target,
        }) catch {
            sendStatus(stream, 500, "text/plain; charset=utf-8", "proxy allocation failure");
            return;
        };

        const uri = std.Uri.parse(url) catch {
            sendStatus(stream, 400, "text/plain; charset=utf-8", "invalid request target");
            return;
        };

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var extra = std.ArrayList(std.http.Header).init(allocator);
        defer extra.deinit();

        for (request.headers.items) |header| {
            if (isHopByHop(header.name)) continue;
            extra.append(.{ .name = header.name, .value = header.value }) catch {
                sendStatus(stream, 500, "text/plain; charset=utf-8", "proxy allocation failure");
                return;
            };
        }

        const header_buffer = allocator.alloc(u8, self.config.request_header_limit) catch {
            sendStatus(stream, 500, "text/plain; charset=utf-8", "proxy allocation failure");
            return;
        };

        var upstream = client.open(toStdMethod(request.method), uri, .{
            .server_header_buffer = header_buffer,
            .extra_headers = extra.items,
        }) catch |err| {
            std.log.warn("upstream open failed: {s}", .{@errorName(err)});
            sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
            return;
        };
        defer upstream.deinit();

        if (request.body.items.len > 0) {
            upstream.transfer_encoding = .{ .content_length = request.body.items.len };
        }

        upstream.send() catch |err| {
            std.log.warn("upstream send failed: {s}", .{@errorName(err)});
            sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
            return;
        };

        if (request.body.items.len > 0) {
            upstream.writeAll(request.body.items) catch |err| {
                std.log.warn("upstream body write failed: {s}", .{@errorName(err)});
                sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
                return;
            };
        }

        upstream.finish() catch |err| {
            std.log.warn("upstream finish failed: {s}", .{@errorName(err)});
            sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
            return;
        };

        upstream.wait() catch |err| {
            std.log.warn("upstream wait failed: {s}", .{@errorName(err)});
            sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
            return;
        };

        const body = upstream.reader().readAllAlloc(allocator, self.config.upstream_body_limit) catch |err| {
            std.log.warn("upstream body read failed: {s}", .{@errorName(err)});
            sendStatus(stream, 502, "text/plain; charset=utf-8", "bad gateway");
            return;
        };

        const status_code: u16 = @intFromEnum(upstream.response.status);

        var head = std.ArrayList(u8).init(allocator);
        defer head.deinit();
        const writer = head.writer();
        writer.print("HTTP/1.1 {d} {s}\r\n", .{ status_code, http_parser.reasonPhrase(status_code) }) catch return;

        var it = upstream.response.iterateHeaders();
        while (it.next()) |header| {
            if (isHopByHop(header.name)) continue;
            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) continue;
            writer.print("{s}: {s}\r\n", .{ header.name, header.value }) catch return;
        }
        writer.print("Content-Length: {d}\r\nConnection: close\r\n\r\n", .{body.len}) catch return;

        stream.writeAll(head.items) catch return;
        stream.writeAll(body) catch return;
    }

    fn isUpstreamReachable(self: *Self) bool {
        const now = std.time.milliTimestamp();
        const last = self.last_probe_ms.load(.acquire);
        if (self.upstream_up.load(.acquire) and now - last < 2000) return true;

        const reachable = probeTcp(self.allocator, self.config.target_host, self.config.target_port, self.config.connect_timeout_ms);
        self.upstream_up.store(reachable, .release);
        self.last_probe_ms.store(now, .release);
        return reachable;
    }

    fn triggerWake(self: *Self) void {
        if (self.config.provider == .none) return;
        if (self.waking.swap(true, .acq_rel)) return;
        const thread = std.Thread.spawn(.{}, wakeMain, .{self}) catch |err| {
            std.log.err("failed to spawn wake thread: {s}", .{@errorName(err)});
            self.waking.store(false, .release);
            return;
        };
        thread.detach();
    }

    fn wakeMain(self: *Self) void {
        defer self.waking.store(false, .release);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        startInstance(allocator, self.config) catch |err| {
            std.log.err("instance start failed: {s}", .{@errorName(err)});
            return;
        };

        var attempt: u32 = 0;
        while (attempt < self.config.wake_poll_attempts) : (attempt += 1) {
            std.time.sleep(self.config.wake_poll_interval_ms * std.time.ns_per_ms);
            if (probeTcp(self.allocator, self.config.target_host, self.config.target_port, self.config.connect_timeout_ms)) {
                self.upstream_up.store(true, .release);
                self.last_probe_ms.store(std.time.milliTimestamp(), .release);
                std.log.info("upstream became reachable after {d} probes", .{attempt + 1});
                return;
            }
        }
        std.log.err("upstream did not become reachable within {d} probes", .{self.config.wake_poll_attempts});
    }
};

fn castParseError(err: anyerror) ?http_parser.ParseError {
    inline for (@typeInfo(http_parser.ParseError).error_set.?) |candidate| {
        const value = @field(http_parser.ParseError, candidate.name);
        if (err == value) return value;
    }
    return null;
}

fn toStdMethod(method: http_parser.Method) std.http.Method {
    return switch (method) {
        .get => .GET,
        .head => .HEAD,
        .post => .POST,
        .put => .PUT,
        .patch => .PATCH,
        .delete => .DELETE,
        .options => .OPTIONS,
        .trace => .TRACE,
        .connect => .CONNECT,
    };
}

fn isHopByHop(name: []const u8) bool {
    const hop = [_][]const u8{
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "host",
    };
    for (hop) |candidate| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}

fn setSocketTimeout(handle: std.posix.socket_t, timeout_ms: u32) void {
    const timeout = std.posix.timeval{
        .sec = @intCast(timeout_ms / 1000),
        .usec = @intCast((timeout_ms % 1000) * 1000),
    };
    std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeout)) catch |err| {
        std.log.debug("failed to set receive timeout: {s}", .{@errorName(err)});
    };
    std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&timeout)) catch |err| {
        std.log.debug("failed to set send timeout: {s}", .{@errorName(err)});
    };
}

pub fn probeTcp(allocator: std.mem.Allocator, host: []const u8, port: u16, timeout_ms: u32) bool {
    const list = std.net.getAddressList(allocator, host, port) catch |err| {
        std.log.debug("address resolution failed for {s}: {s}", .{ host, @errorName(err) });
        return false;
    };
    defer list.deinit();

    for (list.addrs) |addr| {
        if (probeAddress(addr, timeout_ms)) return true;
    }
    return false;
}

fn probeAddress(addr: std.net.Address, timeout_ms: u32) bool {
    const sock = std.posix.socket(
        addr.any.family,
        std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK | std.posix.SOCK.CLOEXEC,
        std.posix.IPPROTO.TCP,
    ) catch return false;
    defer std.posix.close(sock);

    std.posix.connect(sock, &addr.any, addr.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock => {},
        else => return false,
    };

    var pfd = [1]std.posix.pollfd{.{
        .fd = sock,
        .events = std.posix.POLL.OUT,
        .revents = 0,
    }};
    const ready = std.posix.poll(&pfd, @intCast(timeout_ms)) catch return false;
    if (ready == 0) return false;
    if (pfd[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL) != 0) return false;
    if (pfd[0].revents & std.posix.POLL.OUT == 0) return false;

    var err_code: i32 = 0;
    var err_len: std.posix.socklen_t = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.ERROR, @ptrCast(&err_code), &err_len);
    if (std.os.linux.E.init(rc) != .SUCCESS) return false;
    return err_code == 0;
}

fn startInstance(allocator: std.mem.Allocator, config: Config) !void {
    switch (config.provider) {
        .none => return,
        .exec => try runExecHook(allocator, config.exec_command.?),
        .ovh => try ovhStartInstance(allocator, config.ovh.?),
    }
}

fn runExecHook(allocator: std.mem.Allocator, command: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", command }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.ExecHookFailed;
        },
        else => return error.ExecHookFailed,
    }
}

fn ovhStartInstance(allocator: std.mem.Allocator, ovh: OvhConfig) !void {
    const path = try std.fmt.allocPrint(allocator, "/cloud/project/{s}/instance/{s}/start", .{
        ovh.project_id,
        ovh.instance_id,
    });
    defer allocator.free(path);

    var attempt: u32 = 0;
    var backoff_ms: u64 = 500;
    while (attempt < 5) : (attempt += 1) {
        const status = ovhPost(allocator, ovh, path) catch |err| {
            std.log.warn("ovh start attempt {d} failed: {s}", .{ attempt + 1, @errorName(err) });
            std.time.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms *= 2;
            continue;
        };
        if (status >= 200 and status < 300) {
            std.log.info("ovh start accepted with status {d}", .{status});
            return;
        }
        std.log.warn("ovh start attempt {d} returned status {d}", .{ attempt + 1, status });
        if (status < 500 and status != 429) return error.OvhRequestRejected;
        std.time.sleep(backoff_ms * std.time.ns_per_ms);
        backoff_ms *= 2;
    }
    return error.OvhStartExhausted;
}

fn ovhPost(allocator: std.mem.Allocator, ovh: OvhConfig, path: []const u8) !u16 {
    const base = std.mem.trimRight(u8, ovh.endpoint, "/");
    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path });
    defer allocator.free(url);

    const timestamp = try ovhTimestamp(allocator, base);
    const timestamp_text = try std.fmt.allocPrint(allocator, "{d}", .{timestamp});
    defer allocator.free(timestamp_text);

    const to_sign = try std.fmt.allocPrint(allocator, "{s}+{s}+POST+{s}++{s}", .{
        ovh.application_secret,
        ovh.consumer_key,
        url,
        timestamp_text,
    });
    defer allocator.free(to_sign);

    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    std.crypto.hash.Sha1.hash(to_sign, &digest, .{});
    const signature = try std.fmt.allocPrint(allocator, "$1${s}", .{std.fmt.fmtSliceHexLower(&digest)});
    defer allocator.free(signature);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    try client.initDefaultProxies(allocator);

    const uri = try std.Uri.parse(url);
    var header_buffer: [16 * 1024]u8 = undefined;
    var request = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buffer,
        .extra_headers = &.{
            .{ .name = "X-Ovh-Application", .value = ovh.application_key },
            .{ .name = "X-Ovh-Consumer", .value = ovh.consumer_key },
            .{ .name = "X-Ovh-Timestamp", .value = timestamp_text },
            .{ .name = "X-Ovh-Signature", .value = signature },
            .{ .name = "Content-Type", .value = "application/json" },
        },
    });
    defer request.deinit();

    request.transfer_encoding = .{ .content_length = 0 };
    try request.send();
    try request.finish();
    try request.wait();

    const status: u16 = @intFromEnum(request.response.status);
    if (status >= 400) {
        const body = request.reader().readAllAlloc(allocator, 64 * 1024) catch &[_]u8{};
        if (body.len > 0) {
            defer allocator.free(body);
            std.log.warn("ovh error body: {s}", .{body});
        }
    }
    return status;
}

fn ovhTimestamp(allocator: std.mem.Allocator, base: []const u8) !i64 {
    const url = try std.fmt.allocPrint(allocator, "{s}/auth/time", .{base});
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 256,
    }) catch |err| {
        std.log.warn("ovh time endpoint failed, using local clock: {s}", .{@errorName(err)});
        return std.time.timestamp();
    };

    if (@intFromEnum(result.status) != 200) {
        std.log.warn("ovh time endpoint returned {d}, using local clock", .{@intFromEnum(result.status)});
        return std.time.timestamp();
    }

    const trimmed = std.mem.trim(u8, body.items, " \t\r\n\"");
    return std.fmt.parseInt(i64, trimmed, 10) catch {
        std.log.warn("ovh time endpoint returned unparsable value, using local clock", .{});
        return std.time.timestamp();
    };
}

fn sendWaitingPage(stream: std.net.Stream) void {
    sendStatus(stream, 503, "text/html; charset=utf-8", WAITING_PAGE);
}

fn sendStatus(stream: std.net.Stream, status: u16, content_type: []const u8, body: []const u8) void {
    var header_buffer: [512]u8 = undefined;
    const head = std.fmt.bufPrint(
        &header_buffer,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nRetry-After: 10\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n",
        .{ status, http_parser.reasonPhrase(status), content_type, body.len },
    ) catch return;
    stream.writeAll(head) catch return;
    stream.writeAll(body) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = Config.fromEnvironment() catch |err| {
        std.log.err("configuration error: {s}", .{@errorName(err)});
        std.process.exit(2);
    };

    const proxy = try Proxy.init(allocator, config);
    defer proxy.deinit();

    try proxy.serve();
}

test "connection queue rejects when full" {
    const testing = std.testing;
    var queue = try ConnectionQueue.init(testing.allocator, 1);
    defer queue.deinit();

    const dummy = std.net.Server.Connection{
        .stream = .{ .handle = -1 },
        .address = try std.net.Address.parseIp("127.0.0.1", 1),
    };
    try testing.expect(queue.tryPush(dummy));
    try testing.expect(!queue.tryPush(dummy));
    try testing.expectEqual(@as(usize, 1), queue.count());
    const popped = queue.pop();
    try testing.expect(popped != null);
    try testing.expectEqual(@as(usize, 0), queue.count());
    queue.close();
    try testing.expect(queue.pop() == null);
}

test "hop by hop headers are filtered" {
    const testing = std.testing;
    try testing.expect(isHopByHop("Connection"));
    try testing.expect(isHopByHop("transfer-encoding"));
    try testing.expect(isHopByHop("Host"));
    try testing.expect(!isHopByHop("Content-Type"));
    try testing.expect(!isHopByHop("Authorization"));
}

test "provider parsing" {
    const testing = std.testing;
    try testing.expectEqual(ProviderKind.none, ProviderKind.fromSlice("none").?);
    try testing.expectEqual(ProviderKind.ovh, ProviderKind.fromSlice("OVH").?);
    try testing.expectEqual(ProviderKind.exec, ProviderKind.fromSlice("exec").?);
    try testing.expect(ProviderKind.fromSlice("gcp") == null);
}

test "method mapping covers all parser methods" {
    const testing = std.testing;
    try testing.expectEqual(std.http.Method.GET, toStdMethod(.get));
    try testing.expectEqual(std.http.Method.DELETE, toStdMethod(.delete));
    try testing.expectEqual(std.http.Method.CONNECT, toStdMethod(.connect));
}

test "no production endpoint identifiers are embedded" {
    const testing = std.testing;
    const source = @embedFile("wake_proxy_main.zig");
    const ip_needle = "91" ++ "." ++ "134" ++ "." ++ "72" ++ "." ++ "253";
    const project_needle = "5ec8" ++ "a5b1" ++ "d206" ++ "437a";
    const instance_needle = "a99a" ++ "85a1" ++ "-07d0";
    try testing.expect(std.mem.indexOf(u8, source, ip_needle) == null);
    try testing.expect(std.mem.indexOf(u8, source, project_needle) == null);
    try testing.expect(std.mem.indexOf(u8, source, instance_needle) == null);
}
