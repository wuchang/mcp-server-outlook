/// Calendar Graph API — /me/calendar/events

const std = @import("std");
const c = @cImport({ @cInclude("time.h"); });
const gc = @import("client.zig");

const events_path = "/me/calendar/events";

fn now() i64 { return @as(i64, @intCast(c.time(null))); }

fn fmtIsoUtc(allocator: std.mem.Allocator, ts: i64) ![]const u8 {
    const gm_ptr = c.gmtime(&ts);
    if (gm_ptr == null) return "2025-01-01T00:00:00Z";
    const gm = gm_ptr.*;
    return std.fmt.allocPrint(allocator,
        "{d}-{s}-{s}T{s}:{s}:{s}Z",
        .{
            gm.tm_year + 1900,
            pad2(gm.tm_mon + 1),
            pad2(gm.tm_mday),
            pad2(gm.tm_hour),
            pad2(gm.tm_min),
            pad2(gm.tm_sec),
        }
    );
}

fn pad2(n: i32) [2]u8 {
    return .{ @intCast('0' + @divFloor(n, 10)), @intCast('0' + @mod(n, 10)) };
}

pub fn listEvents(client: *gc.GraphClient, days: i64) ![]const u8 {
    const t = now();
    const start = try fmtIsoUtc(client.allocator, t);
    defer client.allocator.free(start);
    const end = try fmtIsoUtc(client.allocator, t + days * 86400);
    defer client.allocator.free(end);

    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=20&$select=subject,start,end,location,showAs&$orderby=start/dateTime+asc&$filter=start/dateTime+ge+'{s}'+and+start/dateTime+le+'{s}'",
        .{ events_path, start, end }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn queryEvents(client: *gc.GraphClient, start_date: []const u8, end_date: []const u8) ![]const u8 {
    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=50&$select=subject,start,end,location,showAs&$orderby=start/dateTime+asc&$filter=start/dateTime+ge+'{s}T00:00:00Z'+and+start/dateTime+le+'{s}T23:59:59Z'",
        .{ events_path, start_date, end_date }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn searchEvents(client: *gc.GraphClient, keyword: []const u8) ![]const u8 {
    const path = try std.fmt.allocPrint(client.allocator,
        "{s}?$top=50&$select=subject,start,end,location,showAs&$orderby=start/dateTime+asc&$search=%22{s}%22",
        .{ events_path, keyword }
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
    var jbuf: [8192]u8 = undefined;
    const json = try std.fmt.bufPrint(&jbuf, "{f}", .{std.json.fmt(std.json.Value{ .object = obj }, .{})});
    return client.post(events_path, json);
}
