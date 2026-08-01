const std = @import("std");
const registry = @import("cloud/registry.zig");
const process_table = @import("cloud/process_table.zig");
const http_server = @import("cloud/http_server.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var reg = try registry.Registry.init(gpa);
    defer reg.deinit();

    const pt = try process_table.ProcessTable.init(gpa);
    defer pt.deinit();

    const dispatch_thread = try std.Thread.spawn(.{}, runDispatch, .{pt});
    dispatch_thread.detach();

    const port_str = std.process.getEnvVarOwned(gpa, "AGDB_CLOUD_PORT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (port_str) |p| gpa.free(p);

    const port: u16 = if (port_str) |p| std.fmt.parseInt(u16, p, 10) catch 7070 else 7070;

    var server = http_server.CloudServer.init(gpa, &reg, pt, port);
    try server.run();
}

fn runDispatch(pt: *process_table.ProcessTable) void {
    pt.runDispatchLoop() catch |err| {
        std.log.err("dispatch loop exited: {}", .{err});
    };
}
