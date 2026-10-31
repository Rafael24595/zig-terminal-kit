const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const allow_deprecated = b.option(
        bool,
        "allow-deprecated",
        "Allow usage of deprecated features. This option will be removed in a future version.",
    ) orelse false;

    const main_options = b.addOptions();
    main_options.addOption(bool, "allow_deprecated", allow_deprecated);

    build_main(b, target, main_options);

    const test_options = b.addOptions();
    test_options.addOption(bool, "allow_deprecated", true);

    build_test(b, target, test_options);
}

fn build_main(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    options: *std.Build.Step.Options,
) void {
    const mod = b.addModule("zig_terminal_kit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = target.result.os.tag != .windows,
    });

    add_build_options(mod, options);
}

fn build_test(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    options: *std.Build.Step.Options,
) void {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .link_libc = target.result.os.tag != .windows,
    });

    add_build_options(test_mod, options);

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const test_step = b.step("test", "Run library tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const compile_tests_step = b.step("test-compile", "Compile library tests without running");
    compile_tests_step.dependOn(&tests.step);
}

fn add_build_options(
    mod: *std.Build.Module,
    options: *std.Build.Step.Options,
) void {
    mod.addImport("build_options", options.createModule());
}
