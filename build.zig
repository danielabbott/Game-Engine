const build_ = @import("std").build;
const Builder = build_.Builder;
const LibExeObjStep = build_.LibExeObjStep;
const builtin = @import("builtin");

const testNames = [_][]const u8{
    "WindowGraphicsInput",
    "ModelFiles",
    "RTRenderEngine",
    "Mathematics",
    "Compress",
    "RGB10A2",
    "Assets",
    "Scene",
};

const testFiles = [_][]const u8{
    "WindowGraphicsInput/WindowGraphicsInput.zig",
    "ModelFiles/ModelFiles.zig",
    "RTRenderEngine/RTRenderEngine.zig",
    "Mathematics/Mathematics.zig",
    "Compress/Compress.zig",
    "RGB10A2/RGB10A2.zig",
    "Assets/Assets.zig",
    "Scene/Scene.zig",
};

fn addSettings(x: *LibExeObjStep) void {
    x.linkSystemLibrary("c");
    x.addIncludeDir("deps/glad");
    x.addIncludeDir("deps/stb_image");
    x.addIncludeDir("deps/glfw/include");
    x.addObjectFile("deps/glad/glad.o");
    x.addIncludeDir("deps/zstd/lib");

    if (builtin.os.tag == builtin.Os.Tag.windows) {
        x.addLibPath("deps/glfw/src/Release");
        x.addLibPath("deps/stb_image/x64/Release");
        x.addLibPath("deps\\zstd\\build\\VS2010\\bin\\x64_Release");
        x.linkSystemLibrary("libzstd_static");
        x.linkSystemLibrary("stb_image");
    } else {
        x.addLibPath("deps/glfw/src");
        x.addLibPath("deps/stb_image");
        x.addLibPath("deps/zstd/lib");
        x.linkSystemLibrary("zstd");
        x.addObjectFile("deps/stb_image/stb_image.o");
        x.linkSystemLibrary("rt");
        x.linkSystemLibrary("m");
        x.linkSystemLibrary("dl");
        x.linkSystemLibrary("X11");
    }

    x.linkSystemLibrary("glfw3");
    if (builtin.os.tag == builtin.Os.Tag.windows) {
        x.linkSystemLibrary("user32");
        x.linkSystemLibrary("gdi32");
        x.linkSystemLibrary("shell32");
    } else {}
}

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const test_step = b.step("test", "Run all tests");

    const demo_step = b.step("Demos", "Build Demos");
    inline for ([_][]const u8{ "Demo1", "Demo2", "Demo3" }) |demo_name| {
        const f = "src/" ++ demo_name ++ ".zig";
        const exe = b.addExecutable(demo_name, f);
        exe.setBuildMode(mode);
        exe.setMainPkgPath("src");
        addSettings(exe);
        b.installArtifact(exe);
    }

    // tools

    const compress_exe = b.addExecutable("compress-file", "src/Compress/CompressApp.zig");
    compress_exe.setBuildMode(mode);
    compress_exe.setMainPkgPath("src");
    addSettings(compress_exe);
    b.installArtifact(compress_exe);

    const rgb10a2convert_exe = b.addExecutable("rgb10a2convert", "src/RGB10A2/RGB10A2ConvertApp.zig");
    rgb10a2convert_exe.setBuildMode(mode);
    rgb10a2convert_exe.setMainPkgPath("src");
    addSettings(rgb10a2convert_exe);
    b.installArtifact(rgb10a2convert_exe);

    // tests

    comptime var i: u32 = 0;
    inline while (i < testNames.len) : (i += 1) {
        const t = b.addTest("src/" ++ testFiles[i]);
        t.setBuildMode(mode);
        t.setMainPkgPath("src");
        addSettings(t);
        test_step.dependOn(&t.step);

        const step = b.step("test-" ++ testNames[i], "Run all tests for " ++ testFiles[i]);
        step.dependOn(&t.step);
    }

    b.default_step.dependOn(demo_step);
}
