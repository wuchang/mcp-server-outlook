/// 轻量日志模块 — 输出到 stderr，不影响 MCP 协议（stdout）
///
/// 级别：debug < info < warn < err
/// 环境变量 OUTLOOK_LOG 控制级别，默认 "info"
///   OUTLOOK_LOG=debug ./mcp-server-outlook   # 详细日志
///   OUTLOOK_LOG=warn  ./mcp-server-outlook   # 仅警告+
///   OUTLOOK_LOG=off   ./mcp-server-outlook   # 完全静默

const std = @import("std");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const c = if (is_windows) @cImport({
    @cInclude("windows.h");
    @cInclude("stdlib.h");
    @cInclude("time.h");
    @cInclude("io.h");
}) else @cImport({
    @cInclude("stdlib.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

pub const Level = enum(u8) { debug, info, warn, err };

var g_level: Level = .info;
var g_start_ms: i64 = 0;

fn monoMs() i64 {
    if (is_windows) {
        return @as(i64, @intCast(c.GetTickCount64()));
    } else {
        var ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
        return @as(i64, @intCast(ts.tv_sec)) * 1000 + @divFloor(@as(i64, @intCast(ts.tv_nsec)), 1_000_000);
    }
}

pub fn init() void {
    g_start_ms = monoMs();
    const s = c.getenv("OUTLOOK_LOG");
    if (s == null) return;
    const val = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(s)), 0);
    if (std.ascii.eqlIgnoreCase(val, "debug")) g_level = .debug;
    if (std.ascii.eqlIgnoreCase(val, "trace")) g_level = .debug;
    if (std.ascii.eqlIgnoreCase(val, "warn")) g_level = .warn;
    if (std.ascii.eqlIgnoreCase(val, "err")) g_level = .err;
    if (std.ascii.eqlIgnoreCase(val, "error")) g_level = .err;
    if (std.ascii.eqlIgnoreCase(val, "off")) g_level = .err;
}

fn writeStderr(msg: []const u8) void {
    if (is_windows) {
        _ = c._write(2, msg.ptr, @as(c_uint, @intCast(msg.len)));
    } else {
        _ = c.write(2, msg.ptr, @as(c_uint, @intCast(msg.len)));
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

fn doLog(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(g_level) > @intFromEnum(level)) return;
    const el = elapsed();
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{d: >6}.{d:0>3} [{s}] " ++ fmt ++ "\n",
        .{ @divFloor(el, 1000), @mod(el, 1000), levelTag(level) } ++ args) catch fmt;
    writeStderr(msg);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    doLog(.debug, fmt, args);
}
pub fn info(comptime fmt: []const u8, args: anytype) void {
    doLog(.info, fmt, args);
}
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    doLog(.warn, fmt, args);
}
pub fn err(comptime fmt: []const u8, args: anytype) void {
    doLog(.err, fmt, args);
}
