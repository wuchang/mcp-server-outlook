/// Outlook MCP Server — Zig 全平台版

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cDefine("__STDC_LIB_EXT1__", "0");
    @cDefine("__STDC_WANT_SECURE_LIB__", "0");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
});
const log = @import("log.zig");
const config_mod = @import("config.zig");
const tls = @import("tls.zig");
const mcp = @import("mcp.zig");
const GraphClient = @import("graph/client.zig").GraphClient;
const calendar_handlers = @import("handlers/calendar.zig");
const mail_handlers = @import("handlers/mail.zig");
const task_handlers = @import("handlers/tasks.zig");
const auth_oauth = @import("auth/oauth.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    log.init();

    // ── 跨平台 args ──
    // 修改点：Windows 上 vector 是 []const u16，Posix 是 []const [*:0]u8
    if (comptime builtin.target.os.tag == .windows) {
        // Windows: 用 Args.Iterator 处理 WTF-16 → UTF-8 转换
        if (init.args.vector.len > 0) {
            var arg_it = std.process.Args.Iterator{ .inner = .{ .allocator = std.heap.page_allocator, .cmd_line = init.args.vector, .buffer = &.{} } };
            defer arg_it.deinit();
            _ = arg_it.next();
            if (arg_it.next()) |a| { handleArg(a); }
        }
    } else {
        // Posix: args 是 [*:0]u8 数组
        const vec = init.args.vector;
        if (vec.len > 1) {
            const arg1 = std.mem.sliceTo(vec[1], 0);
            handleArg(arg1);
        }
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    log.info("starting mcp-server-outlook v0.1.0", .{});
    tls.init() catch |e| { log.err("TLS: {s}", .{@errorName(e)}); return e; };
    defer tls.deinit();

    const config = config_mod.Config.load(a) catch |err| switch (err) {
        error.MissingClientId => {
            createConfigTemplate() catch {};
            log.warn("config template created, edit and re-run", .{});
            return runDiagnosticServer(a);
        },
        else => |e| return e,
    };
    defer { a.free(config.client_id); a.free(config.token_cache_path); }

    log.info("auth starting (client_id={s})", .{config.client_id});
    const token = auth_oauth.getAccessToken(a, &config) catch |err| {
        log.err("auth failed: {s}", .{@errorName(err)});
        return runDiagnosticServer(a);
    };
    log.info("authenticated, expires in {d}s", .{token.expires_in});

    var gc = GraphClient.init(a, token.access_token);
    calendar_handlers.setClient(&gc);
    mail_handlers.setClient(&gc);
    task_handlers.setClient(&gc);

    var server = mcp.Server.init(a, "outlook", "0.1.0");
    defer server.deinit();

    // 注册 13 个 tool
    try registerTools(&server);
    log.info("starting MCP server with 13 tools", .{});
    try server.run();
}

fn registerTools(server: *mcp.Server) !void {
    const s = mcp.emptySchema();
    try server.addTool(.{ .name = "list_events",       .description = "未来 N 天日历事件",     .input_schema = s, .handler = calendar_handlers.list_events.handler });
    try server.addTool(.{ .name = "query_events",      .description = "查询日期范围的事件",     .input_schema = s, .handler = calendar_handlers.query_events.handler });
    try server.addTool(.{ .name = "search_events",     .description = "按标题搜索事件",         .input_schema = s, .handler = calendar_handlers.search_events.handler });
    try server.addTool(.{ .name = "create_event",      .description = "创建日历事件",           .input_schema = s, .handler = calendar_handlers.create_event.handler });
    try server.addTool(.{ .name = "list_emails",       .description = "列出收件箱邮件",         .input_schema = s, .handler = mail_handlers.list_emails.handler });
    try server.addTool(.{ .name = "send_email",        .description = "发送邮件",               .input_schema = s, .handler = mail_handlers.send_email.handler });
    try server.addTool(.{ .name = "search_emails",     .description = "搜索邮件",               .input_schema = s, .handler = mail_handlers.search_emails.handler });
    try server.addTool(.{ .name = "get_unread_count",  .description = "未读邮件数量",           .input_schema = s, .handler = mail_handlers.get_unread_count.handler });
    try server.addTool(.{ .name = "list_task_lists",   .description = "列出任务清单",           .input_schema = s, .handler = task_handlers.list_task_lists.handler });
    try server.addTool(.{ .name = "list_tasks",        .description = "列出清单中任务",         .input_schema = s, .handler = task_handlers.list_tasks.handler });
    try server.addTool(.{ .name = "create_task",       .description = "创建任务",               .input_schema = s, .handler = task_handlers.create_task.handler });
    try server.addTool(.{ .name = "complete_task",     .description = "完成任务",               .input_schema = s, .handler = task_handlers.complete_task.handler });
    try server.addTool(.{ .name = "delete_task",       .description = "删除任务",               .input_schema = s, .handler = task_handlers.delete_task.handler });
}

fn handleArg(arg: []const u8) void {
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) { printUsage(); std.process.exit(0); }
    if (std.mem.eql(u8, arg, "--logout") or std.mem.eql(u8, arg, "-l")) { doLogout(); std.process.exit(0); }
}

fn getHome() []const u8 {
    if (comptime builtin.target.os.tag == .windows) {
        const d = c.getenv("USERPROFILE");
        return if (d) |p| std.mem.sliceTo(p, 0) else ".";
    } else {
        const d = c.getenv("HOME");
        return if (d) |p| std.mem.sliceTo(p, 0) else ".";
    }
}

fn createConfigTemplate() !void {
    const home = getHome();
    const base = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/.config/outlook-mcp", .{home});
    defer std.heap.page_allocator.free(base);
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/config", .{base});
    defer std.heap.page_allocator.free(path);
    const bz = try az(std.heap.page_allocator, base);
    defer std.heap.page_allocator.free(bz);
    if (builtin.target.os.tag == .windows) {
        _ = c.mkdir(@as([*:0]const u8, @ptrCast(bz.ptr)));
    } else {
        _ = c.mkdir(@as([*:0]const u8, @ptrCast(bz.ptr)), 0o755);
    }
    const pz = try az(std.heap.page_allocator, path);
    defer std.heap.page_allocator.free(pz);
    const f = c.fopen(@as([*:0]const u8, @ptrCast(pz.ptr)), "r");
    if (f == null) {
        const fw = c.fopen(@as([*:0]const u8, @ptrCast(pz.ptr)), "w") orelse return;
        const t = "# Outlook MCP\nCLIENT_ID = \"your-app-client-id\"\n";
        _ = c.fwrite(t.ptr, 1, t.len, fw); _ = c.fclose(fw);
    } else { _ = c.fclose(f); }
}

fn az(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    const z = try alloc.alloc(u8, s.len + 1);
    @memcpy(z[0..s.len], s); z[s.len] = 0; return z;
}

fn doLogout() void {
    const b = try_or_ret(std.fmt.allocPrint(std.heap.page_allocator, "{s}/.config/outlook-mcp", .{getHome()}));
    defer std.heap.page_allocator.free(b);
    const tp = try_or_ret(std.fmt.allocPrint(std.heap.page_allocator, "{s}/token.json", .{b}));
    defer std.heap.page_allocator.free(tp);
    const z = az(std.heap.page_allocator, tp) catch return;
    defer std.heap.page_allocator.free(z);
    if (c.remove(@as([*:0]const u8, @ptrCast(z.ptr))) == 0) {
        std.debug.print("✅ logout ok\n", .{});
    } else { std.debug.print("ℹ️  no token cache\n", .{}); }
}

fn try_or_ret(v: anyerror![]const u8) []const u8 {
    return v catch return "";
}

fn printUsage() void { std.debug.print("{s}", .{@embedFile("usage.txt")}); }

fn runDiagnosticServer(alloc: std.mem.Allocator) !void {
    log.info("diagnostic mode (ping only)", .{});
    var sv = mcp.Server.init(alloc, "outlook-diagnostic", "0.1.0");
    defer sv.deinit();
    try sv.addTool(.{ .name = "ping", .description = "health check", .input_schema = mcp.emptySchema(),
        .handler = struct { fn h(_: ?std.json.Value, a2: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
            return .{ .text = try std.fmt.allocPrint(a2, "pong", .{}) };
        } }.h,
    });
    try sv.run();
}
