const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const window = @import("Window.zig");
const img = @import("Image.zig");
const Texture2D = img.Texture2D;
const MinFilter = img.MinFilter;
const ArrayList = std.ArrayList;
const c_allocator = std.heap.c_allocator;
const c = @import("c.zig").c;
const expect = std.testing.expect;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

fn image_data_size(w: usize, h: usize, layers: u32, imgType: img.ImageType) usize {
    var expectedDataSize: usize = 0;
    if (imgType == img.ImageType.RGBA) {
        expectedDataSize = w * h * layers * 4;
    } else if (imgType == img.ImageType.RG) {
        assert(w * 2 % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = w * h * layers * 2;
    } else if (imgType == img.ImageType.R) {
        assert(w % 4 == 0); // Ensure rows are a multiple of 4 bytes
        expectedDataSize = w * h * layers;
    }
    return expectedDataSize;
}

pub const Texture2DArray = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    id: u32,
    width: u32,
    height: u32,
    layers: u32,
    imageType: img.ImageType,

    // createFramebuffers()
    // One framebuffer per texture layer
    frame_buffer_ids: ArrayList(u32),

    // createFramebuffer()
    // One framebuffer with each texture layer attatched
    frame_buffer_id: u32,

    pub fn init(smooth_when_magnified: bool, min_filter: MinFilter) !Texture2DArray {
        return Texture2DArray{
            .id = try img.createTexture(c.GL_TEXTURE_2D_ARRAY, smooth_when_magnified, min_filter),
            .width = 0,
            .height = 0,
            .layers = 0,
            .imageType = img.ImageType.RGBA,
            .frame_buffer_ids = ArrayList(u32).init(c_allocator),
            .frame_buffer_id = 0,
        };
    }

    fn createframe_buffer_ids(self: *Texture2DArray) !void {
        const start = self.frame_buffer_ids.items.len;
        const numToCreate = self.layers - start;

        if (numToCreate < 1) {
            return;
        }

        try self.frame_buffer_ids.resize(self.layers);

        for (self.frame_buffer_ids.items[start..]) |*id| {
            id.* = 0;
        }

        c.glGenFramebuffers(@intCast(c_int, numToCreate), @ptrCast([*c]c_uint, self.frame_buffer_ids.items[start..].ptr));

        var allIdsNon0: bool = true;
        for (self.frame_buffer_ids.items[start..]) |id| {
            if (id == 0) {
                allIdsNon0 = false;
                break;
            }
        }

        if (!allIdsNon0) {
            c.glDeleteFramebuffers(@intCast(c_int, self.layers), @ptrCast([*c]c_uint, self.frame_buffer_ids.items[start..].ptr));
            return error.OpenGLError;
        }
    }

    pub fn createFrameBuffers(self: *Texture2DArray) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        try self.createframe_buffer_ids();

        for (self.frame_buffer_ids.items) |id, i| {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, id);

            c.glFramebufferTextureLayer(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, self.id, 0, @intCast(c_int, i));

            // Configure framebuffer

            var drawBuffers: [1]c_uint = [1]c_uint{c.GL_COLOR_ATTACHMENT0};
            c.glDrawBuffers(1, drawBuffers[0..]);

            // Validate framebuffer

            if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
                assert(false);
                return error.OpenGLError;
            }

            c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        }
    }

    pub fn createFrameBuffer(self: *Texture2DArray, depth_texture: ?*Texture2D) !void {
        if (self.id == 0 or self.width <= 0 or self.height <= 0 or self.layers <= 0) {
            assert(false);
            return error.InvalidState;
        }

        if (self.layers > 8) {
            return error.TooManyLayers;
        }

        // Create FBO

        c.glGenFramebuffers(1, @ptrCast([*c]c_uint, &self.frame_buffer_id));
        if (self.frame_buffer_id == 0) {
            return error.OpenGLError;
        }
        errdefer {
            c.glDeleteFramebuffers(1, @ptrCast([*c]c_uint, &self.frame_buffer_id));
            self.frame_buffer_id = 0;
        }

        // Bind and configure FBO

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frame_buffer_id);

        const drawBuffers = [8]c_uint{
            c.GL_COLOR_ATTACHMENT0, c.GL_COLOR_ATTACHMENT1,
            c.GL_COLOR_ATTACHMENT2, c.GL_COLOR_ATTACHMENT3,
            c.GL_COLOR_ATTACHMENT4, c.GL_COLOR_ATTACHMENT5,
            c.GL_COLOR_ATTACHMENT6, c.GL_COLOR_ATTACHMENT7,
        };
        c.glDrawBuffers(@intCast(c_int, self.layers), drawBuffers[0..].ptr);

        var i: u32 = 0;
        while (i < self.layers) : (i += 1) {
            c.glFramebufferTextureLayer(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0 + i, self.id, 0, @intCast(c_int, i));
        }

        if (depth_texture != null) {
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, depth_texture.?.id, 0);
        }

        // Validate framebuffer

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
            assert(false);
            return error.OpenGLError;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
    }

    pub fn bindFrameBuffer2(self: Texture2DArray) !void {
        if (self.frame_buffer_id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frame_buffer_id);
        c.glViewport(0, 0, @intCast(c_int, self.width), @intCast(c_int, self.height));
    }

    pub fn bindFrameBuffer(self: Texture2DArray, index: u32) !void {
        if (index >= self.layers) {
            assert(false);
            return error.InvalidParameter;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.frame_buffer_ids.at(index));
        c.glViewport(0, 0, @intCast(c_int, self.width), @intCast(c_int, self.height));
    }

    pub fn bindToUnit(self: *Texture2DArray, unit: u32) !void {
        if (self.width == 0 or self.height == 0 or self.layers == 0 or self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        if (unit >= window.maximumNumTextureImageUnits()) {
            return error.InvalidParameter;
        }

        c.glActiveTexture(c.GL_TEXTURE0 + unit);
        c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.id);
    }

    pub fn bind(self: *Texture2DArray) !void {
        try self.bindToUnit(0);
    }

    // Replaces the texture's data (dimensions and depth can change)
    pub fn upload(self: *Texture2DArray, w: u32, h: u32, lyrs: u32, imgType: img.ImageType, data: ?[]const u8) !void {
        if (w == 0 or h == 0 or lyrs == 0 or w > 32768 or h > 32768) {
            assert(false);
            return error.InvalidParameter;
        }

        if (data != null) {
            const expectedDataSize = image_data_size(w, h, lyrs, imgType);

            if (data.?.len != expectedDataSize) {
                assert(false);
                return error.InvalidParameter;
            }
        }

        self.width = w;
        self.height = h;
        self.layers = lyrs;
        self.imageType = imgType;

        var internalFormat: u32 = img.image_type_sized_internal_formats[@enumToInt(imgType)];

        try self.bind();

        var ptr: [*c]const u8 = 0;
        if (data != null) {
            ptr = data.?.ptr;
        }

        c.glTexImage3D(c.GL_TEXTURE_2D_ARRAY, 0, @intCast(c_int, internalFormat), @intCast(c_int, w), @intCast(c_int, h), @intCast(c_int, lyrs), 0, img.image_type_base_internal_formats[@enumToInt(imgType)], c.GL_UNSIGNED_BYTE, ptr);
    }

    // Downloads the entire texture (all layers)
    pub fn download(self: *Texture2DArray, outputBuffer: []u8) !void {
        const expectedDataSize = image_data_size(self.width, self.height, self.layers, self.imageType);

        if (outputBuffer.len != expectedDataSize) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glGetTexImage(c.GL_TEXTURE_2D_ARRAY, 0, img.image_type_base_internal_formats[@enumToInt(self.imageType)], c.GL_UNSIGNED_BYTE, outputBuffer.ptr);
    }

    pub fn free(self: *Texture2DArray) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        self.ref_count.deinit();

        if (self.frame_buffer_ids.items.len > 0) {
            c.glDeleteFramebuffers(@intCast(c_int, self.frame_buffer_ids.items.len), @ptrCast([*c]const c_uint, self.frame_buffer_ids.items.ptr));
        }
        self.frame_buffer_ids.deinit();

        c.glDeleteTextures(1, @ptrCast([*c]const c_uint, &self.id));
        self.id = 0;
    }

    pub fn fill(self: *Texture2DArray, index: u32, colour: [4]f32) !void {
        if (index >= self.layers) {
            assert(false);
            return error.InvalidParameter;
        }

        if (c.GL_ARB_clear_texture != 0) {
            c.glClearTexSubImage(self.id, 0, 0, 0, @intCast(c_int, index), @intCast(c_int, self.width), @intCast(c_int, self.height), 1, c.GL_RGBA, c.GL_FLOAT, colour[0..4].ptr);
        } else if (self.frame_buffer_ids.items.len > 0) {
            try self.bindFrameBuffer(index);
            window.setClearColour(colour[0], colour[1], colour[2], colour[3]);
            window.clear(true, false);
        } else {
            return error.InvalidState;
        }
    }

    // Assumed the bound frame buffer is the same size as the  texture
    pub fn copyFromFrameBuffer(self: *Texture2DArray, index: u32) !void {
        try self.bind();
        c.glCopyTexSubImage3D(0x8C1A, 0, 0, 0, @intCast(c_int, index), 0, 0, @intCast(c_int, self.width), @intCast(c_int, self.height));
    }
};

test "2d texture array" {
    try window.createWindow(false, 200, 200, "test", true, 0);

    var texture: Texture2DArray = try Texture2DArray.init(false, MinFilter.Nearest);

    const dataIn: []const u8 = &[8]u8{ 127, 127, 127, 127, 33, 33, 33, 33 };

    try texture.upload(1, 1, 2, img.ImageType.RGBA, dataIn);
    expect(texture.width == 1);
    expect(texture.height == 1);
    expect(texture.layers == 2);
    expect(texture.imageType == img.ImageType.RGBA);

    try texture.createFrameBuffers();

    var data: [8]u8 = undefined;
    try texture.download(&data);

    expect(mem.eql(u8, data[0..], dataIn));

    try texture.bind();

    texture.free();

    window.closeWindow();
}
