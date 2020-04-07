const anim = @import("Animation.zig");
pub const Animation = anim.Animation;
pub const Mesh = @import("Mesh.zig").Mesh;
pub const MeshRenderer = @import("MeshRenderer.zig").MeshRenderer;
pub const Light = @import("Light.zig").Light;
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
const UniformDataLight = @import("Light.zig").UniformDataLight;
const getLightData = @import("Light.zig").getLightData;

// Number of active lights in scene, recalculated each frame
var lights_count: u32 = 0;

// Time value set at start of each frame
var this_frame_time: u64 = 0;

const MAX_LIGHTS = 256; // Must match value in StandardShader.glsl

pub const SettingsStruct = struct {
    // Changing these variables may result in shaders being recompiled in the next frame
    max_fragment_lights: u32 = 4, // max 4
    max_vertex_lights: u32 = 8, // max 8
    enable_specular_light: bool = true,
    enable_point_lights: bool = true,
    enable_directional_lights: bool = true,
    enable_spot_lights: bool = true,
    enable_shadows: bool = true,

    // These cost nothing to change

    ambient: [3]f32 = [3]f32{ 0.1, 0.1, 0.1 },
    clear_colour: [3]f32 = [3]f32{ 0.5, 0.5, 0.5 },
    fog_colour: [4]f32 = [4]f32{ 0.5, 0.5, 0.5, 1.0 },
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
    fog_colour: [4]f32,
    lights: [MAX_LIGHTS]UniformDataLight,
};

var uniform_data: ?*UniformData = null;



pub const Object = struct {
    name: [16]u8 = ([1]u8{0}) ** 16,
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
        var obj = Object{};
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

        if (self.first_child != null) {
            self.first_child.?.nullifyTrueTransform();
        }
        if (self.next != null and self.next.? != self and self.next.? != self.parent.?.first_child.?) {
            self.next.?.nullifyTrueTransform();
        }
    }

    pub fn delete_(self: *Object, free_resources: bool) void {
        // Detatch associated resources
        if (self.mesh_renderer != null) {
            self.mesh_renderer.?.ref_count.dec();
            if (free_resources) {
                self.mesh_renderer.?.freeIfUnused();
            }
        }
        self.mesh_renderer = null;

        // Delete the children

        if (self.first_child != null) {
            self.first_child.?.delete_(free_resources);
        }
        if (self.next != null and self.next.? != self and self.next.? != self.parent.?.first_child.?) {
            self.next.?.delete_(free_resources);
        }
    }

    // Also deletes all children
    pub fn delete(self: *Object, free_resources: bool) void {
        if (active_camera == self) {
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

                if (self.prev.?.next == self.prev.? or self.prev.?.prev == self.prev.?) {
                    self.prev.?.next = null;
                    self.prev.?.prev = null;
                }

                if (self.next.?.next == self.next.? or self.next.?.prev == self.next.?) {
                    self.next.?.next = null;
                    self.next.?.prev = null;
                }
            }
            self.parent = null;
        }

        if (free_resources) {
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
        if (name.len > 16) {
            return false;
        }
        if (name.len != self.name_length) {
            return false;
        }
        var i: u32 = 0;
        while (i < name.len) : (i += 1) {
            if (name[i] != self.name[i]) {
                return false;
            }
        }

        return true;
    }

    // Only searches direct descendants on this object
    pub fn findChild(self: *Object, child_name: []const u8) ?*Object {
        const first = self.first_child;
        var current = self.first_child;

        while (current != null) {
            if (current.?.nameIs(child_name)) {
                return current.?;
            }

            current = current.?.next;
            if (current == first) {
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
            var draw_data = MeshRenderer.DrawData{
                .mvp_matrix = &mvp_matrix,
                .model_matrix = &self.true_transform.?,
                .model_view_matrix = &model_view_matrix,
                .light = getSettings().ambient,
                .vertex_light_indices = [8]i32{ -1, -1, -1, -1, -1, -1, -1, -1 },
                .fragment_light_indices = [4]i32{ -1, -1, -1, -1 },
                .fragment_light_matrices = undefined,
            };

            var fragment_light_shadow_textures: [4](?*const FrameBuffer) = [4](?*const FrameBuffer){ null, null, null, null };

            getLightData(self, self.mesh_renderer.?.*.max_vertex_lights, self.mesh_renderer.?.*.max_fragment_lights, &draw_data.light, &draw_data.vertex_light_indices, &draw_data.fragment_light_indices, &draw_data.fragment_light_matrices, &fragment_light_shadow_textures);

            var i: u32 = 0;
            while (i < 4) : (i += 1) {
                if (fragment_light_shadow_textures[i] != null) {
                    fragment_light_shadow_textures[i].?.bindTextureToUnit(2 + i) catch {assert(false);};
                } else {
                    wgi.Texture2D.unbind(2 + i);
                }
            }

            try self.mesh_renderer.?.draw(draw_data, allocator);
        }
    }
};

var active_camera: ?*Object = null;
var camera_position = Vector(f32, 3).init([3]f32{ 0, 0, 0 });

// camera direction = transform * (0,0,-1).
pub fn setActiveCamera(camera: *Object) void {
    active_camera = camera;
}

const PrePassError_ = error{PrePassError};

// First iteration over all objects.
// Calculates transformations in world space and gathers and generates light/shadow data ready for rendering
// as well as finding the first active camera
fn objectsPrePass(o: *Object, allocator: *Allocator, root_object: *Object) void {
    o.true_transform = null;

    if (o.light != null and lights_count < MAX_LIGHTS) {
        var err: bool = false;
        lights.?.append(o) catch {
            err = true;
        };

        if(!err) {
            const l = &o.light.?;
            l.lum = 0.2126 * o.light.?.colour[0] + 0.7152 * o.light.?.colour[1] + 0.0722 * o.light.?.colour[2];
            o.calculateTransform();
            l.light_pos = o.true_transform.?.position3D();
            var rot = Vector(f32, 4).init(
                [4]f32{ 0.0, 0.0, -1.0, 0.0 },
            ).mulMat(o.true_transform.?);
            rot.normalise();

            if (l.light_type == Light.LightType.Directional) {
                rot.data[0] = -rot.data[0];
                rot.data[1] = -rot.data[1];
                rot.data[2] = -rot.data[2];
            }

            l.uniform_array_index = lights_count;
            var type_ = @enumToInt(l.light_type) * 2 + 1;
            if (l.cast_realtime_shadows) {
                type_ += 1;
            }
            uniform_data.?.lights[lights_count] = UniformDataLight{
                .positionAndType = [4]f32{ l.light_pos.data[0], l.light_pos.data[1], l.light_pos.data[2], @intToFloat(f32, type_) },
                .directionAndAngle = [4]f32{ rot.data[0], rot.data[1], rot.data[2], l.angle },
                .intensity = [4]f32{ l.colour[0], l.colour[1], l.colour[2], l.attenuation },
            };

            l.createShadowMap(root_object, &o.true_transform.?, allocator) catch {
                l.cast_realtime_shadows = false;
            };
            lights_count += 1;
        }
    }

    // depth-first traversal
    if (o.first_child != null) {
        objectsPrePass(o.first_child.?, allocator, root_object);
    }
    if (o.parent != null and o.next != null and o.next.? != o.parent.?.*.first_child) {
        objectsPrePass(o.next.?, allocator, root_object);
    }
}

// INTERNAL FUNCTION - DO NOT CALL
// obj = root
pub fn renderObjects(o: *Object, allocator: *Allocator, view_matrix: *const Matrix(f32, 4), projection_matrix: *const Matrix(f32, 4), depth_only: bool) void {
    o.renderObject(allocator, view_matrix, projection_matrix, depth_only) catch {
        assert(false);
    };

    // depth-first traversal
    if (o.first_child != null) {
        renderObjects(o.first_child.?, allocator, view_matrix, projection_matrix, depth_only);
    }
    if (o.parent != null and o.next != null and o.next.? != o.parent.?.*.first_child) {
        renderObjects(o.next.?, allocator, view_matrix, projection_matrix, depth_only);
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

    if (window_width == 0 or window_height == 0) {
        // Window is minimised
        return;
    }

    if (active_camera == null) {
        return;
    }

    active_camera.?.calculateTransform();
    camera_position = active_camera.?.*.true_transform.?.position3D();

    window.setCullMode(window.CullMode.AntiClockwise);

    objectsPrePass(root_object, allocator, root_object);

    // Calculate again because the prepass cleared it.
    active_camera.?.calculateTransform();

    wgi.cullFace(wgi.CullFaceMode.Back);

    // If the window has no depth buffer then post processing must be enabled
    try PostProcess.startFrame(window_width, window_height, allocator);

    uniform_data.?.eye_position[0] = camera_position.x();
    uniform_data.?.eye_position[1] = camera_position.y();
    uniform_data.?.eye_position[2] = camera_position.z();
    uniform_data.?.eye_position[3] = 1.0;

    const projection_matrix = Matrix(f32, 4).perspectiveProjectionOpenGLInverseZ(@intToFloat(f32, window_width) / @intToFloat(f32, window_height), (30.0 / 180.0) * 3.141159265, 0.2, 100.0);

    var camera_transform_inverse = try active_camera.?.true_transform.?.inverse();

    // The camera was orbiting about a point 1 unit in front of it
    // This hacky solution fixed the issue
    camera_transform_inverse.data[3][2] += 1.0;

    // uniform_data.?.lights was initialised in objectsPrePass
    std.mem.copy(f32, @alignCast(4, uniform_data.?.fog_colour[0..]), getSettings().fog_colour);
    try uniform_buffer.?.upload(Buffer.BufferType.Uniform, @intToPtr([*]const u8, @ptrToInt(uniform_data.?))[0..(16 * 2 + @sizeOf(UniformDataLight) * lights_count)], true);
    try uniform_buffer.?.bind(Buffer.BufferType.Uniform);
    try uniform_buffer.?.bindUniform(1, 0, uniform_buffer.?.data_size);
    try uniform_buffer.?.bindBufferBase(1);

    wgi.setDepthModeDirectX(false, false);
    wgi.enableDepthWriting();
    window.setCullMode(window.CullMode.AntiClockwise);
    window.setClearColour(getSettings().clear_colour[0], getSettings().clear_colour[1], getSettings().clear_colour[2], 1.0);
    window.clear(true, true);

    renderObjects(root_object, allocator, &camera_transform_inverse, &projection_matrix, false);

    try PostProcess.endFrame(window_width, window_height, brightness, contrast);
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
