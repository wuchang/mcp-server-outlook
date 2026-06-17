/// Tasks Graph API — /me/todo/lists

const std = @import("std");
const gc = @import("client.zig");

pub fn listTaskLists(client: *gc.GraphClient) ![]const u8 {
    return client.get("/me/todo/lists");
}

pub fn listTasks(client: *gc.GraphClient, list_id: []const u8, status: ?[]const u8) ![]const u8 {
    const filter_part = if (status) |s| if (s.len > 0)
        try std.fmt.allocPrint(client.allocator, "&$filter=status eq '{s}'", .{s})
    else
        ""
    else
        "";
    defer if (filter_part.len > 0) client.allocator.free(filter_part);

    const path = try std.fmt.allocPrint(client.allocator,
        "/me/todo/lists/{s}/tasks?$select=title,id,status,dueDateTime{s}",
        .{ list_id, filter_part }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn createTask(client: *gc.GraphClient, list_id: []const u8, title: []const u8, due_date: ?[]const u8) ![]const u8 {
    var json = std.ArrayList(u8).empty;
    defer json.deinit(client.allocator);

    try json.appendSlice(client.allocator, "{\"title\":\"");
    try json.appendSlice(client.allocator, title);
    try json.appendSlice(client.allocator, "\"");

    if (due_date) |d| if (d.len > 0) {
        try json.appendSlice(client.allocator, ",\"dueDateTime\":{\"dateTime\":\"");
        try json.appendSlice(client.allocator, d);
        try json.appendSlice(client.allocator, "T23:59:59\",\"timeZone\":\"China Standard Time\"}");
    };

    try json.appendSlice(client.allocator, "}");

    const path = try std.fmt.allocPrint(client.allocator, "/me/todo/lists/{s}/tasks", .{list_id});
    defer client.allocator.free(path);
    return client.post(path, json.items);
}

pub fn completeTask(client: *gc.GraphClient, list_id: []const u8, task_id: []const u8) ![]const u8 {
    const body = "{\"status\":\"completed\",\"completedDateTime\":{\"dateTime\":\"2025-01-01T00:00:00Z\",\"timeZone\":\"UTC\"}}";
    const path = try std.fmt.allocPrint(client.allocator, "/me/todo/lists/{s}/tasks/{s}", .{ list_id, task_id });
    defer client.allocator.free(path);
    return client.patch(path, body);
}

pub fn deleteTask(client: *gc.GraphClient, list_id: []const u8, task_id: []const u8) ![]const u8 {
    const path = try std.fmt.allocPrint(client.allocator, "/me/todo/lists/{s}/tasks/{s}", .{ list_id, task_id });
    defer client.allocator.free(path);
    return client.delete(path);
}
