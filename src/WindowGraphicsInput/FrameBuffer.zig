const std = @import("std");
const assert = std.debug.assert;
const img = @import("Image.zig");
const ImageType = img.ImageType;
const Texture2D = img.Texture2D;
const window = @import("Window.zig");
const c = @import("c.zig").c;

// Framebuffer with 2D backing texture
pub const FrameBuffer = struct {
    id: u32,
    texture: ?Texture2D,
    depth_texture: ?Texture2D,
    image_type: ?ImageType,

    pub const DepthType = enum {
        None,
        I16,
        I24,
        F32,
    };

    depth_type: DepthType,

    // image_type: If null then no colour buffer is created
    pub fn init(image_type: ?ImageType, width: u32, height: u32, depth_type: DepthType) !FrameBuffer {
        if (depth_type == DepthType.None and image_type == null) {
            return error.NoTexture;
        }

        if (image_type != null and (image_type.? == ImageType.Depth16 or image_type.? == ImageType.Depth24 or image_type.? == ImageType.Depth32 or image_type.? == ImageType.Depth32)) {
            return error.ColourTextureCannotHaveDepthType;
        }


        // Create OpenGL framebuffer object

        var id: u32 = 0;
        c.glGenFramebuffers(1, @ptrCast([*c]c_uint, &id));
        if (id == 0) {
            assert(false);
            return error.OpenGLError;
        }
        errdefer c.glDeleteFramebuffers(1, @ptrCast([*c]c_uint, &id));

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, id);

        var frameBuffer = FrameBuffer {
            .id = id,
            .image_type = image_type,
            .depth_type = depth_type,
            .texture = null,
            .depth_texture = null
        };

        // Create backing texture

        if (image_type == null) {
            frameBuffer.texture = null;
        } else {
            frameBuffer.texture = try Texture2D.init(false, img.MinFilter.Nearest);
            errdefer frameBuffer.texture.?.free();
        }

        if (depth_type != DepthType.None) {
            // Create depth buffer
            frameBuffer.depth_texture = try Texture2D.init(false, img.MinFilter.Nearest);
            errdefer frameBuffer.depth_texture.?.free();
        } else {
            frameBuffer.depth_texture = null;
        }

        try frameBuffer.setTextureSizes(width, height);

        if (image_type != null) {
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, frameBuffer.texture.?.id, 0);
        }
        if (depth_type != DepthType.None) {
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, frameBuffer.depth_texture.?.id, 0);
        }

        // Configure framebuffer

        if (image_type == null) {
            c.glDrawBuffer(c.GL_NONE);
            c.glReadBuffer(c.GL_NONE);
        } else {
            // var drawBuffers: [1]c_uint = [1]c_uint{c.GL_COLOR_ATTACHMENT0};
            // c.glDrawBuffers(1, drawBuffers[0..].ptr);
            c.glDrawBuffer(c.GL_COLOR_ATTACHMENT0);
        }

        // Validate framebuffer

        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) {
            assert(false);
            return error.OpenGLError;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        return frameBuffer;
    }

    // Bind for drawing
    pub fn bind(self: *FrameBuffer) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, self.id);
        if (self.texture == null) {
            c.glViewport(0, 0, @intCast(c_int, self.depth_texture.?.width), @intCast(c_int, self.depth_texture.?.height));
        } else {
            c.glViewport(0, 0, @intCast(c_int, self.texture.?.width), @intCast(c_int, self.texture.?.height));
        }
    }

    pub fn bindTexture(self: FrameBuffer) !void {
        try self.texture.?.bind();
    }

    pub fn bindTextureToUnit(self: FrameBuffer, unit: u32) !void {
        try self.texture.?.bindToUnit(unit);
    }

    pub fn bindDepthTexture(self: FrameBuffer) !void {
        try self.depth_texture.?.bind();
    }

    pub fn bindDepthTextureToUnit(self: FrameBuffer, unit: u32) !void {
        try self.depth_texture.?.bindToUnit(unit);
    }

    pub fn free(self: *FrameBuffer) void {
        if (self.id == 0) {
            assert(false);
            return;
        }

        if (self.texture != null) {
            self.texture.?.free();
        }
        if (self.depth_texture != null) {
            self.depth_texture.?.free();
        }

        c.glDeleteFramebuffers(1, @ptrCast([*c]const c_uint, &self.id));
    }

    pub fn bindDefaultFrameBuffer() void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        var window_width: u32 = 0;
        var window_height: u32 = 0;
        window.getSize(&window_width, &window_height);
        c.glViewport(0, 0, @intCast(c_int, window_width), @intCast(c_int, window_height));
    }

    fn setTextureSizes(self: *FrameBuffer, new_width: u32, new_height: u32) !void {
        if (self.texture != null) {
            try self.texture.?.upload(new_width, new_height, self.image_type.?, null);
        }

        if (self.depth_texture != null) {
            if (self.depth_type == DepthType.I16) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth16, null);
            } else if (self.depth_type == DepthType.I24) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth24, null);
            } else if (self.depth_type == DepthType.F32) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth32F, null);
            } else {
                assert(false);
            }
        }
    }

    // Active framebuffer will be unbound
    pub fn resize(self: *FrameBuffer, new_width: u32, new_height: u32) !void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        try self.setTextureSizes(new_width, new_height);
    }
};

test "framebuffer" {
    try window.createWindow(false, 200, 200, c"test", true, 0);

    var fb: FrameBuffer = try FrameBuffer.init(ImageType.R, 200, 200, FrameBuffer.DepthType.I16);
    try fb.bind();
    fb.free();

    window.closeWindow();
}
