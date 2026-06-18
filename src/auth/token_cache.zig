/// Token cache — persist refresh token to local file via libc

const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
});

pub const TokenCache = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) TokenCache {
        return .{ .allocator = allocator, .path = path };
    }

    pub fn load(self: *const TokenCache) !?TokenData {
        const path_z = try self.allocator.alloc(u8, self.path.len + 1);
        defer self.allocator.free(path_z);
        @memcpy(path_z[0..self.path.len], self.path);
        path_z[self.path.len] = 0;

        const f = c.fopen(@as([*:0]const u8, @ptrCast(path_z.ptr)), "r");
        if (f == null) return null;
        defer _ = c.fclose(f);

        var buf: [1024 * 16]u8 = undefined;
        const n = c.fread(&buf, 1, buf.len, f);
        if (n <= 0) return null;
        const content = buf[0..@as(usize, @intCast(n))];

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch return null;
        defer parsed.deinit();

        const obj = parsed.value.object;
        const refresh_token = if (obj.get("refresh_token")) |v| if (v == .string) v.string else return null else return null;
        const access_token = if (obj.get("access_token")) |v| if (v == .string) v.string else null else null;
        const expires_at = if (obj.get("expires_at")) |v| if (v == .integer) v.integer else null else null;

        return TokenData{
            .refresh_token = try self.allocator.dupe(u8, refresh_token),
            .access_token = if (access_token) |t| try self.allocator.dupe(u8, t) else null,
            .expires_at = expires_at,
        };
    }

    pub fn save(self: *const TokenCache, data: TokenData) !void {
        const path_z = try self.allocator.alloc(u8, self.path.len + 1);
        defer self.allocator.free(path_z);
        @memcpy(path_z[0..self.path.len], self.path);
        path_z[self.path.len] = 0;

        // mkdir -p
        if (std.mem.lastIndexOfScalar(u8, self.path, '/')) |slash| {
            var dir_z = try self.allocator.alloc(u8, slash + 1);
            defer self.allocator.free(dir_z);
            @memcpy(dir_z[0..slash], self.path[0..slash]);
            dir_z[slash] = 0;
            _ = c.mkdir(@as([*:0]const u8, @ptrCast(dir_z.ptr)), 0o755);
        }

        // Build JSON content
        var lines = std.ArrayList(u8).empty;
        defer lines.deinit(self.allocator);
        try lines.appendSlice(self.allocator, "{\"refresh_token\":\"");
        try lines.appendSlice(self.allocator, data.refresh_token);
        try lines.appendSlice(self.allocator, "\"");
        if (data.access_token) |t| {
            try lines.appendSlice(self.allocator, ",\"access_token\":\"");
            try lines.appendSlice(self.allocator, t);
            try lines.appendSlice(self.allocator, "\"");
        }
        if (data.expires_at) |e| {
            var buf: [32]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, ",\"expires_at\":{d}", .{e});
            try lines.appendSlice(self.allocator, s);
        }
        try lines.appendSlice(self.allocator, "}");

        const f = c.fopen(@as([*:0]const u8, @ptrCast(path_z.ptr)), "w");
        if (f == null) return;
        defer _ = c.fclose(f);
        _ = c.fwrite(lines.items.ptr, 1, lines.items.len, f);
    }

    pub fn clear(self: *const TokenCache) void {
        const path_z = self.allocator.alloc(u8, self.path.len + 1) catch return;
        defer self.allocator.free(path_z);
        @memcpy(path_z[0..self.path.len], self.path);
        path_z[self.path.len] = 0;
        _ = c.remove(@as([*:0]const u8, @ptrCast(path_z.ptr)));
    }
};

pub const TokenData = struct {
    refresh_token: []const u8,
    access_token: ?[]const u8 = null,
    expires_at: ?i64 = null,
};
