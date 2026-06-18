/// Outlook MCP Server — Zig Implementation
/// Microsoft Graph API via MCP protocol (JSON-RPC 2.0 over stdio)

const std = @import("std");
const c = @cImport({
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

pub fn main() !void {
    log.init();

    // Parse argv: --help, --logout
    {
        const raw_fd = std.os.linux.open("/proc/self/cmdline", .{}, 0);
        if (raw_fd <= std.math.maxInt(i32)) {
            const fd: i32 = @intCast(raw_fd);
            defer _ = std.os.linux.close(fd);
            var cmd_buf: [4096]u8 = undefined;
            const n = std.os.linux.read(fd, &cmd_buf, cmd_buf.len);
            if (n > 0) {
                const args = cmd_buf[0..n];
                var i: usize = 0;
                while (i < args.len and args[i] != 0) i += 1;
                i += 1;
                const a1 = i;
                while (i < args.len and args[i] != 0) i += 1;
                if (i > a1) {
                    const arg1 = args[a1..i];
                    if (std.mem.eql(u8, arg1, "--help") or std.mem.eql(u8, arg1, "-h")) {
                        printUsage();
                        return;
                    }
                    if (std.mem.eql(u8, arg1, "--logout") or std.mem.eql(u8, arg1, "-l")) {
                        doLogout();
                        return;
                    }
                }
            }
        }
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    log.info("starting mcp-server-outlook v0.1.0", .{});

    // Initialize TLS
    tls.init() catch |e| { log.err("TLS init failed: {s}", .{@errorName(e)}); return e; };
    defer tls.deinit();
    log.debug("TLS initialized", .{});

    // Load config
    const config = config_mod.Config.load(allocator) catch |err| switch (err) {
        error.MissingClientId => {
            // Auto-create config template
            const home = c.getenv("HOME") orelse c.getenv("USERPROFILE");
            const home_slice = if (home) |h| std.mem.sliceTo(h, 0) else ".";
            const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/outlook-mcp", .{home_slice});
            const config_path = try std.fmt.allocPrint(allocator, "{s}/config", .{config_dir});
            defer allocator.free(config_dir);
            defer allocator.free(config_path);

            // Create config dir and template file
            const config_z = try allocator.alloc(u8, config_dir.len + 1);
            defer allocator.free(config_z);
            @memcpy(config_z[0..config_dir.len], config_dir);
            config_z[config_dir.len] = 0;
            _ = c.mkdir(config_z.ptr, 0o755); // ignore if exists

            // Write template if file doesn't exist
            const path_z = try allocator.alloc(u8, config_path.len + 1);
            defer allocator.free(path_z);
            @memcpy(path_z[0..config_path.len], config_path);
            path_z[config_path.len] = 0;

            const f = c.fopen(path_z.ptr, "r");
            if (f == null) {
                const fw = c.fopen(path_z.ptr, "w");
                if (fw) |fw_ptr| {
                    const tmpl =
                        "# Outlook MCP 配置文件\n" ++
                        "# 替换下面的 client id 为你自己的 Azure App Registration\n" ++
                        "CLIENT_ID = \"your-app-client-id\"\n";
                    _ = c.fwrite(tmpl.ptr, 1, tmpl.len, fw_ptr);
                    _ = c.fclose(fw_ptr);
                }
            } else {
                _ = c.fclose(f);
            }

            std.debug.print(
                \\⚠️  未找到 AZURE_CLIENT_ID
                \\
                \\  已创建配置模板：
                \\    {s}
                \\
                \\  请编辑该文件，将 your-app-client-id 替换为你的真实 Client ID。
                \\
                \\  或用环境变量：
                \\    AZURE_CLIENT_ID="your-app-client-id" ./outlook-mcp
                \\
                \\  进入诊断模式（仅 ping tool）
                \\
            , .{config_path});
            return runDiagnosticServer(allocator);
        },
        else => |e| return e,
    };
    defer {
        allocator.free(config.client_id);
        allocator.free(config.token_cache_path);
    }

    // Get access token
    log.info("attempting authentication (client_id={s})", .{config.client_id});
    const token = auth_oauth.getAccessToken(allocator, &config) catch |err| {
        log.err("auth failed: {s} — falling back to diagnostic mode", .{@errorName(err)});
        return runDiagnosticServer(allocator);
    };
    log.info("authenticated successfully, expires in {d}s", .{token.expires_in});

    // Create Graph client
    var graph_client = GraphClient.init(allocator, token.access_token);

    // Set global clients for handlers
    calendar_handlers.setClient(&graph_client);
    mail_handlers.setClient(&graph_client);
    task_handlers.setClient(&graph_client);

    // Create and run MCP server
    var server = mcp.Server.init(allocator, "outlook", "0.1.0");
    defer server.deinit();

    try registerTools(&server);
    log.info("starting MCP server with {d} tools", .{server.tools.count()});
    try server.run();
}

/// Register all 13 MCP tools
fn registerTools(server: *mcp.Server) !void {
    try server.addTool(.{
        .name = "list_events",
        .description = "查询未来 N 天的日历事件（默认 7 天）",
        .input_schema = makeSchema(.{}),
        .handler = calendar_handlers.list_events.handler,
    });
    try server.addTool(.{
        .name = "query_events",
        .description = "查询任意日期范围的事件（支持过去任意时间段）",
        .input_schema = makeSchema(.{}),
        .handler = calendar_handlers.query_events.handler,
    });
    try server.addTool(.{
        .name = "search_events",
        .description = "按关键词搜索日历事件标题",
        .input_schema = makeSchema(.{}),
        .handler = calendar_handlers.search_events.handler,
    });
    try server.addTool(.{
        .name = "create_event",
        .description = "创建新的日历事件",
        .input_schema = makeSchema(.{}),
        .handler = calendar_handlers.create_event.handler,
    });
    try server.addTool(.{
        .name = "list_emails",
        .description = "列出收件箱最新邮件",
        .input_schema = makeSchema(.{}),
        .handler = mail_handlers.list_emails.handler,
    });
    try server.addTool(.{
        .name = "send_email",
        .description = "发送邮件",
        .input_schema = makeSchema(.{}),
        .handler = mail_handlers.send_email.handler,
    });
    try server.addTool(.{
        .name = "search_emails",
        .description = "按关键词搜索邮件",
        .input_schema = makeSchema(.{}),
        .handler = mail_handlers.search_emails.handler,
    });
    try server.addTool(.{
        .name = "get_unread_count",
        .description = "获取未读邮件数量",
        .input_schema = makeSchema(.{}),
        .handler = mail_handlers.get_unread_count.handler,
    });
    try server.addTool(.{
        .name = "list_task_lists",
        .description = "列出所有待办任务清单",
        .input_schema = makeSchema(.{}),
        .handler = task_handlers.list_task_lists.handler,
    });
    try server.addTool(.{
        .name = "list_tasks",
        .description = "列出指定清单中的待办任务",
        .input_schema = makeSchema(.{}),
        .handler = task_handlers.list_tasks.handler,
    });
    try server.addTool(.{
        .name = "create_task",
        .description = "在指定清单中创建新任务",
        .input_schema = makeSchema(.{}),
        .handler = task_handlers.create_task.handler,
    });
    try server.addTool(.{
        .name = "complete_task",
        .description = "将任务标记为已完成",
        .input_schema = makeSchema(.{}),
        .handler = task_handlers.complete_task.handler,
    });
    try server.addTool(.{
        .name = "delete_task",
        .description = "删除指定任务",
        .input_schema = makeSchema(.{}),
        .handler = task_handlers.delete_task.handler,
    });
}

fn makeSchema(fields: anytype) std.json.Value {
    _ = fields;
    return .{
        .object = blk: {
            var obj = std.json.ObjectMap.empty;
            obj.put(std.heap.page_allocator, "type", .{ .string = "object" }) catch {};
            break :blk obj;
        },
    };
}

fn printUsage() void {
    const msg = @embedFile("usage.txt");
    _ = std.os.linux.write(std.posix.STDOUT_FILENO, msg.ptr, msg.len);
}

fn doLogout() void {
    // Delete token cache file
    const home = c.getenv("HOME") orelse c.getenv("USERPROFILE");
    const home_slice = if (home) |h| std.mem.sliceTo(h, 0) else ".";
    const config_dir = std.fmt.allocPrint(std.heap.page_allocator, "{s}/.config/outlook-mcp", .{home_slice}) catch ".";
    defer std.heap.page_allocator.free(config_dir);
    const token_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/token.json", .{config_dir}) catch ".";
    defer std.heap.page_allocator.free(token_path);

    const path_z = std.heap.page_allocator.alloc(u8, token_path.len + 1) catch return;
    defer std.heap.page_allocator.free(path_z);
    @memcpy(path_z[0..token_path.len], token_path);
    path_z[token_path.len] = 0;

    const ret = c.remove(path_z.ptr);
    if (ret == 0) {
        const ok = "✅ 已注销 — token 缓存文件已删除\n";
        _ = std.os.linux.write(std.posix.STDOUT_FILENO, ok.ptr, ok.len);
    } else {
        const fail = "ℹ️  没有已保存的登录凭证\n";
        _ = std.os.linux.write(std.posix.STDOUT_FILENO, fail.ptr, fail.len);
    }
}

fn runDiagnosticServer(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 诊断模式启动（仅 ping tool，无 Graph API）\n", .{});
    var server = mcp.Server.init(allocator, "outlook-diagnostic", "0.1.0");
    defer server.deinit();

    try server.addTool(.{
        .name = "ping",
        .description = "Health check — returns 'pong'",
        .input_schema = makeSchema(.{}),
        .handler = struct {
            fn h(_: ?std.json.Value, alloc: std.mem.Allocator) mcp.ToolError!mcp.ToolResult {
                return mcp.ToolResult{ .text = try std.fmt.allocPrint(alloc, "pong — 完整功能需设置 AZURE_CLIENT_ID\n  写入 ~/.config/outlook-mcp/config：\n    CLIENT_ID = \"your-app-client-id\"\n  或环境变量：AZURE_CLIENT_ID=\"...\" ./outlook-mcp", .{}) };
            }
        }.h,
    });

    try server.run();
}
