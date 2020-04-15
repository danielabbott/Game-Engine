const std = @import("std");
const assert = std.debug.assert;
const img = @import("Image.zig");
const ImageType = img.ImageType;
const MinFilter = img.MinFilter;
const Texture2D = img.Texture2D;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

// Framebuffer with 2D backing texture
pub const FrameBuffer = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    id: u32,

    textures: [8]?*Texture2D = [_]?*Texture2D {null}**8,
    texture_count: u32 = 0,
    depth_texture: ?*Texture2D,

    pub const DepthType = enum {
        None,
        I16,
        I24,
        I32,
        F32,
    };

    depth_type: DepthType,

    // If not null then the texture and/or depth texture were created with this and will be freed with it
    allocator: ?*std.mem.Allocator = null,

    pub fn init3(textures: []*Texture2D, depth_texture: ?*Texture2D) !FrameBuffer {
        if(textures.len > 0) {
            const w = textures[0].width;
            const h = textures[0].height;
            for(textures) |t| {
                if(t.width != w or t.height != h) {
                    return error.InconsistentTextureDimensions;
                }

                t.ref_count.inc();
                errdefer t.ref_count.dec();
            }
        }

        if(depth_texture != null) {
            depth_texture.?.ref_count.inc();
            errdefer depth_texture.?.ref_count.dec();
        }

        // Create FBO

        var id: u32 = 0;
        c.glGenFramebuffers(1, @ptrCast([*c]c_uint, &id));
        if (id == 0) {
            assert(false);
            return error.OpenGLError;
        }
        errdefer c.glDeleteFramebuffers(1, @ptrCast([*c]c_uint, &id));

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, id);

        // Get image types

        var depth_type: DepthType = DepthType.None;

        if(depth_texture != null) {
            const t = depth_texture.?.imageType;

            if(t == ImageType.Depth16) {
                depth_type = DepthType.I16;
            }
            else if(t == ImageType.Depth24) {
                depth_type = DepthType.I24;
            }
            else if(t == ImageType.Depth32) {
                depth_type = DepthType.I32;
            }
            else if(t == ImageType.Depth32F) {
                depth_type = DepthType.F32;
            }
        }

        // Create object

        var frameBuffer = FrameBuffer{
            .id = id,
            .depth_type = depth_type,
            .depth_texture = depth_texture,
        };

        // Configure framebuffer


        
        if (depth_type != DepthType.None) {
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, depth_texture.?.id, 0);
        }

        if (textures.len == 0) {
            c.glDrawBuffer(c.GL_NONE);
            c.glReadBuffer(c.GL_NONE);
        } else {
            try frameBuffer.addMoreTextures(textures);
        }

        // Validate framebuffer

        const status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
        if (status != c.GL_FRAMEBUFFER_COMPLETE) {
            std.debug.warn("Framebuffer incomplete. Error: {}\n", .{status});
            assert(false);
            return error.OpenGLError;
        }

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        return frameBuffer;
    }

    pub fn addMoreTextures(self: *FrameBuffer, textures: []*Texture2D) !void {
        if(textures.len == 0) {
            return;
        }

        var drawBuffers: [8]c_uint = [_]c_uint{c.GL_NONE}**8;

        var i: u32 = 0;
        for(self.textures) |t| {
            if(t == null) {
                break;
            }
            drawBuffers[i] = c.GL_COLOR_ATTACHMENT0 + @intCast(c_uint, i);
            i += 1;
        }

        if(i + textures.len > 8) {
            assert(false);
            return error.TooManyTextures;
        }
        
        for(textures) |t| {
            self.textures[i] = t;
            drawBuffers[i] = c.GL_COLOR_ATTACHMENT0 + @intCast(c_uint, i);
            self.texture_count += 1;
            c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0+@intCast(c_uint, i), c.GL_TEXTURE_2D, t.id, 0);
            t.ref_count.inc();
            i += 1;
        }

        c.glDrawBuffers(@intCast(c_int, textures.len), drawBuffers[0..textures.len].ptr);
    }

    pub fn init2(texture: ?*Texture2D, depth_texture: ?*Texture2D) !FrameBuffer {
        if(texture == null and depth_texture == null) {
            return error.ParameterError;
        }

        if(texture != null) {
            var p = [1]*Texture2D{texture.?};
            return try init3(p[0..], depth_texture);
        }
        else {
             return try init3(&[0]*Texture2D{}, depth_texture);
        }
    }

    // image_type: If null then no colour buffer is created
    pub fn init(image_type: ?ImageType, width: u32, height: u32, depth_type: DepthType, allocator: *std.mem.Allocator) !FrameBuffer {
        if (depth_type == DepthType.None and image_type == null) {
            return error.NoTexture;
        }

        if (image_type != null and (image_type.? == ImageType.Depth16 or image_type.? == ImageType.Depth24 or image_type.? == ImageType.Depth32 or image_type.? == ImageType.Depth32)) {
            return error.ColourTextureCannotHaveDepthType;
        }

        // Create backing texture

        var texture: ?*Texture2D = null;
        var depth_texture: ?*Texture2D = null;

        if (image_type != null) {
            texture = try allocator.create(Texture2D);
            texture.?.* = try Texture2D.init(false, img.MinFilter.Nearest);
            errdefer texture.?.free();
            try texture.?.upload(width, height, image_type.?, null);
        }

        if (depth_type != DepthType.None) {
            // Create depth buffer
            depth_texture = &(try allocator.alloc(Texture2D, 1))[0];
            depth_texture.?.* = try Texture2D.init(false, img.MinFilter.Nearest);
            errdefer depth_texture.?.free();

            if (depth_type == DepthType.I16) {
                try depth_texture.?.upload(width, height, ImageType.Depth16, null);
            } else if (depth_type == DepthType.I24) {
                try depth_texture.?.upload(width, height, ImageType.Depth24, null);
            }  else if (depth_type == DepthType.I32) {
                try depth_texture.?.upload(width, height, ImageType.Depth32, null);
            } else if (depth_type == DepthType.F32) {
                try depth_texture.?.upload(width, height, ImageType.Depth32F, null);
            }
        }


        var fb = try init2(texture, depth_texture);
        fb.allocator = allocator;
        return fb;
    }

    pub fn setTextureFiltering(self: *FrameBuffer, min_blur: bool, mag_blur: bool) !void {
        try self.bindTexture();
        for(self.textures) |*t| {
            if(t.* == null) {
                break;
            }
            if (min_blur) {
                try t.*.?.setFiltering(mag_blur, MinFilter.Linear);
            } else {
                try t.*.?.setFiltering(mag_blur, MinFilter.Nearest);
            }
        }
    }

    // Bind for drawing
    pub fn bind(self: *FrameBuffer) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindFramebuffer(c.GL_DRAW_FRAMEBUFFER, self.id);
        if (self.textures[0] == null) {
            c.glViewport(0, 0, @intCast(c_int, self.depth_texture.?.width), @intCast(c_int, self.depth_texture.?.height));
        } else {
            c.glViewport(0, 0, @intCast(c_int, self.textures[0].?.width), @intCast(c_int, self.textures[0].?.height));
        }
    }

    pub fn bindTexture(self: FrameBuffer) !void {
        try self.textures[0].?.bind();
    }

    pub fn bindTextureToUnit(self: FrameBuffer, unit: u32) !void {
        try self.textures[0].?.bindToUnit(unit);
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
        self.ref_count.deinit();

        for(self.textures) |t| {
            if(t != null) {
                t.?.ref_count.dec();
            }
        }
        if (self.depth_texture != null) {
            self.depth_texture.?.ref_count.dec();
        }

        c.glDeleteFramebuffers(1, @ptrCast([*c]const c_uint, &self.id));

        if(self.allocator != null) {
            for(self.textures) |t| {
                if(t != null) {
                    self.allocator.?.destroy(t.?);
                }
            }
            if(self.depth_texture != null) {
                self.allocator.?.destroy(self.depth_texture.?);
            }
        }
    }

    pub fn bindDefaultFrameBuffer() void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        var window_width: u32 = 0;
        var window_height: u32 = 0;
        window.getSize(&window_width, &window_height);
        c.glViewport(0, 0, @intCast(c_int, window_width), @intCast(c_int, window_height));
    }

    fn setTextureSizes(self: *FrameBuffer, new_width: u32, new_height: u32) !void {
        for(self.textures) |t| {
            if (t != null) {
                try t.?.upload(new_width, new_height, t.?.imageType, null);
            }
        }

        if (self.depth_texture != null) {
            if (self.depth_type == DepthType.I16) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth16, null);
            } else if (self.depth_type == DepthType.I24) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth24, null);
            }  else if (self.depth_type == DepthType.I32) {
                try self.depth_texture.?.upload(new_width, new_height, ImageType.Depth32, null);
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
    try window.createWindow(false, 200, 200, "test", true, 0);

    var a = std.heap.c_allocator;

    var fb: FrameBuffer = try FrameBuffer.init(ImageType.R, 200, 200, FrameBuffer.DepthType.I16, a);
    try fb.bind();
    fb.free();

    window.closeWindow();
}
