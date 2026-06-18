/// Calendar tool handlers with logging

const std = @import("std");
const log = @import("../log.zig");
const mcp = @import("../mcp.zig");
const graph_calendar = @import("../graph/calendar.zig");
const GraphClient = @import("../graph/client.zig").GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_events = .{ .handler = listEvents };
pub const query_events = .{ .handler = queryEvents };
pub const search_events = .{ .handler = searchEvents };
pub const create_event = .{ .handler = createEvent };

fn listEvents(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const days = argInt(args, "days", 7);
    log.info("tool=list_events days={d}", .{days});

    const raw = graph_calendar.listEvents(client, days) catch |e| {
        log.err("list_events failed: {s}", .{@errorName(e)});
        return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(e)}), .is_error = true };
    };
    defer allocator.free(raw);
    log.debug("list_events response: {d} bytes", .{raw.len});
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "📅 日历事件:\n{s}", .{raw}) };
}

fn queryEvents(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const start_date = argStr(args, "start_date", "");
    const end_date = argStr(args, "end_date", "");
    log.info("tool=query_events start={s} end={s}", .{ start_date, end_date });

    const raw = graph_calendar.queryEvents(client, start_date, end_date) catch |e| {
        log.err("query_events failed: {s}", .{@errorName(e)});
        return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(e)}), .is_error = true };
    };
    defer allocator.free(raw);
    log.debug("query_events response: {d} bytes", .{raw.len});
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "📅 {s} → {s}:\n{s}", .{ start_date, end_date, raw }) };
}

fn searchEvents(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const keyword = argStr(args, "keyword", "");
    log.info("tool=search_events keyword={s}", .{keyword});

    const raw = graph_calendar.searchEvents(client, keyword) catch |e| {
        log.err("search_events failed: {s}", .{@errorName(e)});
        return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(e)}), .is_error = true };
    };
    defer allocator.free(raw);
    log.debug("search_events response: {d} bytes", .{raw.len});
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "🔍 搜索 \"{s}\" 结果:\n{s}", .{ keyword, raw }) };
}

fn createEvent(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const subject = argStr(args, "subject", "");
    const start = argStr(args, "start", "");
    const end = argStr(args, "end", "");
    log.info("tool=create_event subject={s}", .{subject});

    if (subject.len == 0 or start.len == 0 or end.len == 0) {
        log.warn("create_event missing required fields", .{});
        return mcp.ToolResult{ .text = "Missing required: subject, start, end", .is_error = true };
    }

    const location = argStrOpt(args, "location");
    const body = argStrOpt(args, "body");
    const raw = graph_calendar.createEvent(client, subject, start, end, location, body) catch |e| {
        log.err("create_event failed: {s}", .{@errorName(e)});
        return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(e)}), .is_error = true };
    };
    defer allocator.free(raw);
    log.info("create_event success", .{});
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, "✅ 事件创建成功", .{}) };
}

fn argStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    return default;
}

fn argInt(args: ?std.json.Value, key: []const u8, default: i64) i64 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .integer) return @intCast(v.integer);
    return default;
}

fn argStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    return null;
}
