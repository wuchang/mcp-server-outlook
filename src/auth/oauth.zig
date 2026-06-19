/// OAuth2 Device Code Flow — 全平台兼容
/// 修改点：移除 std.os.linux 系统调用，统一使用 libc 跨平台 API

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("c_minimal.h");
});
const log = @import("../log.zig");
const tls = @import("../tls.zig");
const token_cache = @import("token_cache.zig");

const login_host = "login.microsoftonline.com";
const login_path = "/common/oauth2/v2.0";

pub const AccessToken = struct {
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i64,
};

fn now() i64 {
    return @as(i64, @intCast(c.time(null)));
}

/// 跨平台 sleep（秒级）：Linux 用 nanosleep，macOS/Windows 用 libc sleep
fn sleepSec(sec: i64) void {
    var ts = c.struct_timespec{ .tv_sec = @intCast(sec), .tv_nsec = 0 };
    _ = c.nanosleep(&ts, null);
}

/// 写 stderr（跨平台）
fn writeErr(msg: []const u8) void {
    std.debug.print("{s}", .{msg});
}

pub fn getAccessToken(allocator: std.mem.Allocator, config: anytype) !AccessToken {
    const cache = token_cache.TokenCache.init(allocator, config.token_cache_path);

    // 尝试缓存
    if (cache.load() catch null) |cached| {
        if (cached.refresh_token.len > 0) {
            log.info("token found in cache, attempting refresh", .{});
            if (refreshAccessToken(allocator, config.client_id, cached.refresh_token)) |refreshed| {
                saveToken(allocator, &cache, &refreshed) catch {};
                log.info("token refreshed from cache", .{});
                return refreshed;
            } else |_| {
                log.info("refresh failed, starting new device code flow", .{});
            }
        }
        if (cached.access_token) |at| {
            if (cached.expires_at) |exp| {
                if (now() < exp - 60) {
                    return AccessToken{
                        .access_token = try allocator.dupe(u8, at),
                        .refresh_token = try allocator.dupe(u8, cached.refresh_token),
                        .expires_in = exp - now(),
                    };
                }
            }
        }
    }

    // Device Code Flow
    log.info("starting device code flow", .{});
    const device = try requestDeviceCode(allocator, config.client_id, config.scopes);
    log.info("device code obtained, polling every {d}s", .{device.interval});

    // 打印登录指引到 stderr
    const msg = try std.fmt.allocPrint(allocator,
        \\    
        \\🔐 请打开浏览器访问:
        \\    {s}
        \\
        \\   验证码: {s}
        \\
        \\
    , .{ device.verification_uri, device.user_code });
    defer allocator.free(msg);
    writeErr(msg);

    const token = try pollForToken(allocator, config.client_id, device.device_code, device.interval, device.expires_in);
    saveToken(allocator, &cache, &token) catch {};
    return token;
}

pub fn refreshAccessToken(allocator: std.mem.Allocator, client_id: []const u8, refresh_token_str: []const u8) !AccessToken {
    const body = try std.fmt.allocPrint(allocator,
        "client_id={s}&grant_type=refresh_token&refresh_token={s}",
        .{ client_id, refresh_token_str }
    );
    defer allocator.free(body);

    const response = try tls.postForm(allocator, login_host, 443, login_path ++ "/token", body);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    if (obj.get("error")) |_| return error.TokenRequestFailed;

    const access_token = getString(obj, "access_token") orelse return error.TokenRequestFailed;
    const new_refresh = getString(obj, "refresh_token") orelse refresh_token_str;

    return AccessToken{
        .access_token = try allocator.dupe(u8, access_token),
        .refresh_token = try allocator.dupe(u8, new_refresh),
        .expires_in = getInt(obj, "expires_in", 3600),
    };
}

fn requestDeviceCode(allocator: std.mem.Allocator, client_id: []const u8, scopes: []const []const u8) !struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    interval: i64,
    expires_in: i64,
} {
    var scope_buf = std.ArrayList(u8).empty;
    defer scope_buf.deinit(allocator);
    for (scopes, 0..) |s, i| {
        if (i > 0) try scope_buf.append(allocator, ' ');
        try scope_buf.appendSlice(allocator, s);
    }

    const body = try std.fmt.allocPrint(allocator, "client_id={s}&scope={s}", .{ client_id, scope_buf.items });
    defer allocator.free(body);

    const response = try tls.postForm(allocator, login_host, 443, login_path ++ "/devicecode", body);
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();

    const obj = parsed.value.object;
    if (obj.get("error") != null) return error.DeviceCodeFailed;

    return .{
        .device_code = try allocator.dupe(u8, getString(obj, "device_code") orelse return error.DeviceCodeFailed),
        .user_code = try allocator.dupe(u8, getString(obj, "user_code") orelse return error.DeviceCodeFailed),
        .verification_uri = try allocator.dupe(u8, getString(obj, "verification_uri") orelse "https://microsoft.com/devicelogin"),
        .interval = getInt(obj, "interval", 5),
        .expires_in = getInt(obj, "expires_in", 900),
    };
}

fn pollForToken(allocator: std.mem.Allocator, client_id: []const u8, device_code: []const u8, interval: i64, expires_in: i64) !AccessToken {
    const body = try std.fmt.allocPrint(allocator,
        "client_id={s}&grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code={s}",
        .{ client_id, device_code }
    );
    defer allocator.free(body);

    const start_time = now();
    var poll_count: u32 = 0;

    while (true) {
        sleepSec(interval);
        poll_count += 1;
        const elapsed = now() - start_time;
        if (elapsed > expires_in) {
            log.warn("device code expired after {d}s", .{elapsed});
            return error.ExpiredToken;
        }
        log.debug("polling token endpoint (attempt {d}, elapsed {d}s)", .{ poll_count, elapsed });

        const response = tls.postForm(allocator, login_host, 443, login_path ++ "/token", body) catch |err| {
            log.debug("poll error: {s}", .{@errorName(err)});
            // Windows: SslInitFailed means TLS not available
            // Other platforms: transient errors to retry on
            continue;
        };
        defer allocator.free(response);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch continue;
        defer parsed.deinit();

        const obj = parsed.value.object;
        if (obj.get("error")) |err_val| {
            const err_str = if (err_val == .string) err_val.string else "";
            log.debug("token poll returned error: {s}", .{err_str});
            if (std.mem.eql(u8, err_str, "authorization_pending") or
                std.mem.eql(u8, err_str, "slow_down")) {
                log.debug("waiting for user to complete login...", .{});
                continue;
            }
            if (std.mem.eql(u8, err_str, "expired_token")) return error.ExpiredToken;
            return error.AuthorizationPending;
        }

        log.debug("token response keys: access_token={} refresh_token={} expires_in={}", .{
            obj.get("access_token") != null,
            obj.get("refresh_token") != null,
            obj.get("expires_in") != null,
        });
        log.info("token obtained after {d} polls", .{poll_count});

        const access_token = getString(obj, "access_token") orelse return error.TokenRequestFailed;
        const refresh_token = getString(obj, "refresh_token") orelse access_token;
        const expires_in_val = getInt(obj, "expires_in", 3600);

        return AccessToken{
            .access_token = try allocator.dupe(u8, access_token),
            .refresh_token = try allocator.dupe(u8, refresh_token),
            .expires_in = expires_in_val,
        };
    }
}

fn saveToken(_: std.mem.Allocator, cache: *const token_cache.TokenCache, token: *const AccessToken) !void {
    try cache.save(.{
        .refresh_token = token.refresh_token,
        .access_token = token.access_token,
        .expires_at = now() + token.expires_in,
    });
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| if (v == .string) return v.string;
    return null;
}

fn getInt(obj: std.json.ObjectMap, key: []const u8, default: i64) i64 {
    if (obj.get(key)) |v| if (v == .integer) return @intCast(v.integer);
    return default;
}
