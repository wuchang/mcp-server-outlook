/// Calendar Graph API — /me/calendar/events

const std = @import("std");
const c = @cImport({ @cInclude("time.h"); });
const gc = @import("client.zig");

const events_path = "/me/calendar/events";

fn now() i64 { return c.time(null); }

fn pad2(buf: *[2]u8, n: i32) []const u8 {
    buf[0] = @intCast('0' + @divFloor(n, 10));
    buf[1] = @intCast('0' + @mod(n, 10));
    return buf;
}

fn fmtIsoUtc(allocator: std.mem.Allocator, ts: i64) ![]const u8 {
    const gm = c.gmtime(&ts);
    if (gm == null) return "2025-01-01T00:00:00Z";
    const y = gm.*.tm_year + 1900;
    const m = gm.*.tm_mon + 1;
    const d = gm.*.tm_mday;
    const hh = gm.*.tm_hour;
    const mm = gm.*.tm_min;
    const ss = gm.*.tm_sec;

    var mbuf: [2]u8 = undefined;
    var dbuf: [2]u8 = undefined;
    var hbuf: [2]u8 = undefined;
    var minbuf: [2]u8 = undefined;
    var sbuf: [2]u8 = undefined;

    return std.fmt.allocPrint(allocator, "{d}-{s}-{s}T{s}:{s}:{s}Z",
        .{ y, pad2(&mbuf, m), pad2(&dbuf, d), pad2(&hbuf, hh), pad2(&minbuf, mm), pad2(&sbuf, ss) }
    );
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
        "{s}?$top=50&$select=subject,start,end,location,showAs&$orderby=start/dateTime+asc&$search=\"{s}\"",
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
