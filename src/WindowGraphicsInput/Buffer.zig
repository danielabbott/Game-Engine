const std = @import("std");
const assert = std.debug.assert;
const window = @import("Window.zig");
const c = @import("c.zig").c;
const expect = std.testing.expect;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

pub const Buffer = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    const buffer_type_gl = [_]c_uint {
        c.GL_ARRAY_BUFFER,
        c.GL_ELEMENT_ARRAY_BUFFER,
        c.GL_UNIFORM_BUFFER
    };

    pub const BufferType = enum(u32) {
        VertexData = 0,
        IndexData = 1,
        Uniform = 2,
    };

    id: u32,
    data_size: u32,

    pub fn init() !Buffer {
        var id: u32 = 0;
        c.glGenBuffers(1, @ptrCast([*c]c_uint, &id));

        if (id == 0) {
            return error.OpenGLError;
        }

        return Buffer{
            .id = id,
            .data_size = 0,
        };
    }

    // Buffer will be bound to target buffer_type
    pub fn upload(self: *Buffer, buffer_type: BufferType, data: []const u8, dynamic: bool) !void {
        if (data.len > 0xffffffff) {
            return error.ArrayTooLarge;
        }

        try self.bind(buffer_type);

        var usage: u32 = c.GL_STATIC_DRAW;
        if (dynamic) {
            usage = c.GL_DYNAMIC_DRAW;
        }

        c.glBufferData(buffer_type_gl[@enumToInt(buffer_type)], @intCast(u32, data.len), data.ptr, usage);
        self.data_size = @intCast(u32, data.len);
    }

    // Wipes the buffer contents and allocates data-size bytes of vram
    pub fn reserveMemory(self: *Buffer, buffer_type: BufferType, data_size: u32, dynamic: bool) !void {
        if (data_size == 0) {
            return error.InvalidParameter;
        }

        try self.bind(buffer_type);

        var usage: u32 = c.GL_STATIC_DRAW;
        if (dynamic) {
            usage = c.GL_DYNAMIC_DRAW;
        }

        c.glBufferData(buffer_type_gl[@enumToInt(buffer_type)], data_size, null, usage);
        self.data_size = data_size;
    }

    pub fn uploadRegion(self: *Buffer, buffer_type: BufferType, data: []const u8, offset: u32, dynamic: bool) !void {
        if (offset + data.len > self.data_size) {
            return error.ArrayTooLarge;
        }

        if (data.len == 0) {
            return error.InvalidParameter;
        }

        try self.bind(buffer_type);

        var usage: u32 = c.GL_STATIC_DRAW;
        if (dynamic) {
            usage = c.GL_DYNAMIC_DRAW;
        }

        c.glBufferSubData(buffer_type_gl[@enumToInt(buffer_type)], offset, @intCast(u32, data.len), data.ptr);
    }

    pub fn bind(self: Buffer, bindAs: BufferType) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindBuffer(buffer_type_gl[@enumToInt(bindAs)], self.id);
    }

    pub fn unbind(target: BufferType) void {
        c.glBindBuffer(buffer_type_gl[@enumToInt(bindAs)], 0);
    }

    pub fn bindUniform(self: *Buffer, bindingPoint: u32, offset: u32, length: u32) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindBufferRange(c.GL_UNIFORM_BUFFER, bindingPoint, self.id, offset, length);
    }

    pub fn free(self: *Buffer) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        self.ref_count.deinit();

        c.glDeleteBuffers(1, @ptrCast([*c]const c_uint, &self.id));
        self.id = 0;
    }

    // For uniform buffers
    pub fn bindBufferBase(self: *Buffer, index: u32) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindBufferBase(c.GL_UNIFORM_BUFFER, index, self.id);
    }
};

test "Buffer" {
    try window.createWindow(false, 200, 200, c"test", true, 0);
    defer window.closeWindow();

    const inData = [4]u8{ 1, 2, 3, 4 };
    var buf: Buffer = try Buffer.init();

    try buf.upload(Buffer.BufferType.VertexData, inData, false);

    // GL_ARRAY_BUFFER, GL_READ_ONLY
    var ptr: [*]const u8 = @ptrCast([*]const u8, c.glMapBuffer(0x8892, 0x88B8).?);
    expect(ptr[0] == 1 and ptr[1] == 2 and ptr[2] == 3 and ptr[3] == 4);

    buf.free();
}
