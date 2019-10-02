const std = @import("std");
const AnimationData = @import("../ModelFiles/AnimationFiles.zig").AnimationData;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const Asset = @import("../Assets/Assets.zig").Asset;
const ShaderInstance = @import("Shader.zig").ShaderInstance;
const Mesh = @import("Mesh.zig").Mesh;

var matrix_buffer: ?[]f32 = null;
extern var this_frame_time: u64;

pub fn allocateStaticData(allocator: *std.mem.Allocator) !void {
    matrix_buffer = try allocator.alloc(f32, 128 * 4 * 4);
}

pub const Animation = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},
    asset: ?*Asset = null,

    active_animation: ?*AnimationData = null,
    animation_start_time: u64 = 0,

    pub fn init() Animation {
        return Animation{};
    }

    fn detatchAsset(self: *Animation, free_if_unused: bool) void {
        if(self.asset != null) {
            self.asset.?.ref_count.dec();
            if(free_if_unused and self.asset.?.ref_count.n == 0) {
                self.asset.?.free(false);
            }
            self.asset = null;
        }
    }

    pub fn playAnimationFromAsset(self: *Animation, asset: *Asset) !void {
        if(asset.asset_type != Asset.AssetType.Animation) {
            return error.InvalidAssetType;
        }
        if(asset.state != Asset.AssetState.Ready) {
            return error.InvalidAssetState;
        }

        self.playAnimation(&asset.animation.?);
        self.asset = asset;
        asset.ref_count.inc();
    }

    pub fn playAnimation(self: *Animation, animation_data: ?*AnimationData) void {
        self.detatchAsset(false);
        self.animation_start_time = this_frame_time;
        self.active_animation = animation_data;
    }

    // Used during render - do not call this function
    pub fn setAnimationMatrices(self: *Animation, shader: *const ShaderInstance, mesh: *Mesh) !void {
        if (self.active_animation != null) {
            const time_difference = this_frame_time - self.animation_start_time;
            var frame_index = @intCast(u32, time_difference / (self.active_animation.?.frame_duration));
            if (time_difference % self.active_animation.?.frame_duration >= time_difference / 2) {
                frame_index += 1;
            }

            frame_index = frame_index % self.active_animation.?.*.frame_count;

            var bone_i: u32 = 0;
            var bone_o: u32 = 0;
            while (bone_i < mesh.model.bone_count) : (bone_i += 1) {
                const name = mesh.model.getBoneName(&bone_o) catch break;
                const animation_bone_index = self.active_animation.?.*.getBoneIndex(name) catch continue;

                // TODO optimise to avoid copy
                // ^ have animation files store data for all bones even if not animated so data for each frame can be uploaded directly
                const animation_bone_matrix_offset = (frame_index * self.active_animation.?.*.bone_count + animation_bone_index) * 4 * 4;
                std.mem.copy(f32, matrix_buffer.?[bone_i * 4 * 4 .. (bone_i + 1) * 4 * 4], self.active_animation.?.*.matrices_absolute[animation_bone_matrix_offset .. animation_bone_matrix_offset + 4 * 4]);
            }
        } else {
            // No animation, fill with identity matrices

            // TODO create array of identity matrices in vram in allocateStaticData and use that to avoid copy
            // TODO ^ or maybe allocate when first needed
            var bone_i: u32 = 0;
            while (bone_i < 128) : (bone_i += 1) {
                std.mem.copy(f32, matrix_buffer.?[bone_i * 4 * 4 .. bone_i * 4 * 4 + 4 * 4], [16]f32{
                    1.0, 0.0, 0.0, 0.0,
                    0.0, 1.0, 0.0, 0.0,
                    0.0, 0.0, 1.0, 0.0,
                    0.0, 0.0, 0.0, 1.0,
                });
            }
        }

        try shader.setBoneMatrices(matrix_buffer.?);
    }

    pub fn deinit(self: *Animation) void {
        self.ref_count.deinit();
        self.detatchAsset(true);
        self.active_animation = null;
    }

    pub fn freeIfUnused(self: *Animation) void {
        if(self.ref_count.n != 0) {
            return;
        }

        self.deinit();
    }
};
