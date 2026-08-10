const std = @import("std");
const registration = @import("registration.zig");
const registry = @import("registry.zig");
const router = @import("router.zig");
const process_table = @import("process_table.zig");
const sandbox = @import("sandbox.zig");
const apikey = @import("apikey.zig");
const metrics = @import("metrics.zig");
const json = @import("../json.zig");

const FRONTEND_HTML = @embedFile("index.html");
const DOCS_HTML = @embedFile("docs.html");
const MAX_CONNECTIONS: u32 = 1024;
const MAX_BODY_SIZE: usize = 16 * 1024 * 1024;

pub const CloudServer = struct {
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
    pt: *process_table.ProcessTable,
    reg_handler: registration.RegistrationHandler,
    rtr: router.Router,
    metric_store: metrics.MetricsStore,
    port: u16,
    active_conn: std.atomic.Value(u32),
    sandbox_mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, reg_ptr: *registry.Registry, pt_ptr: *process_table.ProcessTable, port: u16) CloudServer {
        return .{
            .allocator = allocator,
            .reg = reg_ptr,
            .pt = pt_ptr,
            .reg_handler = registration.RegistrationHandler.init(allocator, reg_ptr, pt_ptr),
            .rtr = router.Router.init(allocator, reg_ptr, pt_ptr),
            .metric_store = metrics.MetricsStore.init(allocator, reg_ptr),
            .port = port,
            .active_conn = std.atomic.Value(u32).init(0),
            .sandbox_mutex = .{},
        };
    }

    pub fn deinit(self: *CloudServer) void {
        self.metric_store.deinit();
    }

    pub fn run(self: *CloudServer) !void {
        const addr = try std.net.Address.parseIp4("0.0.0.0", self.port);
        var server = try addr.listen(.{ .reuse_address = true });
        defer server.deinit();

        std.log.info("agdb cloud server listening on port {d}", .{self.port});

        while (true) {
            const conn = server.accept() catch |err| {
                std.log.err("accept error: {}", .{err});
                continue;
            };
            if (self.active_conn.load(.acquire) >= MAX_CONNECTIONS) {
                conn.stream.close();
                continue;
            }
            _ = self.active_conn.fetchAdd(1, .acq_rel);
            const ctx = self.allocator.create(ConnCtx) catch {
                _ = self.active_conn.fetchSub(1, .acq_rel);
                conn.stream.close();
                continue;
            };
            ctx.* = .{ .server = self, .conn = conn };
            const thread = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
                std.log.err("connection thread error: {}", .{err});
                conn.stream.close();
                _ = self.active_conn.fetchSub(1, .acq_rel);
                self.allocator.destroy(ctx);
                continue;
            };
            thread.detach();
        }
    }
};

const ConnCtx = struct {
    server: *CloudServer,
    conn: std.net.Server.Connection,
    request_started_ns: i128 = 0,
    request_method: []const u8 = "",
    request_path: []const u8 = "",
    request_tenant_id: ?u64 = null,
    response_status: u16 = 500,
    should_record: bool = false,
};

fn handleConn(ctx: *ConnCtx) void {
    defer ctx.conn.stream.close();
    defer ctx.server.allocator.destroy(ctx);
    defer _ = ctx.server.active_conn.fetchSub(1, .acq_rel);
    setSocketTimeouts(ctx.conn.stream.handle);
    handleConnInner(ctx) catch |err| {
        std.log.debug("connection error: {}", .{err});
    };
}

fn setSocketTimeouts(fd: i32) void {
    const tv = std.os.linux.timeval{ .sec = 30, .usec = 0 };
    const bytes = std.mem.asBytes(&tv);
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.RCVTIMEO, bytes.ptr, @intCast(bytes.len));
    _ = std.os.linux.setsockopt(fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.SNDTIMEO, bytes.ptr, @intCast(bytes.len));
}

fn handleConnInner(ctx: *ConnCtx) !void {
    const allocator = ctx.server.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var buffer: [65536]u8 = undefined;
    var total: usize = 0;
    while (true) {
        if (total == buffer.len) {
            try sendError(ctx, 431, "request headers too large");
            return;
        }
        const received = ctx.conn.stream.read(buffer[total..]) catch return;
        if (received == 0) return;
        total += received;
        if (std.mem.indexOf(u8, buffer[0..total], "\r\n\r\n") != null) break;
    }

    const raw = buffer[0..total];
    const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return;
    const header_section = raw[0..header_end];
    var lines = std.mem.splitSequence(u8, header_section, "\r\n");
    const request_line = lines.next() orelse return;
    var request_parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = request_parts.next() orelse return;
    const target = request_parts.next() orelse return;
    if (request_parts.next() == null) return;

    const query_start = std.mem.indexOfScalar(u8, target, '?');
    const path = if (query_start) |index| target[0..index] else target;
    const query = if (query_start) |index| target[index + 1 ..] else "";
    if (path.len == 0 or path[0] != '/') {
        try sendError(ctx, 400, "invalid request target");
        return;
    }

    var content_length: usize = 0;
    var auth_header: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
            const value = std.mem.trim(u8, line["Content-Length:".len..], " \t");
            content_length = std.fmt.parseInt(usize, value, 10) catch {
                try sendError(ctx, 400, "invalid content length");
                return;
            };
            if (content_length > MAX_BODY_SIZE) {
                try sendError(ctx, 413, "payload too large");
                return;
            }
        } else if (std.ascii.startsWithIgnoreCase(line, "Authorization:")) {
            auth_header = std.mem.trim(u8, line["Authorization:".len..], " \t");
        }
    }

    const body_start = header_end + 4;
    if (total < body_start) {
        try sendError(ctx, 400, "invalid request body");
        return;
    }
    var body = try arena.alloc(u8, content_length);
    if (content_length > 0) {
        const available = @min(total - body_start, content_length);
        if (available > 0) @memcpy(body[0..available], raw[body_start .. body_start + available]);
        var read_count = available;
        while (read_count < content_length) {
            const received = ctx.conn.stream.read(body[read_count..]) catch {
                try sendError(ctx, 400, "incomplete request body");
                return;
            };
            if (received == 0) {
                try sendError(ctx, 400, "incomplete request body");
                return;
            }
            read_count += received;
        }
    }

    ctx.request_started_ns = std.time.nanoTimestamp();
    ctx.request_method = method;
    ctx.request_path = path;
    ctx.should_record = std.mem.startsWith(u8, path, "/v1/");
    defer recordRequest(ctx);

    if (std.mem.eql(u8, method, "OPTIONS")) {
        try sendCors(ctx, 204);
        return;
    }

    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
        try sendHtml(ctx, FRONTEND_HTML);
        return;
    }

    if (std.mem.eql(u8, path, "/docs") or std.mem.eql(u8, path, "/docs/")) {
        try sendHtml(ctx, DOCS_HTML);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/health") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"status\":\"ok\",\"version\":\"2.4.0\"}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/auth/register") and std.mem.eql(u8, method, "POST")) {
        var response = std.ArrayList(u8).init(arena);
        ctx.server.reg_handler.handleRegister(body, &response) catch |err| {
            const status: u16 = switch (err) {
                error.EmailAlreadyRegistered => 409,
                error.InvalidEmail, error.MissingEmail, error.BodyTooLarge => 400,
                else => 500,
            };
            try sendError(ctx, status, registrationErrorMessage(err));
            return;
        };
        try sendJson(ctx, 201, response.items);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/auth/login") and std.mem.eql(u8, method, "POST")) {
        try handleLogin(ctx, arena, body);
        return;
    }

    const tenant_rec = authenticateRequest(ctx.server.reg, auth_header) catch |err| {
        if (err == error.Unauthorized) {
            try sendError(ctx, 401, "unauthorized");
        } else {
            try sendError(ctx, 500, "authentication failed");
        }
        return;
    };
    ctx.request_tenant_id = tenant_rec.tenant_id;

    if (std.mem.eql(u8, path, "/v1/account") and std.mem.eql(u8, method, "DELETE")) {
        var response = std.ArrayList(u8).init(arena);
        ctx.server.reg_handler.handleDeleteAccount(auth_header, &response) catch |err| {
            if (err == error.Unauthorized) {
                try sendError(ctx, 401, "unauthorized");
            } else {
                try sendError(ctx, 500, "account deletion failed");
            }
            return;
        };
        try sendJson(ctx, 200, response.items);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/tenant") and std.mem.eql(u8, method, "GET")) {
        try handleTenant(ctx, arena, tenant_rec);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/apikeys") and std.mem.eql(u8, method, "GET")) {
        try handleApiKeyList(ctx, arena, tenant_rec);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/apikeys") and std.mem.eql(u8, method, "POST")) {
        try rotateApiKey(ctx, arena, tenant_rec, 201);
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/apikeys/") and std.mem.endsWith(u8, path, "/rotate") and std.mem.eql(u8, method, "POST")) {
        const key_id = path["/v1/apikeys/".len .. path.len - "/rotate".len];
        if (!std.mem.eql(u8, key_id, "primary")) {
            try sendError(ctx, 404, "api key not found");
            return;
        }
        try rotateApiKey(ctx, arena, tenant_rec, 200);
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/apikeys/") and std.mem.eql(u8, method, "DELETE")) {
        const key_id = path["/v1/apikeys/".len..];
        if (!std.mem.eql(u8, key_id, "primary")) {
            try sendError(ctx, 404, "api key not found");
            return;
        }
        try revokeApiKey(ctx, tenant_rec);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox") and std.mem.eql(u8, method, "GET")) {
        try handleSandboxStatus(ctx, arena, tenant_rec.tenant_id);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/start") and std.mem.eql(u8, method, "POST")) {
        const started = startSandbox(ctx.server, tenant_rec) catch |err| {
            try sendError(ctx, 503, @errorName(err));
            return;
        };
        const body_out = if (started) "{\"status\":\"running\",\"changed\":true}" else "{\"status\":\"running\",\"changed\":false}";
        try sendJson(ctx, 200, body_out);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/stop") and std.mem.eql(u8, method, "POST")) {
        const stopped = stopSandbox(ctx.server, tenant_rec.tenant_id);
        const body_out = if (stopped) "{\"status\":\"stopped\",\"changed\":true}" else "{\"status\":\"stopped\",\"changed\":false}";
        try sendJson(ctx, 200, body_out);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/restart") and std.mem.eql(u8, method, "POST")) {
        _ = stopSandbox(ctx.server, tenant_rec.tenant_id);
        _ = startSandbox(ctx.server, tenant_rec) catch |err| {
            try sendError(ctx, 503, @errorName(err));
            return;
        };
        try sendJson(ctx, 200, "{\"status\":\"running\",\"changed\":true}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/databases") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"databases\":[{\"name\":\"documents\"}]}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/analytics") and std.mem.eql(u8, method, "GET")) {
        const response = ctx.server.metric_store.analyticsJson(tenant_rec.tenant_id, std.time.milliTimestamp()) catch |err| {
            try sendError(ctx, 500, @errorName(err));
            return;
        };
        defer allocator.free(response);
        try sendJson(ctx, 200, response);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/audit") and std.mem.eql(u8, method, "GET")) {
        const response = ctx.server.metric_store.auditJson(tenant_rec.tenant_id) catch |err| {
            try sendError(ctx, 500, @errorName(err));
            return;
        };
        defer allocator.free(response);
        try sendJson(ctx, 200, response);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/stats") and std.mem.eql(u8, method, "GET")) {
        const database_stats = try sandboxResponse(ctx, arena, auth_header, "{\"op\":\"stats\"}") orelse return;
        const analytics = ctx.server.metric_store.analyticsJson(tenant_rec.tenant_id, std.time.milliTimestamp()) catch |err| {
            try sendError(ctx, 500, @errorName(err));
            return;
        };
        defer allocator.free(analytics);
        if (database_stats.len == 0 or database_stats[database_stats.len - 1] != '}') {
            try sendError(ctx, 502, "invalid database statistics response");
            return;
        }
        const response = try std.fmt.allocPrint(arena, "{s},\"analytics\":{s}}}", .{ database_stats[0 .. database_stats.len - 1], analytics });
        try sendJson(ctx, 200, response);
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/databases/")) {
        try handleDatabaseRoute(ctx, arena, tenant_rec, auth_header, method, path, query, body);
        return;
    }

    try sendError(ctx, 404, "not found");
}

fn recordRequest(ctx: *ConnCtx) void {
    if (!ctx.should_record) return;
    if (std.mem.eql(u8, ctx.request_method, "DELETE") and std.mem.eql(u8, ctx.request_path, "/v1/account")) return;
    const tenant_id = ctx.request_tenant_id orelse return;
    const elapsed_ns = std.time.nanoTimestamp() - ctx.request_started_ns;
    const latency_us: u64 = if (elapsed_ns <= 0) 0 else @intCast(@divTrunc(elapsed_ns, 1000));
    ctx.server.metric_store.record(tenant_id, ctx.request_method, ctx.request_path, ctx.response_status, latency_us, std.time.milliTimestamp()) catch |err| {
        std.log.err("metric persistence error: {}", .{err});
    };
}

fn handleLogin(ctx: *ConnCtx, arena: std.mem.Allocator, body: []const u8) !void {
    var parsed = json.parse(arena, body) catch {
        try sendError(ctx, 400, "invalid json");
        return;
    };
    defer parsed.deinit(arena);
    const key_value = parsed.getField("api_key") orelse {
        try sendError(ctx, 400, "missing api_key");
        return;
    };
    const key = key_value.asString() orelse {
        try sendError(ctx, 400, "invalid api_key");
        return;
    };
    const tenant = ctx.server.reg.lookupByApiKey(key) catch {
        try sendError(ctx, 500, "authentication failed");
        return;
    } orelse {
        try sendError(ctx, 401, "invalid api_key");
        return;
    };
    const email = ctx.server.reg.getTenantEmail(arena, tenant.tenant_id) catch null orelse "";
    var output = std.ArrayList(u8).init(arena);
    const writer = output.writer();
    const tenant_id = try tenantIdString(arena, tenant.tenant_id);
    try output.appendSlice("{\"tenant_id\":");
    try appendJsonString(&output, tenant_id);
    try output.appendSlice(",\"email\":");
    try appendJsonString(&output, email);
    try output.appendSlice(",\"status\":\"active\",\"created_at\":");
    try writer.print("{d}", .{tenant.created_at_unix});
    try output.append('}');
    try sendJson(ctx, 200, output.items);
}

fn handleTenant(ctx: *ConnCtx, arena: std.mem.Allocator, tenant: registry.TenantRecord) !void {
    const email = ctx.server.reg.getTenantEmail(arena, tenant.tenant_id) catch null orelse "";
    var output = std.ArrayList(u8).init(arena);
    const writer = output.writer();
    try output.appendSlice("{\"tenant_id\":");
    const tenant_id = try tenantIdString(arena, tenant.tenant_id);
    try appendJsonString(&output, tenant_id);
    try output.appendSlice(",\"email\":");
    try appendJsonString(&output, email);
    try output.appendSlice(",\"status\":");
    try appendJsonString(&output, if (tenant.active == 1) "active" else "inactive");
    try output.appendSlice(",\"created_at\":");
    try writer.print("{d}", .{tenant.created_at_unix});
    try output.append('}');
    try sendJson(ctx, 200, output.items);
}

fn handleApiKeyList(ctx: *ConnCtx, arena: std.mem.Allocator, tenant: registry.TenantRecord) !void {
    _ = tenant;
    var output = std.ArrayList(u8).init(arena);
    try output.appendSlice("{\"keys\":[{\"id\":\"primary\",\"name\":\"Primary Key\",\"status\":\"active\"}]}");
    try sendJson(ctx, 200, output.items);
}

fn rotateApiKey(ctx: *ConnCtx, arena: std.mem.Allocator, tenant: registry.TenantRecord, status: u16) !void {
    const generated = apikey.generateApiKey() catch {
        try sendError(ctx, 500, "key generation failed");
        return;
    };
    const key = generated[0 .. generated.len - 1];
    const hash = apikey.hashApiKey(key);
    removeLegacyPlainApiKey(ctx.server.reg, tenant.tenant_id) catch {
        try sendError(ctx, 500, "key cleanup failed");
        return;
    };
    ctx.server.reg.storeApiKeyHash(tenant.tenant_id, hash) catch {
        try sendError(ctx, 500, "key storage failed");
        return;
    };
    var output = std.ArrayList(u8).init(arena);
    const writer = output.writer();
    try output.appendSlice("{\"id\":\"primary\",\"key\":");
    try appendJsonString(&output, key);
    try output.appendSlice(",\"created_at\":");
    try writer.print("{d}", .{std.time.timestamp()});
    try output.appendSlice(",\"status\":\"active\"}");
    try sendJson(ctx, status, output.items);
}

fn revokeApiKey(ctx: *ConnCtx, tenant: registry.TenantRecord) !void {
    const zero_hash: [32]u8 = [_]u8{0} ** 32;
    removeLegacyPlainApiKey(ctx.server.reg, tenant.tenant_id) catch {
        try sendError(ctx, 500, "key cleanup failed");
        return;
    };
    ctx.server.reg.storeApiKeyHash(tenant.tenant_id, zero_hash) catch {
        try sendError(ctx, 500, "key revocation failed");
        return;
    };
    try sendJson(ctx, 200, "{\"status\":\"revoked\"}");
}

fn removeLegacyPlainApiKey(reg: *registry.Registry, tenant_id: u64) !void {
    var storage_key_buffer: [64]u8 = undefined;
    const storage_key = try std.fmt.bufPrint(&storage_key_buffer, "plainkey:{d}", .{tenant_id});
    try reg.deleteKV(storage_key);
}

fn handleSandboxStatus(ctx: *ConnCtx, arena: std.mem.Allocator, tenant_id: u64) !void {
    const handle = ctx.server.pt.getHandle(tenant_id);
    var output = std.ArrayList(u8).init(arena);
    const writer = output.writer();
    if (handle) |sandbox_handle| {
        try output.appendSlice("{\"status\":\"running\",\"started_at_ms\":");
        try writer.print("{d}", .{sandbox_handle.started_at_unix_ms});
        try output.appendSlice("}");
    } else {
        try output.appendSlice("{\"status\":\"stopped\",\"started_at_ms\":null}");
    }
    try sendJson(ctx, 200, output.items);
}

fn startSandbox(server: *CloudServer, tenant: registry.TenantRecord) !bool {
    server.sandbox_mutex.lock();
    defer server.sandbox_mutex.unlock();
    if (server.pt.getHandle(tenant.tenant_id) != null) return false;
    const handle = try sandbox.spawnTenantSandbox(tenant);
    server.pt.insert(handle) catch |err| {
        sandbox.destroySandbox(handle) catch {};
        return err;
    };
    return true;
}

fn stopSandbox(server: *CloudServer, tenant_id: u64) bool {
    server.sandbox_mutex.lock();
    defer server.sandbox_mutex.unlock();
    var handle: ?sandbox.SandboxHandle = null;
    server.pt.mu.lock();
    if (server.pt.lookupLocked(tenant_id)) |found| {
        handle = found.*;
        server.pt.removeLocked(tenant_id);
    }
    server.pt.mu.unlock();
    if (handle) |sandbox_handle| {
        server.pt.stopSeccompSupervisor(tenant_id);
        sandbox.destroySandbox(sandbox_handle) catch return false;
        return true;
    }
    return false;
}

fn handleDatabaseRoute(ctx: *ConnCtx, arena: std.mem.Allocator, tenant: registry.TenantRecord, auth_header: ?[]const u8, method: []const u8, path: []const u8, query: []const u8, body: []const u8) !void {
    _ = tenant;
    const rest = path["/v1/databases/".len..];
    const slash_index = std.mem.indexOfScalar(u8, rest, '/') orelse {
        try sendError(ctx, 404, "database operation not found");
        return;
    };
    const database_name = rest[0..slash_index];
    const operation = rest[slash_index + 1 ..];
    if (!std.mem.eql(u8, database_name, "documents")) {
        try sendError(ctx, 404, "database not found");
        return;
    }

    if ((std.mem.eql(u8, operation, "query") or std.mem.eql(u8, operation, "search")) and std.mem.eql(u8, method, "POST")) {
        const payload = makeSearchPayload(arena, body, if (std.mem.eql(u8, operation, "search")) "search" else "query") catch {
            try sendError(ctx, 400, "invalid query payload");
            return;
        };
        try dispatchSandbox(ctx, arena, auth_header, payload, 200);
        return;
    }

    if (std.mem.eql(u8, operation, "records") and std.mem.eql(u8, method, "GET")) {
        const pagination = parsePagination(query) catch {
            try sendError(ctx, 400, "invalid pagination");
            return;
        };
        const payload = try std.fmt.allocPrint(arena, "{{\"op\":\"list\",\"limit\":{d},\"offset\":{d}}}", .{ pagination.limit, pagination.offset });
        try dispatchSandbox(ctx, arena, auth_header, payload, 200);
        return;
    }

    if (std.mem.eql(u8, operation, "records") and std.mem.eql(u8, method, "POST")) {
        const payload = makeInsertPayload(arena, body) catch {
            try sendError(ctx, 400, "invalid record payload");
            return;
        };
        try dispatchSandbox(ctx, arena, auth_header, payload, 201);
        return;
    }

    if (std.mem.eql(u8, operation, "stats") and std.mem.eql(u8, method, "GET")) {
        try dispatchSandbox(ctx, arena, auth_header, "{\"op\":\"stats\"}", 200);
        return;
    }

    if (std.mem.startsWith(u8, operation, "records/")) {
        const id_text = operation["records/".len..];
        const id = std.fmt.parseInt(u64, id_text, 10) catch {
            try sendError(ctx, 400, "invalid record id");
            return;
        };
        const operation_name: []const u8 = if (std.mem.eql(u8, method, "GET")) "get" else if (std.mem.eql(u8, method, "DELETE")) "delete" else {
            try sendError(ctx, 405, "method not allowed");
            return;
        };
        const payload = try std.fmt.allocPrint(arena, "{{\"op\":\"{s}\",\"id\":{d}}}", .{ operation_name, id });
        try dispatchSandbox(ctx, arena, auth_header, payload, if (std.mem.eql(u8, method, "DELETE")) 200 else 200);
        return;
    }

    try sendError(ctx, 404, "database operation not found");
}

const Pagination = struct {
    limit: usize,
    offset: usize,
};

fn parsePagination(query: []const u8) !Pagination {
    var pagination = Pagination{ .limit = 100, .offset = 0 };
    if (query.len == 0) return pagination;
    var parameters = std.mem.splitScalar(u8, query, '&');
    while (parameters.next()) |parameter| {
        if (parameter.len == 0) continue;
        const separator = std.mem.indexOfScalar(u8, parameter, '=') orelse continue;
        const name = parameter[0..separator];
        const value = parameter[separator + 1 ..];
        if (std.mem.eql(u8, name, "limit")) {
            const parsed = try std.fmt.parseInt(usize, value, 10);
            if (parsed == 0 or parsed > 1000) return error.InvalidPagination;
            pagination.limit = parsed;
        } else if (std.mem.eql(u8, name, "offset")) {
            const parsed = try std.fmt.parseInt(usize, value, 10);
            if (parsed > 1_000_000) return error.InvalidPagination;
            pagination.offset = parsed;
        }
    }
    return pagination;
}

fn makeSearchPayload(arena: std.mem.Allocator, body: []const u8, operation: []const u8) ![]u8 {
    var parsed = json.parse(arena, body) catch return error.InvalidJson;
    defer parsed.deinit(arena);
    const query = blk: {
        if (parsed.getField("query")) |value| if (value.asString()) |text| break :blk text;
        if (parsed.getField("search")) |value| if (value.asString()) |text| break :blk text;
        break :blk "";
    };
    var limit: i64 = 50;
    if (parsed.getField("limit")) |value| {
        if (value.asInt()) |parsed_limit| limit = parsed_limit;
    }
    if (parsed.getField("top_k")) |value| {
        if (value.asInt()) |parsed_limit| limit = parsed_limit;
    }
    if (parsed.getField("topK")) |value| {
        if (value.asInt()) |parsed_limit| limit = parsed_limit;
    }
    if (limit < 1) limit = 1;
    if (limit > 1000) limit = 1000;
    var offset: i64 = 0;
    if (parsed.getField("offset")) |value| {
        if (value.asInt()) |parsed_offset| offset = parsed_offset;
    }
    if (offset < 0) offset = 0;
    if (offset > 1_000_000) offset = 1_000_000;
    var payload: json.Value = .{ .object = .{} };
    defer payload.deinit(arena);
    try json.objectPut(arena, &payload, "op", try json.makeString(arena, operation));
    try json.objectPut(arena, &payload, "query", try json.makeString(arena, query));
    try json.objectPut(arena, &payload, "limit", json.makeInt(limit));
    try json.objectPut(arena, &payload, "offset", json.makeInt(offset));
    return try json.stringify(arena, payload);
}

fn makeInsertPayload(arena: std.mem.Allocator, body: []const u8) ![]u8 {
    var parsed = json.parse(arena, body) catch return error.InvalidJson;
    defer parsed.deinit(arena);
    const record = parsed.getField("record") orelse parsed;
    if (record != .object) return error.InvalidRecord;
    var payload: json.Value = .{ .object = .{} };
    defer payload.deinit(arena);
    try json.objectPut(arena, &payload, "op", try json.makeString(arena, "insert"));
    try json.objectPut(arena, &payload, "record", try record.clone(arena));
    return try json.stringify(arena, payload);
}

fn dispatchSandbox(ctx: *ConnCtx, arena: std.mem.Allocator, auth_header: ?[]const u8, payload: []const u8, success_status: u16) !void {
    const response = try sandboxResponse(ctx, arena, auth_header, payload) orelse return;
    try sendJson(ctx, success_status, response);
}

fn sandboxResponse(ctx: *ConnCtx, arena: std.mem.Allocator, auth_header: ?[]const u8, payload: []const u8) !?[]const u8 {
    var response = std.ArrayList(u8).init(arena);
    ctx.server.rtr.handleHttpRequest(auth_header, payload, &response) catch |err| {
        if (err == error.Unauthorized) {
            try sendError(ctx, 401, "unauthorized");
        } else if (err == error.QueryTimeout) {
            try sendError(ctx, 504, "database operation timed out");
        } else {
            try sendError(ctx, 503, @errorName(err));
        }
        return null;
    };
    if (sandboxErrorStatus(arena, response.items)) |status| {
        try sendJson(ctx, status, response.items);
        return null;
    }
    return response.items;
}

fn sandboxErrorStatus(arena: std.mem.Allocator, response: []const u8) ?u16 {
    var parsed = json.parse(arena, response) catch return null;
    defer parsed.deinit(arena);
    const error_value = parsed.getField("error") orelse return null;
    const message = error_value.asString() orelse return null;
    if (std.mem.eql(u8, message, "not_found")) return 404;
    if (std.mem.eql(u8, message, "unknown_op")) return 400;
    return 500;
}

fn authenticateRequest(reg: *registry.Registry, auth_header: ?[]const u8) !registry.TenantRecord {
    const header = auth_header orelse return error.Unauthorized;
    if (!std.mem.startsWith(u8, header, "Bearer ")) return error.Unauthorized;
    const key = header["Bearer ".len..];
    if (key.len == 0) return error.Unauthorized;
    return try reg.lookupByApiKey(key) orelse error.Unauthorized;
}

fn tenantIdString(allocator: std.mem.Allocator, tenant_id: u64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{tenant_id});
}

fn registrationErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.EmailAlreadyRegistered => "email already registered",
        error.InvalidEmail, error.MissingEmail => "invalid email",
        error.BodyTooLarge => "payload too large",
        else => "registration failed",
    };
}

fn appendJsonString(output: *std.ArrayList(u8), value: []const u8) !void {
    try output.append('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try output.appendSlice("\\\""),
            '\\' => try output.appendSlice("\\\\"),
            '\n' => try output.appendSlice("\\n"),
            '\r' => try output.appendSlice("\\r"),
            '\t' => try output.appendSlice("\\t"),
            else => {
                if (byte < 0x20) {
                    const hex = "0123456789abcdef";
                    try output.appendSlice("\\u00");
                    try output.append(hex[byte >> 4]);
                    try output.append(hex[byte & 0x0f]);
                } else {
                    try output.append(byte);
                }
            },
        }
    }
    try output.append('"');
}

fn sendHtml(ctx: *ConnCtx, content: []const u8) !void {
    ctx.response_status = 200;
    const header = try std.fmt.allocPrint(
        ctx.server.allocator,
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n",
        .{content.len},
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
    try ctx.conn.stream.writeAll(content);
}

fn sendJson(ctx: *ConnCtx, status: u16, body: []const u8) !void {
    ctx.response_status = status;
    const header = try std.fmt.allocPrint(
        ctx.server.allocator,
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nConnection: close\r\n\r\n",
        .{ status, statusText(status), body.len },
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
    if (body.len > 0) try ctx.conn.stream.writeAll(body);
}

fn sendError(ctx: *ConnCtx, status: u16, message: []const u8) !void {
    var body = std.ArrayList(u8).init(ctx.server.allocator);
    defer body.deinit();
    try body.appendSlice("{\"error\":");
    try appendJsonString(&body, message);
    try body.append('}');
    try sendJson(ctx, status, body.items);
}

fn sendCors(ctx: *ConnCtx, status: u16) !void {
    ctx.response_status = status;
    const header = try std.fmt.allocPrint(
        ctx.server.allocator,
        "HTTP/1.1 {d} {s}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Max-Age: 600\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        .{ status, statusText(status) },
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
}

fn statusText(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Payload Too Large",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        else => "OK",
    };
}

test "pagination parses bounded query parameters" {
    const testing = std.testing;
    const pagination = try parsePagination("limit=75&offset=150");
    try testing.expectEqual(@as(usize, 75), pagination.limit);
    try testing.expectEqual(@as(usize, 150), pagination.offset);
    try testing.expectError(error.InvalidPagination, parsePagination("limit=0"));
    try testing.expectError(error.InvalidPagination, parsePagination("offset=1000001"));
}

test "sandbox errors map to HTTP statuses" {
    const testing = std.testing;
    try testing.expectEqual(@as(?u16, 404), sandboxErrorStatus(testing.allocator, "{\"error\":\"not_found\"}"));
    try testing.expectEqual(@as(?u16, 400), sandboxErrorStatus(testing.allocator, "{\"error\":\"unknown_op\"}"));
    try testing.expectEqual(@as(?u16, null), sandboxErrorStatus(testing.allocator, "{\"records\":1}"));
}
