const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.link_libc = true;
    exe_mod.addIncludePath(.{ .cwd_relative = "src" });

    // ── OpenSSL 库链接 ──
    // Windows MinGW: zig build -Dtarget=x86_64-windows-gnu -Dopenssl-dir=...
    // Linux/macOS: 系统动态链接
    const openssl_dir = b.option([]const u8, "openssl-dir",
        \\MinGW OpenSSL 目录。Linux 交叉编译 Windows 时：
        \\ sudo apt install mingw-w64-x86-64-dev
        \\ 或手动下载后解压，指定此路径。
    );
    if (target.result.os.tag == .windows) {
        if (target.result.abi == .gnu) {
            if (openssl_dir) |dir| {
                exe_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ dir, "include" }) });
                exe_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ dir, "lib" }) });
                exe_mod.linkSystemLibrary("ssl", .{});
                exe_mod.linkSystemLibrary("crypto", .{});
                exe_mod.linkSystemLibrary("ws2_32", .{});
            } else {
                @panic("交叉编译 Windows 需要 -Dopenssl-dir=指向 MinGW OpenSSL。\n  " ++
                    "获取方式: 安装 mingw-w64-x86-64-dev 或从 msys2 下载。");
            }
        }
    } else {
        exe_mod.linkSystemLibrary("ssl", .{});
        exe_mod.linkSystemLibrary("crypto", .{});
    }

    const exe = b.addExecutable(.{ .name = "mcp-server-outlook", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the MCP server (stdio mode)");
    run_step.dependOn(&run_cmd.step);

    // ── Tests ──
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test_graph.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.link_libc = true;
    const test_exe = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run Graph client unit tests");
    test_step.dependOn(&b.addRunArtifact(test_exe).step);
}
