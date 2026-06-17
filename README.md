# Microsoft Graph MCP (Zig)

[![Zig](https://img.shields.io/badge/Zig-0.16-orange)](https://ziglang.org)

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
# 需要 zig 0.16+ 和系统 OpenSSL（libssl + libcrypto）
zig build -Doptimize=ReleaseSafe
```

## 配置

### 方式一：配置文件（推荐）

写入 `~/.config/outlook-mcp/config`：

```ini
CLIENT_ID = "your-app-client-id"
```

支持 `#` 注释，键名 `CLIENT_ID` 或 `AZURE_CLIENT_ID` 均可。

### 方式二：环境变量（覆盖文件配置）

```bash
AZURE_CLIENT_ID="your-app-client-id" ./zig-out/bin/outlook-mcp
```

两种方式都不设时进入**诊断模式**，仅提供 `ping` tool。

### 首次登录

运行后终端会显示：

```
🔐 请打开浏览器访问:
    https://microsoft.com/devicelogin

   验证码: ABC123XYZ
```

在浏览器中打开链接，输入验证码，用你的 Microsoft 账号授权即可。
登录成功后 Token 缓存到 `~/.cache/outlook-mcp/token.json`，下次自动复用。

### 获取 Client ID

去 [Azure Portal → App registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)：

1. **+ New registration**
2. 选 **"Accounts in any organizational directory"**
3. 平台选 **"Mobile and desktop applications"**
4. Redirect URI: `https://login.microsoftonline.com/common/oauth2/nativeclient`
5. 注册后复制 **Application (client) ID**

## 注册到 Agent

```bash
# Reasonix
add_mcp_server(
    name="outlook",
    transport="stdio",
    command="/path/to/outlook-mcp"
)
```

```json
// Claude Code — .claude/settings.local.json
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
