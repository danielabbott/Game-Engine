const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const Tex2D = wgi.Texture2D;
const Asset = @import("../Assets/Assets.zig").Asset;

// Use the functions in the texture variable for uploading data, changing filtering, etc.
pub const Texture2D = struct {
    // Reference counting in WGI texture object is ignored, only this reference counter is used
    ref_count: ReferenceCounter = ReferenceCounter{},

    texture: Tex2D,
    asset: ?*Asset = null,

    // Allocates gpu-side memory for a texture object
    pub fn init() !Texture2D {
        return Texture2D{ .texture = try Tex2D.init(true, Tex2D.MinFilter.Linear) };
    }

    pub fn loadFromAsset(asset: *Asset) !Texture2D {
        if (asset.asset_type != Asset.AssetType.Texture and asset.asset_type != Asset.AssetType.RGB10A2Texture) {
            return error.InvalidAssetType;
        }
        if (asset.state != Asset.AssetState.Ready) {
            return error.InvalidAssetState;
        }

        asset.ref_count.inc();
        errdefer asset.ref_count.dec();

        var t = try Tex2D.init(false, wgi.MinFilter.Linear);
        errdefer t.free();

        if (asset.asset_type == Asset.AssetType.RGB10A2Texture) {
            try t.upload(asset.texture_width.?, asset.texture_height.?, asset.texture_type.?, asset.rgb10a2_data.?);
        } else {
            try t.upload(asset.texture_width.?, asset.texture_height.?, asset.texture_type.?, asset.data.?);
        }

        return Texture2D{
            .texture = t,
            .asset = asset,
        };
    }

    pub fn free(self: *Texture2D) void {
        self.ref_count.deinit();
        self.texture.free();

        if (self.asset != null) {
            self.asset.?.ref_count.dec();
            self.asset = null;
        }
    }

    pub fn freeIfUnused(self: *Texture2D) void {
        if (self.asset != null and self.ref_count.n == 0) {
            self.ref_count.deinit();
            self.texture.free();

            self.asset.?.ref_count.dec();
            if (self.asset.?.ref_count.n == 0) {
                self.asset.?.free(false);
            }
            self.asset = null;
        }
    }
};
