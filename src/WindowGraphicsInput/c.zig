pub const c = @cImport({
    @cInclude("glad/glad.h");

    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");

    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");
});
