const std = @import("std");
const AnimationData = @import("../ModelFiles/AnimationFiles.zig").AnimationData;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const Asset = @import("../Assets/Assets.zig").Asset;
const ShaderInstance = @import("Shader.zig").ShaderInstance;
const Mesh = @import("Mesh.zig").Mesh;
const ModelData = @import("../ModelFiles/ModelFiles.zig").ModelData;

var identity_matrix_buffer: ?[]f32 = null;
extern var this_frame_time: u64;

pub const Animation = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},
    animation_asset: ?*Asset = null,
    model_asset: ?*Asset = null,

    animation_data: *AnimationData,
    model: *ModelData,

    animation_start_time: u64 = 0,

    matrices: [] f32,
    allocator: *std.mem.Allocator,

    paused: bool = false,
    paused_at_time: u64 = 0,

    fn create_matrices(animation_data: *AnimationData, model: *ModelData, allocator: *std.mem.Allocator) ![]f32 {
        const num_frames = animation_data.frame_count;

        var matrices = try allocator.alloc(f32, num_frames * model.bone_count * 4 * 4);

        var frame_index: u32 = 0;
        while(frame_index < num_frames) : (frame_index += 1) {
            var bone_i: u32 = 0;
            var bone_o: u32 = 0; // offset into bones data used by getBoneName
            while (bone_i < model.bone_count) : (bone_i += 1) {
                const name = model.getBoneName(&bone_o) catch break;
                const animation_bone_index = animation_data.*.getBoneIndex(name) catch continue;

                const animation_bone_matrix_offset = (frame_index * animation_data.bone_count + animation_bone_index) * 4 * 4;
                const o = (frame_index * model.bone_count + bone_i) * 4 * 4;
                std.mem.copy(f32, matrices[o .. o + 4 * 4], animation_data.matrices_absolute[animation_bone_matrix_offset .. animation_bone_matrix_offset + 4 * 4]);
            }
        }

        return matrices;
    }

    pub fn init(animation_data: *AnimationData, model: *ModelData, allocator: *std.mem.Allocator) !Animation {
        if(model.attributes_bitmap & (1 << @enumToInt(ModelData.VertexAttributeType.BoneIndices)) == 0
                or model.bone_count == 0) {
            return error.MeshNasNoBones;
        }

        var matrices = try create_matrices(animation_data, model, allocator);
       
        return Animation {
            .animation_data = animation_data,
            .model = model,
            .matrices = matrices,
            .allocator = allocator,
            .animation_start_time = this_frame_time
        };
    }

    pub fn initFromAssets(animation_asset: *Asset, model_asset: *Asset, allocator: *std.mem.Allocator) !Animation {
        if(animation_asset.asset_type != Asset.AssetType.Animation
                or model_asset.asset_type != Asset.AssetType.Model) {
            return error.InvalidAssetType;
        }
        if(animation_asset.state != Asset.AssetState.Ready or model_asset.state != Asset.AssetState.Ready) {
            return error.InvalidAssetState;
        }

        var a = try init(&animation_asset.animation.?, &model_asset.model.?, allocator);
        
        a.animation_asset = animation_asset;
        a.model_asset = model_asset;

        animation_asset.ref_count.inc();
        animation_asset.ref_count2.inc();
        model_asset.ref_count.inc();

        return a;
    }

    fn detatchAssets(self: *Animation, free_if_unused: bool) void {
        if(self.animation_asset != null) {
            self.animation_asset.?.ref_count.dec();
            if(free_if_unused and self.animation_asset.?.ref_count.n == 0) {
                self.animation_asset.?.free(false);
            }
            self.animation_asset = null;
        }
        if(self.model_asset != null) {
            self.model_asset.?.ref_count.dec();
            if(free_if_unused and self.model_asset.?.ref_count.n == 0) {
                self.model_asset.?.free(false);
            }
            self.model_asset = null;
        }
    }

    pub fn play(self: *Animation) void {
        self.animation_start_time = this_frame_time;
    }

    pub fn pause(self: *Animation) void {
        if(self.paused == false) {
            self.paused = true;
            self.paused_at_time = this_frame_time;
        }
    }

    pub fn unpause(self: *Animation) void {
        if(self.paused == true) {
            self.paused = false;
            self.animation_start_time += this_frame_time-self.paused_at_time;
        }
    }


    // Used during render - do not call this function
    pub fn setAnimationMatrices(self: *Animation, shader: *const ShaderInstance, model: *ModelData) !void {
        if(model.bone_count != self.model.bone_count) {
            return error.ModelNotCompatible;
        }

        var now: u64 = this_frame_time;
        if(self.paused) {
            now = self.paused_at_time;
        }

        const time_difference = now - self.animation_start_time;
        var frame_index = @intCast(u32, time_difference / (self.animation_data.frame_duration));
        if (time_difference % self.animation_data.frame_duration >= time_difference / 2) {
            frame_index += 1;
        }

        frame_index = frame_index % self.animation_data.frame_count;
        const o = frame_index*model.bone_count*4*4;

        try shader.setBoneMatrices(self.matrices[o.. o + model.bone_count*4*4]);
    }

    pub fn setAnimationIdentityMatrices(shader: *const ShaderInstance, allocator: *std.mem.Allocator) !void {
        if(identity_matrix_buffer == null) {
            identity_matrix_buffer = try allocator.alloc(f32, 128*4*4);

            var bone_i: u32 = 0;
            while (bone_i < 128) : (bone_i += 1) {
                std.mem.copy(f32, identity_matrix_buffer.?[bone_i * 4 * 4 .. bone_i * 4 * 4 + 4 * 4], [16]f32{
                    1.0, 0.0, 0.0, 0.0,
                    0.0, 1.0, 0.0, 0.0,
                    0.0, 0.0, 1.0, 0.0,
                    0.0, 0.0, 0.0, 1.0,
                });
            }
        }
        try shader.setBoneMatrices(identity_matrix_buffer.?);
    }

    pub fn deinit(self: *Animation) void {
        self.ref_count.deinit();
        self.detatchAssets(false);
        self.allocator.free(self.matrices);
    }

    pub fn freeIfUnused(self: *Animation) void {
        if(self.ref_count.n != 0) {
            return;
        }

        self.ref_count.deinit();
        self.detatchAssets(true);
        self.allocator.free(self.matrices);
    }
};
