pub const window = @import("Window.zig");
pub const input = @import("Input.zig");
pub const c = @import("c.zig").c;
pub const ArrayTexture = @import("ArrayTexture.zig").Texture2DArray;
pub const CubeMap = @import("CubeMap.zig").CubeMap;
pub const Buffer = @import("Buffer.zig").Buffer;
const shdr = @import("Shader.zig");
pub const ShaderObject = shdr.ShaderObject;
pub const ShaderProgram = shdr.ShaderProgram;
pub const ShaderType = shdr.ShaderType;
pub const VertexMeta = @import("VertexMeta.zig").VertexMeta;
pub const FrameBuffer = @import("FrameBuffer.zig").FrameBuffer;
pub const CubeFrameBuffer = @import("CubeFrameBuffer.zig").CubeFrameBuffer;
pub const image = @import("Image.zig");
pub const ImageType = image.ImageType;
pub const MinFilter = image.MinFilter;
pub const imageDataSize = image.imageDataSize;
pub const Texture2D = image.Texture2D;
pub const Constants = @import("Constants.zig");

pub const GraphicsAPI = enum {
    GL33,
    D3D11,
};

pub fn getGraphicsAPI() GraphicsAPI {
    return GraphicsAPI.OpenGL33;
}

pub fn disableDepthTesting() void {
    c.glDepthFunc(c.GL_ALWAYS);
}

pub fn enableDepthWriting() void {
    c.glDepthMask(c.GL_TRUE);
}
pub fn disableDepthWriting() void {
    c.glDepthMask(c.GL_FALSE);
}

// setDepthMode functions enable depth testing

fn setDepthFunc(eql: bool, flip: bool) void {
    if (eql) {
        if (flip) {
            c.glDepthFunc(c.GL_LEQUAL);
        } else {
            c.glDepthFunc(c.GL_GEQUAL);
        }
    } else {
        if (flip) {
            c.glDepthFunc(c.GL_LESS);
        } else {
            c.glDepthFunc(c.GL_GREATER);
        }
    }
}

pub fn setDepthModeDirectX(equal_passes: bool, flip: bool) void {
    c.glClipControl(c.GL_LOWER_LEFT, c.GL_ZERO_TO_ONE);
    c.glClearDepth(0.0);

    setDepthFunc(equal_passes, flip);
}

pub fn setDepthModeOpenGL(equal_passes: bool, flip: bool) void {
    c.glClipControl(c.GL_LOWER_LEFT, c.GL_NEGATIVE_ONE_TO_ONE);
    c.glClearDepth(1.0);

    setDepthFunc(equal_passes, !flip);
}

pub const CullFaceMode = enum(u32) {
    Front = c.GL_FRONT,
    Back = c.GL_BACK,
};

pub fn cullFace(mode: CullFaceMode) void {
    c.glCullFace(@enumToInt(mode));
}
pub fn enableAdditiveBlending() void {
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE);
    c.glBlendEquation(c.GL_FUNC_ADD);
}

pub fn enableRegularBlending() void {
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glBlendEquation(c.GL_FUNC_ADD);
}

pub fn disableBlending() void {
    c.glDisable(c.GL_BLEND);
}

// Individual values are meaningless - use for time deltas
pub fn getMicroTime() u64 {
    const freq = c.glfwGetTimerFrequency();
    if (freq == 0) {
        return 0;
    }
    if (freq % 10 == 0) {
        if (freq < 1000000) {
            return c.glfwGetTimerValue() * (1000000 / freq);
        } else {
            // Same calulation but the alternative code would just produce 0
            return c.glfwGetTimerValue() / (freq / 1000000);
        }
    } else {
        const m = 1000000.0 / @intToFloat(f64, freq);
        return @floatToInt(u64, @intToFloat(f64, c.glfwGetTimerValue()) * m);
    }
}

test "All tests" {
    _ = @import("Window.zig");
    _ = @import("ArrayTexture.zig");
    _ = @import("Buffer.zig");
    _ = @import("Image.zig");
    _ = @import("Shader.zig");
    _ = @import("VertexMeta.zig");
    _ = @import("FrameBuffer.zig");
    _ = @import("CubeMap.zig");
    _ = @import("CubeFrameBuffer.zig");
    _ = @import("Input.zig");
}
