const Vector = @import("../Mathematics/Mathematics.zig").Vector;
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const FrameBuffer = wgi.FrameBuffer;
const MeshRenderer = @import("MeshRenderer.zig").MeshRenderer;
const rtRenderEngine = @import("RTRenderEngine.zig");
const blur_shader_program = &rtRenderEngine.blur_shader_program;
const lights = &rtRenderEngine.lights;
const Object = rtRenderEngine.Object;
const getSettings = rtRenderEngine.getSettings;
const renderObjects = rtRenderEngine.renderObjects;
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const MinFilter = wgi.MinFilter;
const ImageType = wgi.ImageType;
const window = wgi.window;
const ShaderProgram = wgi.ShaderProgram;
const anim = @import("Animation.zig");
pub const Animation = anim.Animation;
pub const Mesh = @import("Mesh.zig").Mesh;
pub const Texture2D = @import("Texture2D.zig").Texture2D;
const PostProcess = @import("PostProcess.zig");
const ShaderObject = wgi.ShaderObject;
const ShaderType = wgi.ShaderType;
const Buffer = wgi.Buffer;
const shdr = @import("Shader.zig");
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const files = @import("../Files.zig");
const loadFileWithNullTerminator = files.loadFileWithNullTerminator;
const VertexMeta = wgi.VertexMeta;
const ArrayList = std.ArrayList;


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
    light_pos: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 0, 0, 0 }),
    uniform_array_index: u32 = 0,
    depth_framebuffer: ?FrameBuffer = null,
    average_depth_framebuffer: ?FrameBuffer = null,
    light_matrix: Matrix(f32, 4) = Matrix(f32, 4).identity(),

    // Checks the mesh renderer variables and global settings to determine whether this light
    // shouldbe used this frame
    pub fn lightShouldBeUsed(self: *Light, mesh_renderer: *MeshRenderer) bool {
        if (self.light_type == Light.LightType.Point) {
            return getSettings().enable_point_lights and mesh_renderer.enable_point_lights;
        }
        if (self.light_type == Light.LightType.Directional) {
            return getSettings().enable_directional_lights and mesh_renderer.enable_directional_lights;
        }
        if (self.light_type == Light.LightType.Spotlight) {
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

        if (self.light_type == LightType.Point) {
            self.cast_realtime_shadows = false;
            return;
        }

        // Position of light in 3D space
        const pos = light_transform.*.position3D();

        // Create frame buffer object

        var shadow_resolution_height = @floatToInt(u32, (@intToFloat(f32, self.shadow_resolution_width) * self.shadow_height) / self.shadow_width);

        if (shadow_resolution_height % 16 != 0) {
            shadow_resolution_height += 16 - (shadow_resolution_height % 16);
        }

        if (self.depth_framebuffer == null) {
            self.depth_framebuffer = FrameBuffer.init(null, self.shadow_resolution_width, shadow_resolution_height, FrameBuffer.DepthType.I16, allocator) catch null;

            if (self.depth_framebuffer == null) {
                self.cast_realtime_shadows = false;
                return;
            }

            try self.depth_framebuffer.?.depth_texture.?.setFiltering(true, MinFilter.Linear);
        }

        if (self.average_depth_framebuffer == null) {
            self.average_depth_framebuffer = FrameBuffer.init(ImageType.RG32F, self.shadow_resolution_width / 16, shadow_resolution_height / 16, FrameBuffer.DepthType.None, allocator) catch null;

            if (self.average_depth_framebuffer == null) {
                self.cast_realtime_shadows = false;
                return;
            }

            try self.average_depth_framebuffer.?.setTextureFiltering(true, true);
        }

        var projection_matrix: ?Matrix(f32, 4) = null;

        if (self.light_type == LightType.Directional) {
            projection_matrix = Matrix(f32, 4).orthoProjectionOpenGLInverseZ(-self.shadow_width * 0.5, self.shadow_width * 0.5, -self.shadow_height * 0.5, self.shadow_height * 0.5, self.shadow_near, self.shadow_far);
        } else {
            const angle = std.math.acos(self.angle) * 2.0;
            projection_matrix = Matrix(f32, 4).perspectiveProjectionOpenGLInverseZ(self.shadow_width / self.shadow_height, angle, self.shadow_near, self.shadow_far);
        }

        var view_matrix = try light_transform.*.inverse();
        view_matrix.data[3][2] += 1.0;

        self.light_matrix = view_matrix.mul(projection_matrix.?);

        try self.depth_framebuffer.?.bind();
        window.setCullMode(window.CullMode.AntiClockwise);
        wgi.cullFace(wgi.CullFaceMode.Back);
        wgi.enableDepthWriting();
        wgi.setDepthModeDirectX(false, false);
        window.clear(false, true);

        renderObjects(root_object, allocator, &view_matrix, &projection_matrix.?, true);

        // Shadow map is now in depth_framebuffer
        // Now blur it
        window.setCullMode(window.CullMode.None);
        wgi.disableDepthTesting();
        wgi.disableDepthWriting();
        try blur_shader_program.*.?.bind();
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


pub fn getLightData(object: *Object, max_vertex_lights: u32, max_fragment_lights: u32, per_obj_light: *([3]f32), vertex_light_indices: *([8]i32), fragment_light_indices: *([4]i32), fragment_light_matrices: *([4]Matrix(f32, 4)), fragment_light_shadow_textures: *([4](?*const FrameBuffer))) void {
    if (lights.*.?.items.len == 0) {
        return;
    }

    const obj_pos = object.true_transform.?.position3D();

    // Calculate effect of each light on the object
    for (lights.*.?.items) |*light| {
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

    if (lights.*.?.items.len > 1) {
        // Sort the lights by the effect on this object (most -> least effect)
        const sortFunction = struct {
            fn f(a: *Object, b: *Object) bool {
                return a.*.light.?.effect > b.*.light.?.effect;
            }
        };

        std.sort.sort(*Object, lights.*.?.items, sortFunction.f);
    }

    // Set light indices

    const lights_slice = lights.*.?.items;

    var i: u32 = 0; // index into lights_slice
    var j: u32 = 0; // index into light arrays
    while (i < getSettings().max_fragment_lights and i < max_fragment_lights and i < lights_slice.len) : (i += 1) {
        if (lights_slice[i].*.light.?.lightShouldBeUsed(object.mesh_renderer.?)) {
            fragment_light_indices[j] = @intCast(i32, lights_slice[i].*.light.?.uniform_array_index);

            if (lights_slice[i].*.light.?.cast_realtime_shadows and getSettings().enable_shadows) {
                if (lights_slice[i].*.light.?.light_type != Light.LightType.Point) {
                    fragment_light_matrices[j] = lights_slice[i].*.light.?.light_matrix;
                    fragment_light_shadow_textures[j] = &lights_slice[i].*.light.?.average_depth_framebuffer.?;
                }
            }

            j += 1;
        }
    }

    j = 0;
    while (j < 8 and i < lights_slice.len and i < max_vertex_lights and i < getSettings().max_vertex_lights) {
        if (lights_slice[i].*.light.?.lightShouldBeUsed(object.mesh_renderer.?)) {
            vertex_light_indices[j] = @intCast(i32, lights_slice[i].*.light.?.uniform_array_index);
            i += 1;
            j += 1;
        }
    }

    if (object.mesh_renderer.?.*.enable_per_object_light) {
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