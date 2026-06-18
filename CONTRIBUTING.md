# Contributing

## 构建

```bash
# 依赖：Zig 0.16+, OpenSSL (libssl-dev)
zig build
zig build test
```

## 目录结构

```
src/
├── main.zig           # 入口
├── mcp.zig            # MCP 协议实现 (JSON-RPC 2.0)
├── tls.zig            # HTTPS 客户端 (OpenSSL)
├── log.zig            # 日志模块
├── config.zig         # 配置加载
├── auth/
│   ├── oauth.zig      # Device Code Flow
│   └── token_cache.zig
├── graph/
│   ├── client.zig     # Graph REST API 客户端
│   ├── calendar.zig
│   ├── mail.zig
│   └── tasks.zig
├── handlers/
│   ├── calendar.zig   # 4 tools
│   ├── mail.zig       # 4 tools
│   └── tasks.zig      # 5 tools
├── test_graph.zig     # 单元测试
└── usage.txt          # --help 文本
```

## 添加新 Tool

1. 在 `graph/` 下实现 Graph API 封装
2. 在 `handlers/` 下实现 handler 函数（签名：`fn(args: ?std.json.Value, allocator: std.mem.Allocator) mcp.ToolError!mcp.ToolResult`）
3. 在 `main.zig` 的 `registerTools()` 中注册

## 测试

```bash
# 单元测试
zig build test

# 集成测试（需要有效 token）
python3 test_mcp_client.py

# 调试
OUTLOOK_LOG=debug ./zig-out/bin/mcp-server-outlook
```

## 提交规范

- 小改动一个 commit，大改动分步
- PR 前确保 `zig build` 和 `zig build test` 通过
