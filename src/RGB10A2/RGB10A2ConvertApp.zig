const std = @import("std");
const c_allocator = std.heap.c_allocator;
const convertFile = @import("RGB10A2.zig").convertFile;

pub fn main() !void {
    const args = try std.process.argsAlloc(c_allocator);
    defer std.process.argsFree(c_allocator, args);

    if (args.len != 3) {
        std.debug.warn("Usage: rgb10a2convert [input 48-bit PNG file] [output file]\n", .{});
        return error.InvalidParameters;
    }

    try convertFile(args[1], args[2], c_allocator);
}
