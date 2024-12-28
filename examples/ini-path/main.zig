pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 4) {
        std.debug.print("usage: {s} <path> <section> <key>\n", .{std.fs.path.basename(args[0])});
        return error.InvalidArguments;
    }

    const path = args[1];
    const section = args[2];
    const key = args[3];

    var ini = inez.Ini.init(allocator, .{});
    defer ini.deinit();

    try ini.loadFile(path);
    var parsed_ini = try ini.parse();
    defer parsed_ini.deinit();

    const value = try parsed_ini.get(section, key);

    std.debug.print("{s}:{s} = {s}\n", .{ section, key, value });
}

const std = @import("std");
const inez = @import("inez");
const assert = std.debug.assert;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
