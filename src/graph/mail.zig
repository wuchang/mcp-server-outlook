/// Mail Graph API — /me/messages / /me/sendMail

const std = @import("std");
const gc = @import("client.zig");

pub fn listEmails(client: *gc.GraphClient, top: i64, unread_only: bool) ![]const u8 {
    const filter_part = if (unread_only) "&$filter=isRead eq false" else "";
    const path = try std.fmt.allocPrint(client.allocator,
        "/me/mailFolders/inbox/messages?$top={d}&$select=subject,from,receivedDateTime,isRead,bodyPreview&$orderby=receivedDateTime desc{s}",
        .{ top, filter_part }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn sendEmail(client: *gc.GraphClient, to: []const u8, subject: []const u8, body: []const u8, cc: ?[]const u8, _: ?[]const []const u8) ![]const u8 {
    // Build JSON manually using allocPrint
    var json = std.ArrayList(u8).empty;
    defer json.deinit(client.allocator);

    try json.appendSlice(client.allocator, "{\"message\":{\"subject\":\"");
    try json.appendSlice(client.allocator, subject);
    try json.appendSlice(client.allocator, "\",\"body\":{\"contentType\":\"Text\",\"content\":\"");
    try json.appendSlice(client.allocator, body);
    try json.appendSlice(client.allocator, "\"}");

    // To recipients
    try json.appendSlice(client.allocator, ",\"toRecipients\":[");
    var first = true;
    var iter = std.mem.splitScalar(u8, to, ';');
    while (iter.next()) |addr| {
        const trimmed = std.mem.trim(u8, addr, " ");
        if (trimmed.len == 0) continue;
        if (!first) try json.appendSlice(client.allocator, ",");
        first = false;
        try json.appendSlice(client.allocator, "{\"emailAddress\":{\"address\":\"");
        try json.appendSlice(client.allocator, trimmed);
        try json.appendSlice(client.allocator, "\"}}");
    }
    try json.appendSlice(client.allocator, "]");

    // CC recipients
    if (cc) |cc_str| if (cc_str.len > 0) {
        try json.appendSlice(client.allocator, ",\"ccRecipients\":[");
        first = true;
        var cc_iter = std.mem.splitScalar(u8, cc_str, ';');
        while (cc_iter.next()) |addr| {
            const trimmed = std.mem.trim(u8, addr, " ");
            if (trimmed.len == 0) continue;
            if (!first) try json.appendSlice(client.allocator, ",");
            first = false;
            try json.appendSlice(client.allocator, "{\"emailAddress\":{\"address\":\"");
            try json.appendSlice(client.allocator, trimmed);
            try json.appendSlice(client.allocator, "\"}}");
        }
        try json.appendSlice(client.allocator, "]");
    };

    try json.appendSlice(client.allocator, "}}");
    return client.post("/me/sendMail", json.items);
}

pub fn searchEmails(client: *gc.GraphClient, keyword: []const u8, top: i64) ![]const u8 {
    const path = try std.fmt.allocPrint(client.allocator,
        "/me/messages?$top={d}&$search=\"{s}\"&$select=subject,from,receivedDateTime,isRead,bodyPreview&$orderby=receivedDateTime desc",
        .{ top, keyword }
    );
    defer client.allocator.free(path);
    return client.get(path);
}

pub fn getUnreadCount(client: *gc.GraphClient) ![]const u8 {
    return client.get("/me/mailFolders/inbox");
}
