/// Tasks tool handlers

const std = @import("std");
const mcp = @import("../mcp.zig");
const graph_tasks = @import("../graph/tasks.zig");
const gc = @import("../graph/client.zig");
const GraphClient = gc.GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_task_lists = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        _ = args;
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const raw = graph_tasks.listTaskLists(client) catch |err| {
            return errRes(allocator, "Error listing task lists: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okRes(allocator, "📋 任务清单:\n{s}", .{raw});
    }
};

pub const list_tasks = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const list_id = getStr(args, "list_id", "");
        const status = getStrOpt(args, "status");

        if (list_id.len == 0) return errRes(allocator, "Missing required field: list_id", .{});

        const raw = graph_tasks.listTasks(client, list_id, status) catch |err| {
            return errRes(allocator, "Error listing tasks: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okRes(allocator, "✅ 任务列表:\n{s}", .{raw});
    }
};

pub const create_task = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const list_id = getStr(args, "list_id", "");
        const title = getStr(args, "title", "");
        const due_date = getStrOpt(args, "due_date");

        if (list_id.len == 0 or title.len == 0) return errRes(allocator, "Missing required fields: list_id, title", .{});

        const raw = graph_tasks.createTask(client, list_id, title, due_date) catch |err| {
            return errRes(allocator, "Error creating task: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okRes(allocator, "✅ 任务创建成功：{s}\n{s}", .{ title, raw });
    }
};

pub const complete_task = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const list_id = getStr(args, "list_id", "");
        const task_id = getStr(args, "task_id", "");

        if (list_id.len == 0 or task_id.len == 0) return errRes(allocator, "Missing required fields: list_id, task_id", .{});

        const raw = graph_tasks.completeTask(client, list_id, task_id) catch |err| {
            return errRes(allocator, "Error completing task: {s}", .{@errorName(err)});
        };
        defer allocator.free(raw);
        return okRes(allocator, "✅ 任务已完成 ({s})", .{task_id});
    }
};

pub const delete_task = struct {
    pub fn handler(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
        const client = global_client orelse return mcp.ToolError.ExecutionFailed;
        const list_id = getStr(args, "list_id", "");
        const task_id = getStr(args, "task_id", "");

        if (list_id.len == 0 or task_id.len == 0) return errRes(allocator, "Missing required fields: list_id, task_id", .{});

        _ = graph_tasks.deleteTask(client, list_id, task_id) catch |err| {
            return errRes(allocator, "Error deleting task: {s}", .{@errorName(err)});
        };
        return okRes(allocator, "🗑️ 任务已删除 ({s})", .{task_id});
    }
};

// ── Shared Helpers (duplicated from mail.zig to avoid cross-dep) ──

fn getStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    return default;
}

fn getStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string and v.string.len > 0) return v.string;
    return null;
}

fn okRes(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args) };
}

fn errRes(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args), .is_error = true };
}
