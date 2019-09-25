const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const expect = std.testing.expect;
const image = @import("Image.zig");
const MinFilter = image.MinFilter;
const image_type_base_internal_formats = image.image_type_base_internal_formats;
const image_type_sized_internal_formats = image.image_type_sized_internal_formats;
const ImageType = image.ImageType;

// For each of the 6 sides (multiply return value by 6 to get total cubemap size)
pub fn imageDataSize(size: u32, imgType: ImageType) u32 {
    var expectedDataSize: u32 = 0;
    if (imgType == ImageType.RGBA or imgType == ImageType.Depth32 or imgType == ImageType.Depth32F) {
        expectedDataSize = size * size * 4;
    } else if (imgType == ImageType.Depth24) {
        expectedDataSize = size * size * 3;
    } else if (imgType == ImageType.RG or imgType == ImageType.Depth16) {
        assert(size * 2 % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = size * size * 2;
    } else if (imgType == ImageType.R) {
        assert(size % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = size * size;
    }
    return expectedDataSize;
}

// Cubemaps are always square
pub const CubeMap = struct {
    // width and height in pixels
    size: u32,
    imageType: ImageType,
    id: u32,

    min_filter: MinFilter,

    pub fn init(smooth_when_magnified: bool, min_filter: MinFilter) !CubeMap {
        return CubeMap{
            .size = 0,
            .imageType = ImageType.RGBA,
            .id = try image.createTexture(c.GL_TEXTURE_CUBE_MAP, smooth_when_magnified, min_filter),
            .min_filter = min_filter,
        };
    }

    pub fn bindToUnit(self: CubeMap, unit: u32) !void {
        if (self.size == 0 or self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        if (unit >= window.maximumNumTextureImageUnits()) {
            return error.InvalidParameter;
        }

        c.glActiveTexture(c.GL_TEXTURE0 + unit);
        c.glBindTexture(c.GL_TEXTURE_CUBE_MAP, self.id);
    }

    pub fn bind(self: CubeMap) !void {
        try self.bindToUnit(0);
    }

    fn validateArraySize(data: ?[]const u8, expected: u32) !void {
        if (data != null) {
            if (data.?.len != expected) {
                assert(false);
                return error.InvalidParameter;
            }
        }
    }

    // If data is null then texture data will be uninitialised
    pub fn upload(self: *CubeMap, size: u32, imgType: ImageType, data_pos_x: ?[]const u8, data_neg_x: ?[]const u8, data_pos_y: ?[]const u8, data_neg_y: ?[]const u8, data_pos_z: ?[]const u8, data_neg_z: ?[]const u8) !void {
        if (size == 0 or size > window.maximumTextureSize()) {
            assert(false);
            return error.InvalidParameter;
        }

        const expectedDataSize = imageDataSize(size, imgType);
        try validateArraySize(data_pos_x, expectedDataSize);
        try validateArraySize(data_neg_x, expectedDataSize);
        try validateArraySize(data_pos_y, expectedDataSize);
        try validateArraySize(data_neg_y, expectedDataSize);
        try validateArraySize(data_pos_z, expectedDataSize);
        try validateArraySize(data_neg_z, expectedDataSize);

        self.size = size;
        self.imageType = imgType;

        var internalFormat: u32 = image_type_sized_internal_formats[@enumToInt(imgType)];

        try self.bind();

        var pos_x: [*c]const u8 = 0;
        var neg_x: [*c]const u8 = 0;
        var pos_y: [*c]const u8 = 0;
        var neg_y: [*c]const u8 = 0;
        var pos_z: [*c]const u8 = 0;
        var neg_z: [*c]const u8 = 0;

        if (data_pos_x != null) {
            pos_x = data_pos_x.?.ptr;
        }
        if (data_neg_x != null) {
            pos_x = data_neg_x.?.ptr;
        }
        if (data_pos_y != null) {
            pos_x = data_pos_y.?.ptr;
        }
        if (data_neg_y != null) {
            pos_x = data_neg_y.?.ptr;
        }
        if (data_pos_z != null) {
            pos_x = data_pos_x.?.ptr;
        }
        if (data_neg_z != null) {
            pos_x = data_neg_y.?.ptr;
        }

        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_X, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, pos_x);
        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_X, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, neg_x);
        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Y, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, pos_y);
        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, neg_y);
        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Z, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, pos_z);
        c.glTexImage2D(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z, 0, @intCast(c_int, internalFormat), @intCast(c_int, size), @intCast(c_int, size), 0, image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, neg_z);

        if (self.min_filter != MinFilter.Nearest and self.min_filter != MinFilter.Linear) {
            c.glGenerateMipmap(c.GL_TEXTURE_CUBE_MAP);
        }
    }

    pub fn download(self: *CubeMap, output_pos_x: []u8, output_neg_x: []u8, output_pos_y: []u8, output_neg_y: []u8, output_pos_z: []u8, output_neg_z: []u8) !void {
        const expectedDataSize = imageDataSize(self.size, self.imageType);

        try validateArraySize(output_pos_x, expectedDataSize);
        try validateArraySize(output_neg_x, expectedDataSize);
        try validateArraySize(output_pos_y, expectedDataSize);
        try validateArraySize(output_neg_y, expectedDataSize);
        try validateArraySize(output_pos_z, expectedDataSize);
        try validateArraySize(output_neg_z, expectedDataSize);

        try self.bind();

        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_POSITIVE_X, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_pos_x.ptr);
        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_X, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_neg_x.ptr);
        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Y, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_pos_y.ptr);
        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_neg_y.ptr);
        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_POSITIVE_Z, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_pos_z.ptr);
        c.glGetTexImage(c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, output_neg_z.ptr);
    }

    pub fn free(self: *CubeMap) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        c.glDeleteTextures(1, @ptrCast([*c]c_uint, &self.id));
    }

    pub fn unbind(unit: u32) !void {
        if (unit > window.maximumNumTextureImageUnits()) {
            return error.InvalidParameter;
        }

        c.glActiveTexture(GL_TEXTURE0 + unit);
        c.glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    }
};

test "cubemap texture" {
    try window.createWindow(false, 200, 200, c"test", true, 0);

    var texture: CubeMap = try CubeMap.init(false, MinFilter.Nearest);
    expect(texture.id > 0);

    const dataIn: []const u8 = [4]u8{ 127, 127, 127, 127 };

    try texture.upload(1, ImageType.RGBA, dataIn, null, null, null, null, null);
    expect(texture.size == 1);
    expect(texture.imageType == ImageType.RGBA);

    var data: [4]u8 = undefined;
    var data2: [4]u8 = undefined;
    var data3: [4]u8 = undefined;
    var data4: [4]u8 = undefined;
    var data5: [4]u8 = undefined;
    var data6: [4]u8 = undefined;
    try texture.download(&data, &data2, &data3, &data4, &data5, &data6);

    expect(mem.eql(u8, data, dataIn));

    try texture.bind();
    try texture.bindToUnit(15);

    texture.free();

    window.closeWindow();
}
