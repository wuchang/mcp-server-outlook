/// Token cache — persist refresh token to local file via libc

const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const TokenCache = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) TokenCache {
        return .{ .allocator = allocator, .path = path };
    }

    fn toCStr(self: *const TokenCache) ![:0]u8 {
        const z = try self.allocator.alloc(u8, self.path.len + 1);
        @memcpy(z[0..self.path.len], self.path);
        z[self.path.len] = 0;
        return z[0..self.path.len :0];
    }

    pub fn load(self: *const TokenCache) !?TokenData {
        const path_z = try self.toCStr();
        defer self.allocator.free(path_z);
        const file = c.fopen(path_z.ptr, "r");
        if (file == null) return null;
        defer _ = c.fclose(file);

        // Get file size
        _ = c.fseek(file, 0, c.SEEK_END);
        const size = c.ftell(file);
        if (size <= 0) return null;
        _ = c.fseek(file, 0, c.SEEK_SET);

        const buf = try self.allocator.alloc(u8, @as(usize, @intCast(size)));
        defer self.allocator.free(buf);

        const read = c.fread(buf.ptr, 1, buf.len, file);
        if (read <= 0) return null;
        const content = buf[0..@as(usize, @intCast(read))];

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
        // Ensure directory exists
        if (std.mem.indexOfScalar(u8, self.path, '/')) |_| {
            const dir_end = std.mem.lastIndexOfScalar(u8, self.path, '/').?;
            const dir_part = self.path[0..dir_end];
            // mkdir -p equivalent
            var dir_buf = try self.allocator.dupe(u8, dir_part);
            defer self.allocator.free(dir_buf);
            for (dir_buf, 0..) |*ch, i| {
                if (ch.* == '/') {
                    dir_buf[i] = 0;
                    _ = if (is_windows) c.mkdir(@as([*:0]const u8, @ptrCast(dir_buf.ptr))) else c.mkdir(@as([*:0]const u8, @ptrCast(dir_buf.ptr)), 0o755);
                    dir_buf[i] = '/';
                }
            }
            _ = if (is_windows) c.mkdir(@as([*:0]const u8, @ptrCast(dir_buf.ptr))) else c.mkdir(@as([*:0]const u8, @ptrCast(dir_buf.ptr)), 0o755);
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
        try lines.appendSlice(self.allocator, "}\n");

        const path_z = try self.toCStr();
        defer self.allocator.free(path_z);
        const file = c.fopen(path_z.ptr, "w");
        if (file == null) return;
        defer _ = c.fclose(file);
        _ = c.fwrite(lines.items.ptr, 1, lines.items.len, file);
    }

    pub fn clear(self: *const TokenCache) !void {
        const path_z = try self.toCStr();
        defer self.allocator.free(path_z);
        _ = c.remove(path_z.ptr);
    }
};

pub const TokenData = struct {
    refresh_token: []const u8,
    access_token: ?[]const u8 = null,
    expires_at: ?i64 = null,
};
