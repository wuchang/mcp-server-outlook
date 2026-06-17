/// Calendar tool handlers

const std = @import("std");
const mcp = @import("../mcp.zig");
const graph_calendar = @import("../graph/calendar.zig");
const GraphClient = @import("../graph/client.zig").GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_events = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const days = if (args) |a|
            if (a.object.get("days")) |v|
                if (v == .integer) @as(i64, @intCast(v.integer)) else @as(i64, 7)
            else
                @as(i64, 7)
        else
            @as(i64, 7);

        const raw = graph_calendar.listEvents(client, days) catch |err| {
            return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error listing events: {s}", .{@errorName(err)}), .is_error = true };
        };
        defer allocator.free(raw);

        return formatEvents(allocator, raw, try std.fmt.allocPrint(allocator, "未来 {d} 天", .{days}));
    }
};

pub const query_events = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;

        const start_date = if (args) |a| getStr(a, "start_date", "") else "";
        const end_date = if (args) |a| getStr(a, "end_date", "") else "";

        const raw = graph_calendar.queryEvents(client, start_date, end_date) catch |err| {
            return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error querying events: {s}", .{@errorName(err)}), .is_error = true };
        };
        defer allocator.free(raw);

        const label = try std.fmt.allocPrint(allocator, "{s} → {s}", .{ start_date, end_date });
        defer allocator.free(label);
        return formatEvents(allocator, raw, label);
    }
};

pub const search_events = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const keyword = if (args) |a| getStr(a, "keyword", "") else "";

        const raw = graph_calendar.searchEvents(client, keyword) catch |err| {
            return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error searching events: {s}", .{@errorName(err)}), .is_error = true };
        };
        defer allocator.free(raw);

        // Client-side filtering by keyword
        // For now, just return raw JSON
        return mcp.ToolResult{ .text = try formatSimple(allocator, "事件搜索结果", raw) };
    }
};

pub const create_event = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;

        const subject = getStr(args, "subject", "");
        const start = getStr(args, "start", "");
        const end = getStr(args, "end", "");
        const location = getStrOpt(args, "location");
        const body = getStrOpt(args, "body");

        if (subject.len == 0 or start.len == 0 or end.len == 0) {
            return mcp.ToolResult{ .text = "Missing required fields: subject, start, end", .is_error = true };
        }

        const raw = graph_calendar.createEvent(client, subject, start, end, location, body) catch |err| {
            return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error creating event: {s}", .{@errorName(err)}), .is_error = true };
        };
        defer allocator.free(raw);

        return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "✅ 事件创建成功：{s}（{s} → {s}）", .{ subject, start, end }) };
    }
};

// ── Helpers ──

fn getStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| {
                if (v == .string and v.string.len > 0) return v.string;
            }
        }
    }
    return default;
}

fn getStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| {
        if (a == .object) {
            if (a.object.get(key)) |v| {
                if (v == .string and v.string.len > 0) return v.string;
            }
        }
    }
    return null;
}

fn formatEvents(allocator: std.mem.Allocator, raw_json: []const u8, label: []const u8) mcp.ToolError!mcp.ToolResult {
    // Simple pass-through: return raw JSON formatted as text
    // In production, parse the JSON response and format nicely
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "📅 {s} 事件：\n{s}", .{ label, raw_json }) };
}

fn formatSimple(allocator: std.mem.Allocator, label: []const u8, raw_json: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}：\n{s}", .{ label, raw_json });
}
