/// Calendar Graph API — /me/calendar/events

const std = @import("std");
const c = @cImport({ @cInclude("time.h"); });
const gc = @import("client.zig");

const events_path = "/me/calendar/events";

fn now() i64 { return c.time(null); }

pub fn listEvents(client: *gc.GraphClient, days: i64) ![]const u8 {
    const t = now();
    const start_str = "2025-01-01T00:00:00Z"; // placeholder - TODO: format properly
    const end_str = "2025-01-08T00:00:00Z";
    _ = t;
    _ = days;

    const filter = try std.fmt.allocPrint(client.allocator,
        "start/dateTime ge '{s}' and start/dateTime le '{s}'",
        .{ start_str, end_str }
    );
    defer client.allocator.free(filter);

    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=20&$select=subject,start,end,location,showAs&$orderby=start/dateTime asc&$filter={s}",
        .{ events_path, filter }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn queryEvents(client: *gc.GraphClient, start_date: []const u8, end_date: []const u8) ![]const u8 {
    const filter = try std.fmt.allocPrint(client.allocator,
        "start/dateTime ge '{s}T00:00:00Z' and start/dateTime le '{s}T23:59:59Z'",
        .{ start_date, end_date }
    );
    defer client.allocator.free(filter);

    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=50&$select=subject,start,end,location,showAs&$orderby=start/dateTime asc&$filter={s}",
        .{ events_path, filter }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn searchEvents(client: *gc.GraphClient, _: []const u8) ![]const u8 {
    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=50&$select=subject,start,end,location,showAs&$orderby=start/dateTime asc",
        .{events_path}
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn createEvent(client: *gc.GraphClient, subject: []const u8, start: []const u8, end: []const u8, location: ?[]const u8, body: ?[]const u8) ![]const u8 {
    var obj = std.json.ObjectMap.empty;
    try obj.put(client.allocator, "subject", .{ .string = subject });

    var start_obj = std.json.ObjectMap.empty;
    try start_obj.put(client.allocator, "dateTime", .{ .string = start });
    try start_obj.put(client.allocator, "timeZone", .{ .string = "China Standard Time" });
    try obj.put(client.allocator, "start", .{ .object = start_obj });

    var end_obj = std.json.ObjectMap.empty;
    try end_obj.put(client.allocator, "dateTime", .{ .string = end });
    try end_obj.put(client.allocator, "timeZone", .{ .string = "China Standard Time" });
    try obj.put(client.allocator, "end", .{ .object = end_obj });

    if (location) |loc| if (loc.len > 0) {
        var loc_obj = std.json.ObjectMap.empty;
        try loc_obj.put(client.allocator, "displayName", .{ .string = loc });
        try obj.put(client.allocator, "location", .{ .object = loc_obj });
    };

    if (body) |b| if (b.len > 0) {
        var body_obj = std.json.ObjectMap.empty;
        try body_obj.put(client.allocator, "content", .{ .string = b });
        try body_obj.put(client.allocator, "contentType", .{ .string = "text" });
        try obj.put(client.allocator, "body", .{ .object = body_obj });
    };

    // Serialize to JSON using std.json.fmt
    var jbuf: [8192]u8 = undefined;
    const json = try std.fmt.bufPrint(&jbuf, "{f}", .{std.json.fmt(std.json.Value{ .object = obj }, .{})});
    return client.post(events_path, json);
}
