const mesh = @import("Mesh.zig");
const anim = @import("Animation.zig");
pub const Animation = anim.Animation;
pub const Mesh = mesh.Mesh;
pub const MeshRenderer = mesh.MeshRenderer;
pub const Texture2D = @import("Texture2D.zig").Texture2D;
const PostProcess = @import("PostProcess.zig");
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const Vector = @import("../Mathematics/Mathematics.zig").Vector;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const Tex2D = wgi.Texture2D;
const ImageType = wgi.ImageType;
const MinFilter = wgi.MinFilter;
const ShaderObject = wgi.ShaderObject;
const ShaderType = wgi.ShaderType;
const ShaderProgram = wgi.ShaderProgram;
const Buffer = wgi.Buffer;
const window = wgi.window;
const FrameBuffer = wgi.FrameBuffer;
const CubeFrameBuffer = wgi.CubeFrameBuffer;
const std = @import("std");
const ArrayList = std.ArrayList;
const shdr = @import("Shader.zig");
const assert = std.debug.assert;
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const files = @import("../Files.zig");
const loadFileWithNullTerminator = files.loadFileWithNullTerminator;
const VertexMeta = wgi.VertexMeta;

// Time value set at start of each frame
var this_frame_time: u64 = 0;

const MAX_LIGHTS = 256; // Must match value in StandardShader.glsl

pub const SettingsStruct = struct {
    max_fragment_lights: u32 = 4,// max 4
    max_vertex_lights: u32 = 8, // max 8
    enable_specular_light: bool = true,
    enable_point_lights: bool = true,
    enable_directional_lights: bool = true,
    enable_spot_lights: bool = true,
    enable_shadows: bool = true,

    ambient: [3]f32 = [3]f32{0.1,0.1,0.1},

    clear_colour: [3]f32 = [3]f32{0.5,0.5,0.5},
};

var settings: ?SettingsStruct = null;

pub fn getSettings() *SettingsStruct {
    return &settings.?;
}

var brightness: f32 = 1.0;
var contrast: f32 = 1.0;

var default_texture: ?Tex2D = null;
var default_normal_map: ?Tex2D = null;

pub fn getDefaultTexture() *const Tex2D {
    return &default_texture.?;
}

pub fn getDefaultNormalMap() *const Tex2D {
    return &default_normal_map.?;
}

var blur_shader_vs_src: ?[]u8 = null;
var blur_shader_fs_src: ?[]u8 = null;
var blur_shader_program: ?ShaderProgram = null;

var lights: ?ArrayList(*Object) = null;

// Per-frame, inter-frame data stored in VRAM

var uniform_buffer: ?Buffer = null;

const UniformData = packed struct {
    eye_position: [4]f32,
    lights: [MAX_LIGHTS]UniformDataLight
};

var uniform_data: ?*UniformData = null;

// Number of active lights in scene, recalculated each frame
var lights_count: u32 = 0;

pub const Light = struct {
    pub const LightType = enum(u32) {
        Point = 0,
        Directional = 1,
        Spotlight = 2,
    };

    light_type: LightType,
    angle: f32 = 0.9,
    colour: [3]f32,
    attenuation: f32 = 1.0, // how fast the light dissipates
    cast_realtime_shadows: bool = false,
    shadow_width: f32 = 20.0,
    shadow_height: f32 = 20.0,
    shadow_near: f32 = 1.0,
    shadow_far: f32 = 50.0,

    // Must be multiple of 16
    shadow_resolution_width: u32 = 512,
    // shadow_resolution_height is calculated using shadow_resolution_width and the aspect ratio
    // of shadow_width and shadow_height, then rounded up to the nearest 16

    // internal variables
    lum: f32 = 0.0,
    effect: f32 = 0.0,
    distance_divider: f32 = 1.0,
    light_pos: Vector(f32, 3) = Vector(f32, 3).init([3]f32{0,0,0}),
    uniform_array_index: u32 = 0,
    depth_framebuffer: ?FrameBuffer = null,
    average_depth_framebuffer: ?FrameBuffer = null,
    light_matrix: Matrix(f32, 4) = Matrix(f32, 4).identity(),

    // Checks the mesh renderer variables and global settings to determine whether this light
    // shouldbe used this frame
    pub fn lightShouldBeUsed(self: *Light, mesh_renderer: *MeshRenderer) bool {
        if(self.light_type == Light.LightType.Point) {
            return getSettings().enable_point_lights and mesh_renderer.enable_point_lights;
        }
        if(self.light_type == Light.LightType.Directional) {
            return getSettings().enable_directional_lights and mesh_renderer.enable_directional_lights;
        }
        if(self.light_type == Light.LightType.Spotlight) {
            return getSettings().enable_spot_lights and mesh_renderer.enable_spot_lights;
        }
        assert(false);
        return false;
    }

    // Draws scene from lights POV to create a depth image. Vertex processing only.
    pub fn createShadowMap(self: *Light, root_object: *Object, light_transform: *Matrix(f32, 4), allocator: *Allocator) !void {
        if (!self.cast_realtime_shadows or !getSettings().enable_shadows) {
            return;
        }

        if(self.light_type == LightType.Point) {
            self.cast_realtime_shadows = false;
            return;
        }

        // Position of light in 3D space
        const pos = light_transform.*.position3D();

        // Create frame buffer object

        var shadow_resolution_height = @floatToInt(u32, (@intToFloat(f32, self.shadow_resolution_width) * self.shadow_height) 
                                            / self.shadow_width);

        if(shadow_resolution_height % 16 != 0) {
            shadow_resolution_height += 16 - (shadow_resolution_height % 16);
        }
        
        if (self.depth_framebuffer == null) {
            self.depth_framebuffer = FrameBuffer.init(null, self.shadow_resolution_width, shadow_resolution_height, FrameBuffer.DepthType.I16) catch null;

            if (self.depth_framebuffer == null) {
                self.cast_realtime_shadows = false;
                return;
            }
        }

        if (self.average_depth_framebuffer == null) {
            self.average_depth_framebuffer = FrameBuffer.init(ImageType.RG32F, self.shadow_resolution_width/16, shadow_resolution_height/16, FrameBuffer.DepthType.None) catch null;
            
            if (self.average_depth_framebuffer == null) {
                self.cast_realtime_shadows = false;
                return;
            }

            try self.average_depth_framebuffer.?.setTextureFiltering(true, true);
        }
        
        var projection_matrix : ?Matrix(f32, 4) = null;

        if(self.light_type == LightType.Directional) {
            projection_matrix = Matrix(f32, 4).orthoProjectionOpenGLInverseZ(-self.shadow_width * 0.5, self.shadow_width * 0.5,
                -self.shadow_height * 0.5, self.shadow_height * 0.5, 
                self.shadow_near, self.shadow_far);
        }
        else {
            const angle = std.math.acos(self.angle) * 2.0;
            projection_matrix = Matrix(f32, 4).perspectiveProjectionOpenGLInverseZ(self.shadow_width / self.shadow_height,
                angle, self.shadow_near, self.shadow_far);
        }

        var view_matrix = try light_transform.*.inverse();
        view_matrix.data[3][2] += 1.0;

        self.light_matrix = view_matrix.mul(projection_matrix.?);

        try self.depth_framebuffer.?.bind();
        window.setCullMode(window.CullMode.AntiClockwise);
        wgi.cullFace(wgi.CullFaceMode.Back);
        wgi.enableDepthWriting();
        wgi.setDepthModeDirectX();
        window.clear(false, true);

        try renderObjects(root_object, allocator, &view_matrix, &projection_matrix.?, true);

        // Shadow map is now in depth_framebuffer
        // Now blur it
        window.setCullMode(window.CullMode.None);
        wgi.disableDepthTesting();
        wgi.disableDepthWriting();
        try blur_shader_program.?.bind();
        try self.average_depth_framebuffer.?.bind();
        try self.depth_framebuffer.?.bindDepthTexture();
        try VertexMeta.drawWithoutData(VertexMeta.PrimitiveType.Triangles, 0, 3);
    }
};

// See StandardShader.glsl
pub const UniformDataLight = packed struct {
    positionAndType: [4]f32,
    directionAndAngle: [4]f32,
    intensity: [4]f32,
};

pub const Object = struct {
    name: [16]u8 = ([1]u8 {0}) ** 16,
    name_length: u32 = 0,


    // If parent is null then the object has been deleted
    parent: ?*Object = null,
    first_child: ?*Object = null,
    next: ?*Object = null,
    prev: ?*Object = null,

    inherit_parent_transform: bool = true,

    // objects don't have to have a mesh renderer.
    // meshes can be used by multiple different objects
    // DO NOT ALTER THIS VARIABLE. USE fn setMeshRenderer
    mesh_renderer: ?*MeshRenderer = null,

    light: ?Light = null,

    // -- INTERNAL VARIABLES (READ-ONLY)

    transform: Matrix(f32, 4) = Matrix(f32, 4).identity(),

    // -- INTERNAL VARIABLES (DO NOT TOUCH) --

    true_transform: ?Matrix(f32, 4) = null,

    pub fn init(name: []const u8) Object {
        var obj = Object {};
        obj.name_length = std.math.min(@intCast(u32, name.len), 16);
        std.mem.copy(u8, obj.name[0..obj.name_length], name[0..obj.name_length]);
        return obj;
    }

    pub fn setTransform(self: *Object, new_transform: Matrix(f32, 4)) void {
        self.transform = new_transform;
        self.nullifyTrueTransform();
    }

    fn nullifyTrueTransform(self: *Object) void {
        self.true_transform = null;

        if(self.first_child != null) {
            self.first_child.?.nullifyTrueTransform();
        }
        if(self.next != null and self.next.? != self and self.next.? != self.parent.?.first_child.?) {
            self.next.?.nullifyTrueTransform();
        }
    }

    pub fn delete_(self: *Object, free_resources: bool) void {
        // Detatch associated resources

        if(self.mesh_renderer != null) {
            self.mesh_renderer.?.ref_count.dec();
            if(free_resources) {
                self.mesh_renderer.?.freeIfUnused();
            }
        }
        self.mesh_renderer = null;

        // Delete the children

        if(self.first_child != null) {
            self.first_child.?.delete_(free_resources);
        }
        if(self.next != null and self.next.? != self and self.next.? != self.parent.?.first_child.?) {
            self.next.?.delete_(free_resources);
        }
    }

    // Also deletes all children
    pub fn delete(self: *Object, free_resources: bool) void {
        if(active_camera == self) {
            active_camera = null;
        }

        // Detatch from parent

        if (self.parent != null) {
            if (self.parent.?.*.first_child == self) {
                if (self.next == null) {
                    self.parent.?.*.first_child = null;
                } else {
                    self.parent.?.*.first_child = self.next;
                    self.next.?.prev = null;
                    self.prev.?.next = null;
                }
            } else {
                self.prev.?.next = self.next;
                self.next.?.prev = self.prev;

                if(self.prev.?.next == self.prev.? or self.prev.?.prev == self.prev.?) {
                    self.prev.?.next = null;
                    self.prev.?.prev = null;
                }

                if(self.next.?.next == self.next.? or self.next.?.prev == self.next.?) {
                    self.next.?.next = null;
                    self.next.?.prev = null;
                }
            }
            self.parent = null;
        }

        if(free_resources) {
            self.delete_(free_resources);
        }

        
    }

    pub fn setMeshRenderer(self: *Object, mesh_renderer: ?*MeshRenderer) void {
        ReferenceCounter.set(MeshRenderer, &self.mesh_renderer, mesh_renderer);
    }

    pub fn addChild(self: *Object, child: *Object) !void {
        if (child.parent != null) {
            return error.ChildIsNotAnOrphan;
        }

        child.parent = self;
        if (self.first_child == null) {
            self.first_child = child;
            child.prev = null;
            child.next = null;
        } else {
            if (self.first_child.?.next == null) {
                assert(self.first_child.?.prev == null);
                self.first_child.?.next = child;
                self.first_child.?.prev = child;
                child.prev = self.first_child.?;
                child.next = self.first_child.?;
            } else {
                self.first_child.?.prev.?.next = child;
                child.prev = self.first_child.?.prev;
                self.first_child.?.prev = child;
                child.next = self.first_child.?;
            }
        }
    }

    pub fn nameIs(self: *Object, name: []const u8) bool {
        if(name.len > 16) {
            return false;
        }
        if(name.len != self.name_length) {
            return false;
        }
        var i: u32 = 0;
        while(i < name.len) : (i += 1) {
            if(name[i] != self.name[i]) {
                return false;
            }
        }

        return true;
    }

    // Only searches direct descendants on this object
    pub fn findChild(self: *Object, child_name: []const u8) ?*Object {
        const first = self.first_child;
        var current = self.first_child;

        while(current != null) {
            if(current.?.nameIs(child_name)){
                return current.?;
            }

            current = current.?.next;
            if(current == first) {
                break;
            }
        }

        return null;
        
    }

    // pub fn findChildRecursive(self: *Object, child_name: []const u8) !*Object {
        // TODO
    // }

    // Calculates transformation matrix of object in world space (applies transformations of all parents)
    pub fn calculateTransform(self: *Object) void {
        if (self.true_transform == null) {
            if (self.inherit_parent_transform and self.parent != null and self.parent.?.parent != null) {
                self.parent.?.calculateTransform();
                self.true_transform = self.parent.?.true_transform.?.mul(self.transform);
            } else {
                self.true_transform = self.transform;
            }
        }
        assert(self.true_transform != null);
    }

    fn getLightData(self: *Object, max_vertex_lights: u32, max_fragment_lights: u32, per_obj_light: *([3]f32), vertex_light_indices: *([8]i32), fragment_light_indices: *([4]i32), fragment_light_matrices: *([4]Matrix(f32, 4)), fragment_light_shadow_textures: *([4](?*const FrameBuffer))) void {
        if (lights.?.len == 0) {
            return;
        }

        const obj_pos = self.true_transform.?.position3D();

        // Calculate effect of each light on the object
        for (lights.?.toSlice()) |*light| {
            if (light.*.light.?.light_type == Light.LightType.Point or light.*.light.?.light_type == Light.LightType.Spotlight) {
                // TODO If the bounding box of the object was known then we could determine if the light effects the object for Spotlights
                var v = light.*.light.?.light_pos;
                v.sub(obj_pos);       

                const x = v.length() * light.*.light.?.attenuation;
                const distDiv = x * x;
                light.*.light.?.distance_divider = distDiv;
                if (distDiv == 0.0) {
                    // Light is inside the object
                    light.*.light.?.distance_divider = 0.001;
                    light.*.light.?.effect = 0.0;
                } else {
                    light.*.light.?.effect = light.*.light.?.lum / distDiv;
                }
            } else if (light.*.light.?.light_type == Light.LightType.Directional) {
                light.*.light.?.effect = light.*.light.?.lum;
            } else {
                assert(false);
            }
        }

        // Pick most significant 4* lights to be per-fragment
        // Then next 8* to be per-vertex
        // Then all other lights are per-object
        // * Max number of lights can be decreased

        if (lights.?.len > 1) {
            // Sort the lights by the effect on this object (most -> least effect)

            const sortFunction = struct {
                fn f(a: *Object, b: *Object) bool {
                    return a.*.light.?.effect > b.*.light.?.effect;
                }
            };

            std.sort.sort(*Object, lights.?.toSlice(), sortFunction.f);
        }

        // Set light indices

        const lights_slice = lights.?.toSlice();

        var i: u32 = 0; // index into lights_slice
        var j: u32 = 0; // index into light arrays
        while (i < getSettings().max_fragment_lights and i < max_fragment_lights and i < lights_slice.len) : (i += 1) {
            if(lights_slice[i].*.light.?.lightShouldBeUsed(self.mesh_renderer.?)) {
                fragment_light_indices[j] = @intCast(i32, lights_slice[i].*.light.?.uniform_array_index);

                if (lights_slice[i].*.light.?.cast_realtime_shadows and getSettings().enable_shadows) {
                    if(lights_slice[i].*.light.?.light_type != Light.LightType.Point){                           
                        fragment_light_matrices[j] = lights_slice[i].*.light.?.light_matrix;
                        fragment_light_shadow_textures[j] = &lights_slice[i].*.light.?.average_depth_framebuffer.?;
                    }
                }

                j += 1;
            }
        }

        j = 0;
        while (j < 8 and i < lights_slice.len and i < max_vertex_lights and i < getSettings().max_vertex_lights) {
            if(lights_slice[i].*.light.?.lightShouldBeUsed(self.mesh_renderer.?)) {                            
                vertex_light_indices[j] = @intCast(i32, lights_slice[i].*.light.?.uniform_array_index);
                i += 1;
                j += 1;
            }
        }

        if(self.mesh_renderer.?.*.enable_per_object_light) {
            // Everything else is applied per-object

            while (i < lights_slice.len) : (i += 1) {
                const light = &lights_slice[i].*.light.?;
                if (light.light_type == Light.LightType.Point) {
                    per_obj_light[0] += (light.colour[0] / light.distance_divider) * 0.7;
                    per_obj_light[1] += (light.colour[1] / light.distance_divider) * 0.7;
                    per_obj_light[2] += (light.colour[2] / light.distance_divider) * 0.7;
                } else if (light.light_type == Light.LightType.Directional) {
                    per_obj_light[0] += light.colour[0] * 0.7;
                    per_obj_light[1] += light.colour[1] * 0.7;
                    per_obj_light[2] += light.colour[2] * 0.7;
                }
                // TODO do Spotlights if bounding box is available
            }
        }
    }

    pub fn renderObject(self: *Object, allocator: *Allocator, view_matrix: *const Matrix(f32, 4), projection_matrix: *const Matrix(f32, 4), depth_only: bool) !void {
        if (self.mesh_renderer == null) {
            return;
        }

        self.calculateTransform();
        assert(self.true_transform != null);

        const model_view_matrix = self.true_transform.?.mul(view_matrix.*);
        const mvp_matrix = model_view_matrix.mul(projection_matrix.*);

        if (depth_only) {
            // For shadow maps
            try self.mesh_renderer.?.*.drawDepthOnly(allocator, &mvp_matrix, &self.true_transform.?);
        } else {
            var draw_data = MeshRenderer.DrawData {
                .mvp_matrix = &mvp_matrix,
                .model_matrix = &self.true_transform.?,
                .model_view_matrix = &model_view_matrix,
                .light = getSettings().ambient,
                .vertex_light_indices = [8]i32{ -1, -1, -1, -1, -1, -1, -1, -1 },
                .fragment_light_indices = [4]i32{ -1, -1, -1, -1 },
                .fragment_light_matrices = undefined
            };

            var fragment_light_shadow_textures: [4](?*const FrameBuffer) = [4](?*const FrameBuffer){ null, null, null, null };

            self.getLightData(self.mesh_renderer.?.*.max_vertex_lights, self.mesh_renderer.?.*.max_fragment_lights, 
                    &draw_data.light, &draw_data.vertex_light_indices, &draw_data.fragment_light_indices, &draw_data.fragment_light_matrices,
                    &fragment_light_shadow_textures);

            var i: u32 = 0;
            while (i < 4) : (i += 1) {
                if (fragment_light_shadow_textures[i] != null) {
                    fragment_light_shadow_textures[i].?.bindTextureToUnit(2 + i) catch {};
                }
                else {
                    wgi.Texture2D.unbind(2 + i);
                }
            }


            try self.mesh_renderer.?.draw(draw_data, allocator);
        }
    }
};

var active_camera: ?*Object = null;
var camera_position = Vector(f32, 3).init([3]f32{0,0,0});

// camera direction = transform * (0,0,-1).
pub fn setActiveCamera(camera: *Object) void {
    active_camera = camera;
}

const PrePassError_ = error{PrePassError};


// First iteration over all objects.
// Calculates transformations in world space and gathers and generates light/shadow data ready for rendering
// as well as finding the first active camera
fn objectsPrePass(o: *Object, allocator: *Allocator, root_object: *Object) PrePassError_!void {
    o.true_transform = null;

    if (o.light != null and lights_count < MAX_LIGHTS) {
        lights.?.append(o) catch return error.PrePassError;

        const l = &o.light.?;
        l.lum = 0.2126 * o.light.?.colour[0] + 0.7152 * o.light.?.colour[1] + 0.0722 * o.light.?.colour[2];
        o.calculateTransform();
        l.light_pos = o.true_transform.?.position3D();
        var rot = Vector(f32, 4).init(
            [4]f32{ 0.0, 0.0, -1.0, 0.0 },
        ).mulMat(o.true_transform.?);
        rot.normalise();

        if(l.light_type == Light.LightType.Directional) {
            rot.data[0] = -rot.data[0];
            rot.data[1] = -rot.data[1];
            rot.data[2] = -rot.data[2];
        }


        l.uniform_array_index = lights_count;
        var type_ = @enumToInt(l.light_type)*2+1;
        if (l.cast_realtime_shadows) {
            type_ += 1;
        }
        uniform_data.?.lights[lights_count] = UniformDataLight{
            .positionAndType = [4]f32{ l.light_pos.data[0], l.light_pos.data[1], l.light_pos.data[2], @intToFloat(f32, type_) },
            .directionAndAngle = [4]f32{ rot.data[0], rot.data[1], rot.data[2], l.angle },
            .intensity = [4]f32{ l.colour[0], l.colour[1], l.colour[2], l.attenuation },
        };

        l.createShadowMap(root_object, &o.true_transform.?, allocator) catch return error.PrePassError;
        lights_count += 1;
    }

    // depth-first traversal
    if (o.first_child != null) {
        try objectsPrePass(o.first_child.?, allocator, root_object);
    }
    if (o.parent != null and o.next != null and o.next.? != o.parent.?.*.first_child) {
        try objectsPrePass(o.next.?, allocator, root_object);
    }
}

// obj = root
fn renderObjects(o: *Object, allocator: *Allocator, view_matrix: *const Matrix(f32, 4), projection_matrix: *const Matrix(f32, 4), depth_only: bool) @typeOf(Object.renderObject).ReturnType.ErrorSet!void {   
    try o.renderObject(allocator, view_matrix, projection_matrix, depth_only);

    // depth-first traversal
    if (o.first_child != null) {
        try renderObjects(o.first_child.?, allocator, view_matrix, projection_matrix, depth_only);
    }
    if (o.parent != null and o.next != null and o.next.? != o.parent.?.*.first_child) {
        try renderObjects(o.next.?, allocator, view_matrix, projection_matrix, depth_only);
    }
}

fn loadBlurShader(allocator: *Allocator) !void {
    blur_shader_vs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "Blur.vs", allocator);
    blur_shader_fs_src = try loadFileWithNullTerminator("StandardAssets" ++ files.path_seperator ++ "Blur.fs", allocator);

    var blur_vs: ShaderObject = try ShaderObject.init(([_]([]const u8){blur_shader_vs_src.?})[0..], ShaderType.Vertex, allocator);
    var blur_fs: ShaderObject = try ShaderObject.init(([_]([]const u8){blur_shader_fs_src.?})[0..], ShaderType.Fragment, allocator);
    blur_shader_program = try ShaderProgram.init(&blur_vs, &blur_fs, [0][]const u8{}, allocator);

    try blur_shader_program.?.setUniform1i(try blur_shader_program.?.getUniformLocation(c"textureSrc"), 0);
}

// Allocator is for temporary allocations (printing shader error logs, temporary arrays, etc.) and permenant allocations (shader source files).
// ^ Best to use c_alloc
// Allocator must remain valid until deinit has been  called
pub fn init(time: u64, allocator: *Allocator) !void {
    settings = SettingsStruct{};
    this_frame_time = time;
    try PostProcess.loadSourceFiles(allocator);

    try loadBlurShader(allocator);

    try shdr.init(allocator);

    default_texture = try Tex2D.init(false, MinFilter.Nearest);
    errdefer default_texture.?.free();
    try default_texture.?.upload(1, 1, ImageType.RGBA, [4]u8{ 0xff, 0xff, 0xff, 0xff });

    
    default_normal_map = try Tex2D.init(false, MinFilter.Nearest);
    errdefer default_normal_map.?.free();
    try default_normal_map.?.upload(1, 1, ImageType.RGBA, [4]u8{ 0x80, 0x80, 0xff, 0xff });

    lights = ArrayList(*Object).init(allocator);

    uniform_buffer = try Buffer.init();
    errdefer uniform_buffer.?.free();

    uniform_data = try allocator.create(UniformData);
}

pub fn deinit(allocator: *Allocator) void {
    lights.?.deinit();
    allocator.destroy(uniform_data);
}

pub fn render(root_object: *Object, micro_time: u64, allocator: *Allocator) !void {
    this_frame_time = micro_time;
    lights_count = 0;
    lights.?.resize(0) catch unreachable;

    var window_width: u32 = 0;
    var window_height: u32 = 0;
    window.getSize(&window_width, &window_height);

    if(window_width == 0 or window_height == 0) {
        // Window is minimised
        return;
    }

    if(active_camera == null) {
        return;
    }


    active_camera.?.calculateTransform();
    camera_position = active_camera.?.*.true_transform.?.position3D();

    window.setCullMode(window.CullMode.AntiClockwise);

    try objectsPrePass(root_object, allocator, root_object);

    // Calculate again because the prepass cleared it.
    active_camera.?.calculateTransform();

    wgi.cullFace(wgi.CullFaceMode.Back);

    // If the window has no depth buffer then post processing must be enabled
    try PostProcess.startFrame(window_width, window_height, allocator);


    uniform_data.?.eye_position[0] = camera_position.x();
    uniform_data.?.eye_position[1] = camera_position.y();
    uniform_data.?.eye_position[2] = camera_position.z();
    uniform_data.?.eye_position[3] = 1.0;

    const projection_matrix = Matrix(f32, 4).perspectiveProjectionOpenGLInverseZ(
        @intToFloat(f32, window_width) / @intToFloat(f32, window_height), (30.0 / 180.0) * 3.141159265, 0.1, 1000.0);        
    

    var camera_transform_inverse = try active_camera.?.true_transform.?.inverse();

    // The camera was orbiting about a point 1 unit in front of it
    // This hacky solution fixed the issue
    camera_transform_inverse.data[3][2] += 1.0;

    if (lights_count > 0) {
        // uniform_data was set in objectsPrePass
        try uniform_buffer.?.upload(Buffer.BufferType.Uniform, @intToPtr([*]const u8, @ptrToInt(uniform_data.?))[0..(16 + @sizeOf(UniformDataLight) * lights_count)], true);
        try uniform_buffer.?.bind(Buffer.BufferType.Uniform);
        try uniform_buffer.?.bindUniform(1, 0, uniform_buffer.?.data_size);
        try uniform_buffer.?.bindBufferBase(1);
    }

    wgi.setDepthModeDirectX();
    wgi.enableDepthWriting();
    window.setCullMode(window.CullMode.AntiClockwise);
    window.setClearColour(getSettings().clear_colour[0], getSettings().clear_colour[1], getSettings().clear_colour[2], 1.0);
    window.clear(true, true);

    try renderObjects(root_object, allocator, &camera_transform_inverse, &projection_matrix, false);

    try PostProcess.endFrame(
        window_width,
        window_height,
        brightness,
        contrast
    );
}

pub fn setImageCorrection(brightness_: f32, contrast_: f32) void {
    brightness = brightness_;
    contrast = contrast_;
}

test "All tests" {
    _ = @import("Mesh.zig");
    _ = @import("Shader.zig");
    _ = @import("PostProcess.zig");
}
