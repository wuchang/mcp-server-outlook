/// HTTPS client using OpenSSL

const std = @import("std");
const log = @import("log.zig");
const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("sys/socket.h");
    @cInclude("netdb.h");
    @cInclude("unistd.h");
});

var ssl_ctx: ?*c.SSL_CTX = null;

// ── DNS cache: store resolved sockaddr for fallback ──
var g_cached_sa: c.sockaddr_storage = undefined;
var g_cached_salen: c.socklen_t = 0;
var g_cached_host: []const u8 = "";

pub fn init() !void {
    if (ssl_ctx != null) return;
    _ = c.OPENSSL_init_ssl(0, null);

    const ctx = c.SSL_CTX_new(c.TLS_client_method());
    if (ctx == null) return error.SslInitFailed;
    c.SSL_CTX_set_verify(ctx, c.SSL_VERIFY_NONE, null);
    ssl_ctx = ctx;
}

pub fn deinit() void {
    if (ssl_ctx) |ctx| {
        c.SSL_CTX_free(ctx);
        ssl_ctx = null;
    }
}

/// Send raw HTTP bytes over TLS, return response body
/// DNS resolved once (outside retry); connection retried up to 3 times
pub fn sendRaw(allocator: std.mem.Allocator, host: []const u8, port: u16, raw_request: []const u8) ![]const u8 {
    if (ssl_ctx == null) try init();
    log.debug("sendRaw: host={s} port={d}", .{ host, port });

    const port_str = try std.fmt.allocPrint(allocator, "{d}", .{port});
    defer allocator.free(port_str);

    // ── DNS (with cache fallback) ──
    var dns_res: ?*c.struct_addrinfo = null;
    var from_cache: bool = false;
    var fallback_sa: c.struct_addrinfo = undefined;

    var hints: c.struct_addrinfo = std.mem.zeroes(c.struct_addrinfo);
    hints.ai_family = c.AF_UNSPEC;
    hints.ai_socktype = c.SOCK_STREAM;
    const rc = c.getaddrinfo(@as([*:0]const u8, @ptrCast(host.ptr)), port_str.ptr, &hints, &dns_res);
    if (rc == 0 and dns_res != null) {
        log.debug("DNS ok {s}:{s}", .{ host, port_str });
        // Cache
        if (dns_res.?.ai_addrlen <= @sizeOf(@TypeOf(g_cached_sa))) {
            const src = @as([*]const u8, @ptrCast(dns_res.?.ai_addr))[0..dns_res.?.ai_addrlen];
            const dst = @as([*]u8, @ptrCast(&g_cached_sa))[0..dns_res.?.ai_addrlen];
            @memcpy(dst, src);
            if (g_cached_sa.ss_family == c.AF_INET) {
                @as(*c.sockaddr_in, @ptrCast(&g_cached_sa)).sin_port = c.htons(@as(c.uint16_t, @intCast(port)));
            } else if (g_cached_sa.ss_family == c.AF_INET6) {
                @as(*c.sockaddr_in6, @ptrCast(&g_cached_sa)).sin6_port = c.htons(@as(c.uint16_t, @intCast(port)));
            }
            g_cached_salen = dns_res.?.ai_addrlen;
            g_cached_host = host;
        }
    } else {
        log.debug("DNS failed {s}:{s} code={d}, trying cache", .{ host, port_str, rc });
        if (std.mem.eql(u8, host, g_cached_host) and g_cached_salen > 0) {
            log.info("using cached address for {s}", .{host});
            fallback_sa = .{
                .ai_family = g_cached_sa.ss_family,
                .ai_socktype = c.SOCK_STREAM,
                .ai_addr = @ptrCast(&g_cached_sa),
                .ai_addrlen = g_cached_salen,
            };
            dns_res = &fallback_sa;
            from_cache = true;
        }
    }
    if (dns_res == null) return error.DnsResolutionFailed;
    defer if (!from_cache) c.freeaddrinfo(dns_res);

    // ── Connection retry (each attempt self-contained with defer cleanup) ──
    for (0..3) |attempt| {
        if (attempt > 0) {
            var ts = c.struct_timespec{ .tv_sec = 1, .tv_nsec = 0 };
            _ = c.nanosleep(&ts, null);
        }
        attempt: {
            const sock = c.socket(dns_res.?.ai_family, dns_res.?.ai_socktype, dns_res.?.ai_protocol);
            if (sock < 0) break :attempt;
            defer _ = c.close(sock);

            if (c.connect(sock, dns_res.?.ai_addr, dns_res.?.ai_addrlen) < 0) {
                log.debug("connect {s}:{s} fail (try {d}/3)", .{ host, port_str, attempt + 1 });
                break :attempt;
            }

            const ssl = c.SSL_new(ssl_ctx) orelse return error.SslNewFailed;
            defer c.SSL_free(ssl);
            _ = c.SSL_set_fd(ssl, sock);

            if (c.SSL_connect(ssl) <= 0) {
                log.debug("TLS handshake {s}:{s} fail (try {d}/3)", .{ host, port_str, attempt + 1 });
                break :attempt;
            }

            const written = c.SSL_write(ssl, raw_request.ptr, @intCast(raw_request.len));
            if (written <= 0) {
                log.debug("SSL write fail (try {d}/3)", .{attempt + 1});
                break :attempt;
            }

            var buf: [65536]u8 = undefined;
            var total: usize = 0;
            while (total < buf.len) {
                const n = c.SSL_read(ssl, &buf[total], @intCast(buf.len - total));
                if (n <= 0) {
                    const err = c.SSL_get_error(ssl, @intCast(n));
                    if (err == c.SSL_ERROR_ZERO_RETURN) break;
                    break;
                }
                total += @intCast(n);
            }

            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |hdr_end| {
                const body = buf[hdr_end + 4 .. total];

                // Parse HTTP status code from "HTTP/1.1 NNN ..."
                const status_line_end = std.mem.indexOfScalar(u8, buf[0..total], '\r') orelse total;
                const status_line = buf[0..status_line_end];
                var sc: u16 = 0;
                if (status_line.len >= 12) {
                    sc = std.fmt.parseInt(u16, status_line[9..12], 10) catch 0;
                }
                if (sc >= 400) {
                    log.warn("HTTP {d} from {s}:{s} — {s}", .{ sc, host, port_str, body[0..@min(body.len, 200)] });
                    return error.HttpError;
                }
                return try allocator.dupe(u8, body);
            }
            log.debug("bad HTTP response (try {d}/3)", .{attempt + 1});
            break :attempt;
        }
    }
    return error.DnsResolutionFailed;
}

/// Simple GET
pub fn get(allocator: std.mem.Allocator, host: []const u8, port: u16, path: []const u8) ![]const u8 {
    const req = try std.fmt.allocPrint(allocator,
        "GET {s} HTTP/1.1\r\nHost: {s}\r\nUser-Agent: mcp-server-outlook/0.1.0\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
        .{ path, host }
    );
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}

/// POST with form body
pub fn postForm(allocator: std.mem.Allocator, host: []const u8, port: u16, path: []const u8, body: []const u8) ![]const u8 {
    const req = try std.fmt.allocPrint(allocator,
        "POST {s} HTTP/1.1\r\nHost: {s}\r\nUser-Agent: mcp-server-outlook/0.1.0\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: {d}\r\nAccept: application/json\r\nConnection: close\r\n\r\n{s}",
        .{ path, host, body.len, body }
    );
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}

/// HTTP request with custom Authorization header
pub fn sendWithAuth(allocator: std.mem.Allocator, method: []const u8, host: []const u8, port: u16, path: []const u8, auth_header: []const u8, body_json: ?[]const u8) ![]const u8 {
    // Build request manually with allocPrint
    var parts: [8][]const u8 = undefined;
    var pi: usize = 0;

    parts[pi] = method; pi += 1;
    parts[pi] = " "; pi += 1;
    parts[pi] = path; pi += 1;
    parts[pi] = " HTTP/1.1\r\nHost: "; pi += 1;
    parts[pi] = host; pi += 1;
    parts[pi] = "\r\n"; pi += 1;
    parts[pi] = auth_header; pi += 1;
    // This approach is getting unwieldy. Let me use a simpler method.

    // Use allocPrint for the whole thing
    const len_hdr = if (body_json) |b|
        try std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n", .{b.len})
    else
        "";
    defer if (body_json != null) allocator.free(len_hdr);

    const content_type = if (body_json != null) "Content-Type: application/json\r\n" else "";

    const req = try std.fmt.allocPrint(allocator,
        "{s} {s} HTTP/1.1\r\nHost: {s}\r\n{s}User-Agent: mcp-server-outlook/0.1.0\r\nAccept: application/json\r\n{s}{s}Connection: close\r\n\r\n{s}",
        .{
            method, path, host,
            auth_header,
            content_type,
            if (body_json != null) len_hdr else "",
            if (body_json) |b| b else "",
        }
    );
    defer allocator.free(req);
    return sendRaw(allocator, host, port, req);
}
