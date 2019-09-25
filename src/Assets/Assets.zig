const std = @import("std");
const assert = std.debug.assert;
const loadFile = @import("../Files.zig").loadFile;
const compress = @import("../Compress/Compress.zig");
const ModelData = @import("../ModelFiles/ModelFiles.zig").ModelData;
const AnimationData = @import("../ModelFiles/AnimationFiles.zig").AnimationData;
const wgi = @import("../WindowGraphicsInput/WindowGraphicsInput.zig");
const ConditionVariable = @import("../ConditionVariable.zig").ConditionVariable;

var assets_directory: ?[]const u8 = null;


// dir should be a global constant and not be changed again
pub fn setAssetsDirectory(dir: []const u8) void {
    assets_directory = dir;
}

// Static buffer used for appending asset file path to global asset directory path
var path: [256]u8 = undefined;

pub const Asset = struct {

    pub const AssetType = enum {
        Model,
        Texture,
        RGB10A2Texture,
        Animation,
        // Shader
    };

    // If true freeData does nothing
    const asset_type_keep_data_on_cpu = [_]bool {
        false,
        false,
        false,
        true
    };

    pub const AssetState = enum {
        NotLoaded, // Default state
        Loaded, // File read from HDD/SDD, ready for decompression
        Ready, // Asset is loaded and ready for use
        Freed, // Data has been freed
    };

    file_path: [32]u8,
    file_path_len: u32,

    asset_type: AssetType,
    compressed: bool, // if true then this is a *.compressed file
    state: AssetState,
    data: ?[]align(4) u8,

    // -- Configuration variables --

    // if asset_type == AssetType.Texture
    texture_channels: u32 = 0,

    // -- Asset (meta)data --

    // if asset_type == AssetType.Model
    model: ?ModelData,

    // if asset_type == AssetType.Animation
    animation: ?AnimationData,

    // if asset_type == AssetType.Texture or asset_type == AssetType.RGB10A2Texture
    texture_width: ?u32,
    texture_height: ?u32,
    texture_type: ?wgi.image.ImageType,

    // if asset_type == AssetType.RGB10A2Texture
    rgb10a2_data: ?[]u8,

    // file_path_ is copied into the returned Asset struct
    // Don't forget to set the relvant configuration variables
    pub fn init(file_path_: []const u8) !Asset {
        if(file_path_.len > 32) {
            return error.PathTooLong;
        }

        var file_path = file_path_;

        var compressed = false;
        if (file_path.len >= 11 and std.mem.compare(u8, file_path[file_path.len - 11 ..], ".compressed") == std.mem.Compare.Equal) {
            compressed = true;
            file_path = file_path[0 .. file_path.len - 11];
        }

        var asset_type: AssetType = undefined;

        if (file_path.len >= 6 and std.mem.eql(u8, file_path[file_path.len - 6 ..], ".model")) {
            asset_type = AssetType.Model;
        }
        else if (file_path.len >= 5 and std.mem.eql(u8, file_path[file_path.len - 5 ..], ".anim")) {
            asset_type = AssetType.Animation;
        } else if (file_path.len >= 4 and std.mem.eql(u8, file_path[file_path.len - 4 ..], ".png")) {
            asset_type = AssetType.Texture;
        } else if (file_path.len >= 4 and std.mem.eql(u8, file_path[file_path.len - 4 ..], ".jpg")) {
            asset_type = AssetType.Texture;
        } else if (file_path.len >= 4 and std.mem.eql(u8, file_path[file_path.len - 4 ..], ".tga")) {
            asset_type = AssetType.Texture;
        } else if (file_path.len >= 4 and std.mem.eql(u8, file_path[file_path.len - 4 ..], ".bmp")) {
            asset_type = AssetType.Texture;
        } else if (file_path.len >= 8 and std.mem.eql(u8, file_path[file_path.len - 8 ..], ".rgb10a2")) {
            asset_type = AssetType.RGB10A2Texture;
        }
        // else if(file_path.len >= 3 and  std.mem.eql(u8,
        //     file_path[file_path.len-3..], ".vs")) {
        //     asset_type = AssetType.Shader;
        // }
        // else if(file_path.len >= 3 and  std.mem.eql(u8,
        //     file_path[file_path.len-3..], ".fs")) {
        //     asset_type = AssetType.Shader;
        // }
        // else if(file_path.len >= 5 and  std.mem.eql(u8,
        //     file_path[file_path.len-5..], ".glsl")) {
        //     asset_type = AssetType.Shader;
        // }
        else {
            return error.UnknownAssetType;
        }

        var a = Asset{
            .file_path = undefined,
            .file_path_len = 0,
            .asset_type = asset_type,
            .compressed = compressed,
            .state = AssetState.NotLoaded,
            .model = null,
            .animation = null,
            .data = null,
            .texture_width = null,
            .texture_height = null,
            .rgb10a2_data = null,
            .texture_type = null,
        };

        std.mem.copy(u8, a.file_path[0..], file_path_);
        a.file_path_len = @intCast(u32, file_path_.len);
        return a;
    }

    pub fn load(self: *Asset, allocator: *std.mem.Allocator) !void {
        if (self.state != AssetState.NotLoaded) {
            return error.InvalidState;
        }

        if(assets_directory == null) {
            self.data = try loadFile(self.file_path[0..self.file_path_len], allocator);
        }
        else {
            const n = std.fmt.bufPrint(path[0..], "{}{}", assets_directory, self.file_path[0..self.file_path_len]) catch unreachable;
            self.data = try loadFile(n, allocator);
        }
        self.state = AssetState.Loaded;
    }

    // Use same allocator as was used for load()
    pub fn decompress(self: *Asset, allocator: *std.mem.Allocator) !void {
        if (self.state != AssetState.Loaded or self.data == null) {
            return error.InvalidState;
        }

        if (self.compressed) {
            const newData = try compress.decompress(self.data.?, allocator);
            allocator.free(self.data.?);
            self.data = newData;
        }

        if (self.asset_type == AssetType.Model) {
            self.model = try ModelData.init(self.data.?, allocator);
        }
        else if (self.asset_type == AssetType.Animation) {
            self.animation = try AnimationData.init(self.data.?);
        } else if (self.asset_type == AssetType.Texture) {
            var w: u32 = 0;
            var h: u32 = 0;
            const newData = try wgi.image.decodeImage(self.data.?, &self.texture_channels, &w, &h, allocator);
            self.texture_width = w;
            self.texture_height = h;
            wgi.image.freeDecodedImage(self.data.?);
            self.data = newData;

            if(self.texture_channels == 3) {
                self.texture_type = wgi.image.ImageType.RGB;
            }
            else if(self.texture_channels == 2) {
                self.texture_type = wgi.image.ImageType.RG;
            }
            else if(self.texture_channels == 1) {
                self.texture_type = wgi.image.ImageType.R;
            }
            else {
                self.texture_type = wgi.image.ImageType.RGBA;
            }
        } else if (self.asset_type == AssetType.RGB10A2Texture) {
            if (self.data.?.len < 16) {
                return error.FileTooSmall;
            }

            const file_data_u32: []u32 = @bytesToSlice(u32, self.data.?);
            if (file_data_u32[0] != 0x62677200 or file_data_u32[1] != 0x32613031) {
                return error.InvalidMagic;
            }

            const w = file_data_u32[2];
            const h = file_data_u32[3];

            if (w == 0 or h == 0 or w > 32768 or h > 32768) {
                return error.InvalidDimensions;
            }

            self.texture_width = w;
            self.texture_height = h;
            self.rgb10a2_data = self.data.?[16..];

            self.texture_type = wgi.image.ImageType.RGB10A2;
        }
        // else if(self.asset_type == AssetType.Shader) {
        // }
        

        self.state = AssetState.Ready;
    }

    // Keeps things such as model file metadata loaded but frees the memory that is typicaly stored in video memory
    // Don't call this if the mesh data is to be freed
    pub fn freeData(self: *Asset, allocator: *std.mem.Allocator) void {
        if (self.state == AssetState.NotLoaded or self.state == AssetState.Freed or self.data == null or asset_type_keep_data_on_cpu[@enumToInt(self.asset_type)]) {
            return;
        }
        allocator.free(self.data.?);
        self.data = null;
    }

    pub fn free(self: *Asset, allocator: *std.mem.Allocator) void {
        if (self.state == AssetState.Ready) {
            if (self.asset_type == AssetType.Model) {
                self.model.?.free(allocator);
            }
        }

        if(self.data != null) {
            allocator.free(self.data.?);
            self.data = null;
        }
        self.state = AssetState.Freed;
    }

};

var assets_to_load = std.atomic.Int(u32).init(0);
var cv: ?ConditionVariable = null;

var assets_to_load_queue: std.atomic.Queue(*Asset) = std.atomic.Queue(*Asset).init();
var assets_to_decompress_queue: std.atomic.Queue(*Asset) = std.atomic.Queue(*Asset).init();

var abort_load = std.atomic.Int(u32).init(0);

// Do not call this while assets are being loaded
pub fn addAssetToQueue(asset: *Asset, allocator: *std.mem.Allocator) !void {
    if(asset.state != Asset.AssetState.NotLoaded) {
        return error.InvalidState;
    }

    var node = try allocator.create(std.atomic.Queue(*Asset).Node);
    node.* = std.atomic.Queue(*Asset).Node.init(asset);

    assets_to_load_queue.put(node);

    _ = assets_to_load.incr();
}

fn fileLoader(allocator: *std.mem.Allocator) void {
    while(abort_load.get() != 1) {
        const asset_node = assets_to_load_queue.get();

        if(asset_node == null) {
            break;
        }
        else {
            asset_node.?.data.*.load(allocator) catch |e| {
                std.debug.warn("Asset '{}' load error: {}\n", asset_node.?.data.file_path[0..asset_node.?.data.file_path_len], e);
                _ = assets_to_load.decr();
                continue;
            };

            assets_to_decompress_queue.put(asset_node.?);
            cv.?.notify();
        }
    }
}

fn assetDecompressor(allocator: *std.mem.Allocator) void {
    while(assets_to_load.get() > 0) {
        const asset = assets_to_decompress_queue.get();

        if(asset == null) {
            cv.?.wait();
        }
        else {
            if(asset.?.data.*.state == Asset.AssetState.Loaded) {
                asset.?.data.*.decompress(allocator) catch |e| {
                    std.debug.warn("Asset '{}' decompress error: {}\n", asset.?.data.file_path[0..asset.?.data.file_path_len], e);
                };
            }

            allocator.destroy(asset);

            if(assets_to_load.decr() == 1) {
                break;
            }
        }
    }
}

pub fn startAssetLoader_(assets_list: ?([]Asset), allocator: *std.mem.Allocator) !void {
    cv = ConditionVariable.init();
    if(assets_list != null) {
        for (assets_list.?) |*a| {
            addAssetToQueue(a, allocator) catch {
                std.debug.warn("Asset {} added to load queue but is already loaded\n", a.file_path[0..a.file_path_len]);
            };
        }
    }
    abort_load.set(0);

    errdefer abort_load.set(1);
    _ = try std.Thread.spawn(allocator, fileLoader);
    _ = try std.Thread.spawn(allocator, assetDecompressor);
}

pub fn startAssetLoader(allocator: *std.mem.Allocator) !void {
    try startAssetLoader_(null, allocator);
}

pub fn startAssetLoader1(assets_list: []Asset, allocator: *std.mem.Allocator) !void {
    try startAssetLoader_(assets_list, allocator);
}

pub fn assetLoaderCleanup() void {
    cv.?.free();
}

pub fn assetsLoaded() bool {
    return assets_to_load.get() == 0;
}

pub fn verifyAllAssetsLoaded(assets_list: []Asset) !void {
    for(assets_list) |a| {
        if(a.state != Asset.AssetState.Ready) {
            return error.AssetLoadError;
        }
    }
    return;
}

test "assets" {
    var asset = try Asset.init("bleh.jpg");
    std.testing.expect(asset.asset_type == Asset.AssetType.Texture);
}
