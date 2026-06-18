# Changelog

## 0.1.0 — 2026-06-18

### Added

- 13 MCP tools: 日历 (4) + 邮件 (4) + 待办 (5)
- Device Code Flow 认证（Microsoft Identity Platform）
- Token 缓存自动刷新（`~/.config/outlook-mcp/token.json`）
- 配置文件支持（`~/.config/outlook-mcp/config`）
- 日志系统（`OUTLOOK_LOG=debug|info|warn|err|off`）
- DNS 缓存 fallback（网络不稳定时自动切换）
- 诊断模式（无 `AZURE_CLIENT_ID` 时提供 `ping` tool）
- `--help` / `--logout` 命令行选项
- HTTPS over OpenSSL
- 单元测试（Graph client mock，6 tests）
- 集成测试脚本（`test_mcp_client.py`）
- GitHub Actions CI (build + test)
- Release workflow (Linux + macOS 二进制)
