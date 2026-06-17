# Microsoft Graph MCP (Zig)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.14-orange)](https://ziglang.org)

一个 Zig 实现的 MCP Server，通过 Microsoft Graph API 操作 Outlook 邮件、日历和待办任务。
编译为单二进制，配合任何支持 MCP 协议的 AI agent 使用。

## 功能

| 分类 | Tool | 说明 |
|------|------|------|
| 📅 日历 | `list_events` | 查未来 N 天日历事件 |
| | `query_events` | 查任意日期范围的事件 |
| | `search_events` | 按关键词搜索事件 |
| | `create_event` | 创建事件 |
| ✅ 待办 | `list_task_lists` | 列出任务清单 |
| | `list_tasks` | 列出清单中的任务 |
| | `create_task` | 创建任务 |
| | `complete_task` | 完成任务 |
| | `delete_task` | 删除任务 |
| 📧 邮件 | `list_emails` | 列出邮件 |
| | `send_email` | 发送邮件 |
| | `search_emails` | 搜索邮件 |
| | `get_unread_count` | 未读数 |

## 构建

```bash
zig build -Doptimize=ReleaseSafe
./zig-out/bin/outlook-mcp
```

依赖 **Zig 0.14+**，零外部依赖。

## 配置

设置环境变量 `AZURE_CLIENT_ID`，首次运行会弹出浏览器进行 Device Code 登录。

## 注册到 Agent

**Claude Code** — 添加到 `.claude/settings.local.json`：

```json
{
  "mcpServers": {
    "outlook": {
      "command": "/path/to/outlook-mcp"
    }
  }
}
```

## License

MIT
