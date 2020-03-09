const std = @import("std");
const assert = std.debug.assert;
const buf = @import("Buffer.zig");
const window = @import("Window.zig");
const c = @import("c.zig").c;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;

var null_vao: ?VertexMeta = null;

pub const VertexMeta = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    pub const VertexInput = struct {
        // Input is ignored if componentCount == 0
        pub const DataType = enum {
            Float,
            IntegerToFloat,
            Integer,
            CompactInts, // GL_INT_2_10_10_10_REV or GL_UNSIGNED_INT_2_10_10_10_REV
        };

        offset: u32, // offset into vertex buffer of first element
        componentCount: u4, // 1, 2, 3, or 4
        stride: u32, // byte offset between elements
        dataType: DataType,
        dataElementSize: u3, // how many bytes for each component in each element in the array
        signed: bool, // for IntegerToFloat and Integer

        normalised: bool, // for IntegerToFloat and Normals, if true maps values to range 0.0 - 1.0
        source: *buf.Buffer,
    };

    const primitive_type_gl = [_]c_uint{
        c.GL_POINTS,
        c.GL_LINE_STRIP,
        c.GL_LINE_LOOP,
        c.GL_LINES,
        //c.GL_LINE_STRIP_ADJACENCY,
        //c.GL_LINES_ADJACENCY,
        c.GL_TRIANGLE_STRIP,
        c.GL_TRIANGLE_FAN,
        c.GL_TRIANGLES,
        //c.GL_TRIANGLE_STRIP_ADJACENCY,
        //c.GL_TRIANGLES_ADJACENCY
    };

    pub const PrimitiveType = enum(u32) {
        Points,
        LineStrips,
        LineLoops,
        Lines,
        //LineStripAdjacency,
        //LinesAdjacency,
        TriangleStrips,
        TriangleFans,
        Triangles,
        //TriangleStripAdjacency,
        //TrianglesAdjacency
    };

    id: u32,

    fn getGLDataType(dataElementSize: u32, signed: bool) !u32 {
        if (dataElementSize == 1) {
            if (signed) {
                return c.GL_BYTE;
            } else {
                return c.GL_UNSIGNED_BYTE;
            }
        } else if (dataElementSize == 2) {
            if (signed) {
                return c.GL_SHORT;
            } else {
                return c.GL_UNSIGNED_SHORT;
            }
        } else if (dataElementSize == 4) {
            if (signed) {
                return c.GL_INT;
            } else {
                return c.GL_UNSIGNED_INT;
            }
        }
        return error.InvalidParameter;
    }

    pub fn init(inputs: []const VertexInput, indices_source: ?*buf.Buffer) !VertexMeta {
        assert(inputs.len <= window.maximumNumVertexAttributes());
        if (inputs.len > window.maximumNumVertexAttributes()) {
            return error.InvalidParameter;
        }

        var id: u32 = 0;
        c.glGenVertexArrays(1, @ptrCast([*c]c_uint, &id));
        errdefer c.glDeleteVertexArrays(1, @ptrCast([*c]c_uint, &id));

        if (id == 0) {
            assert(false);
            return error.OpenGLError;
        }

        c.glBindVertexArray(id);

        if (indices_source != null) {
            try indices_source.?.bind(buf.Buffer.BufferType.IndexData);
        }

        // Set buffer offsets and strides for vertex inputs

        var i: u32 = 0;
        for (inputs) |inp| {
            if (inp.dataType != VertexInput.DataType.CompactInts and (inp.componentCount == 0 or inp.componentCount > 4)) {
                assert(false);
                return error.InvalidParameter;
            }

            try inp.source.bind(buf.Buffer.BufferType.VertexData);

            if (inp.dataType == VertexInput.DataType.Float) {
                if (inp.dataElementSize != 4 and inp.dataElementSize != 2) {
                    assert(false);
                    return error.InvalidParameter;
                }

                var dataType: u32 = 0;
                if (inp.dataElementSize == 4) {
                    dataType = c.GL_FLOAT;
                } else if (inp.dataElementSize == 2) {
                    dataType = c.GL_HALF_FLOAT;
                }
                assert(dataType != 0);

                c.glVertexAttribPointer(i, inp.componentCount, dataType, 0, @intCast(c_int, inp.stride), @intToPtr(?*const c_void, inp.offset));
            } else if (inp.dataType == VertexInput.DataType.CompactInts) {
                var dataType: u32 = 0;
                if (inp.signed) {
                    dataType = c.GL_INT_2_10_10_10_REV;
                } else {
                    dataType = c.GL_UNSIGNED_INT_2_10_10_10_REV;
                }
                c.glVertexAttribPointer(i, 4, dataType, @boolToInt(inp.normalised), @intCast(c_int, inp.stride), @intToPtr(?*const c_void, inp.offset));
            } else {
                if (inp.componentCount * inp.dataElementSize % 4 != 0) {
                    assert(false);
                    return error.InvalidParameter;
                }

                if (inp.dataType == VertexInput.DataType.IntegerToFloat) {
                    var dataType: u32 = try getGLDataType(inp.dataElementSize, inp.signed);
                    assert(dataType != 0);

                    c.glVertexAttribPointer(i, inp.componentCount, dataType, @boolToInt(inp.normalised), @intCast(c_int, inp.stride), @intToPtr(?*const c_void, inp.offset));
                } else if (inp.dataType == VertexInput.DataType.Integer) {
                    var dataType: u32 = try getGLDataType(inp.dataElementSize, inp.signed);
                    assert(dataType != 0);

                    c.glVertexAttribIPointer(i, inp.componentCount, dataType, @intCast(c_int, inp.stride), @intToPtr(?*const c_void, inp.offset));
                }
            }

            c.glEnableVertexAttribArray(i);

            i += 1;
        }

        return VertexMeta{ .id = id };
    }

    pub fn bind(self: VertexMeta) !void {
        if (self.id == 0) {
            assert(false);
            return error.InvalidState;
        }

        c.glBindVertexArray(self.id);
    }

    pub fn draw(self: *VertexMeta, mode: PrimitiveType, first: u32, count: u32) !void {
        if (count == 0) {
            assert(false);
            return error.InvalidParameter;
        }
        try self.bind();
        c.glDrawArrays(primitive_type_gl[@enumToInt(mode)], @intCast(c_int, first), @intCast(c_int, count));
    }

    pub fn drawWithoutData(mode: PrimitiveType, first: u32, count: u32) !void {
        if (count == 0) {
            assert(false);
            return error.InvalidParameter;
        }

        if (null_vao == null) {
            null_vao = try VertexMeta.init([_]VertexInput{}, null);
        }
        try null_vao.?.bind();

        c.glDrawArrays(primitive_type_gl[@enumToInt(mode)], @intCast(c_int, first), @intCast(c_int, count));
    }

    pub fn drawWithIndices(self: *VertexMeta, mode: PrimitiveType, large_indices: bool, first: u32, count: u32) !void {
        if (count == 0) {
            assert(false);
            return error.InvalidParameter;
        }
        try self.bind();

        if (large_indices) {
            c.glDrawElements(primitive_type_gl[@enumToInt(mode)], @intCast(c_int, count), c.GL_UNSIGNED_INT, @intToPtr(?*const c_void, first * 4));
        } else {
            c.glDrawElements(primitive_type_gl[@enumToInt(mode)], @intCast(c_int, count), c.GL_UNSIGNED_SHORT, @intToPtr(?*const c_void, first * 2));
        }
    }

    pub fn free(self: *VertexMeta) void {
        if (self.id == 0) {
            assert(false);
            return;
        }
        self.ref_count.deinit();
        c.glDeleteVertexArrays(1, @ptrCast([*c]const c_uint, &self.id));
        self.id = 0;
    }

    pub fn unbind() void {
        c.glBindVertexArray(0);
    }
};

test "vao" {
    try window.createWindow(false, 200, 200, c"test", true, 0);
    defer window.closeWindow();

    const inData = [4]f32{ 1, 2, 3, 4 };
    var buffer: buf.Buffer = try buf.Buffer.init();

    try buffer.upload(buf.Buffer.BufferType.VertexData, @sliceToBytes(inData[0..]), false);

    const inputs = [_]VertexMeta.VertexInput{VertexMeta.VertexInput{
        .offset = 0,
        .componentCount = 4,
        .stride = 0,
        .dataType = VertexMeta.VertexInput.DataType.Float,
        .dataElementSize = 4,
        .signed = false,
        .normalised = false,
        .source = &buffer,
    }};

    var vao: VertexMeta = try VertexMeta.init(inputs[0..], null);

    vao.free();
    buffer.free();
}
