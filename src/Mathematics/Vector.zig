const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const Matrix = @import("Matrix.zig").Matrix;

pub fn Vector(comptime T: type, comptime S: u32) type {
    return struct {
        const Self = @This();

        data: [S]T,

        pub fn x(self: Vector(T, S)) T {
            return self.data[0];
        }

        pub fn y(self: Vector(T, S)) T {
            return self.data[1];
        }

        pub fn z(self: Vector(T, S)) T {
            comptime {
                if (S < 3) {
                    @compileError("No z component");
                }
            }

            return self.data[2];
        }

        pub fn w(self: Vector(T, S)) T {
            comptime {
                if (S < 4) {
                    @compileError("No w component");
                }
            }

            return self.data[3];
        }

        pub fn setX(self: *Vector(T, S), x: T) void {
            self.data[0] = x;
        }

        pub fn setY(self: *Vector(T, S), y: T) void {
            self.data[1] = y;
        }

        pub fn setZ(self: *Vector(T, S), z: T) void {
            comptime {
                if (S < 2) {
                    @compileError("No z component");
                }
            }

            self.data[2] = z;
        }

        pub fn init(values: [S]T) Self {
            comptime {
                if (S < 2) {
                    @compileError("Vectors must have at least 2 components");
                }
            }

            var a: Self = undefined;
            var i: u32 = 0;
            while (i < S) {
                a.data[i] = values[i];
                i += 1;
            }
            return a;
        }

        pub fn copy(self: Vector(T, S)) Vector(T, S) {
            var a: Vector(T, S) = undefined;
            std.mem.copy(T, a.data[0..], self.data[0..]);
            return a;
        }

        pub fn add(self: *Vector(T, S), v: Vector(T, S)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                self.data[i] += v.data[i];
            }
        }

        pub fn sub(self: *Vector(T, S), v: Vector(T, S)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                self.data[i] -= v.data[i];
            }
        }

        pub fn mul(self: *Vector(T, S), v: Vector(T, S)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                self.data[i] *= v.data[i];
            }
        }

        pub fn div(self: *Vector(T, S), v: Vector(T, S)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                self.data[i] /= v.data[i];
            }
        }

        pub fn lengthNoSqrt(self: Vector(T, S)) T {
            return self.dot(self);
        }

        pub fn length(self: Vector(T, S)) T {
            return std.math.sqrt(self.dot(self));
        }

        pub fn normalise(self: *Vector(T, S)) void {
            const l = self.length();
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                self.data[i] /= l;
            }
        }

        pub fn normalised(self: *Vector(T, S)) Vector(T, S) {
            var v = self.copy();
            v.normalise();
            return v;
        }

        pub fn normalize(self: *Vector(T, S)) void {
            self.normalise();
        }

        pub fn normalized(self: *Vector(T, S)) Vector(T, S) {
            return self.normalised();
        }

        pub fn dot(self: Vector(T, S), v: Vector(T, S)) T {
            var i: u32 = 0;
            var sum: T = 0;
            while (i < S) : (i += 1) {
                sum += self.data[i] * v.data[i];
            }
            return sum;
        }

        pub fn cross(self: Vector(T, S), v: Vector(T, S)) Vector(T, S) {
            comptime {
                if (S < 2) {
                    @compileError("Cross product is for 3D vectors only");
                }
            }

            var new: Vector(T, S) = undefined;
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                new.data[i] = self.data[(i + 1) % S] * v.data[(i + 2) % S] - self.data[(i + 2) % S] * v.data[(i + 1) % S];
            }
            return new;
        }

        pub fn mulMat(self: Vector(T, S), m: Matrix(T, S)) Vector(T, S) {
            var new: Vector(T, S) = undefined;
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var sum: T = 0;
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    sum += m.data[j][i] * self.data[j];
                }
                new.data[i] = sum;
            }
            return new;
        }
    };
}

test "Copy" {
    var v1 = Vector(f32, 2).init([2]f32{ 3, 4 });
    var v2 = v1.copy();

    std.testing.expectEqual(v2.data[0], 3);
    std.testing.expectEqual(v2.data[1], 4);
}

test "Vector add/sub/mul/div" {
    var v1i: Vector(i16, 3) = Vector(i16, 3).init([3]i16{ 1, 2, 3 });
    var v2i: Vector(i16, 3) = Vector(i16, 3).init([3]i16{ 4, 5, 6 });
    v1i.add(v2i);

    std.testing.expectEqual(v1i.data[0], 5);
    std.testing.expectEqual(v1i.data[1], 7);
    std.testing.expectEqual(v1i.data[2], 9);

    var v1: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 4.0, 5.0, 6.0 });
    var v2: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 1.0, 2.0, 3.0 });
    v1.sub(v2);

    std.testing.expect(std.math.approxEq(f32, v1.data[0], 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[1], 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[2], 3.0, 0.00001));

    var v3: Vector(f32, 5) = Vector(f32, 5).init([5]f32{ 4.0, 5.0, 6.0, 1.0, 2.0 });
    var v4: Vector(f32, 5) = Vector(f32, 5).init([5]f32{ 1.0, 2.0, 3.0, 8.0, 0.5 });
    v3.mul(v4);
    assert(v3.data[0] == 4.0);
    assert(v3.data[1] == 10.0);
    assert(v3.data[2] == 18.0);
    assert(v3.data[3] == 8.0);
    assert(v3.data[4] == 1.0);

    std.testing.expect(std.math.approxEq(f32, v3.data[0], 4.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v3.data[1], 10.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v3.data[2], 18.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v3.data[3], 8.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v3.data[4], 1.0, 0.00001));

    var v5: Vector(f32, 2) = Vector(f32, 2).init([2]f32{ 4.0, 5.0 });
    var v6: Vector(f32, 2) = Vector(f32, 2).init([2]f32{ 1.0, 2.0 });
    v5.div(v6);

    std.testing.expect(std.math.approxEq(f32, v5.data[0], 4.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v5.data[1], 2.5, 0.00001));
}

test "Length" {
    var v1: Vector(f64, 3) = Vector(f64, 3).init([3]f64{ 1.0, 0.0, 6.0 });

    std.testing.expect(std.math.approxEq(f64, v1.lengthNoSqrt(), 37.0, 0.00001));
    std.testing.expect(std.math.approxEq(f64, v1.length(), 6.0827625303, 0.00001));
}

test "Dot Product" {
    var v1: Vector(f64, 3) = Vector(f64, 3).init([3]f64{ 1.0, 2.0, 3.0 });
    var v2: Vector(f64, 3) = Vector(f64, 3).init([3]f64{ 4.0, 5.0, 6.0 });

    std.testing.expect(std.math.approxEq(f64, v1.dot(v2), 32.0, 0.00001));
}

test "Cross Product" {
    var v1: Vector(f64, 3) = Vector(f64, 3).init([3]f64{ 1.0, 2.0, 3.0 });
    var v2: Vector(f64, 3) = Vector(f64, 3).init([3]f64{ 4.0, 5.0, 6.0 });
    var v3: Vector(f64, 3) = v1.cross(v2);

    std.testing.expect(std.math.approxEq(f64, v3.data[0], -3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f64, v3.data[1], 6.0, 0.00001));
    std.testing.expect(std.math.approxEq(f64, v3.data[2], -3.0, 0.00001));
}
