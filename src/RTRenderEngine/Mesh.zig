const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const ModelData = @import("../ModelFiles/ModelFiles.zig").ModelData;
const VertexAttributeType = ModelData.VertexAttributeType;
const Buffer = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").Buffer;
const VertexMeta = @import("../WindowGraphicsInput/WindowGraphicsInput.zig").VertexMeta;
const ShaderInstance = @import("Shader.zig").ShaderInstance;
const Matrix = @import("../Mathematics/Mathematics.zig").Matrix;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const Texture2D = @import("Texture2D.zig").Texture2D;
const Animation = @import("Animation.zig").Animation;
const rtrenderengine = @import("RTRenderEngine.zig");
const getSettings = rtrenderengine.getSettings;
const min = std.math.min;
const ReferenceCounter = @import("../RefCount.zig").ReferenceCounter;
const Asset = @import("../Assets/Assets.zig").Asset;

pub const Mesh = struct {
    ref_count: ReferenceCounter = ReferenceCounter{},
    asset: ?*Asset = null,

    vertex_data_buffer: Buffer,
    index_data_buffer: ?Buffer,
    modifiable: bool,
    model: *ModelData,

    pub fn initFromAsset(asset: *Asset, modifiable: bool) !Mesh {
        if (asset.asset_type != Asset.AssetType.Model) {
            return error.InvalidAssetType;
        }
        if (asset.state != Asset.AssetState.Ready) {
            return error.InvalidAssetState;
        }

        var m = try init(&asset.model.?, modifiable);
        m.asset = asset;
        asset.ref_count.inc();
        return m;
    }

    // model object must remain valid for as long as this mesh object is valid
    // model.data can be freed however. That data will not be used again.
    // when_unused is caleld when the mesh is no longer being used by any mesh renderer
    pub fn init(model: *ModelData, modifiable: bool) !Mesh {
        VertexMeta.unbind();

        var vbuf: Buffer = try Buffer.init();
        errdefer vbuf.free();
        try vbuf.upload(Buffer.BufferType.VertexData, @sliceToBytes(model.vertex_data.?), modifiable);

        var ibuf: ?Buffer = null;
        if (model.*.index_count > 0) {
            ibuf = try Buffer.init();
            errdefer ibuf.?.free();
            if (model.indices_u16 != null) {
                try ibuf.?.upload(Buffer.BufferType.IndexData, @sliceToBytes(model.indices_u16.?), modifiable);
            } else {
                try ibuf.?.upload(Buffer.BufferType.IndexData, @sliceToBytes(model.indices_u32.?), modifiable);
            }
        }

        return Mesh{
            .vertex_data_buffer = vbuf,
            .index_data_buffer = ibuf,
            .modifiable = modifiable,
            .model = model,
        };
    }

    pub fn uploadVertexData(self: *Mesh, offset: u32, data: []const u8) !void {
        if (!self.modifiable) {
            return error.ReadOnlyMesh;
        }

        try self.vertex_data_buffer.uploadRegion(Buffer.BufferType.VertexData, data, offset, true);
    }

    pub fn uploadIndexData(self: *Mesh, offset: u32, data: []const u8) !void {
        if (!self.modifiable) {
            return error.ReadOnlyMesh;
        }
        if (self.index_data_buffer == null) {
            return error.NoIndices;
        }

        try self.index_data_buffer.?.uploadRegion(Buffer.BufferType.IndexData, data, offset, true);
    }

    fn free_(self: *Mesh) void {
        self.ref_count.deinit();
        self.vertex_data_buffer.free();
        if (self.index_data_buffer != null) {
            self.index_data_buffer.?.free();
        }
    }

    // Does not delete the model
    pub fn free(self: *Mesh) void {
        self.free_();
        self.asset = null;
    }

    pub fn freeIfUnused(self: *Mesh) void {
        if (self.asset != null and self.ref_count.n == 0) {
            self.ref_count.deinit();
            self.free_();

            self.asset.?.ref_count.dec();
            if (self.asset.?.ref_count.n == 0) {
                self.asset.?.free(false);
            }
            self.asset = null;
        }
    }
};
