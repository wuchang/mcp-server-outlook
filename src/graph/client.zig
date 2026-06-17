/// Microsoft Graph REST API client
/// Supports dependency injection for transport layer (testable).

const std = @import("std");
const tls = @import("../tls.zig");

const graph_host = "graph.microsoft.com";
const graph_port = 443;
const base = "/v1.0";

/// Transport function: (allocator, method, host, port, path, auth_header, body) → body
pub const TransportFn = *const fn (
    allocator: std.mem.Allocator,
    method: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
    auth_header: []const u8,
    body_json: ?[]const u8,
) anyerror![]const u8;

fn defaultTransport(
    allocator: std.mem.Allocator,
    method: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
    auth_header: []const u8,
    body_json: ?[]const u8,
) ![]const u8 {
    return tls.sendWithAuth(allocator, method, host, port, path, auth_header, body_json);
}

pub const GraphClient = struct {
    allocator: std.mem.Allocator,
    access_token: []const u8,
    transport: TransportFn,

    pub fn init(allocator: std.mem.Allocator, token: []const u8) GraphClient {
        return .{ .allocator = allocator, .access_token = token, .transport = defaultTransport };
    }

    pub fn initWithTransport(allocator: std.mem.Allocator, token: []const u8, transport: TransportFn) GraphClient {
        return .{ .allocator = allocator, .access_token = token, .transport = transport };
    }

    pub fn deinit(self: *GraphClient) void {
        self.allocator.free(self.access_token);
    }

    fn buildAuth(self: *GraphClient) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}", .{self.access_token});
    }

    fn doRequest(self: *GraphClient, method: []const u8, path: []const u8, body: ?[]const u8) ![]const u8 {
        const full_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, path });
        defer self.allocator.free(full_path);
        const auth = try self.buildAuth();
        defer self.allocator.free(auth);
        return self.transport(self.allocator, method, graph_host, graph_port, full_path, auth, body);
    }

    pub fn get(self: *GraphClient, path: []const u8) ![]const u8 { return self.doRequest("GET", path, null); }
    pub fn post(self: *GraphClient, path: []const u8, body: ?[]const u8) ![]const u8 { return self.doRequest("POST", path, body); }
    pub fn patch(self: *GraphClient, path: []const u8, body: ?[]const u8) ![]const u8 { return self.doRequest("PATCH", path, body); }
    pub fn delete(self: *GraphClient, path: []const u8) ![]const u8 { return self.doRequest("DELETE", path, null); }
};
