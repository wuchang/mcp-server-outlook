# Design — Microsoft Graph MCP (Zig)

## Overview

```
┌──────────────┐    stdio / JSON-RPC 2.0     ┌──────────────────┐
│ MCP Agent    │ ◄─────────────────────────►  │  outlook-mcp     │
│ (Claude,     │                              │  (Zig binary)    │
│  Reasonix…)  │                              │                  │
└──────────────┘                              ├──────────────────┤
                                              │  mcp/            │
                                              │  auth/           │
                                              │  graph/          │
                                              │  handlers/       │
                                              └──────┬───────────┘
                                                     │ HTTPS
                                                     ▼
                                          ┌──────────────────┐
                                          │ Microsoft Graph   │
                                          │ graph.microsoft.  │
                                          │ com               │
                                          └──────────────────┘
```

## Module Breakdown

### `src/main.zig` — Entry Point

- Parse CLI flags (`--version`, `--help`)
- Load config from environment variables and config file
- Initialize the MCP stdio server
- Wire up tool handlers

Expected size: ~80 lines

### `src/mcp/` — MCP Protocol Layer

Core JSON-RPC 2.0 implementation over stdio. No external dependencies.

| File | Responsibility |
|------|---------------|
| `types.zig` | JSON-RPC request/response structs, MCP protocol types (Tool, ToolSchema, TextContent, etc.) |
| `server.zig` | Stdio transport loop: read JSON-RPC lines from stdin, dispatch to handler, write response to stdout |

**Protocol flow:**
1. Agent sends `initialize` request → Server responds with capabilities
2. Agent sends `notifications/initialized`
3. Agent may call `tools/list` → Server returns registered tool list
4. Agent calls `tools/call` with tool name + arguments → Server executes handler, returns result

Expected size: ~300 lines

### `src/auth/` — OAuth 2.0 Device Code Flow

| File | Responsibility |
|------|---------------|
| `oauth.zig` | Device Code Flow with Microsoft identity platform (login.microsoftonline.com) |
| `token_cache.zig` | Persistent token cache at `~/.cache/outlook-mcp/token.json` |

**Flow:**
1. `POST https://login.microsoftonline.com/common/oauth2/v2.0/devicecode` → get `device_code` + `user_code` + `verification_uri`
2. Print `user_code` + URL for user to open in browser
3. Poll `POST https://login.microsoftonline.com/common/oauth2/v2.0/token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code` until user completes login
4. Cache the refresh token locally
5. On subsequent runs, silently refresh the access token without user interaction

Expected size: ~200 lines

### `src/graph/` — Microsoft Graph REST Client

Generic HTTP + JSON layer for calling the Graph API, plus domain-specific endpoint wrappers.

| File | Responsibility |
|------|---------------|
| `client.zig` | Generic `GraphClient` — holds auth token, provides `get()`, `post()`, `patch()`, `delete()` methods against `graph.microsoft.com/v1.0` |
| `calendar.zig` | Calendar event endpoints: `GET /me/calendar/events`, `POST /me/calendar/events` |
| `mail.zig` | Mail endpoints: `GET /me/messages`, `POST /me/sendMail`, `GET /me/messages/$count` |
| `tasks.zig` | Todo task endpoints: `GET /me/todo/lists`, `GET /me/todo/lists/{id}/tasks`, `POST /me/todo/lists/{id}/tasks`, `PATCH …`, `DELETE …` |

Expected size: ~400 lines total

### `src/handlers/` — MCP Tool Implementations

Each handler accepts parsed arguments, calls the appropriate graph module, and returns formatted text.

| File | Tools |
|------|-------|
| `calendar_handlers.zig` | `list_events`, `query_events`, `search_events`, `create_event` |
| `mail_handlers.zig` | `list_emails`, `send_email`, `search_emails`, `get_unread_count` |
| `task_handlers.zig` | `list_task_lists`, `list_tasks`, `create_task`, `complete_task`, `delete_task` |

Expected size: ~350 lines total

### `src/config.zig` — Configuration

- Read `AZURE_CLIENT_ID` from environment variable
- Fall back to `~/.config/outlook-mcp/config.toml`
- Provide a `Config` struct with validated fields

Expected size: ~60 lines

## Dependencies (Zig)

| Dependency | Why | Bundled? |
|-----------|-----|----------|
| `std.http` | HTTPS requests to Graph API and OAuth endpoints | ✅ stdlib |
| `std.json` | JSON-RPC serialization and Graph API response parsing | ✅ stdlib |
| `std.fs` | Token cache file I/O | ✅ stdlib |
| `std.crypto` | Token cache encryption at rest | ✅ stdlib |
| `std.zig` | Build system | ✅ stdlib |

**Zero external dependencies.** All functionality is built on Zig's standard library.

## Project Structure

```
microsoft-graph-mcp-zig/
├── README.md
├── DESIGN.md
├── LICENSE
├── build.zig
├── build.zig.zon
└── src/
    ├── main.zig
    ├── config.zig
    ├── mcp/
    │   ├── types.zig
    │   └── server.zig
    ├── auth/
    │   ├── oauth.zig
    │   └── token_cache.zig
    ├── graph/
    │   ├── client.zig
    │   ├── calendar.zig
    │   ├── mail.zig
    │   └── tasks.zig
    └── handlers/
        ├── calendar_handlers.zig
        ├── mail_handlers.zig
        └── task_handlers.zig
```

## Future Considerations

- **Rate limiting** — Graph API has per-app and per-user throttle limits. Consider exponential backoff in `graph/client.zig`.
- **Token encryption** — The local token cache contains refresh tokens. Encrypt with machine-local key (DPAPI / Keychain) for production.
- **Multi-account** — Support multiple Azure tenant configurations via named profiles in config file.
- **CI/CD** — GitHub Actions: `zig build test` on push, release binaries on tag.
