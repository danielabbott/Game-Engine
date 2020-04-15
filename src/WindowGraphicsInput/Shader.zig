const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const expect = std.testing.expect;
const loadFile = @import("../Files.zig").loadFile;
const builtin = @import("builtin");
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

var bound_shader: u32 = 0;

const shader_type_gl = [_]c_uint{
    c.GL_VERTEX_SHADER,
    c.GL_FRAGMENT_SHADER,
};

pub const ShaderType = enum(u32) {
    Vertex = 0,
    Fragment = 1,
};

pub const ShaderObject = struct {
    id: u32,
    shaderType: ShaderType,

    // STRING INPUTS MUST BE NULL TERMINATED
    pub fn init(source_strings: []const ([]const u8), sType: ShaderType, allocator: *std.mem.Allocator) !ShaderObject {
        var id: u32 = c.glCreateShader(shader_type_gl[@enumToInt(sType)]);

        if (id == 0) {
            return error.OpenGLError;
        }

        errdefer c.glDeleteShader(id);

        // Upload shader source

        var string_pointers: []([*c]const u8) = try allocator.alloc(([*c]const u8), source_strings.len);
        var i: u32 = 0;
        while (i < source_strings.len) : (i += 1) {
            if (source_strings[i][source_strings[i].len - 1] != 0) {
                assert(false);
                return error.SourceStringNotNullTerminated;
            }
            string_pointers[i] = source_strings[i].ptr;
        }

        c.glShaderSource(id, @intCast(c_int, source_strings.len), &string_pointers[0], 0);
        allocator.free(string_pointers);

        // Compile

        c.glCompileShader(id);

        // Check for errors

        var status: u32 = 0;
        c.glGetShaderiv(id, c.GL_COMPILE_STATUS, @ptrCast([*c]c_int, &status));
        if (status == 0) {
            warn("ShaderObject.init: Shader compilation failed\n", .{});

            var logSize: c_int = 0;
            c.glGetShaderiv(id, c.GL_INFO_LOG_LENGTH, &logSize);

            if (logSize > 0) {
                var log: []u8 = try allocator.alloc(u8, @intCast(usize, logSize) + 1);
                defer allocator.free(log);
                c.glGetShaderInfoLog(id, logSize, 0, log.ptr);
                log[log.len - 1] = 0;

                warn("Log: ###\n{}\n###\nShader that failed:\n###\n", .{log});
                for (source_strings) |a| {
                    warn("{}", .{a[0 .. a.len - 1]});
                }
                warn("###\n", .{});
            }

            return error.OpenGLError;
        }

        return ShaderObject{
            .id = id,
            .shaderType = sType,
        };
    }

    pub fn free(self: *ShaderObject) void {
        if (self.id == 0) {
            assert(false);
            return;
        }

        c.glDeleteShader(self.id);
        self.id = 0;
    }
};

pub const ShaderProgram = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    id: u32,

    // Vertex attribute strings must be null terminated
    pub fn init(vs: *const ShaderObject, fs: ?*const ShaderObject, vertexAttributes: []const ([]const u8), allocator: *std.mem.Allocator) !ShaderProgram {
        if (vs.shaderType != ShaderType.Vertex or (fs != null and fs.?.shaderType != ShaderType.Fragment) or vs.id == 0 or (fs != null and fs.?.id == 0)) {
            assert(false);
            return error.InvalidParameter;
        }

        // Attach shaders

        const id: u32 = c.glCreateProgram();
        errdefer c.glDeleteProgram(id);

        if (id == 0) {
            return error.OpenGLError;
        }

        c.glAttachShader(id, vs.id);

        if (fs != null) {
            c.glAttachShader(id, fs.?.id);
        }

        // Set vertex attributes

        var i: u32 = 0;
        for (vertexAttributes) |a| {
            if (a[a.len - 1] != 0) {
                return error.StringNotNullTerminated;
            }
            c.glBindAttribLocation(id, i, a.ptr);
            i += 1;
        }

        // Link

        c.glLinkProgram(id);

        var s = ShaderProgram{ .id = id };

        // Error check and validate

        var status: u32 = 0;
        c.glGetProgramiv(id, c.GL_LINK_STATUS, @ptrCast([*c]c_int, &status));

        if (status == 0) {
            warn("ShaderProgram.init: Shader linking failed\n", .{});

            s.printLog(allocator);

            return error.OpenGLError;
        }

        return s;
    }

    fn printLog(self: ShaderProgram, allocator: *std.mem.Allocator) void {
        var logSize: c_int = 0;
        c.glGetProgramiv(self.id, c.GL_INFO_LOG_LENGTH, &logSize);

        if (logSize > 0) {
            var log: []u8 = allocator.alloc(u8, @intCast(usize, logSize) + 1) catch return;
            defer allocator.free(log);
            c.glGetProgramInfoLog(self.id, logSize, 0, log.ptr);
            log[log.len - 1] = 0;

            warn("Log: {}\n", .{log});
        }
    }

    pub fn validate(self: ShaderProgram, allocator: *std.mem.Allocator) void {
        if (builtin.mode == builtin.Mode.Debug) {
            if (self.id == 0) {
                assert(false);
                return;
            }

            c.glValidateProgram(self.id);

            var status: c_int = 0;
            c.glGetProgramiv(self.id, c.GL_VALIDATE_STATUS, &status);

            if (status == 0) {
                warn("ShaderProgram.init: Shader validation failed\n", .{});
                self.printLog(allocator);
            }
        }
    }

    pub fn bind(self: ShaderProgram) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        if (bound_shader != self.id) {
            c.glUseProgram(self.id);
            bound_shader = self.id;
        }
    }

    pub fn free(self: *ShaderProgram) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        self.ref_count.deinit();

        c.glDeleteProgram(self.id);
    }

    pub fn getUniformLocation(self: *ShaderProgram, name: [*]const u8) !i32 {
        if (self.id == 0) {
            assert(false);
            return error.ObjectNotCreated;
        }

        var loc: i32 = c.glGetUniformLocation(self.id, name);

        if (loc == -1) {
            return error.UniformNotFound;
        }

        return loc;
    }

    pub fn setUniform1i(self: ShaderProgram, location: i32, data: i32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform1i(location, @intCast(c_int, data));
    }

    pub fn setUniform1f(self: ShaderProgram, location: i32, data: f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform1f(location, data);
    }

    pub fn setUniform2f(self: ShaderProgram, location: i32, data: [2]f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform2f(location, data[0], data[1]);
    }

    pub fn setUniform3f(self: ShaderProgram, location: i32, data: [3]f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform3f(location, data[0], data[1], data[2]);
    }

    pub fn setUniform4f(self: ShaderProgram, location: i32, data: [4]f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform4f(location, data[0], data[1], data[2], data[3]);
    }

    pub fn setUniform2i(self: ShaderProgram, location: i32, data: [2]i32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform2i(location, data[0], data[1]);
    }

    pub fn setUniform3i(self: ShaderProgram, location: i32, data: [3]i32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform3i(location, data[0], data[1], data[2]);
    }

    pub fn setUniform4i(self: ShaderProgram, location: i32, data: [4]i32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform4i(location, data[0], data[1], data[2], data[3]);
    }

    pub fn setUniformMat2(self: ShaderProgram, location: i32, count: i32, data: []const f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (count <= 0) {
            assert(false);
            return error.InvalidParameter;
        }
        if (@intCast(i32, data.len) != count * 4) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniformMatrix2fv(location, count, 0, data.ptr);
    }

    pub fn setUniformMat3(self: ShaderProgram, location: i32, count: i32, data: []const f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (count <= 0) {
            assert(false);
            return error.InvalidParameter;
        }
        if (@intCast(i32, data.len) != count * 9) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniformMatrix3fv(location, count, 0, data.ptr);
    }

    pub fn setUniformMat4(self: ShaderProgram, location: i32, count: i32, data: []const f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (count <= 0) {
            assert(false);
            return error.InvalidParameter;
        }
        if (@intCast(i32, data.len) != count * 16) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniformMatrix4fv(location, count, 0, data.ptr);
    }

    // data.len == count*4*3
    pub fn setUniformMat4x3(self: ShaderProgram, location: i32, count: i32, data: []f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (count <= 0) {
            assert(false);
            return error.InvalidParameter;
        }
        if (@intCast(i32, data.len) != count * 4 * 3) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniformMatrix4x3fv(location, count, 0, data.ptr);
    }

    pub fn setUniform1iv(self: ShaderProgram, location: i32, data: []const i32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (data.len == 0) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform1iv(location, @intCast(c_int, data.len), @ptrCast([*c]const c_int, data.ptr));
    }

    pub fn setUniform1fv(self: ShaderProgram, location: i32, data: []const f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (data.len == 0) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform1fv(location, @intCast(c_int, data.len), @ptrCast([*c]const f32, data.ptr));
    }

    pub fn setUniform2fv(self: ShaderProgram, location: i32, data: []const f32) !void {
        if (location == -1) {
            assert(false);
            return error.InvalidParameter;
        }
        if (data.len == 0 or data.len % 2 != 0) {
            assert(false);
            return error.InvalidParameter;
        }

        try self.bind();

        c.glUniform2fv(location, @intCast(c_int, data.len / 2), @ptrCast([*c]const f32, data.ptr));
    }

    pub fn getUniformBlockIndex(self: ShaderProgram, name: [*]const u8) !u32 {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        const index = c.glGetUniformBlockIndex(self.id, name);
        if (index == 0xffffffff) {
            return error.OpenGLError;
        }

        return @intCast(u32, index);
    }

    pub fn setUniformBlockBinding(self: ShaderProgram, block_index: u32, binding: u32) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glUniformBlockBinding(self.id, block_index, binding);
    }

    pub fn getBinary(self: ShaderProgram, data: *([]u8), binary_format: *u32, allocator: *std.mem.Allocator) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        if (c.GLAD_GL_ARB_get_program_binary == 0) {
            return error.NotSupported;
        }

        var binary_size: c_int = 0;

        c.glGetProgramiv(self.id, c.GL_PROGRAM_BINARY_LENGTH, &binary_size);

        if (binary_size < 1 or binary_size > 100 * 1024 * 1024) {
            return error.OpenGLError;
        }

        data.* = try allocator.alloc(u8, @intCast(usize, binary_size));

        c.glGetProgramBinary(self.id, binary_size, null, @ptrCast([*c]c_uint, binary_format), data.*.ptr);
    }

    pub fn saveBinary(self: ShaderProgram, file_path: []const u8, allocator: *std.mem.Allocator) !void {
        var data: []u8 = undefined;
        var binary_format: [1]u32 = undefined;
        try self.getBinary(&data, &binary_format[0], allocator);

        var file = try std.fs.cwd().openFile(file_path, std.fs.File.OpenFlags{.write=true});
        defer file.close();

        _ = try file.write(std.mem.sliceAsBytes(binary_format[0..]));
        _ = try file.write(data[0..]);

        allocator.free(data);
    }

    pub fn loadFromBinary(binary_format: u32, data: []const u8) !ShaderProgram {
        if (c.GLAD_GL_ARB_get_program_binary == 0) {
            return error.NotSupported;
        }

        const id: u32 = c.glCreateProgram();
        errdefer c.glDeleteProgram(id);

        if (id == 0) {
            return error.OpenGLError;
        }

        c.glProgramBinary(id, binary_format, data[0..].ptr, @intCast(c_int, data.len));

        var status: u32 = 0;
        c.glGetProgramiv(id, c.GL_LINK_STATUS, @ptrCast([*c]c_int, &status));

        if (status == 0) {
            return error.OpenGLError;
        }

        return ShaderProgram{ .id = id };
    }

    pub fn loadFromBinaryFile(file_path: []const u8, allocator: *std.mem.Allocator) !ShaderProgram {
        if (c.GLAD_GL_ARB_get_program_binary == 0) {
            return error.NotSupported;
        }

        var data = try loadFile(file_path, allocator);
        const binary_format = std.mem.bytesAsSlice(u32, data[0..4])[0];

        return loadFromBinary(binary_format, data[4..]);
    }
};

test "shader" {
    try window.createWindow(false, 200, 200, "test", true, 0);
    defer window.closeWindow();

    var a = std.heap.page_allocator;

    const vsSrc = "uniform mat4 matrix; in vec4 coords; in vec4 colour; out vec4 pass_colour; void main() { gl_Position = matrix * coords; pass_colour = colour; }\n#ifdef TEST\nsyntax error\n#endif\n\x00";

    const fsSrc = "#version 140\n in vec4 pass_colour; out vec4 outColour; void main() { outColour = pass_colour; }\n\x00";

    var vs: ShaderObject = try ShaderObject.init(([_]([]const u8){ "#version 140\n#define TEST_\n\x00", vsSrc })[0..], ShaderType.Vertex, a);
    var fs: ShaderObject = try ShaderObject.init(([_]([]const u8){fsSrc})[0..], ShaderType.Fragment, a);

    var program: ShaderProgram = try ShaderProgram.init(&vs, &fs, &[_]([]const u8){ "coords\x00", "colour\x00" }, a);

    vs.free();
    fs.free();

    var binary_data: []u8 = undefined;
    var binary_format: u32 = 0;
    try program.getBinary(&binary_data, &binary_format, std.heap.page_allocator);
    defer std.heap.page_allocator.free(binary_data);

    program.free();

    program = try ShaderProgram.loadFromBinary(binary_format, binary_data);

    var uniformId = try program.getUniformLocation("matrix");
    expect(uniformId != -1);
}
