/// 全平台日志模块 — 输出到 stderr
/// 级别：debug < info < warn < err
/// OUTLOOK_LOG=debug|info|warn|err|off 控制级别，默认 info

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("__STDC_LIB_EXT1__", "0");
    @cDefine("__STDC_WANT_SECURE_LIB__", "0");
    @cInclude("stdlib.h");
    @cInclude("time.h");
    @cInclude("stdio.h");
});

pub const Level = enum(u8) { debug, info, warn, err };
var g_level: Level = .info;
var g_start_ms: i64 = 0;

/// 修改点：移除 std.os.linux 系统调用，用 libc time() 获取秒级时间戳
/// 跨平台：Windows/macOS/Linux 通用
fn monoMs() i64 {
    return @as(i64, @intCast(c.time(null))) * 1000;
}

pub fn init() void {
    g_start_ms = monoMs();
    const env = c.getenv("OUTLOOK_LOG");
    if (env == null) return;
    const val = std.mem.sliceTo(env, 0);
    if (std.ascii.eqlIgnoreCase(val, "debug") or std.ascii.eqlIgnoreCase(val, "trace")) {
        g_level = .debug;
    } else if (std.ascii.eqlIgnoreCase(val, "warn")) {
        g_level = .warn;
    } else if (std.ascii.eqlIgnoreCase(val, "err") or std.ascii.eqlIgnoreCase(val, "error") or std.ascii.eqlIgnoreCase(val, "off")) {
        g_level = .err;
    }
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

/// 写 stderr — 跨平台
fn writeStderr(msg: []const u8) void {
    // 使用 std.debug.print 跨平台输出到 stderr
    std.debug.print("{s}", .{msg});
}

fn doLog(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(g_level) > @intFromEnum(level)) return;
    const el = elapsed();
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{d:0>5}.{d:0>3} [{s}] " ++ fmt ++ "\n",
        .{ @divFloor(el, 1000), @mod(el, 1000), levelTag(level) } ++ args) catch return;
    writeStderr(msg);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void { doLog(.debug, fmt, args); }
pub fn info(comptime fmt: []const u8, args: anytype) void { doLog(.info, fmt, args); }
pub fn warn(comptime fmt: []const u8, args: anytype) void { doLog(.warn, fmt, args); }
pub fn err(comptime fmt: []const u8, args: anytype) void { doLog(.err, fmt, args); }
