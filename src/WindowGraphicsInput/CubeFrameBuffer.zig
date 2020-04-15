const std = @import("std");
const assert = std.debug.assert;
const img = @import("Image.zig");
const ImageType = img.ImageType;
const CubeMap = @import("CubeMap.zig").CubeMap;
const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

// For point shadows
pub const CubeFrameBuffer = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    pub const Direction = enum(u32) {
        PositiveX,
        NegativeX,
        PositiveY,
        NegativeY,
        PositiveZ,
        NegativeZ,
    };

    ids: [6]u32,
    depth_texture: CubeMap,

    depth_type: FrameBuffer.DepthType,

    pub fn init(width_height: u32, depth_type: FrameBuffer.DepthType) !CubeFrameBuffer {
        if (depth_type == FrameBuffer.DepthType.None) {
            return error.NoTexture;
        }

        var frameBuffer = CubeFrameBuffer{
            .ids = ([1]u32{0}) ** 6,
            .depth_type = depth_type,
            .depth_texture = undefined, // set later
        };

        // Create OpenGL framebuffer objects

        c.glGenFramebuffers(6, @ptrCast([*c]c_uint, &frameBuffer.ids));
        errdefer c.glDeleteFramebuffers(6, @ptrCast([*c]c_uint, &frameBuffer.ids));

        var i: u32 = 0;
        while (i < 6) : (i += 1) {
            if (frameBuffer.ids[i] == 0) {
                assert(false);
                return error.OpenGLError;
            }
        }

        // Create depth buffer
        frameBuffer.depth_texture = try CubeMap.init(false, img.MinFilter.Nearest);
        errdefer frameBuffer.depth_texture.free();

        try frameBuffer.setTextureSize(width_height);

        const textureTargets = [6]c_uint{
            c.GL_TEXTURE_CUBE_MAP_POSITIVE_X,
            c.GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
            c.GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
            c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
            c.GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
            c.GL_TEXTURE_CUBE_MAP_NEGATIVE_Z,
        };

        i = 0;
        while (i < 6) : (i += 1) {
            c.glBindFramebuffer(c.GL_FRAMEBUFFER, frameBuffer.ids[i]);
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, textureTargets[i], frameBuffer.depth_texture.id, 0);

            // Configure framebuffer (no colour information is written)

            c.glDrawBuffer(c.GL_NONE);
            c.glReadBuffer(c.GL_NONE);

            // Validate framebuffer

            if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
                assert(false);
                return error.OpenGLError;
            }
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        return frameBuffer;
    }

    // Bind for drawing
    pub fn bind(self: *CubeFrameBuffer, direction: Direction) !void {
        if (self.ids[@enumToInt(direction)] == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, self.ids[@enumToInt(direction)]);
        c.glViewport(0, 0, @intCast(c_int, self.depth_texture.size), @intCast(c_int, self.depth_texture.size));
    }

    pub fn bindDepthTexture(self: CubeFrameBuffer) !void {
        try self.depth_texture.bind();
    }

    pub fn bindDepthTextureToUnit(self: CubeFrameBuffer, unit: u32) !void {
        try self.depth_texture.bindToUnit(unit);
    }

    pub fn free(self: *CubeFrameBuffer) void {
        self.ref_count.deinit();

        var i: u32 = 0;

        while (i < 6) : (i += 1) {
            if (self.ids[i] == 0) {
                assert(false);
                continue;
            }
            self.depth_texture.free();

            self.ids[i] = 0;
        }
        c.glDeleteFramebuffers(6, @ptrCast([*c]const c_uint, &self.ids[0]));
    }

    pub fn bindDefaultFrameBuffer() void {
        FrameBuffer.bindDefaultFrameBuffer();
    }

    fn setTextureSize(self: *CubeFrameBuffer, new_width_height: u32) !void {
        if (self.depth_type == FrameBuffer.DepthType.I16) {
            try self.depth_texture.upload(new_width_height, ImageType.Depth16, null, null, null, null, null, null);
        } else if (self.depth_type == FrameBuffer.DepthType.I24) {
            try self.depth_texture.upload(new_width_height, ImageType.Depth24, null, null, null, null, null, null);
        } else if (self.depth_type == FrameBuffer.DepthType.F32) {
            try self.depth_texture.upload(new_width_height, ImageType.Depth32F, null, null, null, null, null, null);
        } else {
            assert(false);
        }
    }

    // Active framebuffer will be unbound
    pub fn resize(self: *CubeFrameBuffer, new_width_height: u32) !void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        try self.setTextureSize(new_width_height);
    }
};

test "framebuffer" {
    try window.createWindow(false, 200, 200, "test", true, 0);

    var fb: CubeFrameBuffer = try CubeFrameBuffer.init(256, FrameBuffer.DepthType.I16);
    try fb.bind(CubeFrameBuffer.Direction.PositiveY);
    fb.free();

    window.closeWindow();
}
