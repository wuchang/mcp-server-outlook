/// Mail tool handlers with logging

const std = @import("std");
const log = @import("../log.zig");
const mcp = @import("../mcp.zig");
const graph_mail = @import("../graph/mail.zig");
const GraphClient = @import("../graph/client.zig").GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_emails = .{ .handler = listEmails };
pub const send_email = .{ .handler = sendEmail };
pub const search_emails = .{ .handler = searchEmails };
pub const get_unread_count = .{ .handler = getUnreadCount };

fn listEmails(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const top = argInt(args, "top", 10);
    const unread_only = argBool(args, "unread_only", false);
    log.info("tool=list_emails top={d} unread={}", .{ top, unread_only });

    const raw = graph_mail.listEmails(client, top, unread_only) catch |e| {
        log.err("list_emails failed: {s}", .{@errorName(e)});
        return errResult(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.debug("list_emails response: {d} bytes", .{raw.len});
    return okResult(allocator, "📧 邮件列表:\n{s}", .{raw});
}

fn sendEmail(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const to = argStr(args, "to", "");
    const subject = argStr(args, "subject", "");
    log.info("tool=send_email to={s} subject={s}", .{ to, subject });

    if (to.len == 0) {
        log.warn("send_email missing 'to'", .{});
        return errResult(allocator, "Missing required field: to", .{});
    }

    const body = argStr(args, "body", "");
    const cc = argStrOpt(args, "cc");
    const raw = graph_mail.sendEmail(client, to, subject, body, cc, null) catch |e| {
        log.err("send_email failed: {s}", .{@errorName(e)});
        return errResult(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.info("send_email success", .{});
    return okResult(allocator, "✅ 邮件已发送：{s} → {s}", .{ subject, to });
}

fn searchEmails(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const keyword = argStr(args, "keyword", "");
    const top = argInt(args, "top", 20);
    log.info("tool=search_emails keyword={s} top={d}", .{ keyword, top });

    const raw = graph_mail.searchEmails(client, keyword, top) catch |e| {
        log.err("search_emails failed: {s}", .{@errorName(e)});
        return errResult(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.debug("search_emails response: {d} bytes", .{raw.len});
    return okResult(allocator, "🔍 邮件搜索结果 \"{s}\":\n{s}", .{ keyword, raw });
}

fn getUnreadCount(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    _ = args;
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    log.info("tool=get_unread_count", .{});

    const raw = graph_mail.getUnreadCount(client) catch |e| {
        log.err("get_unread_count failed: {s}", .{@errorName(e)});
        return errResult(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.debug("get_unread_count response: {d} bytes", .{raw.len});
    return okResult(allocator, "📬 未读邮件:\n{s}", .{raw});
}

fn argStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    return default;
}

fn argInt(args: ?std.json.Value, key: []const u8, default: i64) i64 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .integer) return @intCast(v.integer);
    return default;
}

fn argBool(args: ?std.json.Value, key: []const u8, default: bool) bool {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .bool) return v.bool;
    return default;
}

fn argStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string and v.string.len > 0) return v.string;
    return null;
}

fn okResult(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args) };
}

fn errResult(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args), .is_error = true };
}
