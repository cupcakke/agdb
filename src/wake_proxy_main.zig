const std = @import("std");

const OVH_HOST = "ca.api.ovh.com";
const OVH_BASE = "/1.0";
const PROJECT_ID = "5ec8a5b1d206437a93f95d444a91e4b3";
const INSTANCE_ID = "a99a85a1-07d0-4c4f-b51e-d0fae9e29472";
const VPS_HOST = "91.134.72.253";
const VPS_PORT: u16 = 80;
const HEALTH_PATH = "/v1/health";
const IDLE_SECONDS: u64 = 15 * 60;

const WAITING_HTML =
    \\<!DOCTYPE html>
    \\<html lang="hu">
    \\<head><meta charset="UTF-8">
    \\<meta http-equiv="refresh" content="8">
    \\<title>Szerver indul...</title>
    \\<style>
    \\body{font-family:system-ui,sans-serif;display:flex;align-items:center;
    \\     justify-content:center;min-height:100vh;margin:0;background:#0f172a;color:#e2e8f0}
    \\.card{text-align:center;padding:3rem;max-width:400px}
    \\.spinner{width:48px;height:48px;border:4px solid #334155;border-top-color:#60a5fa;
    \\         border-radius:50%;animation:spin 1s linear infinite;margin:0 auto 2rem}
    \\@keyframes spin{to{transform:rotate(360deg)}}
    \\h1{font-size:1.5rem;margin:0 0 .5rem}p{color:#94a3b8;margin:0 0 1.5rem}
    \\small{color:#64748b}
    \\</style></head>
    \\<body><div class="card">
    \\<div class="spinner"></div>
    \\<h1>Szerver indul...</h1>
    \\<p>A szerver éppen feléled, ez kb. 30-60 másodperc.</p>
    \\<small>Az oldal automatikusan frissül.</small>
    \\</div></body></html>
;

// Shared waking state (atomic)
var g_waking = std.atomic.Value(bool).init(false);
var g_allocator: std.mem.Allocator = undefined;

const Env = struct {
    app_key: []const u8,
    app_secret: []const u8,
    consumer_key: []const u8,
    port: u16,
};

fn getEnv() !Env {
    return .{
        .app_key = std.posix.getenv("OVH_APP_KEY") orelse return error.MissingOvhAppKey,
        .app_secret = std.posix.getenv("OVH_APP_SECRET") orelse return error.MissingOvhAppSecret,
        .consumer_key = std.posix.getenv("OVH_CONSUMER_KEY") orelse return error.MissingOvhConsumerKey,
        .port = blk: {
            const p = std.posix.getenv("PORT") orelse "5000";
            break :blk std.fmt.parseInt(u16, p, 10) catch 5000;
        },
    };
}

fn hexDigit(v: u8) u8 {
    return if (v < 10) '0' + v else 'a' + v - 10;
}

fn sha1Hex(input: []const u8, out: *[40]u8) void {
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(input);
    const digest = h.finalResult();
    for (digest, 0..) |byte, i| {
        out[i * 2] = hexDigit(byte >> 4);
        out[i * 2 + 1] = hexDigit(byte & 0xf);
    }
}

fn ovhPost(allocator: std.mem.Allocator, env: Env, path: []const u8) !void {
    const now = std.time.timestamp();
    const now_str = try std.fmt.allocPrint(allocator, "{d}", .{now});
    defer allocator.free(now_str);

    const full_url = try std.fmt.allocPrint(allocator, "https://{s}{s}{s}", .{ OVH_HOST, OVH_BASE, path });
    defer allocator.free(full_url);

    const to_sign = try std.fmt.allocPrint(allocator, "{s}+{s}+POST+{s}++{s}", .{
        env.app_secret, env.consumer_key, full_url, now_str,
    });
    defer allocator.free(to_sign);

    var hex: [40]u8 = undefined;
    sha1Hex(to_sign, &hex);
    const sig = try std.fmt.allocPrint(allocator, "$1${s}", .{hex});
    defer allocator.free(sig);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(full_url);
    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .extra_headers = &.{
            .{ .name = "X-Ovh-Application", .value = env.app_key },
            .{ .name = "X-Ovh-Consumer", .value = env.consumer_key },
            .{ .name = "X-Ovh-Timestamp", .value = now_str },
            .{ .name = "X-Ovh-Signature", .value = sig },
            .{ .name = "Content-Type", .value = "application/json" },
        },
    });
    defer req.deinit();
    try req.send();
    try req.finish();
    try req.wait();
    std.log.info("OVH start response: {d}", .{req.response.status});
}

fn isVpsUp() bool {
    // Use a raw non-blocking TCP connect with a 3-second poll timeout.
    // Avoids std.http.Client entirely (which crashes in Zig 0.14 on certain
    // deployment environments) and guarantees we never hang indefinitely.
    const addr = std.net.Address.parseIp4(VPS_HOST, VPS_PORT) catch return false;
    const sock = std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
        std.posix.IPPROTO.TCP,
    ) catch return false;
    defer std.posix.close(sock);

    std.posix.connect(sock, &addr.any, addr.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock => {}, // expected: connect in progress on non-blocking socket
        else => return false,
    };

    // Wait up to 3 seconds for the connection to complete.
    var pfd = [1]std.posix.pollfd{.{
        .fd = sock,
        .events = std.posix.POLL.OUT,
        .revents = 0,
    }};
    const n = std.posix.poll(&pfd, 3000) catch return false;
    if (n == 0) return false; // timeout
    if (pfd[0].revents & std.posix.POLL.ERR != 0) return false; // connect failed
    return pfd[0].revents & std.posix.POLL.OUT != 0;
}

const WakeCtx = struct {
    env: Env,
};

fn wakeThread(ctx: WakeCtx) void {
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.log.info("Waking VPS instance...", .{});

    const path = "/cloud/project/" ++ PROJECT_ID ++ "/instance/" ++ INSTANCE_ID ++ "/start";
    ovhPost(allocator, ctx.env, path) catch |err| {
        std.log.err("OVH start error: {}", .{err});
        g_waking.store(false, .release);
        return;
    };

    std.log.info("Start command sent, polling for VPS...", .{});
    var attempts: u32 = 0;
    while (attempts < 60) : (attempts += 1) {
        std.time.sleep(5 * std.time.ns_per_s);
        if (isVpsUp()) {
            std.log.info("VPS is up after {d} attempts!", .{attempts + 1});
            break;
        }
    }

    g_waking.store(false, .release);
}

const ConnCtx = struct {
    conn: std.net.Server.Connection,
    env: Env,
};

fn sendWaitingPage(stream: std.net.Stream) void {
    const body = WAITING_HTML;
    const response = std.fmt.comptimePrint(
        "HTTP/1.1 503 Service Unavailable\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Retry-After: 10\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
        .{ body.len, body },
    );
    _ = stream.write(response) catch {};
}

fn proxyRequest(allocator: std.mem.Allocator, method_str: []const u8, path: []const u8, req_headers: []const u8, req_body: []const u8, stream: std.net.Stream) void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{ VPS_HOST, VPS_PORT, path }) catch return;
    defer allocator.free(url);

    const uri = std.Uri.parse(url) catch return;

    const method: std.http.Method = blk: {
        if (std.mem.eql(u8, method_str, "GET")) break :blk .GET;
        if (std.mem.eql(u8, method_str, "POST")) break :blk .POST;
        if (std.mem.eql(u8, method_str, "PUT")) break :blk .PUT;
        if (std.mem.eql(u8, method_str, "DELETE")) break :blk .DELETE;
        if (std.mem.eql(u8, method_str, "PATCH")) break :blk .PATCH;
        if (std.mem.eql(u8, method_str, "HEAD")) break :blk .HEAD;
        if (std.mem.eql(u8, method_str, "OPTIONS")) break :blk .OPTIONS;
        break :blk .GET;
    };

    // Pass through relevant headers
    var extra_headers = std.ArrayList(std.http.Header).init(allocator);
    defer extra_headers.deinit();

    var hlines = std.mem.splitSequence(u8, req_headers, "\r\n");
    _ = hlines.next(); // skip request line
    while (hlines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOf(u8, line, ": ") orelse continue;
        const name = line[0..colon];
        const value = line[colon + 2 ..];
        const lower = std.ascii.lowerString(allocator.alloc(u8, name.len) catch continue, name);
        if (std.mem.eql(u8, lower, "host") or
            std.mem.eql(u8, lower, "connection") or
            std.mem.eql(u8, lower, "transfer-encoding")) continue;
        extra_headers.append(.{ .name = name, .value = value }) catch continue;
    }

    var header_buf: [65536]u8 = undefined;
    var proxy_req = client.open(method, uri, .{
        .server_header_buffer = &header_buf,
        .extra_headers = extra_headers.items,
    }) catch {
        sendError(stream, 502, "Bad Gateway");
        return;
    };
    defer proxy_req.deinit();

    if (req_body.len > 0) {
        proxy_req.transfer_encoding = .{ .content_length = req_body.len };
    }

    proxy_req.send() catch {
        sendError(stream, 502, "Bad Gateway");
        return;
    };
    if (req_body.len > 0) {
        proxy_req.writeAll(req_body) catch {};
    }
    proxy_req.finish() catch {};
    proxy_req.wait() catch {
        sendError(stream, 502, "Bad Gateway");
        return;
    };

    const status_code = @intFromEnum(proxy_req.response.status);
    const resp_body = proxy_req.reader().readAllAlloc(allocator, 64 * 1024 * 1024) catch "";

    const resp_head = std.fmt.allocPrint(allocator, "HTTP/1.1 {d} OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status_code, resp_body.len }) catch return;
    defer allocator.free(resp_head);
    _ = stream.write(resp_head) catch {};
    _ = stream.write(resp_body) catch {};
}

fn sendError(stream: std.net.Stream, code: u16, msg: []const u8) void {
    const resp = std.fmt.allocPrint(g_allocator, "HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ code, msg, msg.len, msg }) catch return;
    defer g_allocator.free(resp);
    _ = stream.write(resp) catch {};
}

fn handleConn(ctx: *ConnCtx) void {
    // destroy runs LAST (registered first), close runs FIRST (registered second)
    defer g_allocator.destroy(ctx);
    defer ctx.conn.stream.close();

    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buf: [131072]u8 = undefined;
    var total: usize = 0;

    while (total < buf.len) {
        const n = ctx.conn.stream.read(buf[total..]) catch break;
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
    }
    if (total == 0) return;

    const raw = buf[0..total];
    const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return;
    const header_section = raw[0..header_end];

    var lines = std.mem.splitSequence(u8, header_section, "\r\n");
    const req_line = lines.next() orelse return;
    var parts = std.mem.splitScalar(u8, req_line, ' ');
    const method = parts.next() orelse return;
    const path = parts.next() orelse return;

    // Content-Length for body
    var content_length: usize = 0;
    var hiter = std.mem.splitSequence(u8, header_section, "\r\n");
    _ = hiter.next();
    while (hiter.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            const val = std.mem.trimLeft(u8, line[15..], " ");
            content_length = std.fmt.parseInt(usize, val, 10) catch 0;
        }
    }

    const body_start = header_end + 4;
    var req_body: []const u8 = &.{};
    if (content_length > 0 and body_start < total) {
        req_body = raw[body_start..@min(total, body_start + content_length)];
    }

    // Check VPS
    if (!isVpsUp()) {
        // Try to wake if not already waking
        if (!g_waking.swap(true, .acq_rel)) {
            const wake_ctx = WakeCtx{ .env = ctx.env };
            if (std.Thread.spawn(.{}, wakeThread, .{wake_ctx})) |t| {
                t.detach();
            } else |_| {
                g_waking.store(false, .release);
            }
        }
        sendWaitingPage(ctx.conn.stream);
        return;
    }

    proxyRequest(allocator, method, path, header_section, req_body, ctx.conn.stream);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    g_allocator = gpa.allocator();

    const env = getEnv() catch |err| {
        std.log.err("Missing environment variable: {}", .{err});
        std.process.exit(1);
    };

    const addr = try std.net.Address.parseIp4("0.0.0.0", env.port);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.log.info("agdb wake-proxy listening on port {d}", .{env.port});
    std.log.info("VPS: {s}:{d}", .{ VPS_HOST, VPS_PORT });

    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("accept error: {}", .{err});
            continue;
        };
        const ctx = g_allocator.create(ConnCtx) catch {
            conn.stream.close();
            continue;
        };
        ctx.* = .{ .conn = conn, .env = env };
        if (std.Thread.spawn(.{}, handleConn, .{ctx})) |t| {
            t.detach();
        } else |_| {
            conn.stream.close();
            g_allocator.destroy(ctx);
        }
    }
}
