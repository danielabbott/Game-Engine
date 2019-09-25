const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const File = std.fs.File;
const files = @import("../Files.zig");
const loadFile = files.loadFile;

pub const c = @cImport({
    @cInclude("stb_image.h");
});

fn save(path: []const u8, w: u32, h: u32, data: []const u8) !void {
    assert(data.len == w*h*4);

    var file = try File.openWrite(path);
    defer file.close();

    // Magic bytes
    const header = [8]u8{ 0x00, 0x72, 0x67, 0x62, 0x31, 0x30, 0x61, 0x32 };
    try file.write(header);

    try file.write(@ptrCast([*c]const u8, &w)[0..4]);
    try file.write(@ptrCast([*c]const u8, &h)[0..4]);

    try file.write(data);
}

pub fn convertFile(path: []const u8, output_file_path: []const u8, allocator: *std.mem.Allocator) !void {
    var input_file_data = try loadFile(path, allocator);
    defer allocator.free(input_file_data);

    var w: i32 = 0;
    var h: i32 = 0;
    var n: i32 = 0;

    const decoded_png = c.stbi_load_16_from_memory(input_file_data.ptr, @intCast(c_int, input_file_data.len), @ptrCast([*c]c_int, &w), @ptrCast([*c]c_int, &h), @ptrCast([*c]c_int, &n), 4);
    if (decoded_png == null) {
        return error.ImageDecodeError;
    }
    defer c.stbi_image_free(decoded_png);

    const w_u32 = @intCast(u32, w);
    const h_u32 = @intCast(u32, h);

    var decoded_png_u16 = @bytesToSlice(u16, @sliceToBytes(decoded_png[0..(w_u32 * h_u32 * 4)]));

    var converted_data = try allocator.alloc(u32, w_u32 * h_u32);
    defer allocator.free(converted_data);

    // Convert bit depth from rgba16 to rgb10a2

    var src: u32 = 0; // Index into decoded_png_u16
    var dst: u32 = 0; // Index into converted_data
    var y: u32 = 0;
    while (y < h_u32) : (y += 1) {
        var x: u32 = 0;
        while (x < w_u32) : (x += 1) {
            const a = @intCast(u32, (decoded_png_u16[src + 3] >> 14)) << 0;
            const r = (decoded_png_u16[src+2] >> 6) << 2;
            const g = @intCast(u32, (decoded_png_u16[src + 1] >> 6)) << 12;
            const b = @intCast(u32, (decoded_png_u16[src + 0] >> 6)) << 22;
            converted_data[dst] = r | g | b | a;

            src += 4;
            dst += 1;
        }
    }

    ////

    try save(output_file_path, w_u32, h_u32, @sliceToBytes(converted_data));
}
