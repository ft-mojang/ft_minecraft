const std = @import("std");

const vk = @import("vulkan");
const glfw = @import("mach-glfw");

const window_title = "ft_minecraft";
const window_width = 640;
const window_height = 480;

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("{}: {s}\n", .{ error_code, description });
}

pub fn main() !void {
    glfw.setErrorCallback(logGLFWError);

    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    defer glfw.terminate();

    if (!glfw.vulkanSupported()) {
        std.log.err("host does not support Vulkan", .{});
        return error.GLFWInitFailed;
    }

    const window = glfw.Window.create(window_width, window_height, window_title, null, null, .{
        .client_api = .no_api,
        .resizable = false,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.CreateWindowFailed;
    };
    defer window.destroy();

    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
