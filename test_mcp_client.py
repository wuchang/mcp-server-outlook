#!/usr/bin/env python3
"""MCP client test — 验证 outlook-mcp Zig 二进制是否正常工作"""

import subprocess
import json
import sys
import os

BINARY = os.path.join(os.path.dirname(__file__), "zig-out", "bin", "mcp-server-outlook")


def send(proc, msg):
    line = json.dumps(msg) + "\n"
    proc.stdin.write(line.encode())
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())


def test(proc, label, msg):
    try:
        resp = send(proc, msg)
        ok = "error" not in resp
        print(f"  {'✓' if ok else '✗'} {label}")
        if not ok:
            print(f"      error: {resp['error']}")
        return resp, ok
    except Exception as e:
        print(f"  ✗ {label} — EXCEPTION: {e}")
        return None, False


def main():
    print("=" * 60)
    print("mcp-server-outlook 功能测试")
    print(f"binary: {BINARY}")
    print(f"env:    AZURE_CLIENT_ID={'set' if os.getenv('AZURE_CLIENT_ID') else 'NOT SET'}")
    print("=" * 60)

    proc = subprocess.Popen(
        [BINARY],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=os.environ,
    )

    passed = 0
    failed = 0

    try:
        # 1. initialize
        resp, ok = test(proc, "initialize", {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "clientInfo": {"name": "test", "version": "1.0"},
            },
        })
        if ok:
            passed += 1
            server = resp.get("result", {}).get("serverInfo", {})
            print(f"      server: {server.get('name')} v{server.get('version')}")
        else:
            failed += 1

        # 2. tools/list
        resp, ok = test(proc, "tools/list", {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
        })
        if ok:
            passed += 1
            tools = resp["result"]["tools"]
            print(f"      {len(tools)} tools registered")
            for t in tools:
                print(f"        - {t['name']}")
        else:
            failed += 1

        # 3. tools/call — list_events (一个真实的 Graph API 调用)
        resp, ok = test(proc, "tools/call list_events", {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "list_events", "arguments": {"days": 1}},
        })
        if ok:
            passed += 1
            text = resp["result"]["content"][0]["text"][:120]
            print(f"      list_events → {text}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    # 打印 stderr 日志
    stderr_out = proc.stderr.read().decode()
    if stderr_out.strip():
        print("-" * 60)
        print("stderr log:")
        for line in stderr_out.strip().split("\n"):
            # 过滤诊断信息，只留关键日志
            if any(kw in line for kw in ["INFO", "WARN", "ERR"]):
                print(f"  {line}")

    print("-" * 60)
    print(f"结果: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
