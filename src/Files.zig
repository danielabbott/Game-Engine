const std = @import("std");
const File = std.fs.File;
const builtin = @import("builtin");

pub const path_seperator = if (builtin.os == builtin.Os.windows) "\\" else "/"; 

// Loads file into memory (plus a zero byte) and stores file struct in the given pointer
// The file is _not_ closed
pub fn loadFileWithNullTerminator2(file_path: []const u8, file: *std.fs.File, allocator: *std.mem.Allocator) ![]u8 {
    file.* = try File.openRead(file_path);
    errdefer file.*.close();

    var size: usize = try file.*.getEndPos();

    var buf: []u8 = try allocator.alloc(u8, size + 1);

    const bytesRead = try file.*.read(buf[0..size]);
    if (bytesRead != size) {
        return error.IOError;
    }
    buf[size] = 0;

    return buf;
}

// Loads file into memory (plus a zero byte) and closes the file handle
pub fn loadFileWithNullTerminator(file_path: []const u8, allocator: *std.mem.Allocator) ![]u8 {
    var f: std.fs.File = undefined;
    const buf = try loadFileWithNullTerminator2(file_path, &f, allocator);
    f.close();

    return buf;
}

// Loads file into memory without modification and closes the file handle.
pub fn loadFile(file_path: []const u8, allocator: *std.mem.Allocator) ![]align(4) u8 {
    var in_file = try File.openRead(file_path);
    defer in_file.close();

    var size: usize = try in_file.getEndPos();

    var buf = try allocator.alignedAlloc(u8, 4, size);

    const bytesRead = try in_file.read(buf[0..]);
    if (bytesRead != size) {
        return error.IOError;
    }

    return buf;
}

pub fn loadFileAligned(alignment: u32, file_path: []const u8, allocator: *std.mem.Allocator) ![]u8 {
    var in_file = try File.openRead(file_path);
    defer in_file.close();

    var size: usize = try in_file.getEndPos();

    var buf = try allocator.alignedAlloc(u8, alignment, size);

    const bytesRead = try in_file.read(buf[0..]);
    if (bytesRead != size) {
        return error.IOError;
    }

    return buf;
}
