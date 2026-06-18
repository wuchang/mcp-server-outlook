/// Task tool handlers with logging

const std = @import("std");
const log = @import("../log.zig");
const mcp = @import("../mcp.zig");
const graph_tasks = @import("../graph/tasks.zig");
const GraphClient = @import("../graph/client.zig").GraphClient;

var global_client: ?*GraphClient = null;

pub fn setClient(client: *GraphClient) void {
    global_client = client;
}

pub const list_task_lists = .{ .handler = listTaskLists };
pub const list_tasks = .{ .handler = listTasks };
pub const create_task = .{ .handler = createTask };
pub const complete_task = .{ .handler = completeTask };
pub const delete_task = .{ .handler = deleteTask };

fn listTaskLists(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    _ = args;
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    log.info("tool=list_task_lists", .{});

    const raw = graph_tasks.listTaskLists(client) catch |e| {
        log.err("list_task_lists failed: {s}", .{@errorName(e)});
        return err(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.debug("list_task_lists response: {d} bytes", .{raw.len});
    return ok(allocator, "📋 任务清单:\n{s}", .{raw});
}

fn listTasks(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const list_id = argStr(args, "list_id", "");
    const status = argStrOpt(args, "status");
    log.info("tool=list_tasks list_id={s}", .{list_id});

    if (list_id.len == 0) return err(allocator, "Missing required field: list_id", .{});

    const raw = graph_tasks.listTasks(client, list_id, status) catch |e| {
        log.err("list_tasks failed: {s}", .{@errorName(e)});
        return err(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.debug("list_tasks response: {d} bytes", .{raw.len});
    return ok(allocator, "✅ 任务列表:\n{s}", .{raw});
}

fn createTask(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const list_id = argStr(args, "list_id", "");
    const title = argStr(args, "title", "");
    log.info("tool=create_task list_id={s} title={s}", .{ list_id, title });

    if (list_id.len == 0 or title.len == 0) return err(allocator, "Missing required: list_id, title", .{});

    const due_date = argStrOpt(args, "due_date");
    const raw = graph_tasks.createTask(client, list_id, title, due_date) catch |e| {
        log.err("create_task failed: {s}", .{@errorName(e)});
        return err(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.info("create_task success", .{});
    return ok(allocator, "✅ 任务创建成功：{s}", .{title});
}

fn completeTask(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const list_id = argStr(args, "list_id", "");
    const task_id = argStr(args, "task_id", "");
    log.info("tool=complete_task list_id={s} task_id={s}", .{ list_id, task_id });

    if (list_id.len == 0 or task_id.len == 0) return err(allocator, "Missing required: list_id, task_id", .{});

    const raw = graph_tasks.completeTask(client, list_id, task_id) catch |e| {
        log.err("complete_task failed: {s}", .{@errorName(e)});
        return err(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.info("complete_task success", .{});
    return ok(allocator, "✅ 任务已完成 ({s})", .{task_id});
}

fn deleteTask(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
    const client = global_client orelse return mcp.ToolError.ExecutionFailed;
    const list_id = argStr(args, "list_id", "");
    const task_id = argStr(args, "task_id", "");
    log.info("tool=delete_task list_id={s} task_id={s}", .{ list_id, task_id });

    if (list_id.len == 0 or task_id.len == 0) return err(allocator, "Missing required: list_id, task_id", .{});

    const raw = graph_tasks.deleteTask(client, list_id, task_id) catch |e| {
        log.err("delete_task failed: {s}", .{@errorName(e)});
        return err(allocator, "Error: {s}", .{@errorName(e)});
    };
    defer allocator.free(raw);
    log.info("delete_task success", .{});
    return ok(allocator, "🗑️ 任务已删除 ({s})", .{task_id});
}

fn argStr(args: ?std.json.Value, key: []const u8, default: []const u8) []const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string) return v.string;
    return default;
}

fn argStrOpt(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (args) |a| if (a == .object) if (a.object.get(key)) |v| if (v == .string and v.string.len > 0) return v.string;
    return null;
}

fn ok(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args) };
}

fn err(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) mcp.ToolError!mcp.ToolResult {
    return mcp.ToolResult{ .text = try std.fmt.allocPrint(allocator, fmt, args), .is_error = true };
}
