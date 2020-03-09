const std = @import("std");
const assert = std.debug.assert;

pub const ReferenceCounter = struct {
    n: u32 = 0,

    pub fn inc(self: *ReferenceCounter) void {
        self.n += 1;
    }

    pub fn dec(self: *ReferenceCounter) void {
        assert(self.n != 0);
        if (self.n > 0) {
            self.n -= 1;
        }
    }

    pub fn deinit(self: *ReferenceCounter) void {
        assert(self.n == 0);
        self.n = 0;
    }

    pub fn set(comptime T: type, old: *(?*T), new: ?*T) void {
        if (old.* != null) {
            old.*.?.ref_count.dec();
        }
        old.* = new;
        if (new != null) {
            new.?.ref_count.inc();
        }
    }
};
