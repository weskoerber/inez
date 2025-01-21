const InezContext = struct {
    /// The `inez.Ini` struct
    ini: inez.Ini,

    /// The parsed ini file
    parsed: ?inez.ParsedIni = null,

    /// Error details
    last_error: ?ErrorDetails = null,

    const ErrorDetails = struct {
        /// The Zig error code
        err: anyerror,

        /// A heap-allocated, human readable error message
        msg: ?[:0]const u8 = null,
    };

    pub fn setLastError(self: *InezContext, err: anyerror, comptime fmt: []const u8, args: anytype) void {
        if (self.last_error) |last_error| {
            if (last_error.msg) |msg| {
                self.ini.allocator.free(msg);
            }
        }

        self.last_error = .{
            .err = err,
            .msg = std.fmt.allocPrintZ(self.ini.allocator, fmt ++ "\n", args) catch @panic("OOM"),
        };
    }
};

export fn inezInit(max_read_size: usize) callconv(.C) *InezContext {
    const ctx = std.heap.c_allocator.create(InezContext) catch @panic("OOM");

    ctx.* = .{
        .ini = inez.Ini.init(std.heap.c_allocator, .{ .max_read_size = max_read_size }),
    };

    return ctx;
}

export fn inezDeinit(ptr: ?*InezContext) callconv(.C) void {
    std.debug.assert(ptr != null);

    var ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    ctx.ini.deinit();

    if (ctx.last_error) |err| {
        if (err.msg) |msg| {
            ctx.ini.allocator.free(msg);
        }
    }
    ctx.ini.allocator.destroy(ctx);

    if (ctx.parsed) |*parsed| {
        parsed.deinit();
    }
}

export fn inezLogLastError(ptr: ?*InezContext) void {
    std.debug.assert(ptr != null);

    const ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    if (ctx.last_error) |err| {
        if (err.msg) |msg| {
            std.log.err("{s}: {s}", .{ @errorName(err.err), msg });
        } else {
            std.log.err("{s}", .{@errorName(err.err)});
        }
    }
}

export fn inezLoadBuffer(ptr: ?*InezContext, buffer: ?[*]const u8, buffer_len: usize) void {
    std.debug.assert(ptr != null);
    std.debug.assert(buffer != null);
    std.debug.assert(buffer_len > 0);

    var ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    ctx.ini.loadBuffer(buffer.?[0..buffer_len]);
}

export fn inezLoadBufferOwned(ptr: ?*InezContext, buffer: ?[*]const u8, buffer_len: usize) void {
    std.debug.assert(ptr != null);
    std.debug.assert(buffer != null);
    std.debug.assert(buffer_len > 0);

    var ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    ctx.ini.loadBufferOwned(buffer.?[0..buffer_len]) catch @panic("OOM");
}

export fn inezLoadFile(ptr: ?*InezContext, path: ?[*:0]const u8) bool {
    std.debug.assert(ptr != null);
    std.debug.assert(path != null);

    var ctx: *InezContext = @ptrCast(@alignCast(ptr.?));
    const path_slice = std.mem.span(path.?);

    if (ctx.ini.loadFile(path_slice)) {
        return true;
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => @panic("OOM"),
            else => ctx.setLastError(err, "Unhandled error while opening file '{s}'", .{path_slice}),
        }
    }

    return false;
}

export fn inezParse(ptr: ?*InezContext) bool {
    std.debug.assert(ptr != null);

    var ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    if (ctx.ini.parse()) |parsed| {
        ctx.parsed = parsed;
        return true;
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => @panic("OOM"),
            error.InvalidCharacter => ctx.setLastError(err, "Invalid character", .{}),
        }
    }

    return false;
}

export fn inezGet(
    ptr: ?*InezContext,
    section: ?[*:0]const u8,
    key: ?[*:0]const u8,
    buffer: ?[*]u8,
    buffer_len: usize,
) bool {
    std.debug.assert(ptr != null);
    std.debug.assert(section != null);
    std.debug.assert(key != null);
    std.debug.assert(buffer != null);
    std.debug.assert(buffer_len > 0);

    const ctx: *InezContext = @ptrCast(@alignCast(ptr.?));

    if (ctx.parsed) |parsed| {
        const section_slice = std.mem.span(section.?);
        const key_slice = std.mem.span(key.?);
        const value = parsed.get(section_slice, key_slice) catch |err| {
            switch (err) {
                error.NotFound => ctx.setLastError(err, "{s}:{s} not found", .{ section_slice, key_slice }),
            }
            return false;
        };

        if (std.fmt.bufPrintZ(buffer.?[0..buffer_len], "{s}", .{value})) |_| {
            return true;
        } else |err| {
            ctx.setLastError(err, "buffer size is {d}, but value length was {d}", .{ buffer_len, value.len });
            return false;
        }
    } else {
        ctx.setLastError(error.IniNotParsed, "the ini file has not yet been parsed", .{});
    }

    return false;
}

const std = @import("std");
const inez = @import("inez");
