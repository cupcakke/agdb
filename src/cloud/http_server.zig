const std = @import("std");
const registration = @import("registration.zig");
const registry = @import("registry.zig");
const router = @import("router.zig");
const process_table = @import("process_table.zig");
const sandbox = @import("sandbox.zig");
const apikey = @import("apikey.zig");
const json = @import("../json.zig");
const build_options = @import("build_options");

const FRONTEND_HTML = @embedFile("index.html");
const DOCS_HTML = @embedFile("docs.html");
const CLOUD_VERSION = "2.4.0";

const MAX_CONNECTIONS: u32 = 1024;

pub const CloudServer = struct {
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
    pt: *process_table.ProcessTable,
    reg_handler: registration.RegistrationHandler,
    rtr: router.Router,
    port: u16,
    active_conn: std.atomic.Value(u32),

    pub fn init(allocator: std.mem.Allocator, reg_ptr: *registry.Registry, pt_ptr: *process_table.ProcessTable, port: u16) CloudServer {
        return .{
            .allocator = allocator,
            .reg = reg_ptr,
            .pt = pt_ptr,
            .reg_handler = registration.RegistrationHandler.init(allocator, reg_ptr, pt_ptr),
            .rtr = router.Router.init(allocator, reg_ptr, pt_ptr),
            .port = port,
            .active_conn = std.atomic.Value(u32).init(0),
        };
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
            const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
                std.log.err("spawn thread error: {}", .{err});
                conn.stream.close();
                _ = self.active_conn.fetchSub(1, .acq_rel);
                self.allocator.destroy(ctx);
                continue;
            };
            t.detach();
        }
    }
};

const ConnCtx = struct {
    server: *CloudServer,
    conn: std.net.Server.Connection,
};

fn handleConn(ctx: *ConnCtx) void {
    defer ctx.conn.stream.close();
    defer ctx.server.allocator.destroy(ctx);
    defer _ = ctx.server.active_conn.fetchSub(1, .acq_rel);
    // Set 30s receive/send timeout on the accepted socket
    const tv = std.os.linux.timeval{ .sec = 30, .usec = 0 };
    const tv_bytes = std.mem.asBytes(&tv);
    _ = std.os.linux.setsockopt(ctx.conn.stream.handle, std.os.linux.SOL.SOCKET, std.os.linux.SO.RCVTIMEO, tv_bytes.ptr, @intCast(tv_bytes.len));
    _ = std.os.linux.setsockopt(ctx.conn.stream.handle, std.os.linux.SOL.SOCKET, std.os.linux.SO.SNDTIMEO, tv_bytes.ptr, @intCast(tv_bytes.len));
    handleConnInner(ctx) catch |err| {
        std.log.debug("connection error: {}", .{err});
    };
}

fn handleConnInner(ctx: *ConnCtx) !void {
    const allocator = ctx.server.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var buf: [65536]u8 = undefined;
    var total: usize = 0;

    while (true) {
        const n = ctx.conn.stream.read(buf[total..]) catch break;
        if (n == 0) break;
        total += n;
        if (total >= buf.len) break;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
    }

    if (total == 0) return;

    const raw = buf[0..total];

    const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return;
    const header_section = raw[0..header_end];

    var lines = std.mem.splitSequence(u8, header_section, "\r\n");
    const request_line = lines.next() orelse return;

    var req_parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = req_parts.next() orelse return;
    const path_raw = req_parts.next() orelse return;

    const query_start = std.mem.indexOfScalar(u8, path_raw, '?');
    const path = if (query_start) |qi| path_raw[0..qi] else path_raw;

    var content_length: usize = 0;
    var auth_header: ?[]const u8 = null;

    while (lines.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
            const val = std.mem.trim(u8, line["Content-Length:".len..], " \t");
            const parsed_len = std.fmt.parseInt(usize, val, 10) catch 0;
            if (parsed_len > 16 * 1024 * 1024) {
                try sendError(ctx, 413, "payload too large");
                return;
            }
            content_length = parsed_len;
        } else if (std.ascii.startsWithIgnoreCase(line, "Authorization:")) {
            auth_header = std.mem.trim(u8, line["Authorization:".len..], " \t");
        }
    }

    const body_start = header_end + 4;
    var body_buf = try arena.alloc(u8, content_length);
    if (content_length > 0) {
        const already_have = @min(total - body_start, content_length);
        if (already_have > 0) {
            @memcpy(body_buf[0..already_have], raw[body_start .. body_start + already_have]);
        }
        var received = already_have;
        while (received < content_length) {
            const n = ctx.conn.stream.read(body_buf[received..]) catch break;
            if (n == 0) break;
            received += n;
        }
        body_buf = body_buf[0..received];
    } else {
        body_buf = body_buf[0..0];
    }

    var resp_buf = std.ArrayList(u8).init(arena);

    if (std.mem.eql(u8, method, "OPTIONS")) {
        try sendCors(ctx, 204, "", "");
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

    if (std.mem.eql(u8, path, "/v1/health")) {
        const body = try std.fmt.allocPrint(arena, "{{\"status\":\"ok\",\"version\":\"{s}\"}}", .{CLOUD_VERSION});
        try sendJson(ctx, 200, body);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/auth/register") and std.mem.eql(u8, method, "POST")) {
        ctx.server.reg_handler.handleRegister(body_buf, &resp_buf) catch |err| {
            const code: u16 = switch (err) {
                error.EmailAlreadyRegistered => 409,
                error.InvalidEmail, error.MissingEmail => 400,
                else => 500,
            };
            const msg = switch (err) {
                error.EmailAlreadyRegistered => "email already registered",
                error.InvalidEmail, error.MissingEmail => "invalid email",
                else => "internal error",
            };
            try sendError(ctx, code, msg);
            return;
        };
        if (resp_buf.items.len > 0) {
            var parsed = try json.parse(arena, resp_buf.items);
            defer parsed.deinit(arena);
            const tid_val = parsed.getField("tenant_id") orelse {
                try sendError(ctx, 500, "internal error");
                return;
            };
            const key_val = parsed.getField("api_key") orelse {
                try sendError(ctx, 500, "internal error");
                return;
            };
            const tid_str = tid_val.asString() orelse {
                try sendError(ctx, 500, "internal error");
                return;
            };
            const key_str = key_val.asString() orelse {
                try sendError(ctx, 500, "internal error");
                return;
            };

            var tid_u64: u64 = 0;
            if (key_str.len > 0) {
                const email_from_body = extractEmailFromBody(body_buf);
                if (email_from_body.len > 0) {
                    tid_u64 = std.fmt.parseInt(u64, tid_str, 10) catch 0;
                    if (tid_u64 != 0) {
                        ctx.server.reg.storeTenantEmail(tid_u64, email_from_body) catch {};
                        const key_without_null = if (key_str.len > 0 and key_str[key_str.len - 1] == 0) key_str[0 .. key_str.len - 1] else key_str;
                        ctx.server.reg.storePlainApiKey(tid_u64, key_without_null) catch {};
                    }
                }
            }

            const key_out = if (key_str.len > 0 and key_str[key_str.len - 1] == 0) key_str[0 .. key_str.len - 1] else key_str;
            const ts = std.time.timestamp();
            const resp = try std.fmt.allocPrint(arena,
                \\{{"tenant_id":"{s}","api_key":"{s}","created_at":{d},"status":"active"}}
            , .{ tid_str, key_out, ts });
            try sendJson(ctx, 201, resp);
        }
        return;
    }

    if (std.mem.eql(u8, path, "/v1/auth/login") and std.mem.eql(u8, method, "POST")) {
        var body_parsed = json.parse(arena, body_buf) catch {
            try sendError(ctx, 400, "invalid json");
            return;
        };
        defer body_parsed.deinit(arena);
        const key_val = body_parsed.getField("api_key") orelse {
            try sendError(ctx, 400, "missing api_key");
            return;
        };
        const key_str = key_val.asString() orelse {
            try sendError(ctx, 400, "invalid api_key");
            return;
        };
        const key_clean = if (key_str.len > 0 and key_str[key_str.len - 1] == 0) key_str[0 .. key_str.len - 1] else key_str;
        const tenant_rec = ctx.server.reg.lookupByApiKey(key_clean) catch null orelse {
            try sendError(ctx, 401, "invalid api_key");
            return;
        };
        const email = ctx.server.reg.getTenantEmail(arena, tenant_rec.tenant_id) catch null orelse try arena.dupe(u8, "");
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const resp = try std.fmt.allocPrint(arena,
            \\{{"tenant_id":"{s}","email":"{s}","status":"active","created_at":{d}}}
        , .{ tid_str, email, tenant_rec.created_at_unix });
        try sendJson(ctx, 200, resp);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/account") and std.mem.eql(u8, method, "DELETE")) {
        ctx.server.reg_handler.handleDeleteAccount(auth_header, &resp_buf) catch |err| {
            if (err == error.Unauthorized) {
                try sendError(ctx, 401, "unauthorized");
            } else {
                try sendError(ctx, 500, "internal error");
            }
            return;
        };
        try sendJson(ctx, 200, "{\"status\":\"deleted\"}");
        return;
    }

    const tenant_rec = authenticateRequest(ctx.server.reg, auth_header) catch |err| {
        if (err == error.Unauthorized) {
            try sendError(ctx, 401, "unauthorized");
        } else {
            try sendError(ctx, 500, "internal error");
        }
        return;
    };

    if (std.mem.eql(u8, path, "/v1/tenant") and std.mem.eql(u8, method, "GET")) {
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const email = ctx.server.reg.getTenantEmail(arena, tenant_rec.tenant_id) catch null orelse try arena.dupe(u8, "");
        const data_path = blk: {
            const idx = std.mem.indexOfScalar(u8, &tenant_rec.data_path, 0) orelse tenant_rec.data_path.len;
            break :blk tenant_rec.data_path[0..idx];
        };
        const resp = try std.fmt.allocPrint(arena,
            \\{{"tenant_id":"{s}","email":"{s}","status":"active","region":"eu-west-1","created_at":{d},"data_path":"{s}"}}
        , .{ tid_str, email, tenant_rec.created_at_unix, data_path });
        try sendJson(ctx, 200, resp);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/apikeys") and std.mem.eql(u8, method, "GET")) {
        const plain_key = ctx.server.reg.getPlainApiKey(arena, tenant_rec.tenant_id) catch null orelse try arena.dupe(u8, "");
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const key_id = try std.fmt.allocPrint(arena, "key_{s}", .{tid_str});
        const resp = try std.fmt.allocPrint(arena,
            \\{{"keys":[{{"id":"{s}","name":"Primary Key","key":"{s}","created_at":{d},"status":"active","last_used":null,"scope":"full"}}]}}
        , .{ key_id, plain_key, tenant_rec.created_at_unix });
        try sendJson(ctx, 200, resp);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/apikeys") and std.mem.eql(u8, method, "POST")) {
        const new_key = apikey.generateApiKey() catch {
            try sendError(ctx, 500, "key generation failed");
            return;
        };
        const key_hash = apikey.hashApiKey(&new_key);
        ctx.server.reg.storeApiKeyHash(tenant_rec.tenant_id, key_hash) catch {
            try sendError(ctx, 500, "internal error");
            return;
        };
        const key_without_null = if (new_key[new_key.len - 1] == 0) new_key[0 .. new_key.len - 1] else &new_key;
        ctx.server.reg.storePlainApiKey(tenant_rec.tenant_id, key_without_null) catch {};
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const key_id = try std.fmt.allocPrint(arena, "key_{s}", .{tid_str});
        const ts = std.time.timestamp();
        const resp = try std.fmt.allocPrint(arena,
            \\{{"id":"{s}","name":"Primary Key","key":"{s}","created_at":{d},"status":"active","scope":"full"}}
        , .{ key_id, key_without_null, ts });
        try sendJson(ctx, 201, resp);
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/apikeys/") and std.mem.eql(u8, method, "DELETE")) {
        const zero_hash: [32]u8 = [_]u8{0} ** 32;
        ctx.server.reg.storeApiKeyHash(tenant_rec.tenant_id, zero_hash) catch {};
        var pk_key_buf: [64]u8 = undefined;
        const pk_key = try std.fmt.bufPrint(&pk_key_buf, "plainkey:{d}", .{tenant_rec.tenant_id});
        ctx.server.reg.deleteKV(pk_key) catch {};
        try sendJson(ctx, 200, "{\"status\":\"revoked\"}");
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/apikeys/") and std.mem.endsWith(u8, path, "/rotate") and std.mem.eql(u8, method, "POST")) {
        const new_key = apikey.generateApiKey() catch {
            try sendError(ctx, 500, "key generation failed");
            return;
        };
        const key_hash = apikey.hashApiKey(&new_key);
        ctx.server.reg.storeApiKeyHash(tenant_rec.tenant_id, key_hash) catch {
            try sendError(ctx, 500, "internal error");
            return;
        };
        const key_without_null = if (new_key[new_key.len - 1] == 0) new_key[0 .. new_key.len - 1] else &new_key;
        ctx.server.reg.storePlainApiKey(tenant_rec.tenant_id, key_without_null) catch {};
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const key_id = try std.fmt.allocPrint(arena, "key_{s}", .{tid_str});
        const ts = std.time.timestamp();
        const resp = try std.fmt.allocPrint(arena,
            \\{{"id":"{s}","key":"{s}","created_at":{d},"status":"active"}}
        , .{ key_id, key_without_null, ts });
        try sendJson(ctx, 200, resp);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox") and std.mem.eql(u8, method, "GET")) {
        const maybe_handle = ctx.server.pt.getHandle(tenant_rec.tenant_id);
        const running = maybe_handle != null;
        const status = if (running) "running" else "stopped";
        const started_at: i64 = if (maybe_handle) |h| @divTrunc(h.last_activity_ns, std.time.ns_per_s) else 0;
        const resp = try std.fmt.allocPrint(arena,
            \\{{"status":"{s}","started_at":{d},"restarts":0,"region":"eu-west-1"}}
        , .{ status, started_at });
        try sendJson(ctx, 200, resp);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/start") and std.mem.eql(u8, method, "POST")) {
        if (ctx.server.pt.getHandle(tenant_rec.tenant_id) != null) {
            try sendJson(ctx, 200, "{\"status\":\"running\",\"message\":\"already running\"}");
            return;
        }
        const handle = sandbox.spawnTenantSandbox(tenant_rec) catch |err| {
            std.log.err("sandbox spawn failed for tenant {d}: {}", .{ tenant_rec.tenant_id, err });
            try sendError(ctx, 500, "sandbox spawn failed");
            return;
        };
        ctx.server.pt.mu.lock();
        ctx.server.pt.insertLocked(handle) catch |err| {
            ctx.server.pt.mu.unlock();
            sandbox.destroySandbox(handle) catch {};
            std.log.err("process table insert failed: {}", .{err});
            try sendError(ctx, 500, "internal error");
            return;
        };
        ctx.server.pt.mu.unlock();
        try sendJson(ctx, 200, "{\"status\":\"running\"}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/stop") and std.mem.eql(u8, method, "POST")) {
        var handle_copy: ?sandbox.SandboxHandle = null;
        {
            ctx.server.pt.mu.lock();
            defer ctx.server.pt.mu.unlock();
            if (ctx.server.pt.lookupLocked(tenant_rec.tenant_id)) |h| {
                handle_copy = h.*;
                ctx.server.pt.removeLocked(tenant_rec.tenant_id);
            }
        }
        if (handle_copy) |h| {
            sandbox.destroySandbox(h) catch {};
        }
        try sendJson(ctx, 200, "{\"status\":\"stopped\"}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/sandbox/restart") and std.mem.eql(u8, method, "POST")) {
        var old_handle: ?sandbox.SandboxHandle = null;
        {
            ctx.server.pt.mu.lock();
            defer ctx.server.pt.mu.unlock();
            if (ctx.server.pt.lookupLocked(tenant_rec.tenant_id)) |h| {
                old_handle = h.*;
                ctx.server.pt.removeLocked(tenant_rec.tenant_id);
            }
        }
        if (old_handle) |h| {
            sandbox.destroySandbox(h) catch {};
        }
        const handle = sandbox.spawnTenantSandbox(tenant_rec) catch |err| {
            std.log.err("sandbox restart spawn failed: {}", .{err});
            try sendError(ctx, 500, "sandbox spawn failed");
            return;
        };
        ctx.server.pt.mu.lock();
        ctx.server.pt.insertLocked(handle) catch |err| {
            ctx.server.pt.mu.unlock();
            sandbox.destroySandbox(handle) catch {};
            std.log.err("process table insert failed: {}", .{err});
            try sendError(ctx, 500, "internal error");
            return;
        };
        ctx.server.pt.mu.unlock();
        try sendJson(ctx, 200, "{\"status\":\"running\"}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/databases") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"databases\":[{\"name\":\"documents\",\"status\":\"active\"}]}");
        return;
    }

    if (std.mem.startsWith(u8, path, "/v1/databases/")) {
        const rest = path["/v1/databases/".len..];
        const slash = std.mem.indexOfScalar(u8, rest, '/');
        if (slash != null) {
            const op_part = rest[slash.? + 1 ..];
            const is_query = std.mem.eql(u8, op_part, "query") and std.mem.eql(u8, method, "POST");
            const is_search = std.mem.eql(u8, op_part, "search") and std.mem.eql(u8, method, "POST");
            const is_records_post = std.mem.eql(u8, op_part, "records") and std.mem.eql(u8, method, "POST");
            const is_records_get = std.mem.startsWith(u8, op_part, "records/") and std.mem.eql(u8, method, "GET");
            const is_records_del = std.mem.startsWith(u8, op_part, "records/") and std.mem.eql(u8, method, "DELETE");
            const is_stats = std.mem.eql(u8, op_part, "stats") and std.mem.eql(u8, method, "GET");

            if (is_query or is_search) {
                var query_str: []const u8 = "";
                var top_k: i64 = 10;
                if (body_buf.len > 0) {
                    var bp = json.parse(arena, body_buf) catch null;
                    if (bp) |*bpv| {
                        defer bpv.deinit(arena);
                        if (bpv.getField("search")) |sv| if (sv.asString()) |s| { query_str = s; };
                        if (bpv.getField("query")) |qv| if (qv.asString()) |s| { query_str = s; };
                        if (bpv.getField("topK")) |kv| if (kv.asInt()) |k| { top_k = k; };
                        if (bpv.getField("top_k")) |kv| if (kv.asInt()) |k| { top_k = k; };
                        if (bpv.getField("limit")) |lv| if (lv.asInt()) |l| { top_k = l; };
                    }
                }
                const sandbox_body = try std.fmt.allocPrint(arena,
                    \\{{"op":"search","query":"{s}","top_k":{d}}}
                , .{ query_str, top_k });
                ctx.server.rtr.handleHttpRequest(auth_header, sandbox_body, &resp_buf) catch |err| {
                    if (err == error.Unauthorized) {
                        try sendError(ctx, 401, "unauthorized");
                    } else {
                        try sendError(ctx, 500, "query failed");
                    }
                    return;
                };
                try sendJson(ctx, 200, resp_buf.items);
                return;
            }

            if (is_records_post) {
                var rec_body: []const u8 = "{}";
                if (body_buf.len > 0) {
                    var bp = json.parse(arena, body_buf) catch null;
                    if (bp) |*bpv| {
                        defer bpv.deinit(arena);
                        if (bpv.getField("record")) |rv| {
                            rec_body = try json.stringify(arena, rv);
                        } else {
                            rec_body = body_buf;
                        }
                    }
                }
                const sandbox_body = try std.fmt.allocPrint(arena,
                    \\{{"op":"insert","record":{s}}}
                , .{rec_body});
                ctx.server.rtr.handleHttpRequest(auth_header, sandbox_body, &resp_buf) catch |err| {
                    if (err == error.Unauthorized) {
                        try sendError(ctx, 401, "unauthorized");
                    } else {
                        try sendError(ctx, 500, "insert failed");
                    }
                    return;
                };
                try sendJson(ctx, 201, resp_buf.items);
                return;
            }

            if (is_records_get or is_records_del) {
                const id_str = op_part["records/".len..];
                const op = if (is_records_del) "delete" else "get";
                const sandbox_body = try std.fmt.allocPrint(arena,
                    \\{{"op":"{s}","id":{s}}}
                , .{ op, id_str });
                ctx.server.rtr.handleHttpRequest(auth_header, sandbox_body, &resp_buf) catch |err| {
                    if (err == error.Unauthorized) {
                        try sendError(ctx, 401, "unauthorized");
                    } else {
                        try sendError(ctx, 500, "operation failed");
                    }
                    return;
                };
                const status_code: u16 = if (is_records_del) 204 else 200;
                try sendJson(ctx, status_code, resp_buf.items);
                return;
            }

            if (is_stats) {
                const sandbox_body = "{\"op\":\"stats\"}";
                ctx.server.rtr.handleHttpRequest(auth_header, sandbox_body, &resp_buf) catch |err| {
                    if (err == error.Unauthorized) {
                        try sendError(ctx, 401, "unauthorized");
                    } else {
                        try sendJson(ctx, 200, "{\"records\":0,\"databases\":[\"documents\"],\"status\":\"healthy\"}");
                    }
                    return;
                };
                try sendJson(ctx, 200, resp_buf.items);
                return;
            }
        }
    }

    if (std.mem.eql(u8, path, "/v1/stats") and std.mem.eql(u8, method, "GET")) {
        const sandbox_body = "{\"op\":\"stats\"}";
        ctx.server.rtr.handleHttpRequest(auth_header, sandbox_body, &resp_buf) catch {
            try sendJson(ctx, 200, "{\"records\":0,\"databases\":[\"documents\"],\"status\":\"healthy\"}");
            return;
        };
        try sendJson(ctx, 200, resp_buf.items);
        return;
    }

    if (std.mem.eql(u8, path, "/v1/webhooks")) {
        if (std.mem.eql(u8, method, "GET")) {
            var tid_str_buf: [24]u8 = undefined;
            const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
            const wh_key = try std.fmt.allocPrint(arena, "webhooks:{s}", .{tid_str});
            const stored = ctx.server.reg.getKV(arena, wh_key) catch null;
            if (stored) |s| {
                const resp = try std.fmt.allocPrint(arena, "{{\"webhooks\":{s}}}", .{s});
                try sendJson(ctx, 200, resp);
            } else {
                try sendJson(ctx, 200, "{\"webhooks\":[]}");
            }
            return;
        }
        if (std.mem.eql(u8, method, "POST")) {
            var tid_str_buf: [24]u8 = undefined;
            const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
            const wh_key = try std.fmt.allocPrint(arena, "webhooks:{s}", .{tid_str});

            var name_val: []const u8 = "Webhook";
            var url_val: []const u8 = "";
            var events_val: []const u8 = "[]";
            if (body_buf.len > 0) {
                var bp = json.parse(arena, body_buf) catch null;
                if (bp) |*bpv| {
                    defer bpv.deinit(arena);
                    if (bpv.getField("name")) |nv| if (nv.asString()) |n| { name_val = n; };
                    if (bpv.getField("url")) |uv| if (uv.asString()) |u| { url_val = u; };
                    if (bpv.getField("events")) |ev| {
                        events_val = try json.stringify(arena, ev);
                    }
                }
            }
            const wh_id = try std.fmt.allocPrint(arena, "wh_{d}", .{std.time.timestamp()});
            const ts = std.time.timestamp();
            const new_wh = try std.fmt.allocPrint(arena,
                \\{{"id":"{s}","name":"{s}","url":"{s}","events":{s},"created_at":{d},"status":"active"}}
            , .{ wh_id, name_val, url_val, events_val, ts });

            const existing = ctx.server.reg.getKV(arena, wh_key) catch null;
            var new_list: []u8 = undefined;
            if (existing) |e| {
                new_list = try std.fmt.allocPrint(arena, "[{s},{s}]", .{ e[1 .. e.len - 1], new_wh });
            } else {
                new_list = try std.fmt.allocPrint(arena, "[{s}]", .{new_wh});
            }
            ctx.server.reg.storeKV(wh_key, new_list) catch {
                try sendJson(ctx, 500, "{\"error\":\"Failed to store webhook\"}");
                return;
            };
            try sendJson(ctx, 201, new_wh);
            return;
        }
    }

    if (std.mem.startsWith(u8, path, "/v1/webhooks/") and std.mem.eql(u8, method, "DELETE")) {
        const del_id = path["/v1/webhooks/".len..];
        var tid_str_buf: [24]u8 = undefined;
        const tid_str = try std.fmt.bufPrint(&tid_str_buf, "{d}", .{tenant_rec.tenant_id});
        const wh_key = try std.fmt.allocPrint(arena, "webhooks:{s}", .{tid_str});
        if (ctx.server.reg.getKV(arena, wh_key) catch null) |existing| {
            var new_list = std.ArrayList(u8).init(arena);
            try new_list.append('[');
            var first = true;
            if (json.parse(arena, existing) catch null) |parsed_val| {
                var p = parsed_val;
                defer p.deinit(arena);
                switch (p) {
                    .array => |arr| {
                        for (arr) |item| {
                            var include = true;
                            if (item.getField("id")) |id_field| {
                                if (id_field.asString()) |id_str_v| {
                                    if (std.mem.eql(u8, id_str_v, del_id)) include = false;
                                }
                            }
                            if (include) {
                                if (!first) try new_list.append(',');
                                const item_str = try json.stringify(arena, item);
                                try new_list.appendSlice(item_str);
                                first = false;
                            }
                        }
                    },
                    else => {},
                }
            }
            try new_list.append(']');
            ctx.server.reg.storeKV(wh_key, new_list.items) catch {
                try sendJson(ctx, 500, "{\"error\":\"Failed to update webhook list\"}");
                return;
            };
        }
        try sendJson(ctx, 200, "{\"status\":\"deleted\"}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/analytics") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"total_requests\":0,\"avg_latency_ms\":0,\"error_rate\":0.0}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/audit") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"logs\":[]}");
        return;
    }

    if (std.mem.eql(u8, path, "/v1/admin/tenants") and std.mem.eql(u8, method, "GET")) {
        try sendJson(ctx, 200, "{\"tenants\":[]}");
        return;
    }

    try sendError(ctx, 404, "not found");
}

fn authenticateRequest(reg: *registry.Registry, auth_header: ?[]const u8) !registry.TenantRecord {
    const header = auth_header orelse return error.Unauthorized;
    if (!std.mem.startsWith(u8, header, "Bearer ")) return error.Unauthorized;
    const key = header["Bearer ".len..];
    const key_clean = if (key.len > 0 and key[key.len - 1] == 0) key[0 .. key.len - 1] else key;
    const rec = try reg.lookupByApiKey(key_clean) orelse return error.Unauthorized;
    return rec;
}

fn extractEmailFromBody(body: []const u8) []const u8 {
    const marker = "\"email\"";
    const pos = std.mem.indexOf(u8, body, marker) orelse return "";
    const after_marker = pos + marker.len;
    if (after_marker >= body.len) return "";
    const colon = std.mem.indexOfScalarPos(u8, body, after_marker, ':') orelse return "";
    const value_start_raw = colon + 1;
    var value_start = value_start_raw;
    while (value_start < body.len and (body[value_start] == ' ' or body[value_start] == '\t')) {
        value_start += 1;
    }
    if (value_start >= body.len or body[value_start] != '"') return "";
    const content_start = value_start + 1;
    const content_end = std.mem.indexOfScalarPos(u8, body, content_start, '"') orelse return "";
    return body[content_start..content_end];
}

fn sendHtml(ctx: *ConnCtx, content: []const u8) !void {
    const header = try std.fmt.allocPrint(ctx.server.allocator,
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        .{content.len},
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
    try ctx.conn.stream.writeAll(content);
}

fn sendJson(ctx: *ConnCtx, status: u16, body: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        409 => "Conflict",
        500 => "Internal Server Error",
        else => "OK",
    };
    const header = try std.fmt.allocPrint(ctx.server.allocator,
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nConnection: close\r\n\r\n",
        .{ status, status_text, body.len },
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
    try ctx.conn.stream.writeAll(body);
}

fn sendError(ctx: *ConnCtx, status: u16, msg: []const u8) !void {
    const body = try std.fmt.allocPrint(ctx.server.allocator, "{{\"error\":\"{s}\"}}", .{msg});
    defer ctx.server.allocator.free(body);
    try sendJson(ctx, status, body);
}

fn sendCors(ctx: *ConnCtx, status: u16, _: []const u8, _: []const u8) !void {
    const header = try std.fmt.allocPrint(ctx.server.allocator,
        "HTTP/1.1 {d} No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        .{status},
    );
    defer ctx.server.allocator.free(header);
    try ctx.conn.stream.writeAll(header);
}
