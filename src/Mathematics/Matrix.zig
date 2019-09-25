const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const Vector = @import("Vector.zig").Vector;

pub fn Matrix(comptime T: type, comptime S: u32) type {
    return struct {
        const Self = @This();

        data: [S][S]T,

        // Values in column-major layout
        pub fn init(values: [S][S]T) Self {
            comptime {
                if (S < 2) {
                    @compileError("Matrices must be at least 2x2");
                }
            }

            var a: Self = undefined;
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    a.data[j][i] = values[i][j];
                }
            }
            return a;
        }

        pub fn loadFromSlice(self: Matrix(T, S), slice: []const T) !void {     
            if(slice.len != S*S) {
                assert(false);
                return error.InvalidSliceLength;
            }

            std.mem.copy(f32, @intToPtr([*c]f32, @ptrToInt(&self.data[0][0]))[0..S*S], slice);
        }

        pub fn setArray(self: Matrix(T, S), out: *([S][S]T)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    out.*[i][j] = self.data[i][j];
                }
            }
        }

        pub fn copy(self: Matrix(T, S)) Matrix(T, S) {
            var new: Matrix(T, S) = undefined;

            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    new.data[i][j] = self.data[i][j];
                }
            }

            return new;
        }

        pub fn identity() Matrix(T, S) {
            comptime var m: Matrix(T, S) = undefined;

            comptime {
                var i: u32 = 0;
                while (i < S) : (i += 1) {
                    var j: u32 = 0;
                    while (j < S) : (j += 1) {
                        if (i == j) {
                            m.data[i][j] = 1;
                        } else {
                            m.data[i][j] = 0;
                        }
                    }
                }
            }

            return m;
        }

        pub fn mul(self: Matrix(T, S), m: Matrix(T, S)) Matrix(T, S) {
            var new: Matrix(T, S) = undefined;

            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    var sum: T = 0;
                    var k: u32 = 0;
                    while (k < S) : (k += 1) {
                        sum += self.data[i][k] * m.data[k][j];
                    }
                    new.data[i][j] = sum;
                }
            }

            return new;
        }

        pub fn translate(v: Vector(T, S - 1)) Matrix(T, S) {
            comptime {
                if (S != 3 and S != 4) {
                    @compileError("Translate is only for 3x3 matrices (2D) and 4x4 matrices (3D).");
                }
            }

            var m: Matrix(T, S) = Matrix(T, S).identity();

            if (S == 4) {
                m.data[3][0] = v.x();
                m.data[3][1] = v.y();
                m.data[3][2] = v.z();
            } else if (S == 3) {
                m.data[2][0] = v.x();
                m.data[2][1] = v.y();
            }

            return m;
        }

        pub fn scale(v: Vector(T, S)) Matrix(T, S) {
            comptime {
                if (S != 2 and S != 3 and S != 4) {
                    @compileError("Scale is only for 2x2 matrices (2D) 3x3 matrices (2D/3D) and 4x4 matrices (3D).");
                }
            }

            var m: Matrix(T, S) = Matrix(T, S).identity();

            if (S == 4) {
                m.data[0][0] = v.x();
                m.data[1][1] = v.y();
                m.data[2][2] = v.z();
                m.data[3][3] = v.w();
            } else if (S == 3) {
                m.data[0][0] = v.x();
                m.data[1][1] = v.y();
                m.data[2][2] = v.z();
            } else if (S == 2) {
                m.data[0][0] = v.x();
                m.data[1][1] = v.y();
            }

            return m;
        }

        // https://en.wikipedia.org/wiki/Rotation_matrix#Basic_rotations

        pub fn rotateX(angle: T) Matrix(T, S) {
            comptime {
                if (S != 3 and S != 4) {
                    @compileError("Rotation about an axis is only for 3x3 matrices and 4x4 matrices.");
                }
            }

            var m: Matrix(T, S) = Matrix(T, S).identity();

            const sinTheta = std.math.sin(angle);
            const cosTheta = std.math.cos(angle);

            m.data[1][1] = cosTheta;
            m.data[1][2] = -sinTheta;
            m.data[2][2] = cosTheta;
            m.data[2][1] = sinTheta;

            return m;
        }

        pub fn rotateY(angle: T) Matrix(T, S) {
            comptime {
                if (S != 3 and S != 4) {
                    @compileError("Rotation about an axis is only for 3x3 matrices and 4x4 matrices.");
                }
            }

            var m: Matrix(T, S) = Matrix(T, S).identity();

            const sinTheta = std.math.sin(angle);
            const cosTheta = std.math.cos(angle);

            m.data[0][0] = cosTheta;
            m.data[2][0] = sinTheta;
            m.data[0][2] = -sinTheta;
            m.data[2][2] = cosTheta;

            return m;
        }

        pub fn rotateZ(angle: T) Matrix(T, S) {
            comptime {
                if (S != 3 and S != 4) {
                    @compileError("Rotation about an axis is only for 3x3 matrices and 4x4 matrices.");
                }
            }

            var m: Matrix(T, S) = Matrix(T, S).identity();

            const sinTheta = std.math.sin(angle);
            const cosTheta = std.math.cos(angle);

            m.data[0][0] = cosTheta;
            m.data[1][0] = -sinTheta;
            m.data[0][1] = sinTheta;
            m.data[1][1] = cosTheta;

            return m;
        }

        pub fn transpose(self: Matrix(T, S)) Matrix(T, S) {
            var new: Matrix(T, S) = undefined;
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    new.data[j][i] = self.data[i][j];
                }
            }
            return new;
        }

        fn determinant_3x3(a: T, b: T, c: T, d: T, e: T, f: T, g: T, h: T, i: T) T {
            return a * e * i + b * f * g + c * d * h - c * e * g - b * d * i - a * f * h;
        }

        pub fn determinant(self: Matrix(T, S)) T {
            if (S == 2) {
                return self.data[0][0] * self.data[1][1] - self.data[1][0] * self.data[0][1];
            } else if (S == 3) {
                const a = self.data[0][0];
                const b = self.data[1][0];
                const c = self.data[2][0];
                const d = self.data[0][1];
                const e = self.data[1][1];
                const f = self.data[2][1];
                const g = self.data[0][2];
                const h = self.data[1][2];
                const i = self.data[2][2];
                return determinant_3x3(a, b, c, d, e, f, g, h, i);
            } else if (S == 4) {
                const a = self.data[0][0];
                const b = self.data[1][0];
                const c = self.data[2][0];
                const d = self.data[3][0];
                const e = self.data[0][1];
                const f = self.data[1][1];
                const g = self.data[2][1];
                const h = self.data[3][1];
                const i = self.data[0][2];
                const j = self.data[1][2];
                const k = self.data[2][2];
                const l = self.data[3][2];
                const m = self.data[0][3];
                const n = self.data[1][3];
                const o = self.data[2][3];
                const p = self.data[3][3];

                // return a * determinant_3x3(f, g, h, j, k, l, n, o, p) - b * determinant_3x3(e, g, h, i, k, l, m, o, p) + c * determinant_3x3(e, f, h, i, j, l, m, n, p) - d * determinant_3x3(e, f, g, i, j, k, m, n, o);
                // return a * (f * k * p + g * l * n + h * j * o - h * k * n - g * j * p - f * l * o) - b * (e * k * p + g * l * m + h * i * o - h * k * m - g * i * p - e * l * o) + c * (e * j * p + f * l * m + h * i * n - h * j * m - f * i * p - e * l * n) - d * (e * j * o + f * k * m + g * i * n - g * j * m - f * i * o - e * k * n);

                const ej_ = e * j;
                const ek_ = e * k;
                const el_ = e * l;
                const fi_ = f * i;
                const fk_ = f * k;
                const fl_ = f * l;
                const gi_ = g * i;
                const gj_ = g * j;
                const gl_ = g * l;
                const hi_ = h * i;
                const hj_ = h * j;
                const hk_ = h * k;

                return a * (fk_ * p + gl_ * n + hj_ * o - hk_ * n - gj_ * p - fl_ * o) - b * (ek_ * p + gl_ * m + hi_ * o - hk_ * m - gi_ * p - el_ * o) + c * (ej_ * p + fl_ * m + hi_ * n - hj_ * m - fi_ * p - el_ * n) - d * (ej_ * o + fk_ * m + gi_ * n - gj_ * m - fi_ * o - ek_ * n);
            } else {
                var i: u32 = 0;
                var sign: T = 1;
                var sum: T = 0;
                while (i < S) : (i += 1) {
                    sum += sign * self.data[i][0] * self.subMatDet(i, 0);

                    sign *= -1;
                }
                return sum;
            }
        }

        fn subMatDet(self: Matrix(T, S), i_skip: u32, j_skip: u32) T {
            var m: Matrix(T, S - 1) = undefined;

            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    if (i != i_skip and j != j_skip) {
                        var i_: u32 = i;
                        var j_: u32 = j;

                        if (i_ > i_skip) {
                            i_ -= 1;
                        }

                        if (j_ > j_skip) {
                            j_ -= 1;
                        }

                        m.data[i_][j_] = self.data[i][j];
                    }
                }
            }

            return m.determinant();
        }

        pub fn inverse(self: Matrix(T, S)) !Matrix(T, S) {
            if (S == 2) {
                const det = self.determinant();

                if (det == 0) {
                    return error.NoInverse;
                }

                const detRecip = 1.0 / det;

                const a = self.data[0][0];
                const b = self.data[1][0];
                const c = self.data[0][1];
                const d = self.data[1][1];

                return Matrix(T, 2).init([2][2]T{
                    [2]f32{ detRecip * d, detRecip * -b },
                    [2]f32{ detRecip * -c, detRecip * a },
                });
            } else if (S == 3) {
                const det = self.determinant();

                if (det == 0) {
                    return error.NoInverse;
                }

                const detRecip = 1.0 / det;

                const a = self.data[0][0];
                const b = self.data[1][0];
                const c = self.data[2][0];
                const d = self.data[0][1];
                const e = self.data[1][1];
                const f = self.data[2][1];
                const g = self.data[0][2];
                const h = self.data[1][2];
                const i = self.data[2][2];

                const A_ = e * i - f * h;
                const B_ = -(d * i - f * g);
                const C_ = d * h - e * g;
                const D_ = -(b * i - c * h);
                const E_ = a * i - c * g;
                const F_ = -(a * h - b * g);
                const G_ = b * f - c * e;
                const H_ = -(a * f - c * d);
                const I_ = a * e - b * d;

                return Matrix(f32, 3).init([3][3]f32{
                    [3]f32{ detRecip * A_, detRecip * D_, detRecip * G_ },
                    [3]f32{ detRecip * B_, detRecip * E_, detRecip * H_ },
                    [3]f32{ detRecip * C_, detRecip * F_, detRecip * I_ },
                });
            } else {
                const det = self.determinant();

                if (det == 0) {
                    return error.NoInverse;
                }

                const detRecip = 1.0 / det;
                var result: Matrix(T, S) = undefined;

                var i: u32 = 0;
                var sign: T = 1;
                while (i < S) : (i += 1) {
                    var j: u32 = 0;
                    while (j < S) : (j += 1) {
                        var co: T = self.subMatDet(i, j);

                        result.data[j][i] = sign * detRecip * co;
                        sign *= -1;
                    }
                    sign *= -1;
                }

                return result;
            }
        }

        pub fn increaseDimension(self: Matrix(T, S)) Matrix(T, S + 1) {
            var m: Matrix(T, S + 1) = undefined;
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    m.data[i][j] = self.data[i][j];
                }
                m.data[i][S] = 0;
            }
            var j: u32 = 0;
            while (j < S) : (j += 1) {
                m.data[S][j] = self.data[i][j];
            }
            m.data[S][S] = 1;
            return m;
        }

        pub fn decreaseDimension(self: Matrix(T, S)) Matrix(T, S - 1) {
            var m: Matrix(T, S - 1) = undefined;
            var i: u32 = 0;
            while (i < S-1) : (i += 1) {
                var j: u32 = 0;
                while (j < S-1) : (j += 1) {
                    m.data[i][j] = self.data[i][j];
                }
            }
            return m;
        }

        pub fn dbg_print(self: Matrix(T, S)) void {
            var i: u32 = 0;
            while (i < S) : (i += 1) {
                var j: u32 = 0;
                while (j < S) : (j += 1) {
                    warn("{} ", self.data[j][i]);
                }
                warn("\n");
            }
        }

        // aspect_ratio = window_width / window_height
        // fov is in radians
        // Uses OpenGL coordinate system
        pub fn perspectiveProjectionOpenGL(aspect_ratio: T, fovy: T, near_plane: T, far_plane: T) Matrix(T, 4) {
            var m: Matrix(T, 4) = Matrix(T, 4).identity();

            // Code borrowed from GLM

            const tanHalfFovy = std.math.tan(fovy / 2.0);

            m.data[0][0] = 1.0 / (aspect_ratio * tanHalfFovy);
            m.data[1][1] = 1.0 / tanHalfFovy;
            m.data[2][2] = -(far_plane + near_plane) / (far_plane - near_plane);
            m.data[2][3] = -1.0;
            m.data[3][2] = -(2.0 * far_plane * near_plane) / (far_plane - near_plane);

            return m;
        }

        // OpenGL coordinate system but Z is in the range [0,1] instead of the default [-1,1]
        pub fn perspectiveProjectionOpenGLInverseZ(aspect_ratio: T, fovy: T, near_plane: T, far_plane: T) Matrix(T, 4) {
            var m: Matrix(T, 4) = Matrix(T, 4).identity();

            const tanHalfFovy = std.math.tan(fovy / 2.0);

            // Same as above code but z = -z*0.5 + 0.5

            m.data[0][0] = 1.0 / (aspect_ratio * tanHalfFovy);
            m.data[1][1] = 1.0 / tanHalfFovy;
            m.data[2][2] = -(far_plane + near_plane) / (far_plane - near_plane) * 0.5;
            m.data[2][3] = -1.0;
            m.data[3][2] = (far_plane * near_plane) / (far_plane - near_plane) + 0.5;

            return m;
        }

        pub fn orthoProjectionOpenGL(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Matrix(T, 4) {
            var m: Matrix(T, 4) = Matrix(T, 4).identity();

            // Code borrowed from GLM

            m.data[0][0] = 2.0 / (right - left);
            m.data[1][1] = 2.0 / (top - bottom);
            m.data[2][2] = -2.0 / (far - near);
            m.data[3][0] = -(right + left) / (right - left);
            m.data[3][1] = -(top + bottom) / (top - bottom);
            m.data[3][2] = -(far + near) / (far - near);

            return m;
        }

        pub fn orthoProjectionOpenGLInverseZ(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Matrix(T, 4) {
            var m: Matrix(T, 4) = Matrix(T, 4).identity();

            // Same as above code but z = -z*0.5 + 0.5 and near/far are swapped

            m.data[0][0] = 2.0 / (right - left);
            m.data[1][1] = 2.0 / (top - bottom);
            m.data[2][2] = -1.0 / (near - far);
            m.data[3][0] = -(right + left) / (right - left);
            m.data[3][1] = -(top + bottom) / (top - bottom);
            m.data[3][2] = (-0.5 * (far + near)) / (near - far) + 0.5;

            return m;
        }

        pub fn position3D(self: Matrix(T, S)) Vector(T, 3) {
            if (S == 3) {
                return Vector(T, 3).init([3]f32{ self.data[2][0], self.data[2][1], self.data[2][2] });
            } else if (S == 4) {
                return Vector(T, 3).init([3]f32{ self.data[3][0], self.data[3][1], self.data[3][2] });
            } else {
                @compileError("Matrix.position3D is only for 3x3 and 4x4 matrices.");
            }
        }

        pub fn position2D(self: Matrix(T, S)) Vector(T, S) {
            if (S == 2) {
                return Vector(T, 2).init([2]f32{ 0.0, 0.0 }).mulMat(self);
            } else if (S == 3) {
                return Vector(T, 3).init([3]f32{ 0.0, 0.0, 1.0 }).mulMat(self);
            } else {
                @compileError("Matrix.position2D is only for 2x2 and 3x3 matrices.");
            }
        }
    };
}

test "Multiply matrix by identity" {
    var m: Matrix(f32, 2) = Matrix(f32, 2).identity();
    std.testing.expectEqual(m.data[0][0], 1.0);
    std.testing.expectEqual(m.data[1][1], 1.0);

    var m2: Matrix(f32, 2) = Matrix(f32, 2).init([2][2]f32{
        [2]f32{ 1, 2 },
        [2]f32{ 5, 6 },
    });

    var m3: Matrix(f32, 2) = m2.mul(m);

    std.testing.expect(std.math.approxEq(f32, m3.data[0][0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3.data[0][1], 5.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3.data[1][0], 2.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3.data[1][1], 6.0, 0.00001));
}

test "Multiply vec2 by mat2" {
    var m: Matrix(f32, 2) = Matrix(f32, 2).identity();
    var v1: Vector(f32, 2) = Vector(f32, 2).init([2]f32{ 1.0, 2.0 });
    var v2: Vector(f32, 2) = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v2.data[0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[1], 2.0, 0.00001));
}

test "Multiply vec4 by mat4" {
    var m: Matrix(f32, 4) = Matrix(f32, 4).identity();
    m.data[3][0] = 1.0;
    m.data[3][1] = 2.0;
    m.data[3][2] = 3.0;

    var v1: Vector(f32, 4) = Vector(f32, 4).init([4]f32{ 0.0, 0.0, 0.0, 1.0 });
    var v2: Vector(f32, 4) = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v2.data[0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[1], 2.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[2], 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[3], 1.0, 0.00001));
}

test "Translate vec2 by mat3" {
    var m: Matrix(f32, 3) = Matrix(f32, 3).identity();
    var v1: Vector(f32, 2) = Vector(f32, 2).init([2]f32{ 1.0, 2.0 });
    m = m.mul(Matrix(f32, 3).translate(v1));

    var v2: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 0.0, 0.0, 1.0 });
    v2 = v2.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v2.data[0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[1], 2.0, 0.00001));
}

test "Rotate vec4 about x axis" {
    // Rotate 45 degrees
    var m: Matrix(f32, 4) = Matrix(f32, 4).identity().mul(Matrix(f32, 4).rotateX(0.7853981625));

    var v1: Vector(f32, 4) = Vector(f32, 4).init([4]f32{ 0.0, 1.0, 0.0, 1.0 });
    v1 = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v1.data[0], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[1], 0.7071067811865475, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[2], -0.7071067811865475, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[3], 1.0, 0.00001));
}

test "Rotate vec3 about y axis" {
    // Rotate 45 degrees
    var m: Matrix(f32, 3) = Matrix(f32, 3).identity().mul(Matrix(f32, 3).rotateY(0.7853981625));

    var v1: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 1.0, 0.0, 0.0 });
    v1 = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v1.data[0], 0.7071067811865475, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[1], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[2], -0.7071067811865475, 0.00001));
}

test "Rotate vec3 about z axis" {
    // Rotate 45 degrees
    var m: Matrix(f32, 3) = Matrix(f32, 3).identity().mul(Matrix(f32, 3).rotateZ(0.7853981625));

    var v1: Vector(f32, 3) = Vector(f32, 3).init([3]f32{ 1.0, 0.0, 0.0 });
    v1 = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v1.data[0], 0.7071067811865475, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[1], 0.7071067811865475, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[2], 0.0, 0.00001));
}

test "Transformation matrix" {
    var m: Matrix(f32, 4) = Matrix(f32, 4).identity();
    m = m.mul(Matrix(f32, 4).scale(Vector(f32, 4).init([4]f32{ 2.0, 2.0, 2.0, 1.0 })));
    m = m.mul(Matrix(f32, 4).rotateY(0.7853981625));
    m = m.mul(Matrix(f32, 4).translate(Vector(f32, 3).init([3]f32{ 0.0, 5.0, 0.0 })));

    var v1: Vector(f32, 4) = Vector(f32, 4).init([4]f32{ 0.0, 0.0, 0.0, 1.0 });
    v1 = v1.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v1.data[0], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[1], 5.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[2], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v1.data[3], 1.0, 0.00001));

    var v2: Vector(f32, 4) = Vector(f32, 4).init([4]f32{ 1.0, 0.0, 0.0, 1.0 });
    v2 = v2.mulMat(m);

    std.testing.expect(std.math.approxEq(f32, v2.data[0], 1.414213562373095, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[1], 5.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[2], -1.414213562373095, 0.00001));
    std.testing.expect(std.math.approxEq(f32, v2.data[3], 1.0, 0.00001));
}

test "Determinant" {
    var m: Matrix(f32, 2) = Matrix(f32, 2).init([2][2]f32{
        [2]f32{ 1, 2 },
        [2]f32{ 3, 4 },
    });
    std.testing.expect(std.math.approxEq(f32, m.determinant(), -2.0, 0.00001));

    var m2: Matrix(f32, 3) = Matrix(f32, 3).init([3][3]f32{
        [3]f32{ 2, 8, 5 },
        [3]f32{ 8, 6, 4 },
        [3]f32{ 5, 3, 6 },
    });
    std.testing.expect(std.math.approxEq(f32, m2.determinant(), -206.0, 0.00001));

    var m3: Matrix(f32, 4) = Matrix(f32, 4).init([4][4]f32{
        [4]f32{ 9, 5, 9, 7 },
        [4]f32{ 9, 8, 3, 6 },
        [4]f32{ 4, 8, 5, 2 },
        [4]f32{ 4, 3, 8, 8 },
    });
    std.testing.expect(std.math.approxEq(f32, m3.determinant(), 1623.0, 0.00001));

    var m4: Matrix(f32, 5) = Matrix(f32, 5).init([5][5]f32{
        [5]f32{ 0, 6, -2, -1, 5 },
        [5]f32{ 0, 0, 0, -9, -7 },
        [5]f32{ 0, 0, 15, 35, 0 },
        [5]f32{ 0, 0, -1, -11, -2 },
        [5]f32{ 1, -2, -2, 3, -2 },
    });
    std.testing.expect(std.math.approxEq(f32, m4.determinant(), 3840.0, 0.00001));
}

test "Inverse" {
    var m: Matrix(f32, 2) = Matrix(f32, 2).init([2][2]f32{
        [2]f32{ 1, 2 },
        [2]f32{ 3, 4 },
    });
    const m_ = try m.inverse();
    std.testing.expect(std.math.approxEq(f32, m_.data[0][0], -2.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m_.data[0][1], 3.0 / 2.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m_.data[1][0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m_.data[1][1], -1.0 / 2.0, 0.00001));

    const m__ = try m_.inverse();
    std.testing.expect(std.mem.compare(f32, @bitCast([4]f32, m__.data), @bitCast([4]f32, m.data)) == std.mem.Compare.Equal);

    var m2: Matrix(f32, 3) = Matrix(f32, 3).init([3][3]f32{
        [3]f32{ 2, 8, 5 },
        [3]f32{ 8, 6, 4 },
        [3]f32{ 5, 3, 6 },
    });
    const m2_ = try m2.inverse();
    std.testing.expect(std.math.approxEq(f32, m2_.data[0][0], -12.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[0][1], 14.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[0][2], 3.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[1][0], 33.0 / 206.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[1][1], 13.0 / 206.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[1][2], -17.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[2][0], -1.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[2][1], -16.0 / 103.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m2_.data[2][2], 26.0 / 103.0, 0.00001));

    var m3: Matrix(f32, 4) = Matrix(f32, 4).init([4][4]f32{
        [4]f32{ 1, 2, 1, 1 },
        [4]f32{ 2, 2, 1, 1 },
        [4]f32{ 1, 2, 2, 1 },
        [4]f32{ 1, 1, 1, 2 },
    });

    const m3_ = try m3.inverse();
    std.testing.expect(std.math.approxEq(f32, m3_.data[0][0], -1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[0][1], 4.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[0][2], -1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[0][3], 1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[1][0], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[1][1], -1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[1][2], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[1][3], -1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[2][0], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[2][1], -1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[2][2], 1.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[2][3], -1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[3][0], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[3][1], -1.0 / 3.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[3][2], 0.0, 0.00001));
    std.testing.expect(std.math.approxEq(f32, m3_.data[3][3], 2.0 / 3.0, 0.00001));

    var m4: Matrix(f32, 4) = Matrix(f32, 4).translate(Vector(f32, 3).init([3]f32{ 1.5, 0, 0 }));
    std.testing.expect(std.math.approxEq(f32, m4.data[3][0], 1.5, 0.00001));

    const m4_ = try m4.inverse();

    std.testing.expect(std.math.approxEq(f32, m4_.data[3][0], -1.5, 0.00001));
}
