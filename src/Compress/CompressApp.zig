const std = @import("std");
const c_allocator = std.heap.c_allocator;
const compressFile = @import("Compress.zig").compressFile;

pub fn main() !void {
    const args = try std.process.argsAlloc(c_allocator);
    defer std.process.argsFree(c_allocator, args);

    if (args.len != 3) {
        std.debug.warn("Usage: compress [input file] [output file]\n");
        return error.InvalidParameters;
    }

    try compressFile(args[1], args[2], c_allocator);
}
