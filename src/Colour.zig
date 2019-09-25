const std = @import("std");

fn abs(comptime T: type, x: T) T {
    if (x >= 0) {
        return x;
    }
    return -x;
}

// https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
pub fn HSV2RGB(comptime T: type, rgb: *[3]T, H: T, S: T, V: T) void {
    const C = V * S;

    const H1 = H / 60.0;
    const X = C * (1.0 - abs(T, ((std.math.mod(T, H1, 2) catch unreachable) - 1.0)));

    if (H1 >= 0.0 and H1 <= 1.0) {
        rgb[0] = C;
        rgb[1] = X;
        rgb[2] = 0;
    } else if (H1 >= 1.0 and H1 <= 2.0) {
        rgb[0] = X;
        rgb[1] = C;
        rgb[2] = 0;
    } else if (H1 >= 2.0 and H1 <= 3.0) {
        rgb[0] = 0;
        rgb[1] = C;
        rgb[2] = X;
    } else if (H1 >= 3.0 and H1 <= 4.0) {
        rgb[0] = 0;
        rgb[1] = X;
        rgb[2] = C;
    } else if (H1 >= 4.0 and H1 <= 5.0) {
        rgb[0] = X;
        rgb[1] = 0;
        rgb[2] = C;
    } else if (H1 >= 5.0 and H1 <= 6.0) {
        rgb[0] = C;
        rgb[1] = 0;
        rgb[2] = X;
    } else {
        rgb[0] = 0;
        rgb[1] = 0;
        rgb[2] = 0;
    }

    const m = V - C;

    rgb[0] += m;
    rgb[1] += m;
    rgb[2] += m;
}
