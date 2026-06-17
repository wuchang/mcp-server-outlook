# Design — Microsoft Graph MCP (Zig)

## 外部依赖

唯一的外部依赖是 [`mcp.zig`](https://muhammad-fiaz.github.io/mcp.zig/)（v0.0.5+），负责处理：

- JSON-RPC 2.0 协议
- MCP 生命周期（initialize / tools/list / tools/call）
- Stdio 传输层

`zig fetch --save https://github.com/muhammad-fiaz/mcp.zig/archive/refs/tags/0.0.5.tar.gz`

## 模块分解

```
src/
├── main.zig        入口 — 创建 Server、注册工具、启动 stdio
├── config.zig      读 AZURE_CLIENT_ID 环境变量
├── auth/
│   ├── oauth.zig   Device Code Flow + token 刷新
│   └── token_cache.zig  本地 token 持久化
├── graph/
│   ├── client.zig  Graph REST 客户端（get/post/patch/delete）
│   ├── calendar.zig  日历 API
│   ├── mail.zig      邮件 API
│   └── tasks.zig     待办 API
└── handlers/
    ├── calendar_handlers.zig  4 个 tool
    ├── mail_handlers.zig      4 个 tool
    └── task_handlers.zig      5 个 tool
```

### `main.zig`

```zig
const mcp = @import("mcp");

var server: mcp.Server = .init(allocator, .{
    .name = "outlook",
    .version = "0.1.0",
});
defer server.deinit();

try server.addTool(.{ .name = "list_events", .description = "...", .handler = handlerFn });
// ... 注册其余 12 个 tool

try server.run(io, allocator, .stdio);
```

### `auth/`

调用 Microsoft 身份平台的 Device Code Flow：

1. `POST /common/oauth2/v2.0/devicecode` → 获取设备码 + 用户码
2. 打印验证 URL 和用户码到终端
3. 轮询 `POST /common/oauth2/v2.0/token` 直到用户登录完成
4. 缓存 refresh token 到 `~/.cache/outlook-mcp/token.json`
5. 后续启动时静默用 refresh token 换 access token

使用 Zig 标准库 `std.http` 发请求，`std.json` 解析响应。

### `graph/`

`client.zig` 封装一个 `GraphClient`，持有 access token，提供通用 HTTP 方法。`calendar.zig` / `mail.zig` / `tasks.zig` 各自封装对应的 REST 端点，解析返回的 JSON 并格式化为文本。

### `handlers/`

每个 handler 函数签名：

```zig
fn handler(ctx: ?*anyopaque, io: std.Io, allocator: Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult
```

从 `args` 提取参数 → 调用 `graph/` 对应函数 → 用 `mcp.tools.textResult()` 返回文本结果。
