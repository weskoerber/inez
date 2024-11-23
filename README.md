[![test](https://github.com/weskoerber/inez/actions/workflows/test.yaml/badge.svg)](https://github.com/weskoerber/inez/actions/workflows/test.yaml)
[![docs](https://github.com/weskoerber/inez/actions/workflows/docs.yaml/badge.svg)](https://github.com/weskoerber/inez/actions/workflows/docs.yaml)

# Inez - A fast INI parser

## Quickstart

1. Fetch *inez* using Zig's package manager

    ```shell
    zig fetch --save git+https://github.com/weskoerber/inez#main
    ```

2. Add *inez* to your artifacts in `build.zig`

    ```zig
    const std = @import("std");

    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const inez = b.dependency("inez", .{
                .target = target,
                .optimize = optimize,
        }).module("inez");

        const my_exe = b.addExecutable(.{
            .name = "my_exe",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        my_exe.root_module.addImport(inez);
    }
    ```

## Usage

To use *inez*, there are 4 main steps:
1. Initialize *inez*
2. Load a document
3. Parse the document
4. Use parsed document

See the `examples/` directory for some examples. You can run them by using the
`example` step (where `name` is the name of the example):
```shell
zig build example -Dexample=<name>
```
