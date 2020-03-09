const std = @import("std");
const warn = std.debug.warn;
const File = std.fs.File;
const files = @import("../Files.zig");
const loadFile = files.loadFile;

pub const c = @cImport({
    @cInclude("zstd.h");
});

fn writeCompressed(path: []const u8, data: []const u8, original_size: u32) !void {
    var file = try File.openWrite(path);
    defer file.close();

    const header = [12]u8{ 0x88, 0x7c, 0x77, 0x6a, 0xee, 0x55, 0xdd, 0xcc, 0x37, 0x9a, 0x8b, 0xef };
    try file.write(header);

    try file.write(@ptrCast([*c]const u8, &original_size)[0..4]);

    try file.write(data);
}

pub fn compressFile(input_file_path: []const u8, output_file_path: []const u8, allocator: *std.mem.Allocator) !void {
    var input_file_data = try loadFile(input_file_path, allocator);
    defer allocator.free(input_file_data);

    if (input_file_data.len == 0) {
        return error.EmptyFile;
    }

    const max_size = c.ZSTD_compressBound(input_file_data.len);

    var compressed_data = try allocator.alignedAlloc(u8, 16, max_size);

    const compressed_size = c.ZSTD_compress(compressed_data.ptr, max_size, input_file_data.ptr, input_file_data.len, 22);

    if (compressed_size == 0) {
        return error.ZSTDError;
    }

    if (@intCast(usize, compressed_size) >= input_file_data.len) {
        return error.CompressedBiggerThanOriginal;
    } else {
        try writeCompressed(output_file_path, compressed_data[0..@intCast(usize, compressed_size)], @intCast(u32, input_file_data.len));
    }
}

pub fn isCompressedFile(file_data: []const u8, original_data_size: ?*u32) !bool {
    const data_u32 = @bytesToSlice(u32, file_data);

    if (file_data.len <= 16) {
        return false;
    }

    if (data_u32[0] != 0x6a777c88 or data_u32[1] != 0xccdd55ee or data_u32[2] != 0xef8b9a37) {
        return false;
    }

    if (original_data_size != null) {
        const originalDataSize = data_u32[3];

        if (originalDataSize == 0) {
            return error.InvalidFile;
        } else {
            original_data_size.?.* = originalDataSize;
        }
    }

    return true;
}

pub fn decompress(file_data: []align(4) u8, allocator: *std.mem.Allocator) ![]align(4) u8 {
    if (file_data.len <= 16 or file_data.len >= 2147483663) {
        return error.InvalidFile;
    }

    const data_u32 = @bytesToSlice(u32, file_data[0..16]);

    if (data_u32[0] != 0x6a777c88 or data_u32[1] != 0xccdd55ee or data_u32[2] != 0xef8b9a37) {
        return file_data;
    }

    const originalDataSize = data_u32[3];

    if (originalDataSize == 0 or originalDataSize > 2147483647) {
        return error.InvalidFile;
    }

    var decompressed_data = try allocator.alignedAlloc(u8, 16, originalDataSize);
    errdefer allocator.free(decompressed_data);

    const r = c.ZSTD_decompress(decompressed_data.ptr, @intCast(usize, originalDataSize), file_data[16..].ptr, file_data.len - 16);

    if (r != originalDataSize) {
        return error.ZSTDError;
    }

    return decompressed_data;
}

test "isCompressedFile" {
    var original_data_size: u32 = 0;
    var file_data = [5]u32{ 0x6a777c88, 0xccdd55ee, 0xef8b9a37, 0, 111 };
    std.testing.expectError(error.InvalidFile, isCompressedFile(@sliceToBytes(file_data[0..]), &original_data_size));
}
