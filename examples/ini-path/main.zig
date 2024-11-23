pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 4) {
        return error.InvalidArguments;
    }

    const path = args[1];
    const section = args[2];
    const key = args[3];

    var ini = inez.Ini.init(.{});
    defer ini.deinit(allocator);

    try ini.loadFile(allocator, path);
    var parsed_ini = try ini.parse(allocator);
    defer parsed_ini.deinit(allocator);

    const value = try parsed_ini.get(section, key);

    std.debug.print("{s}:{s} = {s}\n", .{ section, key, value });
}

const std = @import("std");
const inez = @import("inez");
const assert = std.debug.assert;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
