const std = @import("std");

// Shuts down the VPS after IDLE_SECONDS of no nginx traffic.
// Reads /var/log/nginx/access.log and checks the timestamp of the last line.

const IDLE_SECONDS: i64 = 15 * 60;
const CHECK_INTERVAL_SECONDS: u64 = 60;
const ACCESS_LOG = "/var/log/nginx/access.log";

// Nginx default log format:
// 1.2.3.4 - - [05/Jun/2026:14:32:01 +0000] "GET / HTTP/1.1" 200 194607 ...
// Returns unix timestamp of last log entry, or null on error.
fn parseLastAccessTime(allocator: std.mem.Allocator) !i64 {
    const file = try std.fs.openFileAbsolute(ACCESS_LOG, .{});
    defer file.close();

    const size = (try file.stat()).size;
    if (size == 0) return error.EmptyLog;

    // Read last 512 bytes to find last line
    const read_size: u64 = @min(size, 512);
    try file.seekTo(size - read_size);
    const buf = try allocator.alloc(u8, read_size);
    defer allocator.free(buf);
    const n = try file.readAll(buf);
    const data = buf[0..n];

    // Find last complete line
    const last_newline = std.mem.lastIndexOfScalar(u8, data, '\n') orelse 0;
    const search_end = if (last_newline == data.len - 1)
        std.mem.lastIndexOfScalar(u8, data[0 .. data.len - 1], '\n') orelse 0
    else
        last_newline;

    const last_line = blk: {
        const start = if (search_end > 0) search_end + 1 else 0;
        const end = if (last_newline == data.len - 1) data.len - 1 else data.len;
        break :blk data[start..end];
    };

    if (last_line.len == 0) return error.NoLine;

    // Find timestamp: [DD/Mon/YYYY:HH:MM:SS +ZONE]
    const open = std.mem.indexOfScalar(u8, last_line, '[') orelse return error.NoTimestamp;
    const close = std.mem.indexOfScalar(u8, last_line[open..], ']') orelse return error.NoTimestamp;
    const ts_str = last_line[open + 1 .. open + close];
    // ts_str = "05/Jun/2026:14:32:01 +0000"
    return parseNginxTimestamp(ts_str);
}

const MONTHS = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

fn parseNginxTimestamp(ts: []const u8) !i64 {
    // Format: DD/Mon/YYYY:HH:MM:SS +ZONE
    if (ts.len < 20) return error.ShortTimestamp;

    const day = try std.fmt.parseInt(u32, ts[0..2], 10);
    const mon_str = ts[3..6];
    const year = try std.fmt.parseInt(u32, ts[7..11], 10);
    const hour = try std.fmt.parseInt(u32, ts[12..14], 10);
    const min = try std.fmt.parseInt(u32, ts[15..17], 10);
    const sec = try std.fmt.parseInt(u32, ts[18..20], 10);

    var month: u32 = 0;
    for (MONTHS, 0..) |m, i| {
        if (std.mem.eql(u8, mon_str, m)) {
            month = @intCast(i + 1);
            break;
        }
    }
    if (month == 0) return error.BadMonth;

    // Simple UTC epoch calculation (ignores timezone offset, good enough for idle check)
    const days_since_epoch = daysFromYMD(year, month, day);
    const epoch_seconds: i64 = @as(i64, days_since_epoch) * 86400 +
        @as(i64, hour) * 3600 +
        @as(i64, min) * 60 +
        @as(i64, sec);
    return epoch_seconds;
}

fn daysFromYMD(y: u32, m: u32, d: u32) u32 {
    // Days from 1970-01-01 to y-m-d (Gregorian, UTC)
    var yy: i32 = @intCast(y);
    var mm: i32 = @intCast(m);
    if (mm <= 2) {
        yy -= 1;
        mm += 9;
    } else {
        mm -= 3;
    }
    const era: i32 = @divFloor(yy, 400);
    const yoe: i32 = yy - era * 400;
    const doy: i32 = @divTrunc(153 * mm + 2, 5) + @as(i32, @intCast(d)) - 1;
    const doe: i32 = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy;
    const days: i32 = era * 146097 + doe - 719468;
    return @intCast(@max(0, days));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("agdb-autoshutdown started (idle timeout: {d} min)", .{IDLE_SECONDS / 60});

    while (true) {
        std.time.sleep(CHECK_INTERVAL_SECONDS * std.time.ns_per_s);

        const now: i64 = std.time.timestamp();
        const last_access = parseLastAccessTime(allocator) catch |err| {
            std.log.warn("Could not read access log: {} — skipping check", .{err});
            continue;
        };

        const idle = now - last_access;
        std.log.info("Last access {d}s ago (idle limit: {d}s)", .{ idle, IDLE_SECONDS });

        if (idle >= IDLE_SECONDS) {
            std.log.info("Idle timeout reached — shutting down.", .{});
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "sudo", "systemctl", "poweroff" },
            }) catch |err| {
                std.log.err("poweroff failed: {}", .{err});
                continue;
            };
            if (result.term != .Exited) {
                std.log.err("poweroff exit: {}", .{result.term});
            }
        }
    }
}
