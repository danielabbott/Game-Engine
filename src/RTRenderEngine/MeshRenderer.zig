const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const ModelData = @import("../ModelFiles/ModelFiles.zig").ModelData;
const VertexAttributeType = ModelData.VertexAttributeType;
const Buffer = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").Buffer;
const VertexMeta = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").VertexMeta;
const ShaderInstance = @import("Shader.zig").ShaderInstance;
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const Texture2D = @import("Texture2D.zig").Texture2D;
const Animation = @import("Animation.zig").Animation;
const rtrenderengine = @import("RTRenderEngine.zig");
const getSettings = rtrenderengine.getSettings;
const min = std.math.min;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const Asset = @import("../Assets/Assets.zig").Asset;
const Mesh = @import("Mesh.zig").Mesh;


pub const MeshRenderer = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},

    mesh: ?*Mesh,
    vao: VertexMeta,

    max_vertex_lights: u32 = 8,
    max_fragment_lights: u32 = 4,

    // Allow for objects that have different scale values in different axis
    // E.g. An object can be stretched by 2 units in the X axis only
    // Skeletal animation does not work when this is enabled
    non_uniform_scale: bool = false,

    recieve_shadows: bool = true,

    enable_specular_light: bool = true,
    enable_point_lights: bool = true,
    enable_directional_lights: bool = true,
    enable_spot_lights: bool = true,

    // Used when too many lights are affecting an object.
    // Only works for smallish objects such as players.
    // Should be disabled for large objects such as terrain.
    enable_per_object_light: bool = true,

    pub const Material = struct {
        // DO NOT SET THESE VARIABLES USE fn setTexture AND fn setNormalMap
        texture: ?*Texture2D = null,
        normal_map: ?*Texture2D = null,

        pub fn setTexture(self: *Material, texture: ?*Texture2D) void {
            ReferenceCounter.set(Texture2D, &self.texture, texture);
        }

        pub fn setNormalMap(self: *Material, normal_map: ?*Texture2D) void {
            ReferenceCounter.set(Texture2D, &self.normal_map, normal_map);
        }

        pub fn freeTexturesIfUnused(self: *Material) void {
            if (self.texture != null) {
                self.texture.?.ref_count.dec();
                self.texture.?.freeIfUnused();
            }
            if (self.normal_map != null) {
                self.normal_map.?.ref_count.dec();
                self.normal_map.?.freeIfUnused();
            }
        }

        colour_override: ?[3]f32 = null,

        specular_size: f32 = 0.05, // 0 - 1
        specular_intensity: f32 = 1.0,
        specular_colourisation: f32 = 0.025, // 0 = white, 1 = colour of light source
    };

    // Use as few materials as possible to reduce draw calls
    // Materials here map directly to the materials in the mesh's model file
    materials: [32]Material = [1]Material{Material{}} ** 32,

    animation_object: ?*Animation = null,

    pub fn init(mesh: *Mesh, allocator: *std.mem.Allocator) !MeshRenderer {
        mesh.ref_count.inc();
        errdefer mesh.ref_count.dec();

        var inputs: []VertexMeta.VertexInput = try allocator.alloc(VertexMeta.VertexInput, mesh.model.attributes_count);
        defer allocator.free(inputs);

        const interleaved = mesh.model.interleaved;
        const stride = if (interleaved) mesh.model.vertex_size else 0;
        const vertCount = mesh.model.vertex_count;

        var attr: u3 = 0;
        var i: u32 = 0;
        var offset: u32 = 0;
        while (attr < 7) : (attr += 1) {
            if ((mesh.model.attributes_bitmap & (u8(1) << attr)) != 0) {
                inputs[i].offset = offset;
                inputs[i].stride = stride;
                inputs[i].source = &mesh.vertex_data_buffer;

                if (attr == @enumToInt(VertexAttributeType.Position)) {
                    // positions
                    inputs[i].componentCount = 3;
                    inputs[i].dataType = VertexMeta.VertexInput.DataType.Float;
                    inputs[i].dataElementSize = 4;
                    inputs[i].signed = true;
                    inputs[i].normalised = false;
                    offset += if (interleaved) (3 * 4) else (vertCount * 3 * 4);
                } else {
                    if (attr == @enumToInt(VertexAttributeType.Colour)) {
                        // colours
                        inputs[i].componentCount = 4;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.IntegerToFloat;
                        inputs[i].dataElementSize = 1;
                        inputs[i].signed = false;
                        inputs[i].normalised = true;
                    } else if (attr == @enumToInt(VertexAttributeType.TextureCoordinates)) {
                        // tex coords
                        inputs[i].componentCount = 2;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.IntegerToFloat;
                        inputs[i].dataElementSize = 2;
                        inputs[i].signed = false;
                        inputs[i].normalised = true;
                    } else if (attr == @enumToInt(VertexAttributeType.Normal)) {
                        // normals
                        inputs[i].componentCount = 0;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.CompactInts;
                        inputs[i].signed = true;
                        inputs[i].normalised = true;
                    } else if (attr == @enumToInt(VertexAttributeType.BoneIndices)) {
                        // bone indices
                        inputs[i].componentCount = 4;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.Integer;
                        inputs[i].dataElementSize = 1;
                        inputs[i].signed = false;
                    } else if (attr == @enumToInt(VertexAttributeType.BoneWeights)) {
                        // bone weights
                        inputs[i].componentCount = 4;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.IntegerToFloat;
                        inputs[i].dataElementSize = 1;
                        inputs[i].signed = false;
                        inputs[i].normalised = true;
                    } else if (attr == @enumToInt(VertexAttributeType.Tangent)) {
                        // tangents
                        inputs[i].componentCount = 0;
                        inputs[i].dataType = VertexMeta.VertexInput.DataType.CompactInts;
                        inputs[i].signed = true;
                        inputs[i].normalised = true;
                    }

                    offset += if (interleaved) 4 else (vertCount * 4);
                }
                i += 1;
            }
        }

        return MeshRenderer{
            .vao = try VertexMeta.init(inputs, if (mesh.index_data_buffer == null) null else &mesh.index_data_buffer.?),
            .mesh = mesh,
        };
    }

    pub const DrawData = struct {
        mvp_matrix: *const Matrix(f32, 4),
        model_matrix: *const Matrix(f32, 4),
        model_view_matrix: *const Matrix(f32, 4),
        light: [3]f32,
        vertex_light_indices: [8]i32,
        fragment_light_indices: [4]i32,
        fragment_light_matrices: [4]Matrix(f32, 4),
    };

    pub fn draw(self: *MeshRenderer, draw_data: DrawData, allocator: *std.mem.Allocator) !void {
        if (self.mesh == null) {
            return error.MeshRendererDestroyed;
        }

        var shader_config = ShaderInstance.ShaderConfig{
            .shadow = false,
            .inputs_bitmap = self.mesh.?.model.attributes_bitmap,
            .max_vertex_lights = min(self.max_vertex_lights, getSettings().max_vertex_lights),
            .max_fragment_lights = min(self.max_fragment_lights, getSettings().max_fragment_lights),
            .non_uniform_scale = self.non_uniform_scale,
            .recieve_shadows = self.recieve_shadows and getSettings().enable_shadows,
            .enable_specular_light = self.enable_specular_light and getSettings().enable_specular_light,
            .enable_point_lights = self.enable_point_lights and getSettings().enable_point_lights,
            .enable_directional_lights = self.enable_directional_lights and getSettings().enable_directional_lights,
            .enable_spot_lights = self.enable_spot_lights and getSettings().enable_spot_lights,
        };
        var shader: *const ShaderInstance = try ShaderInstance.getShader(shader_config, allocator);

        try shader.setMVPMatrix(draw_data.mvp_matrix);
        try shader.setModelMatrix(draw_data.model_matrix);
        try shader.setModelViewMatrix(draw_data.model_view_matrix);
        try shader.setPerObjLight(draw_data.light);
        try shader.setVertexLightIndices(draw_data.vertex_light_indices);
        try shader.setFragmentLightIndices(draw_data.fragment_light_indices);
        try shader.setLightMatrices(draw_data.fragment_light_matrices);

        if (self.mesh.?.model.attributes_bitmap & (1 << @enumToInt(ModelData.VertexAttributeType.BoneIndices)) != 0) {
            if (self.animation_object == null) {
                Animation.setAnimationIdentityMatrices(shader, allocator) catch {assert(false);};
            } else {
                try self.animation_object.?.setAnimationMatrices(shader, self.mesh.?.model);
            }
        }

        if (shader.config.non_uniform_scale) {
            const normal_mat = try draw_data.model_view_matrix.decreaseDimension().transpose().inverse();
            try shader.setNormalMatrix(&normal_mat);
        }

        var i: u32 = 0;
        while (i < self.mesh.?.model.material_count and i < 32) : (i += 1) {
            if (self.materials[i].texture == null) {
                try rtrenderengine.getDefaultTexture().bindToUnit(0);
            } else {
                try self.materials[i].texture.?.texture.bindToUnit(0);
            }
            if (self.materials[i].normal_map == null) {
                try rtrenderengine.getDefaultNormalMap().bindToUnit(1);
            } else {
                try self.materials[i].normal_map.?.texture.bindToUnit(1);
            }

            try shader.setSpecularIntensity(self.materials[i].specular_intensity);
            try shader.setSpecularSize(self.materials[i].specular_size);
            try shader.setSpecularColouration(self.materials[i].specular_colourisation);

            var first_index: u32 = undefined;
            var index_vertex_count: u32 = undefined;
            var utf8_name: []const u8 = undefined;
            var colour: [3]f32 = undefined;
            self.mesh.?.model.getMaterial(i, &first_index, &index_vertex_count, &colour, &utf8_name) catch break;

            if (self.materials[i].colour_override == null) {
                try shader.setColour(colour);
            } else {
                try shader.setColour(self.materials[i].colour_override.?);
            }

            if (index_vertex_count > 0) {
                shader.validate(allocator);

                if (self.mesh.?.index_data_buffer == null) {
                    try self.vao.draw(VertexMeta.PrimitiveType.Triangles, first_index, index_vertex_count);
                } else {
                    try self.vao.drawWithIndices(VertexMeta.PrimitiveType.Triangles, self.mesh.?.model.vertex_count > 65536, first_index, index_vertex_count);
                }
            }
        }
    }

    // For shadow maps
    pub fn drawDepthOnly(self: *MeshRenderer, allocator: *std.mem.Allocator, mvp_matrix: *const Matrix(f32, 4), model_matrix: *const Matrix(f32, 4)) !void {
        if (self.mesh == null) {
            return error.MeshRendererDestroyed;
        }

        var shader_config = ShaderInstance.ShaderConfig{
            .shadow = true,
            .inputs_bitmap = self.mesh.?.model.attributes_bitmap,

            // Not used for shadows
            .max_vertex_lights = 0,
            .max_fragment_lights = 0,
            .non_uniform_scale = self.non_uniform_scale,
            .recieve_shadows = false,
            .enable_specular_light = false,
            .enable_point_lights = false,
            .enable_directional_lights = false,
            .enable_spot_lights = false,
        };
        var shader: *const ShaderInstance = try ShaderInstance.getShader(shader_config, allocator);

        try shader.setMVPMatrix(mvp_matrix);
        try shader.setModelMatrix(model_matrix);
        // try shader.setModelViewMatrix(model_view_matrix);

        if (self.mesh.?.model.attributes_bitmap & (1 << @enumToInt(ModelData.VertexAttributeType.BoneIndices)) != 0) {
            if (self.animation_object == null) {
                Animation.setAnimationIdentityMatrices(shader, allocator) catch {assert(false);};
            } else {
                try self.animation_object.?.setAnimationMatrices(shader, self.mesh.?.model);
            }
        }

        var first_index: u32 = 0;
        var index_count: u32 = 0;
        var utf8_name: []const u8 = undefined;
        var colour: [3]f32 = undefined;
        var i: u32 = 0;
        while (i < self.mesh.?.model.material_count and i < 32) : (i += 1) {
            var first_index_: u32 = undefined;
            var index_count_: u32 = undefined;
            self.mesh.?.model.getMaterial(i, &first_index_, &index_count_, &colour, &utf8_name) catch break;

            var do_draw: bool = false;

            if(first_index_ == first_index + index_count) {
                index_count += index_count_;
                if(i < self.mesh.?.model.material_count-1 and i < 32-1) {
                    continue;
                }
                else {
                    do_draw = true;
                }
            }
            else {
                do_draw = true;
            }

            if(do_draw) {
                if (index_count > 0) {
                    if (self.mesh.?.index_data_buffer == null) {
                        try self.vao.draw(VertexMeta.PrimitiveType.Triangles, first_index, index_count);
                    } else {
                        try self.vao.drawWithIndices(VertexMeta.PrimitiveType.Triangles, self.mesh.?.model.vertex_count > 65536, first_index, index_count);
                    }
                }

                first_index = first_index_;
                index_count = index_count_;
            }
        }
    }

    pub fn setAnimationObject(self: *MeshRenderer, animation_object: *Animation) void {
        ReferenceCounter.set(Animation, &self.animation_object, animation_object);
    }

    pub fn free(self: *MeshRenderer) void {
        self.ref_count.deinit();
        if (self.mesh != null) {
            self.mesh.?.ref_count.dec();
            self.mesh = null;

            var i: u32 = 0;
            while (i < 32) : (i += 1) {
                self.materials[i].setTexture(null);
                self.materials[i].setNormalMap(null);
            }
        }
    }

    // Frees mesh and textures if they become unused
    pub fn freeIfUnused(self: *MeshRenderer) void {
        if (self.ref_count.n != 0 or self.mesh == null) {
            return;
        }

        self.mesh.?.ref_count.dec();
        self.mesh.?.freeIfUnused();
        self.mesh = null;

        var i: u32 = 0;
        while (i < 32) : (i += 1) {
            self.materials[i].freeTexturesIfUnused();
        }

        if (self.animation_object != null) {
            self.animation_object.?.ref_count.dec();
            self.animation_object.?.freeIfUnused();
        }
    }
};
