/// Token 持久化 — 跨平台文件操作
/// 修改点：移除 std.fs.cwd()（Zig 0.16 不存在），改用 C fopen/fwrite

const std = @import("std");
const c = @cImport({
    @cInclude("c_minimal.h");
});

pub const TokenCache = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) TokenCache {
        return .{ .allocator = allocator, .path = path };
    }

    pub fn load(self: *const TokenCache) !?TokenData {
        const path_z = try allocatorZ(self.allocator, self.path);
        defer self.allocator.free(path_z);

        const f = c.fopen(@as([*:0]const u8, @ptrCast(path_z.ptr)), "r");
        if (f == null) return null;
        defer _ = c.fclose(f);

        var buf: [1024 * 16]u8 = undefined;
        var n: usize = 0;
        while (n < buf.len) {
            const ch = c.fgetc(f);
            if (ch < 0) break;
            buf[n] = @intCast(ch);
            n += 1;
        }
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
        const path_z = try allocatorZ(self.allocator, self.path);
        defer self.allocator.free(path_z);

        // mkdir -p（跨平台：目录分隔符统一用 /，Windows 也支持）
        const slash = std.mem.lastIndexOfScalar(u8, self.path, '/') orelse std.mem.lastIndexOfScalar(u8, self.path, '\\');
        if (slash) |s| {
            var dir_z = try self.allocator.alloc(u8, s + 1);
            defer self.allocator.free(dir_z);
            @memcpy(dir_z[0..s], self.path[0..s]);
            dir_z[s] = 0;
            if (@import("builtin").target.os.tag == .windows) {
                _ = c.mkdir(@as([*:0]const u8, @ptrCast(dir_z.ptr)));
            } else {
                _ = c.mkdir(@as([*:0]const u8, @ptrCast(dir_z.ptr)), 0o755);
            }
        }

        // 构建 JSON
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
        const path_z = allocatorZ(self.allocator, self.path) catch return;
        defer self.allocator.free(path_z);
        _ = c.remove(@as([*:0]const u8, @ptrCast(path_z.ptr)));
    }
};

pub const TokenData = struct {
    refresh_token: []const u8,
    access_token: ?[]const u8 = null,
    expires_at: ?i64 = null,
};

fn allocatorZ(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const z = try allocator.alloc(u8, path.len + 1);
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    return z;
}
