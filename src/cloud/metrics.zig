const std = @import("std");
const registry = @import("registry.zig");

const METRICS_MAGIC: u32 = 0x4d54_5231;
const METRICS_VERSION: u16 = 1;
const HOUR_BUCKET_COUNT: usize = 24;
const ENDPOINT_CAPACITY: usize = 64;
const AUDIT_EVENT_CAPACITY: usize = 96;
const METHOD_CAPACITY: usize = 8;
const PATH_CAPACITY: usize = 160;
const LATENCY_BOUNDARIES_US = [_]u64{ 1_000, 2_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000, 10_000_000, 30_000_000 };
const LATENCY_BUCKET_COUNT: usize = LATENCY_BOUNDARIES_US.len + 1;
const HOUR_MILLISECONDS: i64 = 60 * 60 * 1000;

const HourBucket = struct {
    hour_start_ms: i64 = 0,
    requests: u64 = 0,
    errors: u64 = 0,
    total_latency_us: u64 = 0,
    max_latency_us: u64 = 0,
    histogram: [LATENCY_BUCKET_COUNT]u64 = [_]u64{0} ** LATENCY_BUCKET_COUNT,
};

const EndpointMetric = struct {
    used: bool = false,
    method_len: u8 = 0,
    path_len: u8 = 0,
    method: [METHOD_CAPACITY]u8 = [_]u8{0} ** METHOD_CAPACITY,
    path: [PATH_CAPACITY]u8 = [_]u8{0} ** PATH_CAPACITY,
    requests: u64 = 0,
    errors: u64 = 0,
    total_latency_us: u64 = 0,
    max_latency_us: u64 = 0,
};

const AuditEvent = struct {
    used: bool = false,
    timestamp_ms: i64 = 0,
    status: u16 = 0,
    latency_us: u64 = 0,
    method_len: u8 = 0,
    path_len: u8 = 0,
    method: [METHOD_CAPACITY]u8 = [_]u8{0} ** METHOD_CAPACITY,
    path: [PATH_CAPACITY]u8 = [_]u8{0} ** PATH_CAPACITY,
};

const TenantMetrics = struct {
    total_requests: u64 = 0,
    total_errors: u64 = 0,
    total_latency_us: u64 = 0,
    max_latency_us: u64 = 0,
    histogram: [LATENCY_BUCKET_COUNT]u64 = [_]u64{0} ** LATENCY_BUCKET_COUNT,
    hourly: [HOUR_BUCKET_COUNT]HourBucket = [_]HourBucket{.{}} ** HOUR_BUCKET_COUNT,
    endpoints: [ENDPOINT_CAPACITY]EndpointMetric = [_]EndpointMetric{.{}} ** ENDPOINT_CAPACITY,
    audit_events: [AUDIT_EVENT_CAPACITY]AuditEvent = [_]AuditEvent{.{}} ** AUDIT_EVENT_CAPACITY,
    audit_next: u16 = 0,
    updated_at_ms: i64 = 0,
};

pub const MetricsStore = struct {
    allocator: std.mem.Allocator,
    reg: *registry.Registry,
    mutex: std.Thread.Mutex,
    tenants: std.AutoHashMap(u64, *TenantMetrics),

    pub fn init(allocator: std.mem.Allocator, reg: *registry.Registry) MetricsStore {
        return .{
            .allocator = allocator,
            .reg = reg,
            .mutex = .{},
            .tenants = std.AutoHashMap(u64, *TenantMetrics).init(allocator),
        };
    }

    pub fn deinit(self: *MetricsStore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var it = self.tenants.iterator();
        while (it.next()) |entry| self.allocator.destroy(entry.value_ptr.*);
        self.tenants.deinit();
    }

    pub fn record(self: *MetricsStore, tenant_id: u64, method: []const u8, path: []const u8, status: u16, latency_us: u64, timestamp_ms: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const metric = try self.ensureTenantLocked(tenant_id);
        const normalized_path = canonicalPath(path);
        const failed = status >= 400;
        metric.total_requests = saturatingAdd(metric.total_requests, 1);
        if (failed) metric.total_errors = saturatingAdd(metric.total_errors, 1);
        metric.total_latency_us = saturatingAdd(metric.total_latency_us, latency_us);
        metric.max_latency_us = @max(metric.max_latency_us, latency_us);
        metric.histogram[latencyBucket(latency_us)] = saturatingAdd(metric.histogram[latencyBucket(latency_us)], 1);
        metric.updated_at_ms = timestamp_ms;

        const hourly = selectHourBucket(metric, timestamp_ms);
        hourly.requests = saturatingAdd(hourly.requests, 1);
        if (failed) hourly.errors = saturatingAdd(hourly.errors, 1);
        hourly.total_latency_us = saturatingAdd(hourly.total_latency_us, latency_us);
        hourly.max_latency_us = @max(hourly.max_latency_us, latency_us);
        hourly.histogram[latencyBucket(latency_us)] = saturatingAdd(hourly.histogram[latencyBucket(latency_us)], 1);

        const endpoint = selectEndpointMetric(metric, method, normalized_path);
        endpoint.requests = saturatingAdd(endpoint.requests, 1);
        if (failed) endpoint.errors = saturatingAdd(endpoint.errors, 1);
        endpoint.total_latency_us = saturatingAdd(endpoint.total_latency_us, latency_us);
        endpoint.max_latency_us = @max(endpoint.max_latency_us, latency_us);

        appendAuditEvent(metric, method, normalized_path, status, latency_us, timestamp_ms);
        try self.persistLocked(tenant_id, metric);
    }

    pub fn analyticsJson(self: *MetricsStore, tenant_id: u64, timestamp_ms: i64) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const metric = try self.ensureTenantLocked(tenant_id);
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();
        const writer = output.writer();
        const current_hour_ms = hourStart(timestamp_ms);
        const period_start_ms = current_hour_ms - @as(i64, HOUR_BUCKET_COUNT - 1) * HOUR_MILLISECONDS;

        try output.appendSlice("{\"period_start_ms\":");
        try writer.print("{d}", .{period_start_ms});
        try output.appendSlice(",\"period_end_ms\":");
        try writer.print("{d}", .{timestamp_ms});
        try output.appendSlice(",\"total_requests\":");
        try writer.print("{d}", .{metric.total_requests});
        try output.appendSlice(",\"total_errors\":");
        try writer.print("{d}", .{metric.total_errors});
        try output.appendSlice(",\"error_rate\":");
        try writer.print("{d:.6}", .{ratio(metric.total_errors, metric.total_requests)});
        try output.appendSlice(",\"error_rate_percent\":");
        try writer.print("{d:.4}", .{percentage(metric.total_errors, metric.total_requests)});
        try output.appendSlice(",\"avg_latency_ms\":");
        try writer.print("{d:.3}", .{averageMilliseconds(metric.total_latency_us, metric.total_requests)});
        try output.appendSlice(",\"p95_latency_ms\":");
        try writer.print("{d}", .{percentileMilliseconds(&metric.histogram, metric.total_requests, 95, metric.max_latency_us)});
        try output.appendSlice(",\"p99_latency_ms\":");
        try writer.print("{d}", .{percentileMilliseconds(&metric.histogram, metric.total_requests, 99, metric.max_latency_us)});
        try output.appendSlice(",\"max_latency_ms\":");
        try writer.print("{d:.3}", .{milliseconds(metric.max_latency_us)});
        try output.appendSlice(",\"updated_at_ms\":");
        try writer.print("{d}", .{metric.updated_at_ms});
        try output.appendSlice(",\"hourly\":[");

        for (0..HOUR_BUCKET_COUNT) |index| {
            if (index > 0) try output.append(',');
            const age: i64 = @intCast(HOUR_BUCKET_COUNT - 1 - index);
            const expected_start = current_hour_ms - age * HOUR_MILLISECONDS;
            const hourly = findHourBucket(metric, expected_start);
            const requests: u64 = if (hourly) |bucket| bucket.requests else 0;
            const errors: u64 = if (hourly) |bucket| bucket.errors else 0;
            const latency: u64 = if (hourly) |bucket| bucket.total_latency_us else 0;
            const maximum: u64 = if (hourly) |bucket| bucket.max_latency_us else 0;
            try output.appendSlice("{\"start_ms\":");
            try writer.print("{d}", .{expected_start});
            try output.appendSlice(",\"requests\":");
            try writer.print("{d}", .{requests});
            try output.appendSlice(",\"errors\":");
            try writer.print("{d}", .{errors});
            try output.appendSlice(",\"avg_latency_ms\":");
            try writer.print("{d:.3}", .{averageMilliseconds(latency, requests)});
            try output.appendSlice(",\"max_latency_ms\":");
            try writer.print("{d:.3}", .{milliseconds(maximum)});
            try output.append('}');
        }

        try output.appendSlice("],\"endpoints\":[");
        var first_endpoint = true;
        for (metric.endpoints) |endpoint| {
            if (!endpoint.used or endpoint.requests == 0) continue;
            if (!first_endpoint) try output.append(',');
            first_endpoint = false;
            try output.appendSlice("{\"method\":");
            try appendJsonString(&output, endpoint.method[0..endpoint.method_len]);
            try output.appendSlice(",\"path\":");
            try appendJsonString(&output, endpoint.path[0..endpoint.path_len]);
            try output.appendSlice(",\"requests\":");
            try writer.print("{d}", .{endpoint.requests});
            try output.appendSlice(",\"errors\":");
            try writer.print("{d}", .{endpoint.errors});
            try output.appendSlice(",\"error_rate\":");
            try writer.print("{d:.6}", .{ratio(endpoint.errors, endpoint.requests)});
            try output.appendSlice(",\"error_rate_percent\":");
            try writer.print("{d:.4}", .{percentage(endpoint.errors, endpoint.requests)});
            try output.appendSlice(",\"avg_latency_ms\":");
            try writer.print("{d:.3}", .{averageMilliseconds(endpoint.total_latency_us, endpoint.requests)});
            try output.appendSlice(",\"max_latency_ms\":");
            try writer.print("{d:.3}", .{milliseconds(endpoint.max_latency_us)});
            try output.append('}');
        }
        try output.appendSlice("]}");
        return output.toOwnedSlice();
    }

    pub fn auditJson(self: *MetricsStore, tenant_id: u64) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const metric = try self.ensureTenantLocked(tenant_id);
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();
        const writer = output.writer();
        try output.appendSlice("{\"events\":[");
        var scanned: usize = 0;
        var index: usize = metric.audit_next;
        var first_event = true;
        while (scanned < AUDIT_EVENT_CAPACITY) : (scanned += 1) {
            index = if (index == 0) AUDIT_EVENT_CAPACITY - 1 else index - 1;
            const event = metric.audit_events[index];
            if (!event.used) continue;
            if (!first_event) try output.append(',');
            first_event = false;
            try output.appendSlice("{\"timestamp_ms\":");
            try writer.print("{d}", .{event.timestamp_ms});
            try output.appendSlice(",\"method\":");
            try appendJsonString(&output, event.method[0..event.method_len]);
            try output.appendSlice(",\"path\":");
            try appendJsonString(&output, event.path[0..event.path_len]);
            try output.appendSlice(",\"status\":");
            try writer.print("{d}", .{event.status});
            try output.appendSlice(",\"latency_ms\":");
            try writer.print("{d:.3}", .{milliseconds(event.latency_us)});
            try output.append('}');
        }
        try output.appendSlice("]}");
        return output.toOwnedSlice();
    }

    fn ensureTenantLocked(self: *MetricsStore, tenant_id: u64) !*TenantMetrics {
        if (self.tenants.get(tenant_id)) |metric| return metric;
        const metric = try self.allocator.create(TenantMetrics);
        errdefer self.allocator.destroy(metric);
        metric.* = self.load(tenant_id) catch .{};
        try self.tenants.put(tenant_id, metric);
        return metric;
    }

    fn load(self: *MetricsStore, tenant_id: u64) !TenantMetrics {
        var key_buffer: [64]u8 = undefined;
        const key = try metricStorageKey(&key_buffer, tenant_id);
        const encoded = try self.reg.getKV(self.allocator, key) orelse return .{};
        defer self.allocator.free(encoded);
        return try decode(encoded);
    }

    fn persistLocked(self: *MetricsStore, tenant_id: u64, metric: *const TenantMetrics) !void {
        var key_buffer: [64]u8 = undefined;
        const key = try metricStorageKey(&key_buffer, tenant_id);
        const encoded = try encode(self.allocator, metric);
        defer self.allocator.free(encoded);
        try self.reg.storeKV(key, encoded);
    }
};

fn canonicalPath(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "/v1/databases/") and std.mem.indexOf(u8, path, "/records/") != null) return "/v1/databases/{database}/records/{id}";
    if (std.mem.startsWith(u8, path, "/v1/databases/") and std.mem.endsWith(u8, path, "/records")) return "/v1/databases/{database}/records";
    if (std.mem.startsWith(u8, path, "/v1/databases/") and std.mem.endsWith(u8, path, "/query")) return "/v1/databases/{database}/query";
    if (std.mem.startsWith(u8, path, "/v1/databases/") and std.mem.endsWith(u8, path, "/search")) return "/v1/databases/{database}/search";
    if (std.mem.startsWith(u8, path, "/v1/databases/") and std.mem.endsWith(u8, path, "/stats")) return "/v1/databases/{database}/stats";
    if (std.mem.startsWith(u8, path, "/v1/apikeys/") and std.mem.endsWith(u8, path, "/rotate")) return "/v1/apikeys/{id}/rotate";
    if (std.mem.startsWith(u8, path, "/v1/apikeys/")) return "/v1/apikeys/{id}";
    return path;
}

fn selectHourBucket(metric: *TenantMetrics, timestamp_ms: i64) *HourBucket {
    const start_ms = hourStart(timestamp_ms);
    var empty: ?*HourBucket = null;
    var oldest: *HourBucket = &metric.hourly[0];
    for (&metric.hourly) |*bucket| {
        if (bucket.hour_start_ms == start_ms) return bucket;
        if (bucket.hour_start_ms == 0 and empty == null) empty = bucket;
        if (bucket.hour_start_ms < oldest.hour_start_ms) oldest = bucket;
    }
    const selected = empty orelse oldest;
    selected.* = .{ .hour_start_ms = start_ms };
    return selected;
}

fn findHourBucket(metric: *const TenantMetrics, start_ms: i64) ?*const HourBucket {
    for (&metric.hourly) |*bucket| {
        if (bucket.hour_start_ms == start_ms) return bucket;
    }
    return null;
}

fn selectEndpointMetric(metric: *TenantMetrics, method: []const u8, path: []const u8) *EndpointMetric {
    var empty: ?*EndpointMetric = null;
    for (metric.endpoints[0 .. ENDPOINT_CAPACITY - 1]) |*endpoint| {
        if (!endpoint.used) {
            if (empty == null) empty = endpoint;
            continue;
        }
        if (textEquals(endpoint.method[0..endpoint.method_len], method) and textEquals(endpoint.path[0..endpoint.path_len], path)) return endpoint;
    }
    if (empty) |selected| {
        selected.* = .{};
        selected.used = true;
        selected.method_len = copyText(&selected.method, method);
        selected.path_len = copyText(&selected.path, path);
        return selected;
    }
    const overflow = &metric.endpoints[ENDPOINT_CAPACITY - 1];
    if (!overflow.used) {
        overflow.* = .{};
        overflow.used = true;
        overflow.method_len = copyText(&overflow.method, "*");
        overflow.path_len = copyText(&overflow.path, "/v1/other");
    }
    return overflow;
}

fn appendAuditEvent(metric: *TenantMetrics, method: []const u8, path: []const u8, status: u16, latency_us: u64, timestamp_ms: i64) void {
    const index: usize = metric.audit_next;
    var event = &metric.audit_events[index];
    event.* = .{};
    event.used = true;
    event.timestamp_ms = timestamp_ms;
    event.status = status;
    event.latency_us = latency_us;
    event.method_len = copyText(&event.method, method);
    event.path_len = copyText(&event.path, path);
    metric.audit_next = @intCast((index + 1) % AUDIT_EVENT_CAPACITY);
}

fn hourStart(timestamp_ms: i64) i64 {
    return @divFloor(timestamp_ms, HOUR_MILLISECONDS) * HOUR_MILLISECONDS;
}

fn latencyBucket(latency_us: u64) usize {
    for (LATENCY_BOUNDARIES_US, 0..) |boundary, index| {
        if (latency_us <= boundary) return index;
    }
    return LATENCY_BUCKET_COUNT - 1;
}

fn percentileMilliseconds(histogram: *const [LATENCY_BUCKET_COUNT]u64, total: u64, percentile: u64, maximum_us: u64) u64 {
    if (total == 0) return 0;
    const target = (total * percentile + 99) / 100;
    var cumulative: u64 = 0;
    for (histogram.*, 0..) |count, index| {
        cumulative = saturatingAdd(cumulative, count);
        if (cumulative >= target) {
            if (index < LATENCY_BOUNDARIES_US.len) return (LATENCY_BOUNDARIES_US[index] + 999) / 1000;
            return (maximum_us + 999) / 1000;
        }
    }
    return (maximum_us + 999) / 1000;
}

fn averageMilliseconds(total_latency_us: u64, requests: u64) f64 {
    if (requests == 0) return 0;
    return @as(f64, @floatFromInt(total_latency_us)) / @as(f64, @floatFromInt(requests)) / 1000.0;
}

fn milliseconds(latency_us: u64) f64 {
    return @as(f64, @floatFromInt(latency_us)) / 1000.0;
}

fn ratio(part: u64, total: u64) f64 {
    if (total == 0) return 0;
    return @as(f64, @floatFromInt(part)) / @as(f64, @floatFromInt(total));
}

fn percentage(part: u64, total: u64) f64 {
    return ratio(part, total) * 100.0;
}

fn saturatingAdd(current: u64, value: u64) u64 {
    return std.math.add(u64, current, value) catch std.math.maxInt(u64);
}

fn textEquals(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}

fn copyText(destination: []u8, source: []const u8) u8 {
    @memset(destination, 0);
    const length = @min(destination.len, source.len);
    @memcpy(destination[0..length], source[0..length]);
    return @intCast(length);
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

fn metricStorageKey(buffer: []u8, tenant_id: u64) ![]u8 {
    return std.fmt.bufPrint(buffer, "metrics:v1:{d}", .{tenant_id});
}

fn encode(allocator: std.mem.Allocator, metric: *const TenantMetrics) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const writer = output.writer();
    try writer.writeInt(u32, METRICS_MAGIC, .little);
    try writer.writeInt(u16, METRICS_VERSION, .little);
    try writer.writeInt(u64, metric.total_requests, .little);
    try writer.writeInt(u64, metric.total_errors, .little);
    try writer.writeInt(u64, metric.total_latency_us, .little);
    try writer.writeInt(u64, metric.max_latency_us, .little);
    for (metric.histogram) |value| try writer.writeInt(u64, value, .little);
    try writer.writeInt(i64, metric.updated_at_ms, .little);
    try writer.writeInt(u16, metric.audit_next, .little);

    for (metric.hourly) |bucket| {
        try writer.writeInt(i64, bucket.hour_start_ms, .little);
        try writer.writeInt(u64, bucket.requests, .little);
        try writer.writeInt(u64, bucket.errors, .little);
        try writer.writeInt(u64, bucket.total_latency_us, .little);
        try writer.writeInt(u64, bucket.max_latency_us, .little);
        for (bucket.histogram) |value| try writer.writeInt(u64, value, .little);
    }

    for (metric.endpoints) |endpoint| {
        try writer.writeInt(u8, if (endpoint.used) 1 else 0, .little);
        try writer.writeInt(u8, endpoint.method_len, .little);
        try writer.writeInt(u8, endpoint.path_len, .little);
        try writer.writeAll(endpoint.method[0..]);
        try writer.writeAll(endpoint.path[0..]);
        try writer.writeInt(u64, endpoint.requests, .little);
        try writer.writeInt(u64, endpoint.errors, .little);
        try writer.writeInt(u64, endpoint.total_latency_us, .little);
        try writer.writeInt(u64, endpoint.max_latency_us, .little);
    }

    for (metric.audit_events) |event| {
        try writer.writeInt(u8, if (event.used) 1 else 0, .little);
        try writer.writeInt(i64, event.timestamp_ms, .little);
        try writer.writeInt(u16, event.status, .little);
        try writer.writeInt(u64, event.latency_us, .little);
        try writer.writeInt(u8, event.method_len, .little);
        try writer.writeInt(u8, event.path_len, .little);
        try writer.writeAll(event.method[0..]);
        try writer.writeAll(event.path[0..]);
    }
    return output.toOwnedSlice();
}

fn decode(encoded: []const u8) !TenantMetrics {
    var stream = std.io.fixedBufferStream(encoded);
    const reader = stream.reader();
    if (try reader.readInt(u32, .little) != METRICS_MAGIC) return error.InvalidMetrics;
    if (try reader.readInt(u16, .little) != METRICS_VERSION) return error.InvalidMetrics;

    var metric: TenantMetrics = .{};
    metric.total_requests = try reader.readInt(u64, .little);
    metric.total_errors = try reader.readInt(u64, .little);
    metric.total_latency_us = try reader.readInt(u64, .little);
    metric.max_latency_us = try reader.readInt(u64, .little);
    for (&metric.histogram) |*value| value.* = try reader.readInt(u64, .little);
    metric.updated_at_ms = try reader.readInt(i64, .little);
    metric.audit_next = try reader.readInt(u16, .little);
    if (@as(usize, metric.audit_next) >= AUDIT_EVENT_CAPACITY) return error.InvalidMetrics;

    for (&metric.hourly) |*bucket| {
        bucket.hour_start_ms = try reader.readInt(i64, .little);
        bucket.requests = try reader.readInt(u64, .little);
        bucket.errors = try reader.readInt(u64, .little);
        bucket.total_latency_us = try reader.readInt(u64, .little);
        bucket.max_latency_us = try reader.readInt(u64, .little);
        for (&bucket.histogram) |*value| value.* = try reader.readInt(u64, .little);
    }

    for (&metric.endpoints) |*endpoint| {
        const used = try reader.readInt(u8, .little);
        if (used > 1) return error.InvalidMetrics;
        endpoint.used = used == 1;
        endpoint.method_len = try reader.readInt(u8, .little);
        endpoint.path_len = try reader.readInt(u8, .little);
        if (@as(usize, endpoint.method_len) > METHOD_CAPACITY or @as(usize, endpoint.path_len) > PATH_CAPACITY) return error.InvalidMetrics;
        try reader.readNoEof(endpoint.method[0..]);
        try reader.readNoEof(endpoint.path[0..]);
        endpoint.requests = try reader.readInt(u64, .little);
        endpoint.errors = try reader.readInt(u64, .little);
        endpoint.total_latency_us = try reader.readInt(u64, .little);
        endpoint.max_latency_us = try reader.readInt(u64, .little);
    }

    for (&metric.audit_events) |*event| {
        const used = try reader.readInt(u8, .little);
        if (used > 1) return error.InvalidMetrics;
        event.used = used == 1;
        event.timestamp_ms = try reader.readInt(i64, .little);
        event.status = try reader.readInt(u16, .little);
        event.latency_us = try reader.readInt(u64, .little);
        event.method_len = try reader.readInt(u8, .little);
        event.path_len = try reader.readInt(u8, .little);
        if (@as(usize, event.method_len) > METHOD_CAPACITY or @as(usize, event.path_len) > PATH_CAPACITY) return error.InvalidMetrics;
        try reader.readNoEof(event.method[0..]);
        try reader.readNoEof(event.path[0..]);
    }
    return metric;
}

test "metric serialization preserves hourly endpoint and audit data" {
    const testing = std.testing;
    const timestamp_ms: i64 = 1_734_600_000_000;
    var metric: TenantMetrics = .{};
    metric.total_requests = 2;
    metric.total_errors = 1;
    metric.total_latency_us = 6_000;
    metric.max_latency_us = 5_000;
    metric.histogram[latencyBucket(1_000)] = 1;
    metric.histogram[latencyBucket(5_000)] = 1;
    metric.updated_at_ms = timestamp_ms;

    const hourly = selectHourBucket(&metric, timestamp_ms);
    hourly.requests = 2;
    hourly.errors = 1;
    hourly.total_latency_us = 6_000;
    hourly.max_latency_us = 5_000;
    hourly.histogram[latencyBucket(1_000)] = 1;
    hourly.histogram[latencyBucket(5_000)] = 1;

    const endpoint = selectEndpointMetric(&metric, "GET", "/v1/databases/documents/records/42");
    endpoint.requests = 2;
    endpoint.errors = 1;
    endpoint.total_latency_us = 6_000;
    endpoint.max_latency_us = 5_000;
    appendAuditEvent(&metric, "GET", "/v1/databases/{database}/records/{id}", 404, 5_000, timestamp_ms);

    const encoded = try encode(testing.allocator, &metric);
    defer testing.allocator.free(encoded);
    const decoded = try decode(encoded);

    try testing.expectEqual(@as(u64, 2), decoded.total_requests);
    try testing.expectEqual(@as(u64, 1), decoded.total_errors);
    try testing.expectEqual(@as(u64, 6_000), decoded.total_latency_us);
    try testing.expectEqual(@as(i64, hourStart(timestamp_ms)), decoded.hourly[0].hour_start_ms);
    try testing.expect(decoded.endpoints[0].used);
    try testing.expectEqualStrings("GET", decoded.endpoints[0].method[0..decoded.endpoints[0].method_len]);
    try testing.expectEqualStrings("/v1/databases/documents/records/42", decoded.endpoints[0].path[0..decoded.endpoints[0].path_len]);
    try testing.expect(decoded.audit_events[0].used);
    try testing.expectEqual(@as(u16, 404), decoded.audit_events[0].status);
}

test "metric route normalization preserves bounded endpoint cardinality" {
    const testing = std.testing;
    try testing.expectEqualStrings("/v1/databases/{database}/records/{id}", canonicalPath("/v1/databases/documents/records/998"));
    try testing.expectEqualStrings("/v1/apikeys/{id}/rotate", canonicalPath("/v1/apikeys/primary/rotate"));
}
