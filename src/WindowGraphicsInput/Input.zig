const std = @import("std");
const assert = std.debug.assert;
const c = @import("c.zig").c;

extern var window: ?*c.GLFWwindow;

var key_callback: ?fn (i32, i32, i32, i32) void = null;

extern fn key_callback_f(w: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
    if (key_callback != null) {
        (key_callback.?)(key, scancode, action, mods);
    }
}

pub fn setKeyCallback(clbk: fn (i32, i32, i32, i32) void) void {
    key_callback = clbk;
    _ = c.glfwSetKeyCallback(window, key_callback_f);
}

pub fn getMousePosition() [2]i32 {
    var xpos: f64 = 0.0;
    var ypos: f64 = 0.0;
    c.glfwGetCursorPos(window, &xpos, &ypos);

    return [2]i32{
        @floatToInt(i32, xpos),
        @floatToInt(i32, ypos),
    };
}

var mouse_button_callback: ?fn (i32, i32, i32) void = null;

extern fn mouse_button_callback_f(w: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) void {
    if (mouse_button_callback != null) {
        (mouse_button_callback.?)(button, action, mods);
    }
}

pub fn setMouseButtonCallback(clbk: fn (i32, i32, i32) void) void {
    mouse_button_callback = clbk;
    _ = c.glfwSetMouseButtonCallback(window, mouse_button_callback_f);
}

var mouse_scroll_callback: ?fn (i32, i32) void = null;

extern fn mouse_scroll_callback_f(w: ?*c.GLFWwindow, x: f64, y: f64) void {
    if (mouse_scroll_callback != null) {
        (mouse_scroll_callback.?)(@floatToInt(i32, x), @floatToInt(i32, y));
    }
}

pub fn setMouseScrollCallback(clbk: fn (i32, i32) void) void {
    mouse_scroll_callback = clbk;
    _ = c.glfwSetScrollCallback(window, mouse_scroll_callback_f);
}

pub fn setCursorEnabled(enabled: bool) void {
    if (enabled) {
        c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
    } else {
        c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    }
}

pub fn isKeyDown(key: c_int) bool {
    return c.glfwGetKey(window, key) == c.GLFW_PRESS;
}
