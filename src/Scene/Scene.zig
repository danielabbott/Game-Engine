const std = @import("std");
const assert = std.debug.assert;
const render = @import("../RTRenderEngine/RTRenderEngine.zig");
const loadFile = @import("../Files.zig").loadFile;
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const assets = @import("../Assets/Assets.zig");
const Asset = assets.Asset;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const image = wgi.image;
const Texture2D = render.Texture2D;

pub fn getAmbient(file_data: []align(4) const u8, ambient: *[3]f32) void {
    const scene_file_f32 = @bytesToSlice(f32, file_data);
    ambient.*[0] = scene_file_f32[1];
    ambient.*[1] = scene_file_f32[2];
    ambient.*[2] = scene_file_f32[3];
}

pub fn getClearColour(file_data: []align(4) const u8, c: *[3]f32) void {
    const scene_file_f32 = @bytesToSlice(f32, file_data);
    c.*[0] = scene_file_f32[4];
    c.*[1] = scene_file_f32[5];
    c.*[2] = scene_file_f32[6];
}

pub fn getAssets(file_data: []align(4) const u8, assets_list: *std.ArrayList(Asset)) !void {
    const scene_file_u32 = @bytesToSlice(u32, file_data);
    const scene_file_f32 = @bytesToSlice(f32, file_data);

    if (scene_file_u32[0] != 0x1a98fd34) {
        return error.InvalidMagic;
    }

    const num_assets = scene_file_u32[8];
    if (num_assets > 10000) {
        return error.TooManyAssets;
    }

    var assets_list_original_size = assets_list.*.count();
    try assets_list.resize(assets_list_original_size + num_assets);

    errdefer {
        // Put list back how it was
        // This cannot fail as we are shrinking the list
        assets_list.resize(assets_list_original_size) catch unreachable;
    }

    var i: u32 = 0;
    var offset: u32 = 9;
    while (i < num_assets) {
        const stringLen = @intCast(u8, scene_file_u32[offset] & 0xff);

        const asset_file_path = file_data[(offset * 4 + 1)..(offset * 4 + 1 + stringLen)];

        assets_list.*.toSlice()[assets_list_original_size + i] = try Asset.init(asset_file_path);

        offset += (1 + stringLen + 3) / 4;

        i += 1;
    }
}

// Returns root object
// Assets must be in the ready state
// Assets slie must point to the assets loaded by getAssets or the wrong assets will be used
pub fn loadSceneFromFile(file_data: [] align(4) const u8, assets_list: []Asset, allocator: *std.mem.Allocator) !*render.Object {
    if(file_data.len % 4 != 0) {
        return error.InvalidFile;
    }

    const scene_file_u32 = @bytesToSlice(u32, file_data);
    const scene_file_f32 = @bytesToSlice(f32, file_data);

    if(scene_file_u32[0] != 0x1a98fd34) {
        return error.InvalidMagic;
    }

    var offset: u32 = 9 + scene_file_u32[7];

    var root_object = try allocator.create(render.Object);
    errdefer allocator.destroy(root_object);
    root_object.* = render.Object{
        .name = "scnrootxxxxxxxxx",
        .name_length = 7,
    };

    // Mesh objects
    
    const num_meshes = scene_file_u32[offset];
    offset += 1;

    var meshes = std.ArrayList(?*render.Mesh).init(allocator);
    defer meshes.deinit();
    try meshes.resize(num_meshes);

    var i: u32 = 0;
    while (i < num_meshes) : (i += 1) {
        const asset_index = scene_file_u32[offset];
        const modifiable = scene_file_u32[offset+1] != 0;
        offset += 2;

        const asset = &assets_list[asset_index];

        if(@intCast(usize, asset_index) < assets_list.len and asset.asset_type == Asset.AssetType.Model) {
            var mesh = try allocator.create(render.Mesh);
            errdefer allocator.destroy(mesh);

            mesh.* = try render.Mesh.initFromAsset(asset, modifiable);
            asset.ref_count.inc();
            errdefer { 
                mesh.*.free(); 
                asset.ref_count.dec();
            }

            meshes.toSlice()[i] = mesh;
        }
        else {
            meshes.toSlice()[i] = null;
        }
    }

    // Textures (untested)
    
    const num_textures = scene_file_u32[offset];
    offset += 1;

    var textures = std.ArrayList(?*Texture2D).init(allocator);
    defer textures.deinit();
    try textures.resize(num_textures);

    i = 0;
    while (i < num_textures) : (i += 1)  {
        const asset_index = scene_file_u32[offset];
        const modifiable = scene_file_u32[offset+1] != 0;
        const smooth_when_magnified = scene_file_u32[offset+2] != 0;
        const min_filter = @intToEnum(image.MinFilter, @intCast(i32, std.math.min(5, scene_file_u32[offset+3])));
        offset += 4;

        const asset = &assets_list[asset_index];

        if(@intCast(usize, asset_index) < assets_list.len and 
            (asset.asset_type == Asset.AssetType.Texture or
                asset.asset_type == Asset.AssetType.RGB10A2Texture)) {
            
            var texture = try allocator.create(Texture2D);
            errdefer allocator.destroy(texture);

            texture.* = try Texture2D.loadFromAsset(asset);
            errdefer texture.*.free(); 

            if(asset.asset_type == Asset.AssetType.RGB10A2Texture) {
                try texture.texture.upload(asset.texture_width.?, asset.texture_height.?, asset.texture_type.?, asset.rgb10a2_data.?);
            }
            else {
                try texture.texture.upload(asset.texture_width.?, asset.texture_height.?, asset.texture_type.?, asset.data.?);
            }

            textures.toSlice()[i] = texture;
        }
        else {
            textures.toSlice()[i] = null;
        }
    }

    // Game objects

    const num_objects = scene_file_u32[offset];
    offset += 1;

    var objects_list = std.ArrayList(*render.Object).init(allocator);
    defer objects_list.deinit();
    try objects_list.ensureCapacity(num_objects);

    i = 0;
    while (i < num_objects) : (i += 1)  {
        var o = try allocator.create(render.Object);
        errdefer allocator.destroy(o);
        try objects_list.append(o);
        o.* = render.Object{};

        var name_i: u32 = 0;
        while(name_i < 16 and file_data[offset*4+name_i] != 0) : (name_i += 1) {
            o.name[name_i] = file_data[offset*4+name_i];
        }
        o.name_length = name_i;

        offset += 4;

        const parent = scene_file_u32[offset];
        const has_mesh_renderer = scene_file_u32[offset+1] != 0;
        const has_light = scene_file_u32[offset+2] != 0;
        o.is_camera = scene_file_u32[offset+3] != 0;
        o.inherit_parent_transform = scene_file_u32[offset+4] != 0;
        offset += 5;

        o.*.transform.loadFromSlice(scene_file_f32[offset .. offset+16]) catch unreachable;
        offset += 16;


        if(has_mesh_renderer) {
            const mesh_index = scene_file_u32[offset];
            offset += 1;

            if(mesh_index < meshes.count() and meshes.toSlice()[mesh_index] != null) {
                // TODO scene file should have list of mesh renderers
                // TODO return resource lists to caller
                var mesh_renderer = try allocator.create(render.MeshRenderer);
                errdefer allocator.destroy(mesh_renderer);
                mesh_renderer.* = try render.MeshRenderer.init(meshes.toSlice()[mesh_index].?, allocator);
                o.setMeshRenderer(mesh_renderer);

                // Materials

                var j: u32 = 0;
                while(j < 32) : (j += 1) {
                    const tex = scene_file_u32[offset+0];
                    const norm = scene_file_u32[offset+1];
                    offset += 2;

                    if(tex < textures.count() and textures.toSlice()[tex] != null) {
                        o.mesh_renderer.?.materials[j].setTexture(textures.toSlice()[tex].?);
                    }
                    if(norm < textures.count() and textures.toSlice()[norm] != null) {
                        o.mesh_renderer.?.materials[j].setNormalMap(textures.toSlice()[norm].?);
                    }

                    o.mesh_renderer.?.materials[j].specular_size = scene_file_f32[offset+0];
                    o.mesh_renderer.?.materials[j].specular_intensity = scene_file_f32[offset+1];
                    o.mesh_renderer.?.materials[j].specular_colourisation = scene_file_f32[offset+2];
                    offset += 3;
                }
            }
        }

        if(has_light) {
            const light_type_ = scene_file_u32[offset];
            offset += 1;

            var light_type: render.Light.LightType = undefined;
            if(light_type_ == 0) {
                light_type = render.Light.LightType.Point;
            }
            else if(light_type_ == 1) {
                light_type = render.Light.LightType.Spotlight;
            }
            else {
                light_type = render.Light.LightType.Directional;
            }

            const r = scene_file_f32[offset];
            const g = scene_file_f32[offset+1];
            const b = scene_file_f32[offset+2];

            const cast_shadows = scene_file_f32[offset+3] != 0;

            const clip_start = scene_file_f32[offset+4];
            const clip_end = scene_file_f32[offset+5];

            offset += 6;

            var angle: f32 = 0;
            if(light_type == render.Light.LightType.Spotlight) {
                angle = scene_file_f32[offset];
                offset += 1;
            }
            
            o.*.light = render.Light{
                .light_type = light_type,
                .angle = angle,
                .colour = [3]f32{ r, g, b },
                .attenuation = 1.0,
                .cast_realtime_shadows = cast_shadows,
                .shadow_near = clip_start,
                .shadow_far = clip_end,
                .shadow_width = 30.0,
                .shadow_height = 30.0,
            };
        }

        if(parent != 0xffffffff and parent < objects_list.count()-1) {
            try objects_list.toSlice()[parent].*.addChild(o);
        }
        else {
            try root_object.addChild(o);
        }
    }


    return root_object;

}
