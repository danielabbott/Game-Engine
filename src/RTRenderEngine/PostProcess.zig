const std = @import("std");
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const FrameBuffer = wgi.FrameBuffer;
const ImageType = wgi.ImageType;
const ShaderObject = wgi.ShaderObject;
const ShaderType = wgi.ShaderType;
const ShaderProgram = wgi.ShaderProgram;
const window = wgi.window;
const Buffer = wgi.Buffer;
const VertexMeta = wgi.VertexMeta;
const files = @import("../Files.zig");
const loadFileWithNullTerminator = files.loadFileWithNullTerminator;

var post_process_shader_vs_src: ?[]u8 = null;
var post_process_shader_fs_src: ?[]u8 = null;
var post_process_shader_program: ?ShaderProgram = null;
var post_process_shader_program_window_size_uniform_location: ?i32 = null;
var fbo: ?FrameBuffer = null;
var buffer: ?Buffer = null;
var vao: ?VertexMeta = null;

pub fn loadSourceFiles(allocator: *std.mem.Allocator) !void {
    post_process_shader_vs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "PostProcess.vs", allocator);
    post_process_shader_fs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "PostProcess.fs", allocator);
}

fn createShaderProgram(allocator: *std.mem.Allocator) !void {
    var post_process_vs: ShaderObject = try ShaderObject.init(([_]([]const u8){post_process_shader_vs_src.?})[0..], ShaderType.Vertex, allocator);
    var post_process_fs: ShaderObject = try ShaderObject.init(([_]([]const u8){post_process_shader_fs_src.?})[0..], ShaderType.Fragment, allocator);
    errdefer post_process_shader_program = null;
    post_process_shader_program = try ShaderProgram.init(&post_process_vs, &post_process_fs, [0][]const u8{}, allocator);
    errdefer post_process_shader_program.?.free();

    try post_process_shader_program.?.setUniform1i(try post_process_shader_program.?.getUniformLocation(c"framebuffer"), 0);
    post_process_shader_program_window_size_uniform_location = try post_process_shader_program.?.getUniformLocation(c"window_dimensions");

    post_process_vs.free();
    post_process_fs.free();
}

fn createResources(window_width: u32, window_height: u32, allocator: *std.mem.Allocator) !void {
    if (fbo == null) {
        fbo = try FrameBuffer.init(wgi.ImageType.RGBA, window_width, window_height, FrameBuffer.DepthType.F32);
    } else if (fbo.?.texture.?.width != window_width or fbo.?.texture.?.height != window_height) {
        try fbo.?.resize(window_width, window_height);
    }

    if (post_process_shader_program == null) {
        try createShaderProgram(allocator);
    }

    if (buffer == null) {
        // Cover entire screen with one triangle
        // Coordinates in clip space
        const vData = [6]f32{
            -6.0, -1.0,
            1.0,  -1.0,
            1.0,  6.0,
        };
        buffer = try Buffer.init();

        try buffer.?.upload(Buffer.BufferType.VertexData, @sliceToBytes(vData[0..]), false);
    }

    if (vao == null) {
        const inputs = [_]VertexMeta.VertexInput{ VertexMeta.VertexInput {
            .offset = 0,
            .componentCount = 2,
            .stride = 0,
            .dataType = VertexMeta.VertexInput.DataType.Float,
            .dataElementSize = 4,
            .signed = true,
            .normalised = false,
            .source = &buffer.?,
        }};

        vao = try VertexMeta.init(inputs[0..], null);
    }
}

pub fn startFrame(post_process: bool, window_width: u32, window_height: u32, allocator: *std.mem.Allocator) !void {
    if(window_width == 0 or window_height == 0) {
        return error.InvalidWindowDimensions;
    }

    if (post_process) {
        createResources(window_width, window_height, allocator) catch |e| {
            std.debug.warn("Error creating post-process resources: {}\n", e);
            return e;
        };
        
        try fbo.?.bind();
    } else {
        FrameBuffer.bindDefaultFrameBuffer();
    }
}

pub fn endFrame(post_process_enabled: bool, window_width: u32, window_height: u32) !void {
    if (post_process_enabled) {
        wgi.disableDepthTesting();
        wgi.disableDepthWriting();
        FrameBuffer.bindDefaultFrameBuffer();
        window.clear(true, false);
        try post_process_shader_program.?.bind();
        try post_process_shader_program.?.setUniform2f(post_process_shader_program_window_size_uniform_location.?, [2]f32{ @intToFloat(f32, window_width), @intToFloat(f32, window_height) });
        try fbo.?.bindTexture();
        try vao.?.draw(VertexMeta.PrimitiveType.Triangles, 0, 3);
    }
}
