const std = @import("std");

pub const Method = enum {
    get,
    head,
    post,
    put,
    patch,
    delete,
    options,
    trace,
    connect,

    pub fn fromSlice(text: []const u8) ?Method {
        if (std.mem.eql(u8, text, "GET")) return .get;
        if (std.mem.eql(u8, text, "HEAD")) return .head;
        if (std.mem.eql(u8, text, "POST")) return .post;
        if (std.mem.eql(u8, text, "PUT")) return .put;
        if (std.mem.eql(u8, text, "PATCH")) return .patch;
        if (std.mem.eql(u8, text, "DELETE")) return .delete;
        if (std.mem.eql(u8, text, "OPTIONS")) return .options;
        if (std.mem.eql(u8, text, "TRACE")) return .trace;
        if (std.mem.eql(u8, text, "CONNECT")) return .connect;
        return null;
    }

    pub fn toSlice(self: Method) []const u8 {
        return switch (self) {
            .get => "GET",
            .head => "HEAD",
            .post => "POST",
            .put => "PUT",
            .patch => "PATCH",
            .delete => "DELETE",
            .options => "OPTIONS",
            .trace => "TRACE",
            .connect => "CONNECT",
        };
    }

    pub fn bodyForbidden(self: Method) bool {
        return self == .trace;
    }
};

pub const Version = enum {
    http_1_0,
    http_1_1,

    pub fn defaultKeepAlive(self: Version) bool {
        return self == .http_1_1;
    }

    pub fn toSlice(self: Version) []const u8 {
        return switch (self) {
            .http_1_0 => "HTTP/1.0",
            .http_1_1 => "HTTP/1.1",
        };
    }
};

pub const ParseError = error{
    MalformedRequestLine,
    UnsupportedMethod,
    InvalidTarget,
    TargetTooLong,
    UnsupportedVersion,
    MalformedHeader,
    ObsoleteLineFolding,
    HeaderTooLarge,
    TooManyHeaders,
    DuplicateContentLength,
    ConflictingFraming,
    InvalidContentLength,
    UnsupportedTransferEncoding,
    InvalidChunkSize,
    InvalidChunkTerminator,
    ChunkTooLarge,
    BodyTooLarge,
    MissingHost,
    RequestLineTooLong,
    BodyNotAllowed,
    TrailerTooLarge,
};

pub const Error = ParseError || error{OutOfMemory};

pub fn statusForError(err: ParseError) u16 {
    return switch (err) {
        ParseError.UnsupportedMethod => 501,
        ParseError.UnsupportedTransferEncoding => 501,
        ParseError.UnsupportedVersion => 505,
        ParseError.TargetTooLong, ParseError.RequestLineTooLong => 414,
        ParseError.HeaderTooLarge, ParseError.TooManyHeaders, ParseError.TrailerTooLarge => 431,
        ParseError.BodyTooLarge, ParseError.ChunkTooLarge => 413,
        else => 400,
    };
}

pub const Limits = struct {
    max_request_line: usize = 8 * 1024,
    max_target: usize = 4 * 1024,
    max_header_bytes: usize = 32 * 1024,
    max_header_count: usize = 100,
    max_body_bytes: usize = 16 * 1024 * 1024,
    max_chunk_size: u64 = 64 * 1024 * 1024,
    max_trailer_bytes: usize = 8 * 1024,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    allocator: std.mem.Allocator,
    method: Method,
    version: Version,
    target: []u8,
    path: []u8,
    query: []u8,
    headers: std.ArrayList(Header),
    header_storage: std.ArrayList(u8),
    trailers: std.ArrayList(Header),
    trailer_storage: std.ArrayList(u8),
    body: std.ArrayList(u8),
    content_length: ?u64,
    chunked: bool,
    keep_alive: bool,
    expect_continue: bool,

    pub fn init(allocator: std.mem.Allocator) Request {
        return Request{
            .allocator = allocator,
            .method = .get,
            .version = .http_1_1,
            .target = &[_]u8{},
            .path = &[_]u8{},
            .query = &[_]u8{},
            .headers = std.ArrayList(Header).init(allocator),
            .header_storage = std.ArrayList(u8).init(allocator),
            .trailers = std.ArrayList(Header).init(allocator),
            .trailer_storage = std.ArrayList(u8).init(allocator),
            .body = std.ArrayList(u8).init(allocator),
            .content_length = null,
            .chunked = false,
            .keep_alive = true,
            .expect_continue = false,
        };
    }

    pub fn deinit(self: *Request) void {
        if (self.target.len != 0) self.allocator.free(self.target);
        self.target = &[_]u8{};
        self.path = &[_]u8{};
        self.query = &[_]u8{};
        self.headers.deinit();
        self.header_storage.deinit();
        self.trailers.deinit();
        self.trailer_storage.deinit();
        self.body.deinit();
    }

    pub fn reset(self: *Request) void {
        if (self.target.len != 0) self.allocator.free(self.target);
        self.target = &[_]u8{};
        self.path = &[_]u8{};
        self.query = &[_]u8{};
        self.headers.clearRetainingCapacity();
        self.header_storage.clearRetainingCapacity();
        self.trailers.clearRetainingCapacity();
        self.trailer_storage.clearRetainingCapacity();
        self.body.clearRetainingCapacity();
        self.method = .get;
        self.version = .http_1_1;
        self.content_length = null;
        self.chunked = false;
        self.keep_alive = true;
        self.expect_continue = false;
    }

    pub fn findHeader(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }

    pub fn findTrailer(self: *const Request, name: []const u8) ?[]const u8 {
        for (self.trailers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }

    pub fn headerCount(self: *const Request) usize {
        return self.headers.items.len;
    }
};

pub const State = enum {
    request_line,
    headers,
    body_fixed,
    body_chunk_size,
    body_chunk_data,
    body_chunk_data_crlf,
    body_chunk_trailers,
    complete,
    failed,
};

pub const FeedResult = struct {
    consumed: usize,
    complete: bool,
    expect_continue: bool,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    limits: Limits,
    state: State,
    request: Request,
    scratch: std.ArrayList(u8),
    request_line_bytes: usize,
    header_bytes: usize,
    trailer_bytes: usize,
    remaining_fixed: u64,
    remaining_chunk: u64,
    continue_reported: bool,
    saw_content_length: bool,
    saw_transfer_encoding: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, limits: Limits) Self {
        return Self{
            .allocator = allocator,
            .limits = limits,
            .state = .request_line,
            .request = Request.init(allocator),
            .scratch = std.ArrayList(u8).init(allocator),
            .request_line_bytes = 0,
            .header_bytes = 0,
            .trailer_bytes = 0,
            .remaining_fixed = 0,
            .remaining_chunk = 0,
            .continue_reported = false,
            .saw_content_length = false,
            .saw_transfer_encoding = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.request.deinit();
        self.scratch.deinit();
    }

    pub fn reset(self: *Self) void {
        self.request.reset();
        self.scratch.clearRetainingCapacity();
        self.state = .request_line;
        self.request_line_bytes = 0;
        self.header_bytes = 0;
        self.trailer_bytes = 0;
        self.remaining_fixed = 0;
        self.remaining_chunk = 0;
        self.continue_reported = false;
        self.saw_content_length = false;
        self.saw_transfer_encoding = false;
    }

    pub fn isComplete(self: *const Self) bool {
        return self.state == .complete;
    }

    pub fn feed(self: *Self, input: []const u8) Error!FeedResult {
        var index: usize = 0;
        var expect_continue = false;

        while (index < input.len and self.state != .complete and self.state != .failed) {
            switch (self.state) {
                .request_line => {
                    const line = try self.takeLine(input, &index, self.limits.max_request_line, &self.request_line_bytes, ParseError.RequestLineTooLong);
                    if (line == null) break;
                    if (line.?.len == 0) {
                        self.scratch.clearRetainingCapacity();
                        continue;
                    }
                    try self.parseRequestLine(line.?);
                    self.scratch.clearRetainingCapacity();
                    self.state = .headers;
                },
                .headers => {
                    const line = try self.takeLine(input, &index, self.limits.max_header_bytes, &self.header_bytes, ParseError.HeaderTooLarge);
                    if (line == null) break;
                    if (line.?.len == 0) {
                        self.scratch.clearRetainingCapacity();
                        try self.finishHeaders();
                        if (self.request.expect_continue and !self.continue_reported) {
                            self.continue_reported = true;
                            expect_continue = true;
                        }
                        continue;
                    }
                    try self.parseHeaderLine(line.?);
                    self.scratch.clearRetainingCapacity();
                },
                .body_fixed => {
                    const available = input.len - index;
                    const want: usize = if (self.remaining_fixed > available) available else @intCast(self.remaining_fixed);
                    if (self.request.body.items.len + want > self.limits.max_body_bytes) {
                        self.state = .failed;
                        return ParseError.BodyTooLarge;
                    }
                    try self.request.body.appendSlice(input[index .. index + want]);
                    index += want;
                    self.remaining_fixed -= want;
                    if (self.remaining_fixed == 0) self.state = .complete;
                },
                .body_chunk_size => {
                    const line = try self.takeLine(input, &index, self.limits.max_header_bytes, &self.header_bytes, ParseError.HeaderTooLarge);
                    if (line == null) break;
                    const size = try parseChunkSize(line.?, self.limits.max_chunk_size);
                    self.scratch.clearRetainingCapacity();
                    self.remaining_chunk = size;
                    if (size == 0) {
                        self.state = .body_chunk_trailers;
                    } else {
                        self.state = .body_chunk_data;
                    }
                },
                .body_chunk_data => {
                    const available = input.len - index;
                    const want: usize = if (self.remaining_chunk > available) available else @intCast(self.remaining_chunk);
                    if (self.request.body.items.len + want > self.limits.max_body_bytes) {
                        self.state = .failed;
                        return ParseError.BodyTooLarge;
                    }
                    try self.request.body.appendSlice(input[index .. index + want]);
                    index += want;
                    self.remaining_chunk -= want;
                    if (self.remaining_chunk == 0) self.state = .body_chunk_data_crlf;
                },
                .body_chunk_data_crlf => {
                    const line = try self.takeLine(input, &index, 2, &self.trailer_bytes, ParseError.InvalidChunkTerminator);
                    if (line == null) break;
                    if (line.?.len != 0) {
                        self.state = .failed;
                        return ParseError.InvalidChunkTerminator;
                    }
                    self.scratch.clearRetainingCapacity();
                    self.trailer_bytes = 0;
                    self.state = .body_chunk_size;
                },
                .body_chunk_trailers => {
                    const line = try self.takeLine(input, &index, self.limits.max_trailer_bytes, &self.trailer_bytes, ParseError.TrailerTooLarge);
                    if (line == null) break;
                    if (line.?.len == 0) {
                        self.scratch.clearRetainingCapacity();
                        self.state = .complete;
                        continue;
                    }
                    try self.parseTrailerLine(line.?);
                    self.scratch.clearRetainingCapacity();
                },
                .complete, .failed => break,
            }
        }

        return FeedResult{
            .consumed = index,
            .complete = self.state == .complete,
            .expect_continue = expect_continue,
        };
    }

    fn takeLine(
        self: *Self,
        input: []const u8,
        index: *usize,
        limit: usize,
        counter: *usize,
        limit_error: ParseError,
    ) Error!?[]const u8 {
        while (index.* < input.len) {
            const byte = input[index.*];
            index.* += 1;
            counter.* += 1;
            if (counter.* > limit) {
                self.state = .failed;
                return limit_error;
            }
            if (byte == '\n') {
                var line = self.scratch.items;
                if (line.len > 0 and line[line.len - 1] == '\r') {
                    line = line[0 .. line.len - 1];
                } else {
                    self.state = .failed;
                    return ParseError.MalformedHeader;
                }
                return line;
            }
            if (byte == 0) {
                self.state = .failed;
                return ParseError.MalformedHeader;
            }
            try self.scratch.append(byte);
        }
        return null;
    }

    fn parseRequestLine(self: *Self, line: []const u8) Error!void {
        var it = std.mem.splitScalar(u8, line, ' ');
        const method_text = it.next() orelse {
            self.state = .failed;
            return ParseError.MalformedRequestLine;
        };
        const target_text = it.next() orelse {
            self.state = .failed;
            return ParseError.MalformedRequestLine;
        };
        const version_text = it.next() orelse {
            self.state = .failed;
            return ParseError.MalformedRequestLine;
        };
        if (it.next() != null) {
            self.state = .failed;
            return ParseError.MalformedRequestLine;
        }
        if (method_text.len == 0 or target_text.len == 0) {
            self.state = .failed;
            return ParseError.MalformedRequestLine;
        }
        for (method_text) |c| {
            if (!isTokenChar(c)) {
                self.state = .failed;
                return ParseError.MalformedRequestLine;
            }
        }
        const method = Method.fromSlice(method_text) orelse {
            self.state = .failed;
            return ParseError.UnsupportedMethod;
        };
        if (target_text.len > self.limits.max_target) {
            self.state = .failed;
            return ParseError.TargetTooLong;
        }
        for (target_text) |c| {
            if (c <= 0x20 or c == 0x7F) {
                self.state = .failed;
                return ParseError.InvalidTarget;
            }
        }
        if (method != .connect and method != .options and target_text[0] != '/') {
            if (!std.ascii.startsWithIgnoreCase(target_text, "http://") and !std.ascii.startsWithIgnoreCase(target_text, "https://")) {
                self.state = .failed;
                return ParseError.InvalidTarget;
            }
        }
        const version: Version = blk: {
            if (std.mem.eql(u8, version_text, "HTTP/1.1")) break :blk .http_1_1;
            if (std.mem.eql(u8, version_text, "HTTP/1.0")) break :blk .http_1_0;
            self.state = .failed;
            return ParseError.UnsupportedVersion;
        };

        const owned = try self.allocator.dupe(u8, target_text);
        errdefer self.allocator.free(owned);
        if (self.request.target.len != 0) self.allocator.free(self.request.target);
        self.request.target = owned;
        self.request.method = method;
        self.request.version = version;
        self.request.keep_alive = version.defaultKeepAlive();

        const q_index = std.mem.indexOfScalar(u8, owned, '?');
        if (q_index) |qi| {
            self.request.path = owned[0..qi];
            self.request.query = owned[qi + 1 ..];
        } else {
            self.request.path = owned;
            self.request.query = owned[owned.len..];
        }
    }

    fn parseHeaderLine(self: *Self, line: []const u8) Error!void {
        if (line[0] == ' ' or line[0] == '\t') {
            self.state = .failed;
            return ParseError.ObsoleteLineFolding;
        }
        if (self.request.headers.items.len >= self.limits.max_header_count) {
            self.state = .failed;
            return ParseError.TooManyHeaders;
        }
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
            self.state = .failed;
            return ParseError.MalformedHeader;
        };
        const raw_name = line[0..colon];
        if (raw_name.len == 0) {
            self.state = .failed;
            return ParseError.MalformedHeader;
        }
        for (raw_name) |c| {
            if (!isTokenChar(c)) {
                self.state = .failed;
                return ParseError.MalformedHeader;
            }
        }
        const raw_value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        for (raw_value) |c| {
            if (c < 0x20 and c != '\t') {
                self.state = .failed;
                return ParseError.MalformedHeader;
            }
        }

        const name_start = self.request.header_storage.items.len;
        try self.request.header_storage.appendSlice(raw_name);
        const value_start = self.request.header_storage.items.len;
        try self.request.header_storage.appendSlice(raw_value);
        const value_end = self.request.header_storage.items.len;

        try self.request.headers.append(Header{
            .name = self.request.header_storage.items[name_start..value_start],
            .value = self.request.header_storage.items[value_start..value_end],
        });
        self.rebindHeaderSlices();

        const name = self.request.headers.items[self.request.headers.items.len - 1].name;
        const value = self.request.headers.items[self.request.headers.items.len - 1].value;

        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            const parsed = std.fmt.parseInt(u64, value, 10) catch {
                self.state = .failed;
                return ParseError.InvalidContentLength;
            };
            if (self.saw_content_length) {
                if (self.request.content_length.? != parsed) {
                    self.state = .failed;
                    return ParseError.DuplicateContentLength;
                }
            }
            self.saw_content_length = true;
            self.request.content_length = parsed;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            self.saw_transfer_encoding = true;
            var tokens = std.mem.splitScalar(u8, value, ',');
            var last_is_chunked = false;
            var any = false;
            while (tokens.next()) |token_raw| {
                const token = std.mem.trim(u8, token_raw, " \t");
                if (token.len == 0) continue;
                any = true;
                if (std.ascii.eqlIgnoreCase(token, "chunked")) {
                    last_is_chunked = true;
                } else if (std.ascii.eqlIgnoreCase(token, "identity")) {
                    last_is_chunked = false;
                } else {
                    self.state = .failed;
                    return ParseError.UnsupportedTransferEncoding;
                }
            }
            if (!any) {
                self.state = .failed;
                return ParseError.UnsupportedTransferEncoding;
            }
            self.request.chunked = last_is_chunked;
        } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
            var tokens = std.mem.splitScalar(u8, value, ',');
            while (tokens.next()) |token_raw| {
                const token = std.mem.trim(u8, token_raw, " \t");
                if (std.ascii.eqlIgnoreCase(token, "close")) {
                    self.request.keep_alive = false;
                } else if (std.ascii.eqlIgnoreCase(token, "keep-alive")) {
                    self.request.keep_alive = true;
                }
            }
        } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, value, " \t"), "100-continue")) {
                self.request.expect_continue = true;
            }
        }
    }

    fn parseTrailerLine(self: *Self, line: []const u8) Error!void {
        if (line[0] == ' ' or line[0] == '\t') {
            self.state = .failed;
            return ParseError.ObsoleteLineFolding;
        }
        if (self.request.trailers.items.len >= self.limits.max_header_count) {
            self.state = .failed;
            return ParseError.TooManyHeaders;
        }
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
            self.state = .failed;
            return ParseError.MalformedHeader;
        };
        const raw_name = line[0..colon];
        if (raw_name.len == 0) {
            self.state = .failed;
            return ParseError.MalformedHeader;
        }
        for (raw_name) |c| {
            if (!isTokenChar(c)) {
                self.state = .failed;
                return ParseError.MalformedHeader;
            }
        }
        if (std.ascii.eqlIgnoreCase(raw_name, "content-length") or
            std.ascii.eqlIgnoreCase(raw_name, "transfer-encoding") or
            std.ascii.eqlIgnoreCase(raw_name, "host"))
        {
            self.state = .failed;
            return ParseError.MalformedHeader;
        }
        const raw_value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        const name_start = self.request.trailer_storage.items.len;
        try self.request.trailer_storage.appendSlice(raw_name);
        const value_start = self.request.trailer_storage.items.len;
        try self.request.trailer_storage.appendSlice(raw_value);
        const value_end = self.request.trailer_storage.items.len;

        try self.request.trailers.append(Header{
            .name = self.request.trailer_storage.items[name_start..value_start],
            .value = self.request.trailer_storage.items[value_start..value_end],
        });
        self.rebindTrailerSlices();
    }

    fn rebindHeaderSlices(self: *Self) void {
        var cursor: usize = 0;
        for (self.request.headers.items) |*h| {
            const name_len = h.name.len;
            const value_len = h.value.len;
            h.name = self.request.header_storage.items[cursor .. cursor + name_len];
            cursor += name_len;
            h.value = self.request.header_storage.items[cursor .. cursor + value_len];
            cursor += value_len;
        }
    }

    fn rebindTrailerSlices(self: *Self) void {
        var cursor: usize = 0;
        for (self.request.trailers.items) |*h| {
            const name_len = h.name.len;
            const value_len = h.value.len;
            h.name = self.request.trailer_storage.items[cursor .. cursor + name_len];
            cursor += name_len;
            h.value = self.request.trailer_storage.items[cursor .. cursor + value_len];
            cursor += value_len;
        }
    }

    fn finishHeaders(self: *Self) Error!void {
        if (self.request.version == .http_1_1 and self.request.findHeader("host") == null) {
            self.state = .failed;
            return ParseError.MissingHost;
        }
        if (self.saw_content_length and self.saw_transfer_encoding) {
            self.state = .failed;
            return ParseError.ConflictingFraming;
        }
        if (self.saw_transfer_encoding and !self.request.chunked and self.request.version == .http_1_1) {
            self.state = .failed;
            return ParseError.UnsupportedTransferEncoding;
        }
        if (self.request.chunked) {
            if (self.request.method.bodyForbidden()) {
                self.state = .failed;
                return ParseError.BodyNotAllowed;
            }
            self.header_bytes = 0;
            self.state = .body_chunk_size;
            return;
        }
        const length = self.request.content_length orelse 0;
        if (length > 0 and self.request.method.bodyForbidden()) {
            self.state = .failed;
            return ParseError.BodyNotAllowed;
        }
        if (length > self.limits.max_body_bytes) {
            self.state = .failed;
            return ParseError.BodyTooLarge;
        }
        self.remaining_fixed = length;
        if (length == 0) {
            self.state = .complete;
        } else {
            try self.request.body.ensureTotalCapacity(@intCast(length));
            self.state = .body_fixed;
        }
    }
};

fn isTokenChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9' => true,
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}

fn parseChunkSize(line: []const u8, max_chunk_size: u64) ParseError!u64 {
    if (line.len == 0) return ParseError.InvalidChunkSize;
    var end: usize = line.len;
    if (std.mem.indexOfScalar(u8, line, ';')) |semi| {
        end = semi;
    }
    const digits = std.mem.trim(u8, line[0..end], " \t");
    if (digits.len == 0 or digits.len > 16) return ParseError.InvalidChunkSize;
    var value: u64 = 0;
    for (digits) |c| {
        const digit: u64 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return ParseError.InvalidChunkSize,
        };
        value = value * 16 + digit;
    }
    if (value > max_chunk_size) return ParseError.ChunkTooLarge;
    return value;
}

pub fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        100 => "Continue",
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        409 => "Conflict",
        413 => "Content Too Large",
        414 => "URI Too Long",
        429 => "Too Many Requests",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        503 => "Service Unavailable",
        505 => "HTTP Version Not Supported",
        else => "Unknown",
    };
}

test "parse simple get request" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "GET /v1/health?verbose=1 HTTP/1.1\r\nHost: example.org\r\nUser-Agent: agdb-test\r\n\r\n";
    const result = try parser.feed(raw);
    try testing.expect(result.complete);
    try testing.expectEqual(raw.len, result.consumed);
    try testing.expectEqual(Method.get, parser.request.method);
    try testing.expectEqualStrings("/v1/health", parser.request.path);
    try testing.expectEqualStrings("verbose=1", parser.request.query);
    try testing.expectEqualStrings("example.org", parser.request.findHeader("HOST").?);
    try testing.expect(parser.request.keep_alive);
    try testing.expectEqual(@as(usize, 0), parser.request.body.items.len);
}

test "parse request split at every byte boundary" {
    const testing = std.testing;
    const raw = "POST /v1/records HTTP/1.1\r\nHost: a.b\r\nContent-Length: 11\r\n\r\nhello world";
    var split: usize = 1;
    while (split < raw.len) : (split += 1) {
        var parser = Parser.init(testing.allocator, .{});
        defer parser.deinit();
        const first = try parser.feed(raw[0..split]);
        try testing.expect(!first.complete);
        const second = try parser.feed(raw[split..]);
        try testing.expect(second.complete);
        try testing.expectEqualStrings("hello world", parser.request.body.items);
        try testing.expectEqual(@as(u64, 11), parser.request.content_length.?);
    }
}

test "chunked body with trailers" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST /ingest HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n" ++
        "5\r\nhello\r\n" ++
        "6;ext=1\r\n world\r\n" ++
        "0\r\nX-Checksum: abc\r\n\r\n";
    const result = try parser.feed(raw);
    try testing.expect(result.complete);
    try testing.expectEqualStrings("hello world", parser.request.body.items);
    try testing.expectEqualStrings("abc", parser.request.findTrailer("x-checksum").?);
}

test "reject conflicting content length and transfer encoding" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n";
    try testing.expectError(ParseError.ConflictingFraming, parser.feed(raw));
    try testing.expectEqual(@as(u16, 400), statusForError(ParseError.ConflictingFraming));
}

test "reject duplicate conflicting content length" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n";
    try testing.expectError(ParseError.DuplicateContentLength, parser.feed(raw));
}

test "reject obsolete line folding" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "GET / HTTP/1.1\r\nHost: h\r\nX-Long: a\r\n b\r\n\r\n";
    try testing.expectError(ParseError.ObsoleteLineFolding, parser.feed(raw));
}

test "reject missing host on http 1.1" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "GET / HTTP/1.1\r\nAccept: */*\r\n\r\n";
    try testing.expectError(ParseError.MissingHost, parser.feed(raw));
}

test "reject unknown transfer encoding" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: gzip\r\n\r\n";
    try testing.expectError(ParseError.UnsupportedTransferEncoding, parser.feed(raw));
    try testing.expectEqual(@as(u16, 501), statusForError(ParseError.UnsupportedTransferEncoding));
}

test "enforce body limit" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{ .max_body_bytes = 4 });
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 8\r\n\r\n12345678";
    try testing.expectError(ParseError.BodyTooLarge, parser.feed(raw));
    try testing.expectEqual(@as(u16, 413), statusForError(ParseError.BodyTooLarge));
}

test "enforce header count limit" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{ .max_header_count = 2 });
    defer parser.deinit();

    const raw = "GET / HTTP/1.1\r\nHost: h\r\nA: 1\r\nB: 2\r\n\r\n";
    try testing.expectError(ParseError.TooManyHeaders, parser.feed(raw));
    try testing.expectEqual(@as(u16, 431), statusForError(ParseError.TooManyHeaders));
}

test "enforce request line limit" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{ .max_request_line = 16 });
    defer parser.deinit();

    const raw = "GET /this/target/is/too/long HTTP/1.1\r\nHost: h\r\n\r\n";
    try testing.expectError(ParseError.RequestLineTooLong, parser.feed(raw));
    try testing.expectEqual(@as(u16, 414), statusForError(ParseError.RequestLineTooLong));
}

test "reject unsupported version" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    try testing.expectError(ParseError.UnsupportedVersion, parser.feed("GET / HTTP/2.0\r\nHost: h\r\n\r\n"));
    try testing.expectEqual(@as(u16, 505), statusForError(ParseError.UnsupportedVersion));
}

test "reject bare line feed in headers" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    try testing.expectError(ParseError.MalformedHeader, parser.feed("GET / HTTP/1.1\nHost: h\r\n\r\n"));
}

test "pipelined requests on one connection" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "GET /a HTTP/1.1\r\nHost: h\r\n\r\nGET /b HTTP/1.1\r\nHost: h\r\nConnection: close\r\n\r\n";
    const first = try parser.feed(raw);
    try testing.expect(first.complete);
    try testing.expectEqualStrings("/a", parser.request.path);
    try testing.expect(parser.request.keep_alive);

    parser.reset();
    const second = try parser.feed(raw[first.consumed..]);
    try testing.expect(second.complete);
    try testing.expectEqualStrings("/b", parser.request.path);
    try testing.expect(!parser.request.keep_alive);
}

test "expect continue is reported once" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const head = "PUT /x HTTP/1.1\r\nHost: h\r\nExpect: 100-continue\r\nContent-Length: 3\r\n\r\n";
    const first = try parser.feed(head);
    try testing.expect(first.expect_continue);
    try testing.expect(!first.complete);
    const second = try parser.feed("abc");
    try testing.expect(!second.expect_continue);
    try testing.expect(second.complete);
    try testing.expectEqualStrings("abc", parser.request.body.items);
}

test "http 1.0 defaults to close" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const result = try parser.feed("GET / HTTP/1.0\r\n\r\n");
    try testing.expect(result.complete);
    try testing.expect(!parser.request.keep_alive);
}

test "reject invalid chunk size" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n";
    try testing.expectError(ParseError.InvalidChunkSize, parser.feed(raw));
}

test "reject chunk larger than limit" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{ .max_chunk_size = 4 });
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n10\r\n";
    try testing.expectError(ParseError.ChunkTooLarge, parser.feed(raw));
}

test "reject smuggling via trailer framing header" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    const raw = "POST / HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 10\r\n\r\n";
    try testing.expectError(ParseError.MalformedHeader, parser.feed(raw));
}

test "parser reuse after reset keeps no stale state" {
    const testing = std.testing;
    var parser = Parser.init(testing.allocator, .{});
    defer parser.deinit();

    _ = try parser.feed("POST /one HTTP/1.1\r\nHost: h\r\nContent-Length: 2\r\n\r\nhi");
    try testing.expectEqualStrings("hi", parser.request.body.items);
    parser.reset();
    const result = try parser.feed("GET /two HTTP/1.1\r\nHost: h\r\n\r\n");
    try testing.expect(result.complete);
    try testing.expectEqual(@as(usize, 0), parser.request.body.items.len);
    try testing.expect(parser.request.content_length == null);
    try testing.expectEqualStrings("/two", parser.request.path);
}
