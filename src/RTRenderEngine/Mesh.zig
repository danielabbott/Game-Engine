const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const ModelData = @import("../ModelFiles/ModelFiles.zig").ModelData;
const VertexAttributeType = ModelData.VertexAttributeType;
const AnimationData = @import("../ModelFiles/AnimationFiles.zig").AnimationData;
const Buffer = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").Buffer;
const VertexMeta = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").VertexMeta;
const ShaderInstance = @import("Shader.zig").ShaderInstance;
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const Texture2D = wgi.Texture2D;
const rtrenderengine = @import("RTRenderEngine.zig");
const getSettings = rtrenderengine.getSettings;
const min = std.math.min;

var matrix_buffer: ?[]f32 = null;
extern var this_frame_time: u64;

pub fn allocateStaticData(allocator: *std.mem.Allocator) !void {
    matrix_buffer = try allocator.alloc(f32, 128*4*4);
}

pub const Mesh = struct {
    vertex_data_buffer: Buffer,
    index_data_buffer: ?Buffer,
    modifiable: bool,
    model: *ModelData,

    // model object must remain valid for as long as this mesh object is valid
    // model.data can be freed however. That data will not be used again.
    pub fn init(model: *ModelData, modifiable: bool, allocator: *std.mem.Allocator) !Mesh {
        VertexMeta.unbind();

        var vbuf: Buffer = try Buffer.init();
        errdefer vbuf.free();
        try vbuf.upload(Buffer.BufferType.VertexData, @sliceToBytes(model.vertex_data.?), modifiable);

        var ibuf: ?Buffer = null;
        if (model.*.index_count > 0) {
            ibuf = try Buffer.init();
            errdefer ibuf.?.free();
            if (model.indices_u16 != null) {
                try ibuf.?.upload(Buffer.BufferType.IndexData, @sliceToBytes(model.indices_u16.?), modifiable);
            } else {
                try ibuf.?.upload(Buffer.BufferType.IndexData, @sliceToBytes(model.indices_u32.?), modifiable);
            }
        }

        return Mesh{
            .vertex_data_buffer = vbuf,
            .index_data_buffer = ibuf,
            .modifiable = modifiable,
            .model = model,
        };
    }

    pub fn uploadVertexData(self: *Mesh, offset: u32, data: []const u8) !void {
        if(!self.modifiable) {
            return error.ReadOnlyMesh;
        }

        try self.vertex_data_buffer.uploadRegion(Buffer.BufferType.VertexData, data, offset, true);
    }

    pub fn uploadIndexData(self: *Mesh, offset: u32, data: []const u8) !void {
        if(!self.modifiable) {
            return error.ReadOnlyMesh;
        }
        if(self.index_data_buffer == null) {
            return error.NoIndices;
        }

        try self.index_data_buffer.?.uploadRegion(Buffer.BufferType.IndexData, data, offset, true);
    }

    // Does not delete the model
    pub fn free(self: *Mesh) void {
        self.vertex_data_buffer.free();
        if (self.index_data_buffer != null) {
            self.index_data_buffer.?.free();
        }
    }
};


pub const MeshRenderer = struct {
    mesh: *Mesh,
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
        texture: ?*Texture2D = null,
        normal_map: ?*Texture2D = null,

        colour_override: ?[3]f32 = null,

        specular_size: f32 = 0.05,// 0 - 1
        specular_intensity: f32 = 1.0,
        specular_colourisation: f32 = 0.025, // 0 = white, 1 = colour of light source
    };

    // Use as few materials as possible to reduce draw calls
    // Materials here map directly to the materials in the mesh's model file
    materials: [32]Material = [1]Material{Material{}} ** 32,


    // internal variables

    active_animation: ?*AnimationData = null,
    animation_start_time: u64 = 0,

    pub fn init(mesh: *Mesh, allocator: *std.mem.Allocator) !MeshRenderer {
        var inputs: []VertexMeta.VertexInput = try allocator.alloc(VertexMeta.VertexInput, mesh.model.attributes_count);
        defer allocator.free(inputs);

        const interleaved = mesh.model.interleaved;
        const stride = if (interleaved) mesh.model.vertex_size else 0;
        const vertCount = mesh.model.vertex_count;

        var attr: u3 = 0;
        var i: u32 = 0;
        var offset: u32 = 0;
        while (attr < 7) : (attr += 1) {
            if((mesh.model.attributes_bitmap & (u8(1) << attr)) != 0) {
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

        return MeshRenderer {
            .vao = try VertexMeta.init(inputs, if (mesh.index_data_buffer == null) null else &mesh.index_data_buffer.?),
            .mesh = mesh,
        };
    }

    fn setAnimationMatrices(self: *MeshRenderer, shader: *const ShaderInstance) void {
        if(self.active_animation != null) {
            const time_difference = this_frame_time - self.animation_start_time;
            var frame_index = @intCast(u32, time_difference / (self.active_animation.?.frame_duration));
            if(time_difference % self.active_animation.?.frame_duration >= time_difference/2) {
                frame_index += 1;
            }

            frame_index = frame_index % self.active_animation.?.*.frame_count;

            var bone_i: u32 = 0;
            var bone_o: u32 = 0;
            while(bone_i < self.mesh.model.bone_count) : (bone_i += 1) {
                const name = self.mesh.model.getBoneName(&bone_o) catch break;
                const animation_bone_index = self.active_animation.?.*.getBoneIndex(name) catch continue;
                
                // TODO optimise to avoid copy
                // ^ have animation files store data for all bones even if not animated so data for each frame can be uploaded directly 
                const animation_bone_matrix_offset = (frame_index * self.active_animation.?.*.bone_count + animation_bone_index)*4*4;
                std.mem.copy(f32, matrix_buffer.?[bone_i*4*4 .. (bone_i+1)*4*4], 
                self.active_animation.?.*.matrices_absolute[animation_bone_matrix_offset..animation_bone_matrix_offset+4*4]);

            }
        }
        else {
            // No animation, fill with identity matrices

            // TODO create array of identity matrices in RTRenderEngine.init() and use that to avoid copy
            var bone_i : u32 = 0;
            while(bone_i < 128) : (bone_i += 1) {
                std.mem.copy(f32, matrix_buffer.?[bone_i*4*4 .. bone_i*4*4+4*4], [16] f32{
                    1.0,0.0,0.0,0.0,
                    0.0,1.0,0.0,0.0,
                    0.0,0.0,1.0,0.0,
                    0.0,0.0,0.0,1.0});
            }
        }
    }

    pub const DrawData = struct {
        mvp_matrix: *const Matrix(f32, 4), 
        model_matrix: *const Matrix(f32, 4),
        model_view_matrix: *const Matrix(f32, 4), 
        light: [3]f32,
        vertex_light_indices: [8]i32,
        fragment_light_indices: [4]i32,
        brightness: f32, 
        contrast: f32,
        fragment_light_matrices: [4]Matrix(f32, 4),
        near_planes: [4]f32,
        far_planes: [4]f32
    };

    pub fn draw(self: *MeshRenderer, draw_data: DrawData, allocator: *std.mem.Allocator) !void {
        var shader_config = ShaderInstance.ShaderConfig {
            .shadow = false,
            .inputs_bitmap = self.mesh.model.attributes_bitmap,
            .max_vertex_lights =  min(self.max_vertex_lights, getSettings().max_vertex_lights),
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
        try shader.setBrightness(draw_data.brightness);
        try shader.setContrast(draw_data.contrast);
        try shader.setLightMatrices(draw_data.fragment_light_matrices);
        try shader.setNearPlanes(draw_data.near_planes);
        try shader.setFarPlanes(draw_data.far_planes);

        if(self.mesh.model.attributes_bitmap & (1 << @enumToInt(ModelData.VertexAttributeType.BoneIndices)) != 0) {
            self.setAnimationMatrices(shader);
            try shader.setBoneMatrices(matrix_buffer.?);
        }

        if(shader.config.non_uniform_scale) {
            const normal_mat = try draw_data.model_view_matrix.decreaseDimension().transpose().inverse();
            try shader.setNormalMatrix(&normal_mat);
        }

        var i: u32 = 0;
        while (i < self.mesh.model.material_count and i < 32) : (i += 1) {
            if (self.materials[i].texture == null) {
                try rtrenderengine.getDefaultTexture().bindToUnit(0);
            } else {
                try self.materials[i].texture.?.bindToUnit(0);
            }
            if (self.materials[i].normal_map == null) {
                try rtrenderengine.getDefaultNormalMap().bindToUnit(1);
            }
            else {
                try self.materials[i].normal_map.?.bindToUnit(1);
            }

            try shader.setSpecularIntensity(self.materials[i].specular_intensity);
            try shader.setSpecularSize(self.materials[i].specular_size);
            try shader.setSpecularColouration(self.materials[i].specular_colourisation);

            var first_index: u32 = undefined;
            var index_vertex_count: u32 = undefined;
            var utf8_name: []const u8 = undefined;
            var colour: [3]f32 = undefined;
            self.mesh.model.getMaterial(i, &first_index, &index_vertex_count, &colour, &utf8_name) catch break;

            if(self.materials[i].colour_override == null) {
                try shader.setColour(colour);
            }
            else {
                try shader.setColour(self.materials[i].colour_override.?);
            }

            if(index_vertex_count > 0) {
                shader.validate(allocator);

                if (self.mesh.index_data_buffer == null) {
                    try self.vao.draw(VertexMeta.PrimitiveType.Triangles, first_index, index_vertex_count);
                } else {
                    try self.vao.drawWithIndices(VertexMeta.PrimitiveType.Triangles, self.mesh.model.vertex_count > 65536, first_index, index_vertex_count);
                }
            }
        }
    }

    // For shadow maps
    pub fn drawDepthOnly(self: *MeshRenderer, allocator: *std.mem.Allocator, mvp_matrix: *const Matrix(f32, 4), 
            model_matrix: *const Matrix(f32, 4)) !void {

        var shader_config = ShaderInstance.ShaderConfig {
            .shadow = true,
            .inputs_bitmap = self.mesh.model.attributes_bitmap,

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

        if(self.mesh.model.attributes_bitmap & (1 << @enumToInt(ModelData.VertexAttributeType.BoneIndices)) != 0) {
            self.setAnimationMatrices(shader);
            try shader.setBoneMatrices(matrix_buffer.?);
        }

        // TODO: Merge into one draw call where possible
        var i: u32 = 0;
        while (i < self.mesh.model.material_count and i < 32) : (i += 1) {
            var first_index: u32 = undefined;
            var index_count: u32 = undefined;
            var utf8_name: []const u8 = undefined;
            var colour: [3]f32 = undefined;
            self.mesh.model.getMaterial(i, &first_index, &index_count, &colour, &utf8_name) catch break;

            if(index_count > 0) {
                if (self.mesh.index_data_buffer == null) {
                    try self.vao.draw(VertexMeta.PrimitiveType.Triangles, first_index, index_count);
                } else {
                    try self.vao.drawWithIndices(VertexMeta.PrimitiveType.Triangles, self.mesh.model.vertex_count > 65536, first_index, index_count);
                }
            }
        }
    }

    pub fn playAnimation(self: *MeshRenderer, animation: *AnimationData) void {
        self.animation_start_time = this_frame_time;
        self.active_animation = animation;
    }
};
