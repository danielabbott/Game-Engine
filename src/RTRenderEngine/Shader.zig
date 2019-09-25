const std = @import("std");
const assert = std.debug.assert;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const ShaderProgram = wgi.ShaderProgram;
const ShaderObject = wgi.ShaderObject;
const ShaderType = wgi.ShaderType;
const ArrayList = @import("std").ArrayList;
const renderEngine = @import("RTRenderEngine.zig");
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const files = @import("../Files.zig");
const loadFileWithNullTerminator = files.loadFileWithNullTerminator;
const min = std.math.min;
const getSettings = @import("RTRenderEngine.zig").getSettings;
const builtin = @import("builtin");
const VertexAttributeType = @import("../ModelFiles/ModelFiles.zig").ModelData.VertexAttributeType;

var standard_shader_vs_src: ?[]u8 = null;
var standard_shader_fs_src: ?[]u8 = null;
var standard_shader_common_src: ?[]u8 = null;

// Appends src onto dst at the given offset into dst
fn addString(src: []const u8, dst: []u8, offset: *u32) void {
    for (src[0..]) |b, i| dst[offset.* + i] = b;
    offset.* += @intCast(u32, src.len);
}

pub const ShaderInstance = struct {
    pub const ShaderConfig = struct {
        shadow: bool, // if true then this shader is for generating shadow maps
        inputs_bitmap: u8,

        // Only used if shadow = false
        
        max_vertex_lights: u32,
        max_fragment_lights: u32,
        non_uniform_scale: bool,
        recieve_shadows: bool,
        enable_specular_light: bool,

        enable_point_lights: bool,
        enable_directional_lights: bool,
        enable_spot_lights: bool,    
    };

    config: ShaderConfig,

    shader_name: []const u8,

    shader_program: ShaderProgram,

    mvp_matrix_location: ?i32 = null,
    model_matrix_location: ?i32 = null,
    model_view_matrix_location: ?i32 = null,
    normal_matrix_location: ?i32 = null,
    colour_location: ?i32 = null,
    per_obj_light_location: ?i32 = null,
    vertex_light_indices_location: ?i32 = null,
    fragment_light_indices_location: ?i32 = null,
    near_planes_location: ?i32 = null,
    far_planes_location: ?i32 = null,
    brightness_location: ?i32 = null,
    contrast_location: ?i32 = null,
    light_matrices_location: ?i32 = null,
    bone_matrices_location: ?i32 = null,
    specular_size_location: ?i32 = null,
    specular_intensity_location: ?i32 = null,
    specular_colouration_location: ?i32 = null,

    pub fn getShader(config_: ShaderInstance.ShaderConfig, allocator: *std.mem.Allocator) !*const ShaderInstance {
        var config = config_;

        config.max_fragment_lights = min(config.max_fragment_lights, 4);
        if(!config.shadow and !config.enable_point_lights and !config.enable_directional_lights and !config.enable_spot_lights and (config.max_fragment_lights != 0 or config.max_vertex_lights != 0)) {
            // assert(false);
            config.max_fragment_lights = 0;
            config.max_vertex_lights = 0;
        }
        config.max_vertex_lights = min(config.max_vertex_lights, 8);

        // Find loaded shader
        if(config.shadow) {
            for (shader_instances.?.toSliceConst()) |*a| {
                if (a.*.config.shadow and a.*.config.inputs_bitmap == config.inputs_bitmap) {
                    return a;
                }
            }
        }
        else {
            for (shader_instances.?.toSliceConst()) |*a| {
                if (!a.*.config.shadow and a.*.config.inputs_bitmap == config.inputs_bitmap and a.*.config.max_vertex_lights == config.max_vertex_lights
                    and a.*.config.max_fragment_lights == config.max_fragment_lights
                    and a.*.config.non_uniform_scale == config.non_uniform_scale and a.*.config.recieve_shadows == config.recieve_shadows
                    and a.*.config.enable_point_lights == config.enable_point_lights and a.*.config.enable_spot_lights == config.enable_spot_lights
                    and a.*.config.enable_directional_lights == config.enable_directional_lights
                    and a.*.config.enable_specular_light == config.enable_specular_light) {
                    return a;
                }
            }
        }

        // Find cached shader or create new
        
        var si: *ShaderInstance = try shader_instances.?.addOne();
        errdefer _ = shader_instances.?.pop();

        if(builtin.mode == builtin.Mode.Debug) {
            si.* = try ShaderInstance.init(false, config, allocator);
        }
        else {
            si.* = ShaderInstance.loadFromBinaryFile(
                "std", config, allocator) catch 
                    // Create the shader
                    try ShaderInstance.init(true, config, allocator);
        }


        return si;
    }

    fn init(cache: bool, config: ShaderConfig, allocator: *std.mem.Allocator) !ShaderInstance {
        const glsl_version_string = "#version 330\n";
        const vertex_positions_string = "#define HAS_VERTEX_COORDINATES\n";
        const vertex_colours_string = "#define HAS_VERTEX_COLOURS\n";
        const tex_coords_string = "#define HAS_TEXTURE_COORDINATES\n";
        const normals_string = "#define HAS_NORMALS\n";
        const vertex_weights_string = "#define HAS_VERTEX_WEIGHTS\n";
        const normal_map_string = "#define NORMAL_MAP\n";
        const max_vertex_lights_string = "#define MAX_VERTEX_LIGHTS x\n";
        const max_fragment_lights_string = "#define MAX_FRAGMENT_LIGHTS x\n";
        const non_uniform_scale_string = "#define ENABLE_NON_UNIFORM_SCALE\n";
        const enable_shadows_string = "#define ENABLE_SHADOWS\n";
        const enable_point_lights_string = "#define ENABLE_POINT_LIGHTS\n";
        const enable_directional_lights_string = "#define ENABLE_DIRECTIONAL_LIGHTS\n";
        const enable_spot_lights_string = "#define ENABLE_SPOT_LIGHTS\n";
        const enable_specular_string = "#define ENABLE_SPECULAR\n";

        var string: []u8 = try allocator.alloc(u8, 1024);
        defer allocator.free(string);
        var string_offset: u32 = 0;

        addString(glsl_version_string, string, &string_offset);

        if(config.enable_point_lights and getSettings().enable_point_lights) {
            addString(enable_point_lights_string, string, &string_offset);
        }
        if(config.enable_directional_lights and getSettings().enable_directional_lights) {
            addString(enable_directional_lights_string, string, &string_offset);
        }
        if(config.enable_spot_lights and getSettings().enable_spot_lights) {
            addString(enable_spot_lights_string, string, &string_offset);
        }

        if(config.enable_specular_light) {
            addString(enable_specular_string, string, &string_offset);
        }

        addString(max_vertex_lights_string, string, &string_offset);
        string[string_offset-2] = '0' + @intCast(u8, config.max_vertex_lights);

        addString(max_fragment_lights_string, string, &string_offset);
        string[string_offset-2] = '0' + @intCast(u8, config.max_fragment_lights);

        if(config.non_uniform_scale) {
            addString(non_uniform_scale_string, string, &string_offset);
        }

        if(config.recieve_shadows and getSettings().enable_shadows) {
            addString(enable_shadows_string, string, &string_offset);
        }
        
        const inputs_bitmap = config.inputs_bitmap;
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Position))) != 0) {
            addString(vertex_positions_string, string, &string_offset);
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Colour))) != 0) {
            addString(vertex_colours_string, string, &string_offset);
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.TextureCoordinates))) != 0) {
            addString(tex_coords_string, string, &string_offset);
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Normal))) != 0) {
            addString(normals_string, string, &string_offset);
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.BoneIndices))) != 0) {
            if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.BoneWeights))) == 0) {
                assert(false);
                return error.NoBoneWeights;
            }
            addString(vertex_weights_string, string, &string_offset);
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Tangent))) != 0) {
            if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Normal))) == 0) {
                assert(false);
                return error.NoNormals;
            }
            if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.TextureCoordinates))) == 0) {
                assert(false);
                return error.NoTexCoords;
            }
            addString(normal_map_string, string, &string_offset);
        }
        string[string_offset] = 0;


        var vertex_input_names: [8]([]const u8) = undefined;
        var i: u32 = 0;
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Position))) != 0) {
            vertex_input_names[i] = "in_coords\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Colour))) != 0) {
            vertex_input_names[i] = "in_vertex_colour\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.TextureCoordinates))) != 0) {
            vertex_input_names[i] = "in_texture_coordinates\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Normal))) != 0) {
            vertex_input_names[i] = "in_normal\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.BoneIndices))) != 0) {
            vertex_input_names[i] = "in_bone_indices\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.BoneWeights))) != 0) {
            vertex_input_names[i] = "in_vertex_weights\x00";
            i += 1;
        }
        if ((inputs_bitmap & (1 << @enumToInt(VertexAttributeType.Tangent))) != 0) {
            vertex_input_names[i] = "in_tangent\x00";
            i += 1;
        }

        var shader_program: ShaderProgram = undefined;
        if(config.shadow) {
            var vs_shadow: ShaderObject = try ShaderObject.init(([_]([]const u8){
                string[0..(string_offset + 1)],
                "#define VERTEX_SHADER\n#define SHADOW_MAP\n\x00",
                standard_shader_common_src.?,
                standard_shader_vs_src.?,
            })[0..], ShaderType.Vertex, allocator);
            defer vs_shadow.free();

            shader_program = try ShaderProgram.init(&vs_shadow, null, vertex_input_names[0..i], allocator);
            errdefer shader_program.free();
        }
        else {
            var vs: ShaderObject = try ShaderObject.init(([_]([]const u8){
                string[0..(string_offset + 1)],
                "#define VERTEX_SHADER\n\x00",
                standard_shader_common_src.?,
                standard_shader_vs_src.?,
            })[0..], ShaderType.Vertex, allocator);
            defer vs.free();

            var fs: ShaderObject = try ShaderObject.init(([_]([]const u8){
                string[0..(string_offset + 1)],
                "#define FRAGMENT_SHADER\n\x00",
                standard_shader_common_src.?,
                standard_shader_fs_src.?,
            })[0..], ShaderType.Fragment, allocator);
            defer fs.free();

            shader_program = try ShaderProgram.init(&vs, &fs, vertex_input_names[0..i], allocator);
            errdefer shader_program.free();
        }

        var program = ShaderInstance {
            .config = config,
            .shader_program = shader_program,
            .shader_name = "std",
        };

        try program.setUniforms();

        if(cache) {
            std.fs.makeDir("ShaderCache") catch |e| {
                if(e != std.os.MakeDirError.PathAlreadyExists) {
                    return e;
                }
            };

            var file_path_: [128]u8 = undefined;
            const file_path = getFileName(file_path_[0..],
                program.shader_name, config) catch return program;

            program.shader_program.saveBinary(file_path, allocator) catch {
                std.fs.deleteFile(file_path) catch {};
            };
        }

        return program;
    }

    fn setUniforms(self: *ShaderInstance) !void {
        const index = self.shader_program.getUniformBlockIndex(c"UniformData") catch null;
        if(index != null) {
            try self.shader_program.setUniformBlockBinding(index.?, 1);
        }

        self.mvp_matrix_location = self.shader_program.getUniformLocation(c"mvp_matrix") catch null;
        self.model_matrix_location = self.shader_program.getUniformLocation(c"model_matrix") catch null;
        self.model_view_matrix_location = self.shader_program.getUniformLocation(c"model_view_matrix") catch null;
        self.normal_matrix_location = self.shader_program.getUniformLocation(c"normalMatrix") catch null;
        self.colour_location = self.shader_program.getUniformLocation(c"object_colour") catch null;
        self.per_obj_light_location = self.shader_program.getUniformLocation(c"per_obj_light") catch null;
        self.vertex_light_indices_location = self.shader_program.getUniformLocation(c"vertex_lights") catch null;
        self.fragment_light_indices_location = self.shader_program.getUniformLocation(c"fragment_lights") catch null;
        self.near_planes_location = self.shader_program.getUniformLocation(c"nearPlanes") catch null;
        self.far_planes_location = self.shader_program.getUniformLocation(c"farPlanes") catch null;
        self.brightness_location = self.shader_program.getUniformLocation(c"brightness") catch null;
        self.contrast_location = self.shader_program.getUniformLocation(c"contrast") catch null;
        self.specular_intensity_location = self.shader_program.getUniformLocation(c"specularIntensity") catch null;
        self.specular_size_location = self.shader_program.getUniformLocation(c"specularSize") catch null;
        self.specular_colouration_location = self.shader_program.getUniformLocation(c"specularColouration") catch null;

        const texLoc = self.shader_program.getUniformLocation(c"main_texture") catch null;
        if (texLoc != null) {
            try self.shader_program.setUniform1i(texLoc.?, 0);
        }

        const nmapLoc = self.shader_program.getUniformLocation(c"texture_normal_map") catch null;
        if (nmapLoc != null) {
            try self.shader_program.setUniform1i(nmapLoc.?, 1);
        }

        self.light_matrices_location = self.shader_program.getUniformLocation(c"lightMatrices") catch null;

        var shadow_texture_locations: [4]?i32 = [1]?i32{null} ** 4;
        var shadow_cube_texture_locations: [4]?i32 = [1]?i32{null} ** 4;

        shadow_texture_locations[0] = self.shader_program.getUniformLocation(c"shadowTexture0") catch null;
        shadow_texture_locations[1] = self.shader_program.getUniformLocation(c"shadowTexture1") catch null;
        shadow_texture_locations[2] = self.shader_program.getUniformLocation(c"shadowTexture2") catch null;
        shadow_texture_locations[3] = self.shader_program.getUniformLocation(c"shadowTexture3") catch null;

        shadow_cube_texture_locations[0] = self.shader_program.getUniformLocation(c"shadowCubeTextures0") catch null;
        shadow_cube_texture_locations[1] = self.shader_program.getUniformLocation(c"shadowCubeTextures1") catch null;
        shadow_cube_texture_locations[2] = self.shader_program.getUniformLocation(c"shadowCubeTextures2") catch null;
        shadow_cube_texture_locations[3] = self.shader_program.getUniformLocation(c"shadowCubeTextures3") catch null;

        var i: u32 = 0;
        while(i < 4) : (i += 1) {
            if (shadow_texture_locations[i] != null) {
                try self.shader_program.setUniform1i(shadow_texture_locations[i].?, @intCast(i32, 2+i));
            }
            if (shadow_cube_texture_locations[i] != null) {
                try self.shader_program.setUniform1i(shadow_cube_texture_locations[i].?, @intCast(i32, 6+i));
            }
        }

        self.bone_matrices_location = self.shader_program.getUniformLocation(c"boneMatrices") catch null;

    }

    pub fn getFileName(buf: []u8, shader_name: []const u8, config: ShaderConfig) ![]u8 {
        return try std.fmt.bufPrint(buf, "ShaderCache{}{}.{}.{}.{}.{}.{}.{}.{}.{}.{}.{}.bin",
            files.path_seperator,
            shader_name,
            @boolToInt(config.shadow),
            config.inputs_bitmap,
            config.max_vertex_lights,
            config.max_fragment_lights,
            @boolToInt(config.non_uniform_scale),
            @boolToInt(config.recieve_shadows),
            @boolToInt(config.enable_specular_light),
            @boolToInt(config.enable_point_lights),
            @boolToInt(config.enable_directional_lights),
            @boolToInt(config.enable_spot_lights));
    }

    pub fn loadFromBinaryFile(shader_name: []const u8, config: ShaderConfig, allocator: *std.mem.Allocator ) !ShaderInstance {
        var file_name_: [128]u8 = undefined;
        const file_name = try ShaderInstance.getFileName(file_name_[0..], shader_name, config);
        
        var shader_program = try ShaderProgram.loadFromBinaryFile(file_name, allocator);

        var si = ShaderInstance {
            .config = config,
            .shader_name = shader_name,
            .shader_program = shader_program
        };
        try si.setUniforms();
        return si;
    }

    pub fn bind(self: ShaderInstance) !void {
        try self.shader_program.bind();
    }

    pub fn setMVPMatrix(self: ShaderInstance, matrix: *const Matrix(f32, 4)) !void {
        if (self.mvp_matrix_location != null) {
            try self.shader_program.setUniformMat4(self.mvp_matrix_location.?, 1, @bitCast([16]f32, matrix.data)[0..]);
        }
    }

    pub fn setModelMatrix(self: ShaderInstance, matrix: *const Matrix(f32, 4)) !void {
        if (self.model_matrix_location != null) {
            try self.shader_program.setUniformMat4(self.model_matrix_location.?, 1, @bitCast([16]f32, matrix.data)[0..]);
        }
    }

    pub fn setModelViewMatrix(self: ShaderInstance, matrix: *const Matrix(f32, 4)) !void {
        if (self.model_view_matrix_location != null) {
            try self.shader_program.setUniformMat4(self.model_view_matrix_location.?, 1, @bitCast([16]f32, matrix.data)[0..]);
        }
    }
    

    pub fn setNormalMatrix(self: ShaderInstance, matrix: *const Matrix(f32, 3)) !void {
        if (self.normal_matrix_location != null) {
            try self.shader_program.setUniformMat3(self.normal_matrix_location.?, 1, @bitCast([9]f32, matrix.data)[0..]);
        }
    }

    pub fn setColour(self: ShaderInstance, colour: [3]f32) !void {
        if (self.colour_location != null) {
            try self.shader_program.setUniform3f(self.colour_location.?, colour);
        }
    }

    pub fn setPerObjLight(self: ShaderInstance, colour: [3]f32) !void {
        if (self.per_obj_light_location != null) {
            try self.shader_program.setUniform3f(self.per_obj_light_location.?, colour);
        }
    }

    pub fn setVertexLightIndices(self: ShaderInstance, indices: [8]i32) !void {
        if (self.vertex_light_indices_location != null) {
            try self.shader_program.setUniform1iv(self.vertex_light_indices_location.?, indices[0..self.config.max_vertex_lights]);
        }
    }

    pub fn setFragmentLightIndices(self: ShaderInstance, indices: [4]i32) !void {
        if (self.fragment_light_indices_location != null) {
            try self.shader_program.setUniform1iv(self.fragment_light_indices_location.?, indices[0..self.config.max_fragment_lights]);
        }
    }

    // Near planes of shadow-casting lights
    pub fn setNearPlanes(self: ShaderInstance, near_planes: [4]f32) !void {
        if (self.near_planes_location != null) {
            try self.shader_program.setUniform1fv(self.near_planes_location.?, near_planes[0..self.config.max_fragment_lights]);
        }
    }

    // Far planes of shadow-casting lights
    pub fn setFarPlanes(self: ShaderInstance, far_planes: [4]f32) !void {
        if (self.far_planes_location != null) {
            try self.shader_program.setUniform1fv(self.far_planes_location.?, far_planes[0..self.config.max_fragment_lights]);
        }
    }

    pub fn setBrightness(self: ShaderInstance, c: f32) !void {
        if (self.brightness_location != null) {
            try self.shader_program.setUniform1f(self.brightness_location.?, c);
        }
    }

    pub fn setContrast(self: ShaderInstance, c: f32) !void {
        if (self.contrast_location != null) {
            try self.shader_program.setUniform1f(self.contrast_location.?, c);
        }
    }

    pub fn setLightMatrices(self: ShaderInstance, matrices: [4]Matrix(f32, 4)) !void {
        if (self.light_matrices_location != null) {
            try self.shader_program.setUniformMat4(self.light_matrices_location.?, 4, @bitCast([64]f32, matrices)[0..]);
        }
    }

    pub fn setBoneMatrices (self: ShaderInstance, matrices: []f32) !void {
        if (self.bone_matrices_location != null) {
            try self.shader_program.setUniformMat4(self.bone_matrices_location.?, @intCast(i32, matrices.len / 16), matrices);
        }
    }

    pub fn setSpecularIntensity(self: ShaderInstance, c: f32) !void {
        if (self.specular_intensity_location != null) {
            try self.shader_program.setUniform1f(self.specular_intensity_location.?, c);
        }
    }

    pub fn setSpecularSize(self: ShaderInstance, c: f32) !void {
        if (self.specular_size_location != null) {
            try self.shader_program.setUniform1f(self.specular_size_location.?, 1.0-c);
        }
    }

    pub fn setSpecularColouration(self: ShaderInstance, c: f32) !void {
        if (self.specular_colouration_location != null) {
            try self.shader_program.setUniform1f(self.specular_colouration_location.?, c);
        }
    }

    // Used during development to detect shader performance problems
    pub fn validate(self: ShaderInstance, allocator: *std.mem.Allocator) void {
        if(builtin.mode == builtin.Mode.Debug) {
            // Uncomment this to enable shader validation
            // No idea if it does anything useful or not..
            // self.shader_program.validate(allocator);
        }
    }
    
        
};

var shader_instances: ?ArrayList(ShaderInstance) = null;

// Called by RenderEngine.init.
pub fn init(allocator: *std.mem.Allocator) !void {
    shader_instances = ArrayList(ShaderInstance).init(allocator);

    standard_shader_vs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "StandardShader.vs", allocator);
    standard_shader_fs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "StandardShader.fs", allocator);
    standard_shader_common_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "StandardShader.glsl", allocator);



}

const window = wgi.window;

fn intToBool(b: var) bool {
    return b != 0;
}

test "Standard Shader all combinations" {
    std.debug.warn("This may take some time...");

    var a = std.heap.direct_allocator;

    try window.createWindow(false, 200, 200, c"test", true, 0);
    defer window.closeWindow();
    try renderEngine.init(wgi.getMicroTime(), a);   

    try init(a);

    var inputs_bitmap: u8 = 0;
    var i: u32 = 0;
    while(inputs_bitmap < 128) : (inputs_bitmap += 1) { // 2^7 combinations of inputs
        if((inputs_bitmap & (1 << 4)) >> 4 != (inputs_bitmap & (1 << 5)) >> 5) {
            continue;
        }
        if(inputs_bitmap & (1 << 6) != 0) {
            if(inputs_bitmap & (1 << 3) == 0) {
                // Can't have normal maps without normals
                continue;
            }
            else if(inputs_bitmap & (1 << 2) == 0) {
                // Can't have normal maps without texture coordinates
                continue;
            }
        }


        var inputs: [8]u32 = [1]u32{0}**8;
        
        var inputs_bitmap_: u8 = inputs_bitmap;
        const attribs_n = @popCount(u8, inputs_bitmap);
        var inputs_i: u32 = 0;
        var x: u32 = 1;
        while(inputs_bitmap_ != 0) : (inputs_bitmap_ >>= 1) {
            if(inputs_bitmap_ & 1 != 0) {
                inputs[inputs_i] = x;
                inputs_i += 1;
            }
            x += 1;
        }
        std.testing.expect(inputs_bitmap_ == 0);

        var shadow: u32 = 0;
        while(shadow < 2) : (shadow += 1) {
            var v_lights: u32 = 0;
            while(v_lights < 2) : (v_lights += 1) {
                var f_lights: u32 = 0;
                while(f_lights < 2) : (f_lights += 1) {
                    var recv_shadows: u32 = 0;
                    while(recv_shadows < 2) : (recv_shadows += 1) {

                        if(intToBool(shadow) and (intToBool(recv_shadows) or v_lights != 0 or f_lights != 0)) {
                            continue;
                        }

                        var config = ShaderInstance.ShaderConfig {
                            .shadow = intToBool(shadow), 
                            .inputs_bitmap = inputs_bitmap,
                            .max_vertex_lights = v_lights,
                            .max_fragment_lights = f_lights,
                            .non_uniform_scale = false,
                            .recieve_shadows = intToBool(recv_shadows),
                            .enable_specular_light = true,
                            .enable_point_lights = true,
                            .enable_directional_lights = true,
                            .enable_spot_lights = true,
                        };

                        var sh = ShaderInstance.init(false, config, a) catch |e| {
                            std.debug.warn("bitmap {}, attribs: {} {} {} {} {} {} {} {}\n", inputs_bitmap, inputs[0], inputs[1], inputs[2], inputs[3], inputs[4], inputs[5], inputs[6], inputs[7]);
                            std.debug.warn("shadow {}, vertex lights {}, fragment lights {}, recieve shadows {}\n", intToBool(shadow), v_lights, f_lights, intToBool(recv_shadows));
                            return e;
                        };
                        sh.shader_program.free();
                    }
                }
            }
        }

    }

}
