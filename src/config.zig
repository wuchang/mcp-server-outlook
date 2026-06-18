/// 配置加载 — XDG 惯例
///
/// 优先级（后加载的覆盖先加载的）：
///   1. 环境变量 AZURE_CLIENT_ID
///   2. ~/.config/outlook-mcp/config  (KEY=VALUE 格式)
///
/// 路径：
///   config file:  ~/.config/outlook-mcp/config
///   token cache:  ~/.config/outlook-mcp/token.json

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
});

pub const Config = struct {
    client_id: []const u8,
    scopes: []const []const u8,
    token_cache_path: []const u8,
    config_path: []const u8, // for error messages

    pub fn load(allocator: std.mem.Allocator) !Config {
        const home = getHome();
        const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/outlook-mcp", .{home});
        const config_path = try std.fmt.allocPrint(allocator, "{s}/config", .{config_dir});
        const token_cache_path = try std.fmt.allocPrint(allocator, "{s}/token.json", .{config_dir});

        // 1. Try reading config file
        var client_id: ?[]const u8 = try readConfigFile(allocator, config_path);

        // 2. Env var overrides file
        const env_val = c.getenv("AZURE_CLIENT_ID");
        if (env_val) |ptr| {
            if (client_id) |old| allocator.free(old);
            client_id = try allocator.dupe(u8, std.mem.sliceTo(ptr, 0));
        }

        const resolved = client_id orelse {
            allocator.free(config_dir);
            allocator.free(config_path);
            allocator.free(token_cache_path);
            return error.MissingClientId;
        };

        const scopes = try allocator.alloc([]const u8, 6);
        scopes[0] = "offline_access";
        scopes[1] = "Mail.ReadWrite";
        scopes[2] = "Mail.Send";
        scopes[3] = "Calendars.ReadWrite";
        scopes[4] = "User.Read";
        scopes[5] = "Tasks.ReadWrite";

        return Config{
            .client_id = resolved,
            .scopes = scopes,
            .token_cache_path = token_cache_path,
            .config_path = config_path,
        };
    }
};

pub const Error = error{
    MissingClientId,
};

fn getHome() []const u8 {
    const h = c.getenv("HOME") orelse c.getenv("USERPROFILE");
    return if (h) |ptr| std.mem.sliceTo(ptr, 0) else ".";
}

/// Read KEY=VALUE lines from config file, look for CLIENT_ID
fn readConfigFile(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    // Use POSIX open/read — avoids fgets C translation bug in ReleaseSafe
    const path_z = try allocator.alloc(u8, path.len + 1);
    defer allocator.free(path_z);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;

    const raw_fd = std.os.linux.open(@as([*:0]const u8, @ptrCast(path_z.ptr)), .{}, 0);
    if (raw_fd > std.math.maxInt(i32)) return null;
    const fd: i32 = @intCast(raw_fd);
    defer _ = std.os.linux.close(fd);

    var buf: [4096]u8 = undefined;
    const n = std.os.linux.read(fd, &buf, buf.len);
    if (n == 0) return null;

    // Parse line by line
    var start: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (buf[i] == '\n' or i == n - 1) {
            const end = if (i < n and buf[i] == '\n') i else i + 1;
            const ln = std.mem.trimEnd(u8, buf[start..end], " \t\r\n");
            start = i + 1;

            if (ln.len == 0 or ln[0] == '#' or ln[0] == ';') continue;

            const eq_pos = std.mem.indexOfScalar(u8, ln, '=') orelse continue;
            const key = std.mem.trim(u8, ln[0..eq_pos], " \t");
            const value = std.mem.trim(u8, ln[eq_pos + 1 ..], " \t\"'");

            if (std.ascii.eqlIgnoreCase(key, "CLIENT_ID") or std.ascii.eqlIgnoreCase(key, "AZURE_CLIENT_ID")) {
                if (value.len > 0) {
                    return try allocator.dupe(u8, value);
                }
            }
        }
    }

    return null;
}
