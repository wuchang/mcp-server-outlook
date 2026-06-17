/// Graph client unit tests — mock transport, verify request construction
const std = @import("std");
const client = @import("graph/client.zig");
const GraphClient = client.GraphClient;

/// Test state shared with mock transport (module-level vars are OK in tests)
const TEST = struct {
    var method: []const u8 = "";
    var path: [256]u8 = undefined;
    var path_len: usize = 0;
    var auth: [256]u8 = undefined;
    var auth_len: usize = 0;
    var has_body: bool = false;
    var body: [256]u8 = undefined;
    var body_len: usize = 0;
};

fn mockTransport(
    _: std.mem.Allocator,
    m: []const u8,
    _: []const u8,
    _: u16,
    p: []const u8,
    a: []const u8,
    b: ?[]const u8,
) anyerror![]const u8 {
    TEST.method = m;
    TEST.path_len = @min(p.len, TEST.path.len);
    @memcpy(TEST.path[0..TEST.path_len], p[0..TEST.path_len]);
    TEST.auth_len = @min(a.len, TEST.auth.len);
    @memcpy(TEST.auth[0..TEST.auth_len], a[0..TEST.auth_len]);
    if (b) |body| {
        TEST.has_body = true;
        TEST.body_len = @min(body.len, TEST.body.len);
        @memcpy(TEST.body[0..TEST.body_len], body[0..TEST.body_len]);
    } else {
        TEST.has_body = false;
        TEST.body_len = 0;
    }
    return "{\"ok\":true}";
}

/// Helper: create client with test allocator + dupe'd token
fn testClient(a: std.mem.Allocator, token_str: []const u8) GraphClient {
    const token = a.dupe(u8, token_str) catch unreachable;
    return GraphClient.initWithTransport(a, token, mockTransport);
}

test "GET: method, v1.0 prefix, auth header, no body" {
    const a = std.testing.allocator;
    var gclient = testClient(a, "my-test-token");
    defer gclient.deinit();

    _ = try gclient.get("/me/calendar/events");

    try std.testing.expectEqualStrings("GET", TEST.method);
    try std.testing.expectEqualStrings("/v1.0/me/calendar/events", TEST.path[0..TEST.path_len]);
    try std.testing.expectEqualStrings("Authorization: Bearer my-test-token", TEST.auth[0..TEST.auth_len]);
    try std.testing.expect(!TEST.has_body);
}

test "POST: method and body passthrough" {
    const a = std.testing.allocator;
    var gclient = testClient(a, "post-token");
    defer gclient.deinit();

    _ = try gclient.post("/me/calendar/events", "{\"subject\":\"hello\"}");

    try std.testing.expectEqualStrings("POST", TEST.method);
    try std.testing.expect(TEST.has_body);
    try std.testing.expectEqualStrings("{\"subject\":\"hello\"}", TEST.body[0..TEST.body_len]);
}

test "PATCH: method" {
    const a = std.testing.allocator;
    var gclient = testClient(a, "patch-token");
    defer gclient.deinit();

    _ = try gclient.patch("/me/tasks/1", "{\"status\":\"done\"}");
    try std.testing.expectEqualStrings("PATCH", TEST.method);
}

test "DELETE: method" {
    const a = std.testing.allocator;
    var gclient = testClient(a, "del-token");
    defer gclient.deinit();

    _ = try gclient.delete("/me/tasks/1");
    try std.testing.expectEqualStrings("DELETE", TEST.method);
}

test "POST null body" {
    TEST.has_body = true;

    const a = std.testing.allocator;
    var gclient = testClient(a, "null-test");
    defer gclient.deinit();

    _ = try gclient.post("/me/calendar/events", null);
    try std.testing.expect(!TEST.has_body);
}

test "response passthrough" {
    const a = std.testing.allocator;
    var gclient = testClient(a, "resp-test");
    defer gclient.deinit();

    const result = try gclient.get("/me");
    // result is a string literal from the mock, not heap-allocated — don't free
    try std.testing.expectEqualStrings("{\"ok\":true}", result);
}
