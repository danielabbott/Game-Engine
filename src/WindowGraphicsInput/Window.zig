const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const c = @import("c.zig").c;
const mem = std.mem;
const builtin = @import("builtin");
const wgi = @import("WindowGraphicsInput.zig");
const Files = @import("../Files.zig");
const image = @import("Image.zig");

var maxVertexAttribs: u32 = 16;
var maxTextureSize: u32 = 1024;
var maxTextureUnits: u32 = 16;
var disableDepthBuffer = false;

var window: ?*c.GLFWwindow = null;

var gl_version: u32 = 33;

pub fn windowWasCreatedWithoutDepthBuffer() bool {
    return disableDepthBuffer;
}

export fn debug_callback(source: c_uint, type_: c_uint, id: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, userParam: ?*const c_void) void {
    if (type_ != c.GL_DEBUG_TYPE_OTHER_ARB) { // gets rid of the 'Buffer detailed info' messages
        warn("OpenGL error: {}\n", message[0..mem.len(u8, message)]);

        assert(type_ != c.GL_DEBUG_TYPE_ERROR_ARB);
    }
}

extern fn glfw_error_callback(code: c_int, description: [*c]const u8) void {
    warn("GLFW error: {} {}\n", code, description[0..mem.len(u8, description)]);
}

// If fullscreen is true then width and height are ignored.
// disableDepthBuffer_ is used to avoid unnecessarily allocating a depth buffer if FXAA will be used
pub fn createWindow(fullscreen: bool, width: u32, height: u32, title: [*]const u8, disableDepthBuffer_: bool, msaa: u32) !void {
    disableDepthBuffer = disableDepthBuffer_;

    if (disableDepthBuffer and msaa > 0) {
        return error.ParameterError;
    }

    if (c.glfwInit() == c.GLFW_FALSE) {
        return error.GLFWError;
    }

    errdefer c.glfwTerminate();

    _ = c.glfwSetErrorCallback(glfw_error_callback);

    // 3.3 is needed for GL_INT_2_10_10_10_REV
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    c.glfwWindowHint(c.GLFW_STENCIL_BITS, 0);
    if (disableDepthBuffer) {
        c.glfwWindowHint(c.GLFW_DEPTH_BITS, 0);
    } else {
        c.glfwWindowHint(c.GLFW_DEPTH_BITS, 32);
    }

    if (builtin.mode == builtin.Mode.Debug) {
        c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
    }

    // OpenGL will automatically do gamma correction when writing to the main frame buffer
    // c.glfwWindowHint(c.GLFW_SRGB_CAPABLE, 1);

    // Disable deprecated functionality
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, 1);

    c.glfwWindowHint(c.GLFW_SAMPLES, if (msaa <= 32) @intCast(c_int, msaa) else 32);

    if (fullscreen) {
        const monitor = c.glfwGetPrimaryMonitor();
        const mode = c.glfwGetVideoMode(monitor);
        c.glfwWindowHint(c.GLFW_RED_BITS, mode.*.redBits);
        c.glfwWindowHint(c.GLFW_GREEN_BITS, mode.*.greenBits);
        c.glfwWindowHint(c.GLFW_BLUE_BITS, mode.*.blueBits);
        c.glfwWindowHint(c.GLFW_REFRESH_RATE, mode.*.refreshRate);
        window = c.glfwCreateWindow(@intCast(c_int, mode.*.width), @intCast(c_int, mode.*.height), title, monitor, null);
    } else {
        window = c.glfwCreateWindow(@intCast(c_int, width), @intCast(c_int, height), title, null, null);
    }

    if (window == null) {
        return error.GLFWError;
    }

    errdefer c.glfwDestroyWindow(window);

    // Disable mouse acceleration (good for 3D games, bad for GUI)
    // TODO Add functions for enabling/disabling this at any time
    if (c.glfwRawMouseMotionSupported() == c.GLFW_TRUE)
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);

    c.glfwMakeContextCurrent(window);
    const gladLoadRet = c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, c.glfwGetProcAddress));

    if (gladLoadRet == 0) {
        warn("Possible error in gladLoadGLLoader\n");
    }

    c.glfwSwapInterval(1);

    if (c.GLAD_GL_ARB_clip_control == 0) {
        warn("ARB_clip_control OpenGL extension is not supported\n");
        return error.ARBClipControlNotSupported;
    }

    c.glEnable(c.GL_DEPTH_TEST);
    // Switch to optimal depth buffer configuration
    wgi.setDepthModeDirectX(false, false);

    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    c.glClearColor(0.1, 0.1, 0.1, 1.0);

    // OpenGL will automatically do gamma correction when writing to the main frame buffer
    // c.glEnable(c.GL_FRAMEBUFFER_SRGB);

    if (msaa == 0) {
        c.glDisable(c.GL_MULTISAMPLE);
    } else {
        c.glEnable(c.GL_MULTISAMPLE);
    }

    c.glEnable(c.GL_DEPTH_CLAMP);

    if (builtin.mode == builtin.Mode.Debug and c.GL_ARB_debug_output != 0) {
        c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);
        c.glDebugMessageCallbackARB(debug_callback, null);
    }

    c.glGetIntegerv(c.GL_MAX_TEXTURE_SIZE, @ptrCast([*c]c_int, &maxTextureSize));
    if (maxTextureSize < 1024) {
        maxTextureSize = 1024;
    }
    c.glGetIntegerv(c.GL_MAX_VERTEX_ATTRIBS, @ptrCast([*c]c_int, &maxVertexAttribs));
    if (maxVertexAttribs < 16) {
        maxVertexAttribs = 16;
    }
    c.glGetIntegerv(c.GL_MAX_TEXTURE_IMAGE_UNITS, @ptrCast([*c]c_int, &maxTextureUnits));
    if (maxTextureUnits < 16) {
        maxTextureUnits = 16;
    }
}

pub fn goFullScreen() void {
    const monitor = c.glfwGetPrimaryMonitor();
    const mode = c.glfwGetVideoMode(monitor);
    c.glfwSetWindowMonitor(window, monitor, 0, 0, @intCast(c_int, mode.*.width), @intCast(c_int, mode.*.height), mode.*.refreshRate);
    c.glfwSwapInterval(1);
}

pub fn exitFullScreen(width: u32, height: u32) void {
    const monitor = c.glfwGetPrimaryMonitor();
    const mode = c.glfwGetVideoMode(monitor);
    c.glfwSetWindowMonitor(window, null, 0, 0, @intCast(c_int, width), @intCast(c_int, height), mode.*.refreshRate);
    c.glfwSwapInterval(1);
    c.glfwSetWindowPos(window, 20, 30);
}

pub fn closeWindow() void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

pub fn windowShouldClose() bool {
    return c.glfwWindowShouldClose(window) == c.GLFW_TRUE;
}

pub fn swapBuffers() void {
    return c.glfwSwapBuffers(window);
}

// Thread goes to sleep until there are input events
pub fn waitEvents() void {
    return c.glfwWaitEvents();
}

pub fn pollEvents() void {
    return c.glfwPollEvents();
}

pub fn getSize(w: *u32, h: *u32) void {
    var w_: c_int = 0;
    var h_: c_int = 0;
    c.glfwGetFramebufferSize(window, &w_, &h_);
    if (w_ < 0) {
        w_ = 0;
    }
    if (h_ < 0) {
        h_ = 0;
    }
    w.* = @intCast(u32, w_);
    h.* = @intCast(u32, h_);
}

pub const StringName = enum(u32) {
    Vendor = c.GL_VENDOR,
    Renderer = c.GL_RENDERER,
    Version = c.GL_VERSION,
    ShadingLanguageVersion = c.GL_SHADING_LANGUAGE_VERSION,
};

pub fn getString(stringRequest: StringName) ![]const u8 {
    var s = c.glGetString(@enumToInt(stringRequest));
    if (s == 0) {
        return error.OpenGLError;
    }
    return s[0..mem.len(u8, s)];
}

pub const CullMode = enum {
    None,
    Clockwise, // cull anti-clockwise faces
    AntiClockwise, // cull clockwise faces
};

pub fn setCullMode(newMode: CullMode) void {
    if (newMode == CullMode.None) {
        c.glDisable(c.GL_CULL_FACE);
    } else {
        c.glEnable(c.GL_CULL_FACE);

        if (newMode == CullMode.Clockwise) {
            c.glFrontFace(c.GL_CW);
        } else if (newMode == CullMode.AntiClockwise) {
            c.glFrontFace(c.GL_CCW);
        }
    }
}

pub const BlendMode = enum(u32) {
    None,
    Max,
    Standard,
};

pub fn setBlendMode(mode: BlendMode) void {
    switch (mode) {
        BlendMode.None => {
            c.glDisable(c.GL_BLEND);
        },
        BlendMode.Max => {
            c.glEnable(c.GL_BLEND);
            c.glBlendFunc(1, 1);
            c.glBlendEquation(c.GL_MAX);
        },
        BlendMode.Standard => {
            c.glEnable(c.GL_BLEND);
            c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
            c.glBlendEquation(c.GL_FUNC_ADD);
        },
    }
}

pub fn setClearColour(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub fn clear(colourBuffer: bool, depthBuffer: bool) void {
    var parameter: u32 = 0;
    if (colourBuffer) {
        parameter |= c.GL_COLOR_BUFFER_BIT;
    }
    if (depthBuffer) {
        parameter |= c.GL_DEPTH_BUFFER_BIT;
    }
    c.glClear(parameter);
}

// Maximum size of each dimension for a 2D texture
pub fn maximumTextureSize() u32 {
    return maxTextureSize;
}

// Maximum number of vec/ivec/uvec/ vertex inputs
pub fn maximumNumVertexAttributes() u32 {
    return maxVertexAttribs;
}

// Maximum number of bound textures
// Note that multiple textures of different types cannot be bound to the same texture unit
pub fn maximumNumTextureImageUnits() u32 {
    return maxTextureUnits;
}

pub fn setResizeable(resizable: bool) void {
    if (resizable) {
        c.glfwSetWindowAttrib(window, c.GLFW_RESIZABLE, c.GLFW_TRUE);
    } else {
        c.glfwSetWindowAttrib(window, c.GLFW_RESIZABLE, c.GLFW_FALSE);
    }
}

pub fn isKeyDown(key: c_int) bool {
    return c.glfwGetKey(window, key) == c.GLFW_PRESS;
}

pub fn setIcon(icon_16x16: ?[]u32, icon_32x32: ?[]u32, icon_48x48: ?[]u32, icon_256x256: ?[]u32) void {
    var images: [4]c.GLFWimage = undefined;
    var i: u32 = 0;
    if (icon_16x16 != null and icon_16x16.?.len == 16 * 16) {
        images[i].width = 16;
        images[i].height = 16;
        images[i].pixels = @ptrCast([*c]u8, &icon_16x16.?[0]);
        i += 1;
    }
    if (icon_32x32 != null and icon_32x32.?.len == 32 * 32) {
        images[i].width = 32;
        images[i].height = 32;
        images[i].pixels = @ptrCast([*c]u8, &icon_32x32.?[0]);
        i += 1;
    }
    if (icon_48x48 != null and icon_48x48.?.len == 48 * 48) {
        images[i].width = 48;
        images[i].height = 48;
        images[i].pixels = @ptrCast([*c]u8, &icon_48x48.?[0]);
        i += 1;
    }
    if (icon_256x256 != null and icon_256x256.?.len == 256 * 256) {
        images[i].width = 256;
        images[i].height = 256;
        images[i].pixels = @ptrCast([*c]u8, &icon_256x256.?[0]);
        i += 1;
    }
    if (i != 0) {
        c.glfwSetWindowIcon(window, @intCast(c_int, i), &images[0]);
    }
}

pub fn loadIcon(file_path: []const u8, allocator: *std.mem.Allocator) !void {
    const image_file_data = try Files.loadFile(file_path, allocator);
    defer allocator.free(image_file_data);
    var ico_components: u32 = 4;
    var ico_width: u32 = 0;
    var ico_height: u32 = 0;
    const ico_data = try image.decodeImage(image_file_data, &ico_components, &ico_width, &ico_height, allocator);
    defer image.freeDecodedImage(ico_data);

    if (ico_components != 4 or ico_data.len != ico_width * ico_height * 4) {
        return error.ImageDecodeError;
    }

    if (ico_width == 16 and ico_height == 16) {
        setIcon(@bytesToSlice(u32, @sliceToBytes(ico_data)), null, null, null);
    } else if (ico_width == 32 and ico_height == 32) {
        setIcon(null, @bytesToSlice(u32, @sliceToBytes(ico_data)), null, null);
    } else if (ico_width == 48 and ico_height == 48) {
        setIcon(null, null, @bytesToSlice(u32, @sliceToBytes(ico_data)), null);
    } else if (ico_width == 256 and ico_height == 256) {
        setIcon(null, null, null, @bytesToSlice(u32, @sliceToBytes(ico_data)));
    } else {
        return error.IconWrongSize;
    }
}
