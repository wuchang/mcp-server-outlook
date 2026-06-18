# Microsoft Graph MCP (Zig)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16-orange)](https://ziglang.org)

一个 Zig 编写的 MCP Server，通过 Microsoft Graph API 操作 Outlook 邮件、日历和待办任务。
编译为单二进制（~2MB），配合任何支持 MCP 协议的 AI agent 使用。

## 安装

### 从源码构建

```bash
# 系统依赖
sudo apt install libssl-dev   # Debian/Ubuntu
# 或 brew install openssl     # macOS
# 或 pacman -S openssl        # Arch

# 需要 Zig 0.16+
zig build -Doptimize=ReleaseSafe
```

产物在 `zig-out/bin/mcp-server-outlook`（Debug ~17MB，ReleaseSafe ~4MB / strip 后 ~750KB）。

### 验证

```bash
./zig-out/bin/mcp-server-outlook --help
```

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

## 配置

### 方式一：配置文件（推荐）

写入 `~/.config/outlook-mcp/config`：

```ini
CLIENT_ID = "your-app-client-id"
```

支持 `#` 注释，键名 `CLIENT_ID` 或 `AZURE_CLIENT_ID` 均可。

### 方式二：环境变量（覆盖文件配置）

```bash
AZURE_CLIENT_ID="your-app-client-id" ./zig-out/bin/mcp-server-outlook
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
登录成功后 Token 缓存到 `~/.config/outlook-mcp/token.json`，下次启动自动复用，无需重新登录。

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
    command="/path/to/mcp-server-outlook"
)
```

```json
// Claude Code — .claude/settings.local.json
{
  "mcpServers": {
    "outlook": {
      "command": "/path/to/mcp-server-outlook"
    }
  }
}
```

**OpenClaw**:

```bash
# 方式一：环境变量（无需配置文件）
openclaw mcp set outlook \
  '{"command":"/path/to/mcp-server-outlook","env":{"AZURE_CLIENT_ID":"your-client-id"}}'

# 方式二：配置文件
openclaw mcp set outlook \
  '{"command":"/path/to/mcp-server-outlook"}'
# 然后确保 ~/.config/outlook-mcp/config 里已写好 CLIENT_ID
```

## 测试

```bash
# 单元测试（Graph client mock）
zig build test

# 集成测试（需要 AZURE_CLIENT_ID 或已配置 ~/.config/outlook-mcp/config）
python3 test_mcp_client.py
```

## License

MIT
