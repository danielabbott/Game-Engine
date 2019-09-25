pub const Vector = @import("Vector.zig").Vector;
pub const Matrix = @import("Matrix.zig").Matrix;

test "All tests" {
    _ = @import("Vector.zig");
    _ = @import("Matrix.zig");
}