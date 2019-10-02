const std = @import("std");
const warn = std.debug.warn;
const wgi = @import("WindowGraphicsInput/WindowGraphicsInput.zig");
const window = wgi.window;
const input = wgi.input;
const c = wgi.c;
const Constants = wgi.Constants;
const vertexarray = wgi.vertexarray;
const buffer = wgi.buffer;
const render = @import("RTRenderEngine/RTRenderEngine.zig");
const Texture2D = render.Texture2D;
const ModelData = render.ModelData;
const Animation = render.Animation;
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

var mouse_button_down: bool = false;

fn mouseCallback(button: i32, action: i32, mods: i32) void {
    if (button == 0) {
        mouse_button_down = action != Constants.RELEASE;
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

pub fn main() !void {
    assets.setAssetsDirectory("DemoAssets" ++ Files.path_seperator);

    var assets_list = std.ArrayList(Asset).init(c_allocator);
    defer assets_list.deinit();
    try assets_list.resize(6);

    var minotaur_model_asset = &assets_list.toSlice()[0];
    var minotaur_texture_asset = &assets_list.toSlice()[1];
    var minotaur_normal_map_asset = &assets_list.toSlice()[2];
    var minotaur_texture2_asset = &assets_list.toSlice()[3];
    var minotaur_normal_map2_asset = &assets_list.toSlice()[4];
    var minotaur_animation_asset = &assets_list.toSlice()[5];
    
    minotaur_model_asset.* = try Asset.init("minotaur.model.compressed");
    minotaur_texture_asset.* = try Asset.init("minotaur.png");
    minotaur_texture_asset.texture_channels = 4;
    minotaur_normal_map_asset.* = try Asset.init("minotaur_normal.png");
    minotaur_normal_map_asset.texture_channels = 4;
    minotaur_texture2_asset.* = try Asset.init("minotaur2.png");
    minotaur_texture2_asset.texture_channels = 4;
    minotaur_normal_map2_asset.* = try Asset.init("minotaur_normal2.png");
    minotaur_normal_map2_asset.texture_channels = 4;
    minotaur_animation_asset.* = try Asset.init("minotaur_idle.anim.compressed");

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

    try assets.startAssetLoader1(assets_list.toSlice(), c_allocator);
    defer assets.assetLoaderCleanup();

    try window.createWindow(fullscreen, 1024, 768, c"Example application 2 - Minotaur", true, 0);
    defer window.closeWindow();
    input.setKeyCallback(keyCallback);
    window.setResizeable(true);

    input.setMouseButtonCallback(mouseCallback);

    try render.init(wgi.getMicroTime(), c_allocator);
    defer render.deinit(c_allocator);

    const settings = render.getSettings();
    settings.max_fragment_lights = 1;
    settings.max_vertex_lights = 0;
    settings.post_process_enabled = true;
    settings.ambient[0] = 0.1;
    settings.ambient[1] = 0.1;
    settings.ambient[2] = 0.1;
    settings.clear_colour[0] = 0.5;
    settings.clear_colour[1] = 0.5;
    settings.clear_colour[2] = 0.5;

    settings.enable_directional_lights = false;
    settings.enable_spot_lights = false;
    settings.enable_shadows = false;

    var root_object: render.Object = render.Object.init("root");

    // Deletes all objects and frees all resources
    defer root_object.delete(true);

    var camera: render.Object = render.Object.init("camera");
    try root_object.addChild(&camera);
    camera.is_camera = true;
    camera.transform = Matrix(f32, 4).translate(Vector(f32, 3).init([3]f32{0, 1, 5}));

    var light: render.Object = render.Object.init("light");
    light.light = render.Light{
        .light_type = render.Light.LightType.Point,
        .colour = [3]f32{ 100.0, 100.0, 100.0 },
        .attenuation = 0.8,
        .cast_realtime_shadows = false,
    };
    light.transform = Matrix(f32, 4).translate(Vector(f32, 3).init([3]f32{ 4.0, 4.0, 1.0 }));
    try root_object.addChild(&light);

    // Wait for game assets to finish loading

    while (!assets.assetsLoaded()) {
        window.pollEvents();
        if (window.windowShouldClose()) {
            return;
        }
        std.time.sleep(100000000);
    }

    for(assets_list.toSlice()) |*a| {
        if(a.state != Asset.AssetState.Ready) {
            return error.AssetLoadError;
        }
    }

    var minotaur_object = render.Object.init("minotaur");

    var minotaur_mesh: render.Mesh = try render.Mesh.initFromAsset(minotaur_model_asset, false);

    var t = try Texture2D.loadFromAsset(minotaur_texture_asset);
    var t2 = try Texture2D.loadFromAsset(minotaur_normal_map_asset);
    var t3 = try Texture2D.loadFromAsset(minotaur_texture2_asset);
    var t4 = try Texture2D.loadFromAsset(minotaur_normal_map2_asset);

    var minotaur_mesh_renderer = try render.MeshRenderer.init(&minotaur_mesh, c_allocator);
    minotaur_object.setMeshRenderer(&minotaur_mesh_renderer);

    // Body
    minotaur_object.mesh_renderer.?.materials[1].setTexture(&t);
    minotaur_object.mesh_renderer.?.materials[1].setNormalMap(&t2);
    minotaur_object.mesh_renderer.?.materials[1].specular_intensity = 10.0;
    // Clothes
    minotaur_object.mesh_renderer.?.materials[0].setTexture(&t3);
    minotaur_object.mesh_renderer.?.materials[0].setNormalMap(&t4);
    minotaur_object.mesh_renderer.?.materials[0].specular_intensity = 0.0;

    var animation_object = Animation.init();
    try animation_object.playAnimationFromAsset(minotaur_animation_asset);
    minotaur_object.mesh_renderer.?.setAnimationObject(&animation_object);

    try root_object.addChild(&minotaur_object);

    // Free assets (data has been uploaded the GPU)
    for(assets_list.toSlice()) |*a| {
        a.freeData();
    }

    // -

    var mouse_pos_prev: [2]i32 = input.getMousePosition();

    var last_frame_time = wgi.getMicroTime();
    var last_fps_print_time = last_frame_time;
    var fps_count: u32 = 0;

    var brightness: f32 = 1.0;
    var contrast: f32 = 1.0;

    var model_rotation: f32 = 0.0;

    // Game loop

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
            brightness -= 0.06;

            if (brightness < 0.0) {
                brightness = 0.0;
            }
        } else if (input.isKeyDown(Constants.KEY_RIGHT_BRACKET)) {
            brightness += 0.06;
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

        const mouse_pos = input.getMousePosition();
        if (mouse_button_down) {
            // Rotate minotaur to in direction of mouse cursor
            model_rotation += @intToFloat(f32, mouse_pos[0] - mouse_pos_prev[0]) * deltaTime;
            minotaur_object.transform = Matrix(f32, 4).rotateY(model_rotation);
        }
        mouse_pos_prev = mouse_pos;

        try render.render(&root_object, micro_time, c_allocator);

        window.swapBuffers();
        window.pollEvents();
    }
}
