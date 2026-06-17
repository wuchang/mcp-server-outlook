# Microsoft Graph MCP (Zig)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.14-orange)](https://ziglang.org)

A **single-binary** MCP server that exposes Microsoft 365 (Outlook / Exchange Online) capabilities — calendar, mail, and tasks — via the [Model Context Protocol](https://modelcontextprotocol.io).

Works with **any MCP-compatible agent**: Claude Code, Claude Desktop, Reasonix, OpenClaw, Cursor, and more.

## Features

### 📅 Calendar
| Tool | Description |
|------|-------------|
| `list_events` | List calendar events for the next N days |
| `query_events` | Query events in an arbitrary date range |
| `search_events` | Search events by keyword, optionally scoped to a date range |
| `create_event` | Create a new calendar event with subject, time, location, body |

### ✅ Tasks
| Tool | Description |
|------|-------------|
| `list_task_lists` | List all Microsoft To-Do task lists |
| `list_tasks` | List tasks in a list, optionally filtered by status |
| `create_task` | Create a new task with title and optional due date |
| `complete_task` | Mark a task as completed |
| `delete_task` | Delete a task |

### 📧 Mail
| Tool | Description |
|------|-------------|
| `list_emails` | List inbox emails, optionally filter by folder or unread only |
| `send_email` | Send an email with subject, body, CC, and file attachments |
| `search_emails` | Search emails by keyword across subject and body |
| `get_unread_count` | Get the count of unread emails |

## Quick Start

### 1. Download / Build

```bash
# Build from source (requires Zig 0.14+)
git clone https://github.com/<your-org>/microsoft-graph-mcp-zig.git
cd microsoft-graph-mcp-zig
zig build -Doptimize=ReleaseSafe

# Binary is at ./zig-out/bin/outlook-mcp
```

### 2. Azure App Registration

1. Go to [Azure Portal → App Registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. Create a **Public Client / Mobile and desktop application**
3. Add redirect URI: `https://login.microsoftonline.com/common/oauth2/nativeclient`
4. Enable **Allow public client flows**
5. Add these **Microsoft Graph delegated permissions**:
   - `Mail.ReadWrite`
   - `Mail.Send`
   - `Calendars.ReadWrite`
   - `User.Read`
   - `Tasks.ReadWrite`
6. Note the **Application (client) ID**

### 3. Configure

```bash
# Set your Azure App Client ID
export AZURE_CLIENT_ID="your-client-id-here"
```

Or create `~/.config/outlook-mcp/config.toml`:

```toml
client_id = "your-client-id-here"
```

### 4. Test

```bash
# Run directly (MCP stdio mode)
outlook-mcp

# Or test with a JSON-RPC request
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | outlook-mcp
```

### 5. Configure Your Agent

**Claude Code** — add to `.claude/settings.local.json`:

```json
{
  "mcpServers": {
    "outlook": {
      "command": "/path/to/outlook-mcp"
    }
  }
}
```

**Reasonix**:

```
add_mcp_server(name="outlook", transport="stdio", command="/path/to/outlook-mcp")
```

**OpenClaw / Others** — add a stdio MCP server entry pointing to the binary.

## Authentication

First use triggers a **Device Code Flow** — the server prints a URL and code. Open the URL in your browser, enter the code, and log in. Tokens are cached locally in `~/.cache/outlook-mcp/token.json` (encrypted at rest).

## Architecture

See [DESIGN.md](DESIGN.md) for the full module breakdown.

## License

MIT
