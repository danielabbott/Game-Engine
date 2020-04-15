const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const mem = std.mem;

pub const ModelData = struct {
    pub const VertexAttributeType = enum(u8) {
        Position = 0,
        Colour = 1,
        TextureCoordinates = 2,
        Normal = 3,
        BoneIndices = 4,
        BoneWeights = 5,
        Tangent = 6,
    };

    // If bigger than 65536 then indices are 32-bit
    vertex_count: u32 = 0,

    // If zero then use non-indexed rendering
    index_count: u32 = 0,

    // See model file format.odt for attribute descriptions
    // See VertexAttributeType for attribute bit positions
    attributes_bitmap: u8 = 0,
    attributes_count: u32 = 0,

    interleaved: bool = false,

    vertex_data: ?[]const u32 = null,

    // These are used if interleaved == false
    positions: ?[]const f32 = null, // 3 per vertex
    colours: ?[]const u32 = null, // each u32 is a rgba8 packed colour
    tex_coords: ?[]const u32 = null, // each u32 is a u,v pair
    normals: ?[]const u32 = null, // each u32 is a packed normal
    bone_indices: ?[]const u32 = null, // each u32 is 4xu8
    vertex_weights: ?[]const u32 = null, // each u32 is 4xu8 (normalised)
    tangents: ?[]const u32 = null, // same format as normals

    // These are used if interleaved == true
    vertex_size: u32 = 0, // in bytes

    // One or both of these will be null
    indices_u16: ?[]const u16 = null,
    indices_u32: ?[]const u32 = null,

    // See model file format.odt for the format of this data:

    material_count: u32 = 0,

    materials: ?[]u32 = null,

    bone_count: u32 = 0,

    bones: ?[]u8 = null,

    // This struct references (read-only) the data until delete is called (unless this function returns with an error)
    pub fn init(data: []align(4) const u8, allocator: *mem.Allocator) !ModelData {
        if (data.len < 7 * 4) {
            warn("ModelData.init: Data length is only {}\n", .{data.len});
            return error.FileTooSmall;
        }

        if (data.len % 4 != 0) {
            return error.InvalidFileSize;
        }

        var model_data: ModelData = ModelData{};

        const data_u32 = std.mem.bytesAsSlice(u32, data);
        const data_f32 = std.mem.bytesAsSlice(f32, data);

        if (data_u32[0] != 0xaaeecdbb) {
            warn("ModelData.init: Magic field incorrect. Value was {}\n", .{data_u32[0]});
            return error.NotAModelFile;
        }
        model_data.attributes_bitmap = @intCast(u8, data_u32[2] & 0x7f);

        // Number of bits set
        model_data.attributes_count = @popCount(u8, model_data.attributes_bitmap);

        if (model_data.attributes_bitmap == 0) {
            return error.NoVertexDataAttributes;
        }

        model_data.index_count = data_u32[1];

        model_data.interleaved = data_u32[3] != 0;

        model_data.vertex_count = data_u32[4];
        if (model_data.vertex_count == 0) {
            return error.NoVertices;
        }

        // offset into data_u32
        var offset: u32 = 5;

        if (model_data.interleaved) {
            if (model_data.attributes_bitmap & (1 << @enumToInt(VertexAttributeType.Position)) != 0) {
                model_data.vertex_size = 3 * 4;
            }
            model_data.vertex_size += @popCount(u8, model_data.attributes_bitmap >> 1) * 4;

            const vertex_data_size = model_data.vertex_count * model_data.vertex_size;

            model_data.vertex_data = data_u32[5..(5 + vertex_data_size)];

            if (5 + vertex_data_size > data_u32.len) {
                return error.FileTooSmall;
            }

            offset += vertex_data_size;
        } else {
            var attrib_i: u3 = 0;
            while (attrib_i < 7) : (attrib_i += 1) {
                const attrib_bit_set = (model_data.attributes_bitmap & (@as(u8, 1) << attrib_i)) != 0;
                if (attrib_bit_set) {
                    if (attrib_i == @enumToInt(VertexAttributeType.Position)) {
                        if (offset + model_data.vertex_count * 3 > data_u32.len) {
                            return error.FileTooSmall;
                        }
                    } else {
                        if (offset + model_data.vertex_count > data_u32.len) {
                            return error.FileTooSmall;
                        }
                    }

                    if (attrib_i == @enumToInt(VertexAttributeType.Position)) {
                        model_data.positions = data_f32[offset..(offset + model_data.vertex_count * 3)];
                    } else {
                        const a = data_u32[offset..(offset + model_data.vertex_count)];
                        if (attrib_i == @enumToInt(VertexAttributeType.Colour)) {
                            model_data.colours = a;
                        } else if (attrib_i == @enumToInt(VertexAttributeType.TextureCoordinates)) {
                            model_data.tex_coords = a;
                        } else if (attrib_i == @enumToInt(VertexAttributeType.Normal)) {
                            model_data.normals = a;
                        } else if (attrib_i == @enumToInt(VertexAttributeType.BoneIndices)) {
                            model_data.bone_indices = a;
                        } else if (attrib_i == @enumToInt(VertexAttributeType.BoneWeights)) {
                            model_data.vertex_weights = a;
                        } else if (attrib_i == @enumToInt(VertexAttributeType.Tangent)) {
                            model_data.tangents = a;
                        }
                    }

                    if (attrib_i == @enumToInt(VertexAttributeType.Position)) {
                        offset += model_data.vertex_count * 3;
                    } else {
                        offset += model_data.vertex_count;
                    }
                }
            }
            model_data.vertex_data = data_u32[5..offset];

            const has_bone_indices = (model_data.attributes_bitmap & (1 << @enumToInt(VertexAttributeType.BoneIndices))) != 0;
            const has_bone_weights = (model_data.attributes_bitmap & (1 << @enumToInt(VertexAttributeType.BoneWeights))) != 0;

            if (has_bone_indices != has_bone_weights and (has_bone_indices or has_bone_weights)) {
                return error.VertexWeightsRequireBoneIndices;
            }
        }

        // index data

        if (model_data.index_count == 0) {
            model_data.indices_u32 = null;
            model_data.indices_u16 = null;
        } else {
            if (model_data.vertex_count > 65536) {
                // large indices
                if (offset + model_data.index_count > data_u32.len) {
                    return error.FileTooSmall;
                }

                model_data.indices_u32 = data_u32[offset..(offset + model_data.index_count)];

                offset += model_data.index_count;
            } else {
                // small indices (if number of indices is odd then an extra u16 is added to the end of the data)
                if (offset + (model_data.index_count + 1) / 2 > data_u32.len) {
                    return error.FileTooSmall;
                }

                model_data.indices_u16 = std.mem.bytesAsSlice(u16, data)[(offset * 2)..(offset * 2 + model_data.index_count)];

                offset += (model_data.index_count + 1) / 2;
            }
        }

        // Materials

        if (offset + 1 > data_u32.len) {
            return error.FileTooSmall;
        }

        model_data.material_count = data_u32[offset];
        offset += 1;

        if (model_data.material_count > 32) {
            warn("ModelData.init: Material count field invalid. Value was {}\n", .{model_data.material_count});
            return error.TooManyMaterials;
        }

        if (offset + model_data.material_count * 3 > data_u32.len) {
            return error.FileTooSmall;
        }

        const offsetAtMaterialsListStart = offset;

        var i: u32 = 0;
        while (i < model_data.material_count) {
            if (offset + 3 > data_u32.len) {
                return error.FileTooSmall;
            }

            const first = data_u32[offset];
            const n = data_u32[offset + 1];
            offset += 2;

            if (model_data.index_count == 0) {
                if (first + n > model_data.vertex_count) {
                    return error.InvalidModelMaterial;
                }
            } else {
                if (first + n > model_data.index_count) {
                    return error.InvalidModelMaterial;
                }
            }

            // Diffuse colour
            offset += 3;

            const stringLen = data_u32[offset] & 0xff;

            if (offset + (1 + stringLen + 3) / 4 > data_u32.len) {
                return error.FileTooSmall;
            }

            offset += (1 + stringLen + 3) / 4;

            i += 1;
        }
        model_data.materials = try allocator.alloc(u32, offset - offsetAtMaterialsListStart);
        errdefer allocator.free(model_data.materials.?);
        mem.copy(u32, model_data.materials.?, data_u32[offsetAtMaterialsListStart..offset]);

        // Bones

        if (offset + 1 > data_u32.len) {
            return error.FileTooSmall;
        }

        model_data.bone_count = data_u32[offset];
        offset += 1;

        if (model_data.bone_count != 0) {
            if (offset + model_data.bone_count * 8 > data_u32.len) {
                return error.FileTooSmall;
            }

            const offsetAtBonesListStart = offset;

            i = 0;
            while (i < model_data.bone_count) {
                if (offset + 8 > data_u32.len) {
                    return error.FileTooSmall;
                }

                const parent = data_u32[offset + 6];

                if (parent >= model_data.bone_count and @bitCast(i32, parent) >= 0) {
                    return error.InvalidBoneParentIndex;
                }

                offset += 7;

                const stringLen = data_u32[offset] & 0xff;

                if (offset + (1 + stringLen + 3) / 4 > data_u32.len) {
                    return error.FileTooSmall;
                }

                offset += (1 + stringLen + 3) / 4;

                i += 1;
            }
            model_data.bones = try allocator.alloc(u8, (offset - offsetAtBonesListStart) * 4);
            errdefer allocator.free(model_data.bones.?);
            mem.copy(u8, model_data.bones.?, std.mem.sliceAsBytes(data_u32[offsetAtBonesListStart..offset]));
        }

        return model_data;
    }

    // utf8 string is u8 length (bytes) followed by string data
    pub fn getMaterial(self: *ModelData, i: u32, first_index: *u32, index_vertex_count: *u32, default_colour: *([3]f32), utf8_name: *([]const u8)) !void {
        if (i >= self.material_count) {
            return error.NoSuchMaterial;
        }

        var j: u32 = 0;
        var offset: u32 = 0;
        while (j < self.material_count and j <= i) {
            const stringLen = @intCast(u8, self.materials.?[offset + 5] & 0xff);

            default_colour.*[0] = @bitCast(f32, self.materials.?[offset + 2]);
            default_colour.*[1] = @bitCast(f32, self.materials.?[offset + 3]);
            default_colour.*[2] = @bitCast(f32, self.materials.?[offset + 4]);

            if (j == i) {
                first_index.* = self.materials.?[offset];
                index_vertex_count.* = self.materials.?[offset + 1];
                offset += 2;
                utf8_name.* = std.mem.sliceAsBytes(self.materials.?)[(offset * 4 + 1)..(offset * 4 + 1 + stringLen)];
                return;
            }

            offset += 5 + (1 + stringLen + 3) / 4;

            j += 1;
        }

        unreachable;
    }

    // Sets bone_data_offset to offset of next bone in array
    // Stop iterating when bone_data_offset >= bones.len
    pub fn getBoneName(self: ModelData, bone_data_offset: *u32) ![]const u8 {
        if (self.bone_count == 0 or bone_data_offset.* + 7 * 4 > self.bones.?.len) {
            std.testing.expect(false);
            return error.IndexOutOfBounds;
        }

        bone_data_offset.* += 7 * 4;
        const len = self.bones.?[bone_data_offset.*];

        bone_data_offset.* += 1;
        const offset = bone_data_offset.*;
        bone_data_offset.* += len;

        if (bone_data_offset.* % 4 != 0) {
            bone_data_offset.* += 4 - (bone_data_offset.* % 4);
        }

        return self.bones.?[offset .. offset + len];
    }

    // Does not delete the data that was passed to init()
    pub fn free(self: *ModelData, allocator: *mem.Allocator) void {
        if (self.materials != null) {
            allocator.free(self.materials.?);
        }
        if (self.bones != null) {
            allocator.free(self.bones.?);
        }
        self.vertex_data = null;
        self.indices_u16 = null;
        self.indices_u32 = null;
    }
};

test "Model import test (non-interleaved)" {
    const testData = [_]u32{
        0xaaeecdbb,
        1,

        63,

        0,
        1,

        0,
        0,
        0,
        0xffffffff,
        0x80008000,
        0,
        1 << 24,
        255 << 24,

        0,

        1,

        0,
        1,
        33,
        33,
        33,
        0x0043402,

        1,
        2,
        3,
        4,
        0,
        0,
        0,
        0xffffffff,
        0x00000601,

        0,
        0,
        0,
        0,
        0,
    };

    var buf: [1024]u8 = undefined;
    const a = &std.heap.FixedBufferAllocator.init(&buf).allocator;

    var m: ModelData = try ModelData.init(std.mem.sliceAsBytes(testData[0..]), a);
    defer m.free(a);

    std.testing.expect(m.vertex_count == 1);
    std.testing.expect(m.index_count == 1);
    std.testing.expect(m.positions.?.len == 3);
    std.testing.expect(m.colours.?.len == 1);
    std.testing.expect(m.tex_coords.?.len == 1);
    std.testing.expect(m.normals.?.len == 1);
    std.testing.expect(m.bone_indices.?.len == 1);
    std.testing.expect(m.vertex_weights.?.len == 1);
    std.testing.expect(m.indices_u16.?.len == 1);
    std.testing.expect(m.indices_u32 == null);
    std.testing.expect(m.interleaved == false);
    std.testing.expect(m.vertex_data.?.len == 8);
    std.testing.expect(m.material_count == 1);
    std.testing.expect(m.bone_count == 1);

    var first_index: u32 = undefined;
    var index_count: u32 = undefined;
    var utf8_name: []const u8 = undefined;
    var colour: [3]f32 = undefined;
    try m.getMaterial(0, &first_index, &index_count, &colour, &utf8_name);

    var bone_data_offset: u32 = 0;
    const bone_name = try m.getBoneName(&bone_data_offset);
    std.testing.expect(bone_name.len == 1 and bone_name[0] == 6);
}
