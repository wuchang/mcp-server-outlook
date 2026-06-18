/// 配置加载 — 全平台路径适配
///
/// 优先级（后加载覆盖先加载）：
///   1. 环境变量 AZURE_CLIENT_ID
///   2. ~/.config/outlook-mcp/config (macOS/Linux)
///      %APPDATA%/outlook-mcp/config  (Windows)
///
/// 路径：
///   config:  XDG_CONFIG_HOME/outlook-mcp/config 或 %APPDATA%/outlook-mcp/config
///   token:   同目录下的 token.json

const std = @import("std");
const builtin = @import("builtin");

// 修改点：C 互操作仅在 Zig 无原生 API 时保留（环境变量）
const c = @cImport({
    // 使用 c_minimal.h 避免 MinGW 编译错误
    @cInclude("c_minimal.h");
});

pub const Config = struct {
    client_id: []const u8,
    scopes: []const []const u8,
    token_cache_path: []const u8,
    config_path: []const u8,

    pub fn load(allocator: std.mem.Allocator) !Config {
        const base = try getConfigDir(allocator);
        defer allocator.free(base);

        const config_path = try std.fmt.allocPrint(allocator, "{s}/config", .{base});
        errdefer allocator.free(config_path);
        const token_cache_path = try std.fmt.allocPrint(allocator, "{s}/token.json", .{base});
        errdefer allocator.free(token_cache_path);

        // 1. 读取配置文件
        var client_id: ?[]const u8 = try readConfigFile(allocator, config_path);

        // 2. 环境变量覆盖
        const env_val = c.getenv("AZURE_CLIENT_ID");
        if (env_val) |ptr| {
            if (client_id) |old| allocator.free(old);
            client_id = try allocator.dupe(u8, std.mem.sliceTo(ptr, 0));
        }

        const resolved = client_id orelse {
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

pub const Error = error{MissingClientId};

/// 跨平台配置目录：Linux/macOS 用 $HOME/.config/outlook-mcp，
/// Windows 用 %APPDATA%/outlook-mcp
fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (comptime builtin.target.os.tag == .windows) {
        // Windows: %APPDATA%/outlook-mcp
        const appdata = if (c.getenv("APPDATA")) |a| std.mem.sliceTo(a, 0) else ".";
        return std.fmt.allocPrint(allocator, "{s}/outlook-mcp", .{std.mem.sliceTo(appdata, 0)});
    } else {
        // macOS/Linux: $HOME/.config/outlook-mcp
        // 优先 XDG_CONFIG_HOME 环境变量
        const xdg = c.getenv("XDG_CONFIG_HOME");
        if (xdg) |ptr| {
            return std.fmt.allocPrint(allocator, "{s}/outlook-mcp", .{std.mem.sliceTo(ptr, 0)});
        }
        const home = if (c.getenv("HOME")) |h| std.mem.sliceTo(h, 0) else if (c.getenv("USERPROFILE")) |u| std.mem.sliceTo(u, 0) else ".";
        return std.fmt.allocPrint(allocator, "{s}/.config/outlook-mcp", .{std.mem.sliceTo(home, 0)});
    }
}

/// 读取 KEY=VALUE 格式的配置文件
fn readConfigFile(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    // 修改点：跨平台路径 null-terminated 后用 C fopen
    // Zig 0.16 的 std.fs 为空，无法替代
    const path_z = try allocator.alloc(u8, path.len + 1);
    defer allocator.free(path_z);
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;

    const f = c.fopen(@as([*:0]const u8, @ptrCast(path_z.ptr)), "r");
    if (f == null) return null;
    defer _ = c.fclose(f);

    var buf: [4096]u8 = undefined;
    var n: usize = 0;
    while (n < buf.len) {
        const ch = c.fgetc(f);
        if (ch < 0) break;
        buf[n] = @intCast(ch);
        n += 1;
    }
    if (n == 0) return null;

    const content = buf[0..@as(usize, @intCast(n))];
    var start: usize = 0;
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '\n' or i == content.len - 1) {
            const end = if (i < content.len and content[i] == '\n') i else i + 1;
            const ln = std.mem.trimEnd(u8, content[start..end], " \t\r\n");
            start = i + 1;
            if (ln.len == 0 or ln[0] == '#' or ln[0] == ';') continue;
            const eq_pos = std.mem.indexOfScalar(u8, ln, '=') orelse continue;
            const key = std.mem.trim(u8, ln[0..eq_pos], " \t");
            const value = std.mem.trim(u8, ln[eq_pos + 1 ..], " \t\"'");
            if (std.ascii.eqlIgnoreCase(key, "CLIENT_ID") or std.ascii.eqlIgnoreCase(key, "AZURE_CLIENT_ID")) {
                if (value.len > 0) return try allocator.dupe(u8, value);
            }
        }
    }
    return null;
}
