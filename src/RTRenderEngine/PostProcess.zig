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
var post_process_shader_program_contrast_uniform_location: ?i32 = null;
var post_process_shader_program_brightness_uniform_location: ?i32 = null;
var fbo: ?FrameBuffer = null;

pub fn loadSourceFiles(allocator: *std.mem.Allocator) !void {
    post_process_shader_vs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "PostProcess.vs", allocator);
    post_process_shader_fs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "PostProcess.fs", allocator);
}

fn createShaderProgram(allocator: *std.mem.Allocator) !void {
    var post_process_vs: ShaderObject = try ShaderObject.init(([_]([]const u8){post_process_shader_vs_src.?})[0..], ShaderType.Vertex, allocator);
    var post_process_fs: ShaderObject = try ShaderObject.init(([_]([]const u8){post_process_shader_fs_src.?})[0..], ShaderType.Fragment, allocator);
    errdefer post_process_shader_program = null;
    post_process_shader_program = try ShaderProgram.init(&post_process_vs, &post_process_fs, &[0][]const u8{}, allocator);
    errdefer post_process_shader_program.?.free();

    try post_process_shader_program.?.setUniform1i(try post_process_shader_program.?.getUniformLocation("framebuffer"), 0);
    post_process_shader_program_window_size_uniform_location = try post_process_shader_program.?.getUniformLocation("window_dimensions");

    post_process_shader_program_contrast_uniform_location = try post_process_shader_program.?.getUniformLocation("contrast");
    post_process_shader_program_brightness_uniform_location = try post_process_shader_program.?.getUniformLocation("brightness");

    post_process_vs.free();
    post_process_fs.free();
}

fn createResources(window_width: u32, window_height: u32, allocator: *std.mem.Allocator) !void {
    if (fbo == null) {
        fbo = try FrameBuffer.init(wgi.ImageType.RG11FB10F, window_width, window_height, FrameBuffer.DepthType.F32, allocator);
    } else if (fbo.?.textures[0].?.width != window_width or fbo.?.textures[0].?.height != window_height) {
        try fbo.?.resize(window_width, window_height);
    }

    if (post_process_shader_program == null) {
        try createShaderProgram(allocator);
    }
}

pub fn startFrame(window_width: u32, window_height: u32, allocator: *std.mem.Allocator) !void {
    if (window_width == 0 or window_height == 0) {
        return error.InvalidWindowDimensions;
    }

    createResources(window_width, window_height, allocator) catch |e| {
        std.debug.warn("Error creating post-process resources: {}\n", .{e});
        return e;
    };

    try fbo.?.bind();
}

pub fn endFrame(window_width: u32, window_height: u32, brightness: f32, contrast: f32) !void {
    wgi.disableDepthTesting();
    wgi.disableDepthWriting();
    FrameBuffer.bindDefaultFrameBuffer();
    window.clear(true, false);
    try post_process_shader_program.?.bind();
    try post_process_shader_program.?.setUniform2f(post_process_shader_program_window_size_uniform_location.?, [2]f32{ @intToFloat(f32, window_width), @intToFloat(f32, window_height) });
    try post_process_shader_program.?.setUniform1f(post_process_shader_program_brightness_uniform_location.?, brightness);
    try post_process_shader_program.?.setUniform1f(post_process_shader_program_contrast_uniform_location.?, contrast);
    try fbo.?.bindTexture();
    try VertexMeta.drawWithoutData(VertexMeta.PrimitiveType.Triangles, 0, 3);
    wgi.Texture2D.unbind(0);
}
