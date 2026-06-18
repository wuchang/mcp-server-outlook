const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Executable ──

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.link_libc = true;

    // tls.zig uses @cImport with tls_cimport.h — make src/ available as include path
    exe_mod.addIncludePath(.{ .cwd_relative = "src" });

    const openssl_dir = b.option([]const u8, "openssl-dir", "OpenSSL installation directory (include/ and lib/ subdirs expected)");
    if (openssl_dir) |dir| {
        exe_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ dir, "include" }) });
        exe_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ dir, "lib" }) });
    }
    if (target.result.os.tag == .windows) {
        // On Windows, Zig strips the "lib" prefix, so linkSystemLibrary("libssl")
        // passes -lssl which looks for ssl.lib — but vcpkg provides libssl.lib.
        // Use addObjectFile to reference the actual file instead.
        if (openssl_dir) |dir| {
            exe_mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ dir, "lib", "libssl.lib" }) });
            exe_mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ dir, "lib", "libcrypto.lib" }) });
        }
        exe_mod.linkSystemLibrary("ws2_32", .{});
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

    // Use a wrapper file that doesn't need `../` imports
    // Create the test in a file at src/ level
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
