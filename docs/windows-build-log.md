# Windows 构建记录

这个项目原本是为 Linux 编写的 Zig MCP Server，以下是将其移植到 Windows（x86_64-windows-gnu）的完整过程。

---

## 第 1 轮 — 直接编译，失败

| 项目 | 内容 |
|------|------|
| **尝试** | 执行 `zig build` |
| **问题** | 不认识 `-Dopenssl-dir` 参数；`"openssl/ssl.h"` 找不到；默认 target 为 msvc，POSIX API 报错 |
| **方案** | 指定 `-Dtarget=x86_64-windows-gnu -Dopenssl-dir=...` |
| **结果** | ✅ 可行，但还有后续编译错误 |

---

## 第 2 轮 — 缺失 POSIX 头文件

| 项目 | 内容 |
|------|------|
| **尝试** | `zig build "-Dtarget=x86_64-windows-gnu" "-Dopenssl-dir=..."` |
| **问题** | `sys/socket.h`、`netdb.h`、`unistd.h` 在 MinGW 下找不到 |
| **方案** | 创建 `src/compat/sys/socket.h`、`src/compat/netdb.h`、`src/compat/unistd.h`，分别映射到 `<winsock2.h>`、`<ws2tcpip.h>`、`<io.h>`/`<process.h>`；build.zig 加 compat include path |
| **结果** | ✅ 头文件问题解决 |

---

## 第 3 轮 — `std.os.linux.*` 系统调用在 Windows 上不存在

| 项目 | 内容 |
|------|------|
| **尝试** | 修复头文件后编译 |
| **问题** | 代码大面积使用 `std.os.linux.open`、`std.os.linux.write`、`std.os.linux.read`、`std.os.linux.close` 等，Windows 上不存在 |
| **方案** | 逐个文件替换为 C 标准库/Windows API 等价物： |
| | • `tls.zig`: `c.close` → `c.closesocket`，`sock < 0` → `INVALID_SOCKET`，`c.nanosleep` → `c.Sleep` |
| | • `mcp.zig`: `std.io.getStdOut().write()` → `c._write(1,...)`，`std.io.getStdIn().read()` → `c._read(0,...)` |
| | • `log.zig`: `std.io.getStdErr().write()` → `c._write(2,...)`，`clock_gettime` → `GetTickCount64` |
| | • `config.zig`: `std.os.linux.open/read/close` → `c.fopen/fread/fclose` |
| | • `oauth.zig`: 同上模式 |
| | • `token_cache.zig`: `mkdir(path, mode)` → `mkdir(path)`，路径加 null 终止 |
| **结果** | ✅ 跨平台编译通过 |

---

## 第 4 轮 — `/proc/self/cmdline` 命令行参数获取

| 项目 | 内容 |
|------|------|
| **尝试** | 修复 syscall 后编译 |
| **问题** | `arg_parser.zig` 里用 `/proc/self/cmdline` 读取 argv（Linux only） |
| **方案** | Windows 用 `c.__p___argc()` / `c.__p___argv()`（CRT 函数）；POSIX 用 `@extern` 取 `__argc`/`__argv` |
| | 先试 `@extern(__argc)` — 失败，因为 `__argc` 在 MSVC/MinGW 里是**宏**不是符号；改用 CRT 函数解决 |
| **结果** | ✅ argv 获取正常 |

---

## 第 5 轮 — Winsock 未初始化

| 项目 | 内容 |
|------|------|
| **尝试** | 编译通过后首次运行 |
| **问题** | `socket()` 返回 INVALID_SOCKET，Winsock 未调用 `WSAStartup` |
| **方案** | 在 `tls.init()` 里加 `WSAStartup(0x202, &wsa)` |
| **结果** | ✅ socket 创建正常 |

---

## 第 6 轮 — 中文字符乱码

| 项目 | 内容 |
|------|------|
| **尝试** | 运行后看输出 |
| **问题** | 中文显示为 `???` 或乱码 |
| **方案** | 在 `main()` 开头加 `SetConsoleOutputCP(65001)` |
| **结果** | ✅ 中文正常显示 |

---

## 第 7 轮 — `SSL_set_fd` 在 Windows 上失败

| 项目 | 内容 |
|------|------|
| **尝试** | HTTPS 请求 |
| **问题** | OpenSSL 的 `SSL_set_fd` 接受 `int` 文件描述符，但 Windows SOCKET 是 `UINT_PTR`；`_open_osfhandle` 转换的 fd 不好使 |
| **方案** | Windows 路径：`BIO_new(BIO_s_socket())` + `BIO_set_fd(bio, sock, BIO_NOCLOSE)` + `SSL_set_bio(ssl, bio, bio)` |
| **结果** | ✅ TLS 握手成功，HTTPS 连接正常 |

---

## 第 8 轮 — C API 调用因字符串未 null 终止而失败

| 项目 | 内容 |
|------|------|
| **尝试** | 调试 HTTPS 连接 |
| **问题** | `getaddrinfo` 偶尔返回非零；`fopen` 失败；`remove` 不工作 |
| **方案** | 所有传给 C API 的 Zig slice 都要手动加 `\x00` 或用 `alloc(u8, len+1)` + `@memcpy` + 末尾写 0 |
| **结果** | ✅ 所有 C API 调用正常 |

---

## 第 9 轮 — OAuth `authorization_pending` 导致退出

| 项目 | 内容 |
|------|------|
| **尝试** | 第一次用真实 Azure Client ID 运行 |
| **问题** | 设备码流中 `authorization_pending` 返回 HTTP 400，`tls.sendRaw` 返回 `error.HttpError` 并把 body 丢弃；`pollForToken` 的 catch 没处理该错误，直接退出轮询 |
| **方案** | 重构 `tls.zig`：`sendRaw` 拆为内部 `sendRawFull`（返回 `HttpResponse{body, status}`）和新 `sendRaw`（状态≥400 时返回 `HttpError`）；新增 `postFormRaw`；`pollForToken` 改用 `postFormRaw`，检查 JSON error 字段 |
| **结果** | ✅ 轮询持续工作，用户完成登录后 token 获取成功 |

---

## 第 10 轮 — 登录提示信息未显示

| 项目 | 内容 |
|------|------|
| **尝试** | 观察输出 |
| **问题** | `oauth.zig` 里登录提示用 `std.os.linux.write(STDERR_FILENO, ...)`，Windows 上不存在 |
| **方案** | 改为 `c._write(2, ...)` |
| **结果** | ✅ 登录提示正常显示到 stderr |

---

## 第 11 轮 — `doLogout` 同样用了 linux.write

| 项目 | 内容 |
|------|------|
| **尝试** | 编译构建 |
| **问题** | `main.zig:doLogout` 里也有 `std.os.linux.write`；修复时报 `stdout` 宏不能在 comptime 求值 |
| **方案** | 先试 `c.fwrite` → 不行（`stdout` 是 `__acrt_iob_func(1)` 调用）；改为 `c._write(1, ...)`（需在 cImport 加 `"io.h"`） |
| **结果** | ✅ 编译通过，logout 正常工作 |

---

## 第 12 轮 — GitHub Actions release.yml

| 项目 | 内容 |
|------|------|
| **尝试** | 用户问有没有 CI 配置 |
| **问题** | 无 `.github/workflows/` |
| **方案** | 创建 `release.yml`：Windows（scoop OpenSSL + Zig 0.16）、Linux（apt libssl-dev + Zig 0.16），打 tag 自动构建并发布 Release |
| **结果** | ✅ 已创建，待推送验证 |

---

## 第 13 轮 — README 构建文档

| 项目 | 内容 |
|------|------|
| **尝试** | 用户要求补充各平台构建方法 |
| **问题** | README 只有 Linux 构建说明 |
| **方案** | 补充 Linux / macOS / Windows 三平台构建命令、依赖安装、参数说明、Windows DLL 注意事项 |
| **结果** | ✅ 已更新 |

---

## 改动汇总

| 领域 | 改动范围 | 文件数 |
|------|---------|--------|
| 构建系统 | build.zig — 加 compat 路径、ws2_32、平台条件 OpenSSL 库名 | 1 |
| 兼容头文件 | `src/compat/sys/socket.h`, `netdb.h`, `unistd.h` | 3 |
| 平台条件编译 | `is_windows` + C 函数替代 Linux 系统调用 | 6 个 src 文件 |
| ARGV 获取 | `__p___argc/__p___argv` 替代 `/proc/self/cmdline` | 1 |
| Winsock 初始化 | `WSAStartup` 加到 `tls.init()` | 1 |
| UTF-8 控制台 | `SetConsoleOutputCP(65001)` | 1 |
| TLS 传输 | BIO_s_socket 路径替代 SSL_set_fd | 1 |
| 字符串 null 终止 | 所有 C API 调用手动加 `\x00` | 4 |
| OAuth 轮询 | 新增 postFormRaw / HttpResponse 结构体 | 2 |
| 自动构建 | `.github/workflows/release.yml` | 1 |
| 文档 | README + docs/windows-build-log.md | 2 |

总计改了 **10 个源文件**、**3 个兼容头文件**、**1 个 workflow 文件**、**2 个文档**。
