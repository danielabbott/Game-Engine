const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const mem = std.mem;

pub const AnimationData = struct {
    frame_count: u32,
    frame_duration: u32, // microseconds
    bone_count: u32,
    bone_names: []const u8,
    matrices_relative: []const f32,
    matrices_absolute: []const f32,

    // This struct references (read-only) the data until delete is called (unless this function returns with an error)
    pub fn init(data: []align(4) const u8) !AnimationData {
        if (data.len < 16) {
            warn("AnimationData.init: Data length is only {}\n", .{data.len});
            return error.FileTooSmall;
        }

        if (data.len % 4 != 0) {
            return error.InvalidFileSize;
        }

        const data_u32 = std.mem.bytesAsSlice(u32, data);
        const data_f32 = std.mem.bytesAsSlice(f32, data);

        if (data_u32[0] != 0xee334507) {
            warn("AnimationData.init: Magic field incorrect. Value was {}\n", .{data_u32[0]});
            return error.NotAnAnimationFile;
        }

        const frame_count = data_u32[1];
        const frame_duration = data_u32[2];
        const bone_count = data_u32[3];

        var overflow_bits: u32 = undefined;
        if (@mulWithOverflow(u32, frame_duration, frame_count, &overflow_bits)) {
            return error.AnimationTooLong;
        }

        var offset: u32 = 4;

        if (4 + bone_count > data_u32.len) {
            return error.FileTooSmall;
        }

        const bone_names_list_start = offset;

        var i: u32 = 0;
        while (i < bone_count) {
            if (offset + 1 > data_u32.len) {
                return error.FileTooSmall;
            }

            const stringLen = data_u32[offset] & 0xff;

            if (offset + (1 + stringLen + 3) / 4 > data_u32.len) {
                return error.FileTooSmall;
            }

            offset += (1 + stringLen + 3) / 4;

            i += 1;
        }

        const bone_names = std.mem.sliceAsBytes(data_u32[bone_names_list_start..offset]);

        const matrix_array_size = bone_count * frame_count * 4 * 4;

        if (offset + matrix_array_size * 2 > data_u32.len) {
            return error.FileTooSmall;
        }

        const matrices_relative = data_f32[offset .. offset + matrix_array_size];
        const matrices_absolute = data_f32[offset + matrix_array_size .. offset + matrix_array_size * 2];

        return AnimationData{
            .frame_count = frame_count,
            .frame_duration = frame_duration,
            .bone_count = bone_count,
            .bone_names = bone_names,
            .matrices_relative = matrices_relative,
            .matrices_absolute = matrices_absolute,
        };
    }

    pub fn getBoneIndex(self: AnimationData, bone_name: []const u8) !u32 {
        var i: u32 = 0;
        var offset: u32 = 0;
        while (i < self.bone_count) : (i += 1) {
            const stringLen = self.bone_names[offset];

            if (std.mem.eql(u8, self.bone_names[offset + 1 .. offset + 1 + stringLen], bone_name)) {
                return i;
            }

            offset += 1 + stringLen;

            if (offset % 4 != 0) {
                offset += 4 - (offset % 4);
            }
        }
        return error.NoSuchBone;
    }
};
