const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("zig_terminal_kit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const test_step = b.step("test", "Run library tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const compile_tests_step = b.step("test-compile", "Compile library tests without running");
    compile_tests_step.dependOn(&tests.step);
}
