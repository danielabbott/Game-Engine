// Controls
// Right-click to capture mouse
// Move mouse to look around
// WASD, space bar, left shift to move
// Left control to go faster

const std = @import("std");
const warn = std.debug.warn;
const wgi = @import("WindowGraphicsInput/WindowGraphicsInput.zig");
const window = wgi.window;
const input = wgi.input;
const image = wgi.image;
const c = wgi.c;
const Constants = wgi.Constants;
const vertexarray = wgi.vertexarray;
const buffer = wgi.buffer;
const render = @import("RTRenderEngine/RTRenderEngine.zig");
const ModelData = @import("ModelFiles/ModelFiles.zig").ModelData;
const c_allocator = std.heap.c_allocator;
const maths = @import("Mathematics/Mathematics.zig");
const Matrix = maths.Matrix;
const Vector = maths.Vector;
const Files = @import("Files.zig");
const loadFile = Files.loadFile;
const compress = @import("Compress/Compress.zig");
const assets = @import("Assets/Assets.zig");
const Asset = assets.Asset;
const HSV2RGB = @import("Colour.zig").HSV2RGB;
const scenes = @import("Scene/Scene.zig");

var camera_position: [3]f32 = [3]f32{ 0.0, 1.75, 10.0 };
var camera_rotation_euler: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 };
var cursor_enabled: bool = true;

fn mouseCallback(button: i32, action: i32, mods: i32) void {
    if (button == 1 and action == Constants.RELEASE) {
        cursor_enabled = !cursor_enabled;
        input.setCursorEnabled(cursor_enabled);
    }
}

fn moveNoUp(x: f32, y: f32, z: f32) void {
    if (z != 0.0) {
        camera_position[0] += (z * std.math.sin(camera_rotation_euler[1]));
        camera_position[2] += (z * std.math.cos(camera_rotation_euler[1]));
    }

    if (x != 0.0) {
        camera_position[0] += (x * std.math.sin(camera_rotation_euler[1] + 1.57079632679));
        camera_position[2] += (x * std.math.cos(camera_rotation_euler[1] + 1.57079632679));
    }

    if (y != 0.0) {
        camera_position[0] += y * std.math.sin(camera_rotation_euler[2]);
        camera_position[2] += -std.math.sin(camera_rotation_euler[0]) * y;
    }
}

var fullscreen: bool = false;

fn keyCallback(key: i32, scancode: i32, action: i32, mods: i32) void {
    if(action == Constants.RELEASE and key == Constants.KEY_F11) {
        if(fullscreen) {
            window.exitFullScreen(1024, 768);
        }
        else {
            window.goFullScreen();
        }
        fullscreen = !fullscreen;
    }
}

pub fn loadIcon() !void {    
    const image_file_data = try Files.loadFile("DemoAssets" ++ Files.path_seperator ++ "icon.jpg", c_allocator);
    defer c_allocator.free(image_file_data);
    var ico_components: u32 = 4;
    var ico_width: u32 = 0;
    var ico_height: u32 = 0;
    const ico_data = try image.decodeImage(image_file_data, &ico_components, &ico_width, &ico_height, c_allocator);
    defer image.freeDecodedImage(ico_data);

    if(ico_width != 48 or ico_height != 48) {
        return error.IconWrongSize;
    }

    if(ico_components != 4 or ico_data.len != 48*48*4) {
        return error.ImageDecodeError;
    }

    window.setIcon(null, null, @bytesToSlice(u32, @sliceToBytes(ico_data)), null);
}

pub fn main() !void {
    assets.setAssetsDirectory("DemoAssets" ++ Files.path_seperator);

    const scene_file = try loadFile("DemoAssets" ++ Files.path_seperator ++ "Farm.scene", c_allocator);
    defer c_allocator.free(scene_file);

    var assets_list = std.ArrayList(Asset).init(c_allocator);
    defer assets_list.deinit();

    defer {
        for(assets_list.toSlice()) |*a| {
            if(a.state != Asset.AssetState.Freed) {
                std.debug.warn("Asset {} not freed\n", a.file_path[0..a.file_path_len]);
                if(a.data != null) {
                    std.debug.warn("\t^ Data has not been freed either\n");
                }
            }
        }
    }

    try scenes.getAssets(scene_file, &assets_list);

    const num_scene_assets = assets_list.count();

    defer {
        for (assets_list.toSlice()) |*a| {
            a.*.free(true);
        }
    }

    try assets.startAssetLoader1(assets_list.toSlice(), c_allocator);


    try window.createWindow(false, 1024, 768, c"Demo 1", true, 0);
    defer window.closeWindow();
    window.setResizeable(true);

    loadIcon() catch |e| {
        warn("Error loading icon: {}\n", e);
    };

    input.setKeyCallback(keyCallback);
    input.setMouseButtonCallback(mouseCallback);

    try render.init(wgi.getMicroTime(), c_allocator);
    defer render.deinit(c_allocator);

    const settings = render.getSettings();
    scenes.getAmbient(scene_file, &settings.*.ambient);
    scenes.getClearColour(scene_file, &settings.*.clear_colour);
    settings.enable_point_lights = false;
    settings.enable_spot_lights = true;
    settings.max_fragment_lights = 2;
    settings.max_vertex_lights = 0;
    settings.enable_specular_light = false;

    var root_object: render.Object = render.Object.init("root");
    defer root_object.delete(true);

    var camera: render.Object = render.Object.init("camera");
    try root_object.addChild(&camera);
    render.setActiveCamera(&camera);

    var spotlight: render.Object = render.Object.init("light");
    spotlight.light = render.Light{
        .light_type = render.Light.LightType.Spotlight,
        .colour = [3]f32{ 100, 100, 100 },
        .attenuation = 1,
        .cast_realtime_shadows = false,
        .shadow_near = 0.1,
        .shadow_far = 20.0,
        .shadow_resolution_width = 256
    };
    try root_object.addChild(&spotlight);

    // Wait for game assets to finish loading
    // Keep calling pollEvents() to stop the window freezing
    // This would be where a loading bar is shown

    while (!assets.assetsLoaded()) {
        window.pollEvents();
        if (window.windowShouldClose()) {
            return;
        }
        // 0.1s
        std.time.sleep(100000000);
    }
    assets.assetLoaderCleanup();

    // Check all assets were loaded successfully

    for(assets_list.toSlice()) |*a| {
        if(a.state != Asset.AssetState.Ready) {
            return error.AssetLoadError;
        }
    }

    // Load the farm

    const scene = try scenes.loadSceneFromFile(scene_file, assets_list.toSlice()[0..num_scene_assets], c_allocator);
    try root_object.addChild(scene);

    // Free assets (data has been uploaded the GPU)
    // This frees the cpu-side copy of model data and textures which is now stored on the GPU
    for(assets_list.toSlice()) |*a| {
        a.freeData();
    }

    const windmill_blades = scene.findChild("Windmill_Blades");
    if(windmill_blades == null) {
        return error.NoWindmillBlades;
    }

    // Copy of the windmill blades default position/rotation/scale
    const windmill_blades_default_transform = windmill_blades.?.*.transform;

    // Artistic choice
    windmill_blades.?.mesh_renderer.?.recieve_shadows = false;

    const static_geometry = scene.findChild("FarmStatic");
    if(static_geometry == null) {
        return error.NoStaticGeometry;
    }
    static_geometry.?.mesh_renderer.?.enable_per_object_light = false;

    const light = scene.findChild("Light");
    if(light != null) {
        // These values have been tweaked to provide a near-optimal depth texture
        // TODO This information should be moved into the scene file
        light.?.light.?.shadow_width = 54.0;
        light.?.light.?.shadow_height = 60.0;
        light.?.light.?.shadow_resolution_width = 1024;
    }


    var mouse_pos_prev: [2]i32 = input.getMousePosition();

    var brightness: f32 = 1.0;
    var contrast: f32 = 1.0;

    var last_frame_time = wgi.getMicroTime();
    var last_fps_print_time = last_frame_time;
    var fps_count: u32 = 0;

    // Game loop

    var rotation: f32 = 0;
    while (!window.windowShouldClose()) {
        if (input.isKeyDown(Constants.KEY_ESCAPE)) {
            break;
        }

        const micro_time = wgi.getMicroTime();

        const this_frame_time = micro_time;
        const deltaTime = @intToFloat(f32, this_frame_time - last_frame_time) * 0.000001;
        last_frame_time = this_frame_time;

        if (this_frame_time - last_fps_print_time >= 990000) {
            warn("{}\n", fps_count+1);
            fps_count = 0;
            last_fps_print_time = this_frame_time;
        } else {
            fps_count += 1;
        }

        if (input.isKeyDown(Constants.KEY_LEFT_BRACKET)) {
            brightness -= 0.08;

            if (brightness < 0.0) {
                brightness = 0.0;
            }
        } else if (input.isKeyDown(Constants.KEY_RIGHT_BRACKET)) {
            brightness += 0.08;
        }

        if (input.isKeyDown(Constants.KEY_COMMA)) {
            contrast -= 0.01;
            if (contrast < 0.0) {
                contrast = 0.0;
            }
        } else if (input.isKeyDown(Constants.KEY_PERIOD)) {
            contrast += 0.01;
        }

        render.setImageCorrection(brightness, contrast);

        // FPS-style camera rotation

        const mouse_pos = input.getMousePosition();
        if (!cursor_enabled) {
            camera_rotation_euler[1] += -0.1 * deltaTime * @intToFloat(f32, mouse_pos[0] - mouse_pos_prev[0]);
            camera_rotation_euler[0] += 0.1 * deltaTime * @intToFloat(f32, mouse_pos[1] - mouse_pos_prev[1]);

            const max_angle = 1.4;
            if (camera_rotation_euler[0] > max_angle) {
                camera_rotation_euler[0] = max_angle;
            } else if (camera_rotation_euler[0] < -max_angle) {
                camera_rotation_euler[0] = -max_angle;
            }
        }
        mouse_pos_prev = mouse_pos;

        // FPS-style movement

        var speed: f32 = 1.0;
        if (input.isKeyDown(Constants.KEY_LEFT_CONTROL)) {
            speed = 10.0;
        }

        if (input.isKeyDown(Constants.KEY_W)) {
            moveNoUp(0.0, 0.0, -1.875 * deltaTime * speed);
        } else if (input.isKeyDown(Constants.KEY_S)) {
            moveNoUp(0.0, 0.0, 1.875 * deltaTime * speed);
        }
        if (input.isKeyDown(Constants.KEY_D)) {
            moveNoUp(1.875 * deltaTime * speed, 0.0, 0.0);
        } else if (input.isKeyDown(Constants.KEY_A)) {
            moveNoUp(-1.875 * deltaTime * speed, 0.0, 0.0);
        }


        var m = Matrix(f32, 4).rotateY(camera_rotation_euler[1]);
        m = m.mul(Matrix(f32, 4).translate(Vector(f32, 3).init([3]f32
            {camera_position[0], camera_position[1]-0.4, camera_position[2]}
        )));
        spotlight.setTransform(m);

        // Levitation (does not take camera rotation into account)

        if (input.isKeyDown(Constants.KEY_SPACE)) {
            camera_position[1] += 1.875 * deltaTime * speed;
        } else if (input.isKeyDown(Constants.KEY_LEFT_SHIFT)) {
            camera_position[1] -= 1.875 * deltaTime * speed;
        }

        // Transforms must be done in this order:
        // Scale
        // Rotate x
        // Rotate y
        // Rotate z
        // Translation
        m = Matrix(f32, 4).rotateX(camera_rotation_euler[0]);
        m = m.mul(Matrix(f32, 4).rotateY(camera_rotation_euler[1]));
        m = m.mul(Matrix(f32, 4).rotateZ(camera_rotation_euler[2]));
        m = m.mul(Matrix(f32, 4).translate(Vector(f32, 3).init(camera_position)));
        camera.setTransform(m);

        // Use deltaTime to make rotation speed consistent, regardless of frame rate.
        rotation += deltaTime*0.1;
        windmill_blades.?.setTransform(Matrix(f32, 4).rotateZ(rotation)
            .mul(windmill_blades_default_transform));

        try render.render(&root_object, micro_time, c_allocator);

        window.swapBuffers();
        window.pollEvents();
    }
}
