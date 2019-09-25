pub const window = @import("Window.zig");
pub const input = @import("Input.zig");
pub const c = @import("c.zig").c;
pub const ArrayTexture = @import("ArrayTexture.zig").ArrayTexture;
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
    D3D11
};

pub fn getGraphicsAPI() GraphicsAPI {
    return GraphicsAPI.OpenGL33;
}

pub fn enableDepthTesting() void {
    c.glEnable(c.GL_DEPTH_TEST);
}

pub fn disableDepthTesting() void {
    c.glDisable(c.GL_DEPTH_TEST);
}

pub fn enableDepthWriting() void {
    c.glDepthMask (c.GL_TRUE);
}
pub fn disableDepthWriting() void {
    c.glDepthMask (c.GL_FALSE);
}

pub const CullFaceMode = enum(u32) {
    Front = c.GL_FRONT,
    Back = c.GL_BACK,
};

pub fn cullFace(mode: CullFaceMode) void {
    c.glCullFace(@enumToInt(mode));
}

// Individual values are meaningless - use for time deltas
pub fn getMicroTime() u64 {
    const freq = c.glfwGetTimerFrequency();
    if(freq == 0) {
       return 0;
    }
    if(freq % 10 == 0) {
        if(freq < 1000000) {
            return c.glfwGetTimerValue() * (1000000 / freq);
        }
        else {
            // Same calulation but the alternative code would just produce 0
            return c.glfwGetTimerValue() / (freq / 1000000);
        }
    }
    else {
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
