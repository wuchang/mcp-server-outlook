/// Mail tool handlers

const std = @import("std");
const mcp = @import("../mcp.zig");
const graph_mail = @import("../graph/mail.zig");
const gc = @import("../graph/client.zig");
const GraphClient = gc.GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_emails = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const top = getInt(args, "top", 10);
        const unread_only = getBool(args, "unread_only", false);

        const raw = graph_mail.listEmails(client, top, unread_only) catch |err| {
            return errResult(allocator, "Error listing emails: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okResult(allocator, "📧 邮件列表:\n{s}", .{raw});
    }
};

pub const send_email = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const to = getStr(args, "to", "");
        const subject = getStr(args, "subject", "");
        const body = getStr(args, "body", "");
        const cc = getStrOpt(args, "cc");

        if (to.len == 0) return errResult(allocator, "Missing required field: to", .{});

        const raw = graph_mail.sendEmail(client, to, subject, body, cc, null) catch |err| {
            return errResult(allocator, "Error sending email: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        // sendEmail returns the send result on success
        return okResult(allocator, "✅ 邮件已发送：「{s}」→ {s}\n{s}", .{ subject, to, raw });
    }
};

pub const search_emails = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const keyword = getStr(args, "keyword", "");
        const top = getInt(args, "top", 20);

        const raw = graph_mail.searchEmails(client, keyword, top) catch |err| {
            return errResult(allocator, "Error searching emails: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okResult(allocator, "🔍 邮件搜索结果:\n{s}", .{raw});
    }
};

pub const get_unread_count = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        _ = args;
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const raw = graph_mail.getUnreadCount(client) catch |err| {
            return errResult(allocator, "Error getting unread count: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okResult(allocator, "📬 未读邮件:\n{s}", .{raw});
    }
};

// ── Helpers ──

fn getStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| {
        if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    }
    return default;
}

fn getStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| {
        if (a == .object) if (a.object.get(key)) |v| if (v == .string and v.string.len > 0) return v.string;
    }
    return null;
}

fn getInt(args: ?std.json.Value, key: []const u8, default: i64) i64 {
    if (args) |a| {
        if (a == .object) if (a.object.get(key)) |v| if (v == .integer) return @intCast(v.integer);
    }
    return default;
}

fn getBool(args: ?std.json.Value, key: []const u8, default: bool) bool {
    if (args) |a| {
        if (a == .object) if (a.object.get(key)) |v| if (v == .bool) return v.bool;
    }
    return default;
}

fn okResult(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args) };
}

fn errResult(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args), .is_error = true };
}
