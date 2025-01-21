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

    // ffi
    const ffi_static = b.addStaticLibrary(.{
        .name = "inez",
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const ffi_shared = b.addSharedLibrary(.{
        .name = "inez",
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    ffi_static.root_module.addImport("inez", inez);
    ffi_shared.root_module.addImport("inez", inez);

    const ffi_step = b.step("ffi", "Build FFI (C) bindings");
    const ffi_install_static = b.addInstallArtifact(ffi_static, .{});
    const ffi_install_shared = b.addInstallArtifact(ffi_shared, .{});

    ffi_step.dependOn(&ffi_install_static.step);
    ffi_step.dependOn(&ffi_install_shared.step);

    b.getInstallStep().dependOn(&ffi_install_static.step);
    b.getInstallStep().dependOn(&ffi_install_shared.step);

    // examples
    {
        const Example = enum { @"ini-path", @"ffi-c" };

        inline for (std.meta.fields(Example)) |field| {
            const example: Example = @enumFromInt(field.value);
            const example_name = field.name;
            const example_step = b.step("run-" ++ example_name, "Run the " ++ example_name ++ " example");

            const example_exe = switch (example) {
                .@"ini-path" => b: {
                    const example_exe = b.addExecutable(.{
                        .name = example_name,
                        .root_source_file = b.path(b.fmt("examples/{s}/main.zig", .{example_name})),
                        .target = target,
                        .optimize = .ReleaseFast,
                    });
                    example_exe.root_module.addImport("inez", inez);

                    break :b example_exe;
                },
                .@"ffi-c" => b: {
                    const example_exe = b.addExecutable(.{
                        .name = example_name,
                        .target = target,
                        .optimize = .ReleaseFast,
                        .link_libc = true,
                    });

                    example_exe.addIncludePath(b.path("include"));
                    example_exe.addCSourceFile(.{ .file = b.path(b.fmt("examples/{s}/main.c", .{example_name})) });
                    example_exe.linkLibrary(ffi_static);

                    break :b example_exe;
                },
            };

            const run_example_exe = b.addRunArtifact(example_exe);
            example_step.dependOn(&run_example_exe.step);

            if (b.args) |args| {
                run_example_exe.addArgs(args);
            }

            const install_example_exe = b.addInstallArtifact(example_exe, .{ .dest_dir = .{ .override = .{ .custom = "bin/examples" } } });
            b.getInstallStep().dependOn(&install_example_exe.step);
        }
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
