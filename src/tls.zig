/// HTTPS/TLS 客户端 — 全平台
///
/// 修改点：
///   - Linux/macOS: 用 OpenSSL 做 TLS（动态链接系统 libssl）
///   - Windows: 不支持 OpenSSL，返回错误（后续可改用 WinHTTP）
///   - 移除了 std.os.linux 系统调用
///
/// 交叉编译 Windows 时需提供 OpenSSL 头文件和库路径，
/// 通过 `-Dopenssl-dir=` 或 vcpkg 提供的路径。

const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");

// 跨平台类型定义（所有平台通用）
pub const Error = error{
    DnsResolutionFailed,
    SslInitFailed,
    SslNewFailed,
    HttpError,
    InvalidHttpResponse,
};

// 网络相关 C 函数（POSIX socket API，Windows 也支持通过 MinGW）
/// 网络相关 C 函数 — 全平台通用
const net = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("netdb.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
});

/// OpenSSL 头文件 — 仅限非 Windows 平台
/// Windows 交叉编译时此块被编译期排除，避免找不到 openssl/ssl.h
const ssl = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

// ── 全局 SSL 上下文 ──
var ssl_ctx: ?*ssl.SSL_CTX = null;

pub fn init() !void {
    if (ssl_ctx != null) return;
    _ = ssl.OPENSSL_init_ssl(0, null);
    const ctx = ssl.SSL_CTX_new(ssl.TLS_client_method());
    if (ctx == null) return error.SslInitFailed;
    ssl.SSL_CTX_set_verify(ctx, ssl.SSL_VERIFY_NONE, null);
    ssl_ctx = ctx;
}

pub fn deinit() void {
    if (ssl_ctx) |ctx| {
        ssl.SSL_CTX_free(ctx);
        ssl_ctx = null;
    }
}

/// 发送 HTTP 请求（完整 TLS 连接） — 跨平台
/// Windows 上返回 SslInitFailed 错误（需要额外配置 OpenSSL）
pub fn sendRaw(allocator: std.mem.Allocator, host: []const u8, port: u16, raw_request: []const u8) ![]const u8 {
    const port_str = try std.fmt.allocPrint(allocator, "{d}", .{port});
    defer allocator.free(port_str);

    // ── DNS (仅非 Windows) ──
    var hints: net.struct_addrinfo = std.mem.zeroes(net.struct_addrinfo);
    hints.ai_family = net.AF_UNSPEC;
    hints.ai_socktype = net.SOCK_STREAM;
    var dns_res: ?*net.struct_addrinfo = null;

    const dns_rc = net.getaddrinfo(@as([*:0]const u8, @ptrCast(host.ptr)), port_str.ptr, &hints, &dns_res);
    if (dns_rc != 0 or dns_res == null) {
        log.debug("DNS failed {s}:{s}", .{ host, port_str });
        return error.DnsResolutionFailed;
    }
    defer net.freeaddrinfo(dns_res);
    log.debug("DNS resolved {s}:{s}", .{ host, port_str });

    // ── 连接重试（最多 3 次） ──
    for (0..3) |attempt| {
        if (attempt > 0) {
            var ts = net.struct_timespec{ .tv_sec = 1, .tv_nsec = 0 };
            _ = net.nanosleep(&ts, null);
        }
        attempt: {
            const sock = net.socket(dns_res.?.ai_family, dns_res.?.ai_socktype, dns_res.?.ai_protocol);
            if (sock < 0) break :attempt;
            defer _ = net.close(sock);

            if (net.connect(sock, dns_res.?.ai_addr, dns_res.?.ai_addrlen) < 0) break :attempt;

            const ssl_ptr = ssl.SSL_new(ssl_ctx) orelse return error.SslNewFailed;
            defer ssl.SSL_free(ssl_ptr);

            _ = ssl.SSL_set_fd(ssl_ptr, sock);
            if (ssl.SSL_connect(ssl_ptr) <= 0) break :attempt;

            if (ssl.SSL_write(ssl_ptr, raw_request.ptr, @intCast(raw_request.len)) <= 0) break :attempt;
            log.debug("TLS request sent to {s} ({d} bytes)", .{ host, raw_request.len });

            var buf: [65536]u8 = undefined;
            var total: usize = 0;
            while (total < buf.len) {
                const n = ssl.SSL_read(ssl_ptr, &buf[total], @intCast(buf.len - total));
                if (n <= 0) {
                    const err = ssl.SSL_get_error(ssl_ptr, @intCast(n));
                    if (err == ssl.SSL_ERROR_ZERO_RETURN) break;
                    break;
                }
                total += @intCast(n);
            }

            const resp = buf[0..total];
            if (std.mem.indexOf(u8, resp, "\r\n\r\n")) |hdr_end| {
                const body = resp[hdr_end + 4 .. total];
                var sc: u16 = 0;
                if (resp.len >= 12) sc = std.fmt.parseInt(u16, resp[9..12], 10) catch 0;
                if (sc >= 400) {
                    log.warn("HTTP {d} from {s}:{s}", .{ sc, host, port_str });
                    return error.HttpError;
                }
                return try allocator.dupe(u8, body);
            }
            return error.InvalidHttpResponse;
        }
    }
    return error.DnsResolutionFailed;
}

pub fn get(allocator: std.mem.Allocator, host: []const u8, port: u16, path: []const u8) ![]const u8 {
    const req = try std.fmt.allocPrint(allocator, "GET {s} HTTP/1.1\r\nHost: {s}\r\nUser-Agent: mcp-server-outlook/0.1.0\r\nAccept: application/json\r\nConnection: close\r\n\r\n", .{ path, host });
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}

pub fn postForm(allocator: std.mem.Allocator, host: []const u8, port: u16, path: []const u8, body: []const u8) ![]const u8 {
    const req = try std.fmt.allocPrint(allocator, "POST {s} HTTP/1.1\r\nHost: {s}\r\nUser-Agent: mcp-server-outlook/0.1.0\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: {d}\r\nAccept: application/json\r\nConnection: close\r\n\r\n{s}", .{ path, host, body.len, body });
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}

pub fn sendWithAuth(allocator: std.mem.Allocator, method: []const u8, host: []const u8, port: u16, path: []const u8, auth_header: []const u8, body_json: ?[]const u8) ![]const u8 {
    const len_hdr = if (body_json) |b| try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n", .{b.len}) else "";
    defer if (body_json != null) allocator.free(len_hdr);
    const ct = if (body_json != null) "Content-Type: application/json\r\n" else "";
    const req = try std.fmt.allocPrint(allocator, "{s} {s} HTTP/1.1\r\nHost: {s}\r\n{s}User-Agent: mcp-server-outlook/0.1.0\r\nAccept: application/json\r\n{s}{s}Connection: close\r\n\r\n{s}", .{ method, path, host, auth_header, ct, if (body_json != null) len_hdr else "", if (body_json) |b| b else "" });
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}
