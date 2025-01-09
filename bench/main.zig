pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ini = inez.Ini.init(allocator, .{});
    defer ini.deinit();

    ini.loadBuffer(ini_data[0..]);
    var parsed_ini = try ini.parse();
    defer parsed_ini.deinit();

    const value = try parsed_ini.get("Experimentation", "TestDuration");
    std.debug.assert(std.mem.eql(u8, "60", value));
    std.debug.print("{s}\n", .{value});
}

const std = @import("std");
const inez = @import("inez");

const ini_data = @embedFile("ini_path");
