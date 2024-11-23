pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const inez = b.addModule("inez", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_test = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_test.root_module.addImport("inez", inez);

    const run_lib_test = b.addRunArtifact(lib_test);

    const test_step = b.step("test", "Run the unit tests");

    test_step.dependOn(&run_lib_test.step);

    // examples
    {
        const Example = enum { @"ini-path" };
        const example_step = b.step("example", "Run an example");
        const example_option = b.option(Example, "example", "An example name to run with the `example` step (default: chat-gippity)") orelse Example.@"ini-path";

        const example_exe = b.addExecutable(.{
            .name = @tagName(example_option),
            .root_source_file = b.path(b.fmt("examples/{s}/main.zig", .{@tagName(example_option)})),
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("inez", inez);

        const run_example_exe = b.addRunArtifact(example_exe);
        example_step.dependOn(&run_example_exe.step);

        if (b.args) |args| {
            run_example_exe.addArgs(args);
        }

        b.installArtifact(example_exe);
    }

    // docs
    {
        const docs_lib = b.addStaticLibrary(.{
            .name = "docs_lib",
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        const docs_step = b.step("docs", "Emit docs");
        const docs_install = b.addInstallDirectory(.{
            .install_dir = .prefix,
            .install_subdir = "docs",
            .source_dir = docs_lib.getEmittedDocs(),
        });
        docs_step.dependOn(&docs_install.step);
    }
}

const std = @import("std");
