const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const files = @import("../Files.zig");
const expect = std.testing.expect;

// Base internal formats
pub const image_type_base_internal_formats: [9]u32 = [9]u32{
    c.GL_RED,
    c.GL_RG,
    c.GL_RGB,
    c.GL_RGBA,
    c.GL_RGBA,
    c.GL_DEPTH_COMPONENT,
    c.GL_DEPTH_COMPONENT,
    c.GL_DEPTH_COMPONENT,
    c.GL_DEPTH_COMPONENT,
};

pub const image_type_sized_internal_formats: [9]u32 = [9]u32{
    c.GL_R8,
    c.GL_RG8,
    c.GL_RGB8,
    c.GL_RGBA8,
    c.GL_RGB10_A2,
    c.GL_DEPTH_COMPONENT16,
    c.GL_DEPTH_COMPONENT24,
    c.GL_DEPTH_COMPONENT32,
    c.GL_DEPTH_COMPONENT32F,
};

pub const ImageType = enum {
    R,
    RG,
    RGB,
    RGBA,
    RGB10A2,
    Depth16,
    Depth24,
    Depth32,
    Depth32F,
};

const min_filter_gl_values = [_]i32 {
    c.GL_NEAREST,
    c.GL_LINEAR,
    c.GL_NEAREST_MIPMAP_NEAREST,
    c.GL_LINEAR_MIPMAP_NEAREST,
    c.GL_NEAREST_MIPMAP_LINEAR,
    c.GL_LINEAR_MIPMAP_LINEAR,
};

// Do not change - scene files depend on the integer values of this enum
pub const MinFilter = enum(i32) {
    Nearest,
    Linear,

    // One mip-map level
    NearestMipMapNearest,
    LinearMipMapNearest,

    // Two mip-map levels
    NearestMipMapLinear,
    LinearMipMapLinear,
};

pub fn imageDataSize(w: usize, h: usize, imgType: ImageType) usize {
    var expectedDataSize: usize = 0;
    if (imgType == ImageType.RGBA or imgType == ImageType.Depth32 or imgType == ImageType.Depth32F or imgType == ImageType.RGB10A2) {
        expectedDataSize = w * h * 4;
    } else if (imgType == ImageType.RGB or imgType == ImageType.Depth24) {
        expectedDataSize = w * h * 3;
    } else if (imgType == ImageType.RG or imgType == ImageType.Depth16) {
        assert(w * 2 % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = w * h * 2;
    } else if (imgType == ImageType.R) {
        assert(w % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = w * h;
    } else {
        assert(false);
    }
    return expectedDataSize;
}

pub fn createTexture(gl_type: c_uint, smooth_when_magnified: bool, min_filter: MinFilter) !c_uint {
    var textureId: u32 = 0;
    c.glGenTextures(1, @ptrCast([*c]c_uint, &textureId));

    if (textureId == 0) {
        return error.OpenGLError;
    }

    c.glBindTexture(gl_type, textureId);

    if (smooth_when_magnified) {
        c.glTexParameteri(gl_type, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    } else {
        c.glTexParameteri(gl_type, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    }

    c.glTexParameteri(gl_type, c.GL_TEXTURE_MIN_FILTER, min_filter_gl_values[@intCast(usize, @enumToInt(min_filter))]);

    if (min_filter == MinFilter.Nearest or min_filter == MinFilter.Linear) {
        c.glTexParameteri(gl_type, c.GL_TEXTURE_BASE_LEVEL, 0);
        c.glTexParameteri(gl_type, c.GL_TEXTURE_MAX_LEVEL, 0);
    }

    c.glTexParameteri(gl_type, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(gl_type, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);

    return textureId;
}

pub const Texture2D = struct {
    width: u32,
    height: u32,
    imageType: ImageType,
    id: u32,
    min_filter: MinFilter,

    pub fn initAndUpload(w: u32, h: u32, imgType: ImageType, data: ?[]const u8, smooth_when_magnified: bool, min_filter: MinFilter) !Texture2D {
        var t = try init(smooth_when_magnified, min_filter);
        try t.upload(w, h, imgType, data);
        return t;
    }

    pub fn init(smooth_when_magnified: bool, min_filter: MinFilter) !Texture2D {
        return Texture2D{
            .width = 0,
            .height = 0,
            .imageType = ImageType.RGBA,
            .id = try createTexture(c.GL_TEXTURE_2D, smooth_when_magnified, min_filter),
            .min_filter = min_filter,
        };
    }

    // Needed if using shadow sampler types
    // (untested)
    pub fn enableDepthCompare(self: Texture2D) void {
        c.glBindTexture(c.GL_TEXTURE_2D, self.id);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_MODE, c.GL_COMPARE_REF_TO_TEXTURE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_FUNC, c.GL_LESS);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);         
    }

    pub fn bindToUnit(self: Texture2D, unit: u32) !void {
        if (self.width == 0 or self.height == 0 or self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        if (unit >= window.maximumNumTextureImageUnits()) {
            return error.InvalidParameter;
        }

        c.glActiveTexture(c.GL_TEXTURE0 + unit);
        c.glBindTexture(c.GL_TEXTURE_2D, self.id);
    }

    pub fn bind(self: Texture2D) !void {
        try self.bindToUnit(0);
    }

    // If data is null then texture data will be uninitialised
    pub fn upload(self: *Texture2D, w: u32, h: u32, imgType: ImageType, data: ?[]const u8) !void {
        if (w == 0 or h == 0 or w > window.maximumTextureSize() or h > window.maximumTextureSize()) {
            assert(false);
            return error.InvalidParameter;
        }

        if (data != null) {
            const expectedDataSize = imageDataSize(w, h, imgType);
            if (data.?.len != expectedDataSize) {
                assert(false);
                return error.InvalidParameter;
            }
        }

        self.width = w;
        self.height = h;
        self.imageType = imgType;

        var internalFormat: u32 = image_type_sized_internal_formats[@enumToInt(imgType)];

        try self.bind();

        var ptr: [*c]const u8 = 0;
        if (data != null) {
            ptr = data.?.ptr;
        }

        var data_format: c_uint = c.GL_UNSIGNED_BYTE;
        if(imgType == ImageType.RGB10A2) {
            data_format = c.GL_UNSIGNED_INT_10_10_10_2;
        }
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, @intCast(c_int, internalFormat), @intCast(c_int, w), @intCast(c_int, h), 0, image_type_base_internal_formats[@enumToInt(imgType)], data_format, ptr);

        if (self.min_filter != MinFilter.Nearest and self.min_filter != MinFilter.Linear) {
            c.glGenerateMipmap(c.GL_TEXTURE_2D);
        }
    }

    pub fn download(self: Texture2D, outputBuffer: []u8) !void {
        const expectedDataSize = imageDataSize(self.width, self.height, self.imageType);

        if (outputBuffer.len != expectedDataSize) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glGetTexImage(c.GL_TEXTURE_2D, 0, image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, outputBuffer.ptr);
    }

    pub fn free(self: *Texture2D) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        c.glDeleteTextures(1, @ptrCast([*c]c_uint, &self.id));
        self.id = 0;
    }

    pub fn loadFromFile(file_path: []const u8, allocator: *std.mem.Allocator, smooth_when_magnified: bool, min_filter: MinFilter, components: u32) !Texture2D {
        if (components == 0 or components > 4) {
            return error.InvalidParameter;
        }

        var tex = try Texture2D.init(smooth_when_magnified, min_filter);
        errdefer tex.free();
        const file_data = try files.loadFile(file_path, allocator);
        defer files.freeLoadedFile(file_data, allocator);

        var w: i32 = undefined;
        var h: i32 = undefined;
        var n: i32 = undefined;

        const data = c.stbi_load_from_memory(file_data.ptr, @intCast(c_int, file_data.len), @ptrCast([*c]c_int, &w), @ptrCast([*c]c_int, &h), @ptrCast([*c]c_int, &n), @intCast(c_int, components));
        if (data == null) {
            return error.DecodeError;
        }
        defer c.stbi_image_free(data);

        assert(w > 0);
        assert(h > 0);

        var img_type: ImageType = undefined;
        if (components == 1) {
            img_type = ImageType.R;
        } else if (components == 2) {
            img_type = ImageType.RG;
        } else if (components == 3) {
            img_type = ImageType.RGB;
        } else if (components == 4) {
            img_type = ImageType.RGBA;
        } else {
            assert(false);
            return error.InvalidParameter;
        }

        try tex.upload(@intCast(u32, w), @intCast(u32, h), img_type, data[0..(@intCast(u32, w) * @intCast(u32, h) * components)]);

        return tex;
    }

    // Use the asset module if you need to load compressed rgb10a2 images
    pub fn loadFromRGB10A2File(file_path: []const u8, allocator: *std.mem.Allocator, smooth_when_magnified: bool, min_filter: MinFilter) !Texture2D {
        var tex = try Texture2D.init(smooth_when_magnified, min_filter);
        errdefer tex.free();

        const file_data = try files.loadFile(file_path, allocator);
        defer files.freeLoadedFile(file_data, allocator);

        const file_data_u32: []u32 = @bytesToSlice(u32, file_data);
        if (file_data_u32[0] != 0x62677200 or file_data_u32[1] != 0x32613031) {
            return error.InvalidMagic;
        }

        const w = file_data_u32[2];
        const h = file_data_u32[3];

        if (w == 0 or h == 0 or w > 32768 or h > 32768) {
            return error.InvalidDimensions;
        }

        try tex.upload(w, h, ImageType.RGB10A2, file_data[16..(w * h * 4 + 16)]);

        return tex;
    }

    pub fn saveToFile(self: Texture2D, file_path: []const u8, allocator: *std.mem.Allocator) !void {
        if (self.imageType != ImageType.RGBA) {
            return error.ImageFormatNotSupported;
        }

        const expectedDataSize = self.width * self.height * 4;
        var outputBuffer = try allocator.alloc(u8, expectedDataSize);
        try self.download(outputBuffer);

        const err = c.stbi_write_png(@ptrCast([*c]const u8, file_path.ptr), @intCast(c_int, self.width), @intCast(c_int, self.height), 4, outputBuffer.ptr, @intCast(c_int, self.width * 4));
        if (err == 0) {
            return error.STBImageWriteError;
        }
    }
};

// Use freeDecodedImage to free the returned slice
// 'components' should be 0 or the desired number of data channels
// If components is 0 then it is set to the number of channels in the image
pub fn decodeImage(image_file_data: []const u8, components: *u32, image_width: *u32, image_height: *u32, allocator: *std.mem.Allocator) ![]align(4) u8 {
    if (components.* > 4) {
        return error.InvalidParameter;
    }

    var desired_channels = components.*;

    var w: i32 = undefined;
    var h: i32 = undefined;
    var n: i32 = undefined;

    const data = c.stbi_load_from_memory(image_file_data.ptr, @intCast(c_int, image_file_data.len), @ptrCast([*c]c_int, &w), @ptrCast([*c]c_int, &h), @ptrCast([*c]c_int, &n), @intCast(c_int, desired_channels));
    if (data == null or w < 1 or h < 1 or n == 0 or n > 4) {
        return error.DecodeError;
    }

    if(components.* == 0) {
        components.* = @intCast(u32, n);
    }

    image_width.* = @intCast(u32, w);
    image_height.* = @intCast(u32, w);
    
    return @alignCast(4, data[0..(@intCast(u32, w) * @intCast(u32, h) * @intCast(u32, desired_channels))]);
}

pub fn freeDecodedImage(data: []align(4) u8) void {
    var d: *c_void = @ptrCast(*c_void, data.ptr);
    var d2: ?*c_void = d;
    c.stbi_image_free(d2);
}

test "2d texture" {
    try window.createWindow(false, 200, 200, c"test", true, 0);

    var texture: Texture2D = try Texture2D.init(false, MinFilter.Nearest);
    expect(texture.id > 0);

    const dataIn: []const u8 = [4]u8{ 127, 127, 127, 127 };

    try texture.upload(1, 1, ImageType.RGBA, dataIn);
    expect(texture.width == 1);
    expect(texture.height == 1);
    expect(texture.imageType == ImageType.RGBA);

    var data: [4]u8 = undefined;
    try texture.download(&data);

    expect(mem.eql(u8, data, dataIn));

    try texture.bind();
    try texture.bindToUnit(15);

    texture.free();

    window.closeWindow();
}
