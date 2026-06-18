/// 轻量日志模块 — 输出到 stderr
/// 级别：debug < info < warn < err
/// OUTLOOK_LOG=debug|info|warn|err|off 控制级别，默认 info

const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("time.h");
});

pub const Level = enum(u8) { debug, info, warn, err };
var g_level: Level = .info;
var g_start_ms: i64 = 0;

fn monoMs() i64 {
    // time(NULL) works on both Linux and Windows (libc)
    return @as(i64, @intCast(c.time(null))) * 1000;
}

pub fn init() void {
    g_start_ms = monoMs();
    const env = c.getenv("OUTLOOK_LOG");
    if (env == null) return;
    const val = std.mem.sliceTo(env, 0);
    if (std.ascii.eqlIgnoreCase(val, "debug")) g_level = .debug;
    if (std.ascii.eqlIgnoreCase(val, "trace")) g_level = .debug;
    if (std.ascii.eqlIgnoreCase(val, "warn")) g_level = .warn;
    if (std.ascii.eqlIgnoreCase(val, "err")) g_level = .err;
    if (std.ascii.eqlIgnoreCase(val, "error")) g_level = .err;
    if (std.ascii.eqlIgnoreCase(val, "off")) g_level = .err;
}

fn elapsed() i64 {
    return monoMs() - g_start_ms;
}

fn levelTag(level: Level) []const u8 {
    return switch (level) {
        .debug => "DEBG",
        .info => "INFO",
        .warn => "WARN",
        .err => "ERR!",
    };
}

fn doLog(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(g_level) > @intFromEnum(level)) return;
    const el = elapsed();
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{d:0>6}.{d:0>3} [{s}] " ++ fmt ++ "\n",
        .{ @divFloor(el, 1000), @mod(el, 1000), levelTag(level) } ++ args) catch "";
    _ = std.os.linux.write(std.posix.STDERR_FILENO, msg.ptr, msg.len);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void { doLog(.debug, fmt, args); }
pub fn info(comptime fmt: []const u8, args: anytype) void { doLog(.info, fmt, args); }
pub fn warn(comptime fmt: []const u8, args: anytype) void { doLog(.warn, fmt, args); }
pub fn err(comptime fmt: []const u8, args: anytype) void { doLog(.err, fmt, args); }
