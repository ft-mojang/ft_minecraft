const std = @import("std");

const vk = @import("vulkan");
const glfw = @import("mach-glfw");

const vulkan = @import("vulkan.zig");
const VulkanContext = vulkan.Context;
const VulkanAllocator = vulkan.allocator.Allocator;
const worldgen = @import("worldgen.zig");

const window_title = "ft_minecraft";
const window_width = 640;
const window_height = 480;

fn update(t: f64, dt: f64) void {
    _ = t;
    _ = dt;
}

fn render(interpolation_alpha: f64) void {
    _ = interpolation_alpha;
}

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("{}: {s}\n", .{ error_code, description });
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = general_purpose_allocator.deinit();
    const gpa = general_purpose_allocator.allocator();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer _ = arena_allocator.deinit();
    const arena = arena_allocator.allocator();

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

    const glfw_extensions = glfw.getRequiredInstanceExtensions() orelse {
        std.log.err("failed to get required vulkan instance extensions: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    };

    const window = glfw.Window.create(window_width, window_height, window_title, null, null, .{
        .client_api = .no_api,
        .resizable = false,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.CreateWindowFailed;
    };
    defer window.destroy();

    const fn_get_proc_addr = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    var vk_ctx = try VulkanContext.init(arena, fn_get_proc_addr, glfw_extensions, window);
    defer vk_ctx.deinit();

    var vk_allocator = VulkanAllocator.init(arena, vk_ctx);
    defer vk_allocator.deinit();

    const chunk = worldgen.generateChunk(134217727, 0);
    worldgen.printChunk(chunk);

    const max_updates_per_loop = 8;
    const fixed_time_step = 1.0 / 60.0;
    var simulation_time: f64 = 0.0;
    var accumulated_update_time: f64 = 0.0;
    var prev_time: f64 = glfw.getTime();
    while (!window.shouldClose()) {
        const curr_time = glfw.getTime();
        const delta_time = curr_time - prev_time;
        accumulated_update_time += delta_time;

        glfw.pollEvents();

        var update_count: u8 = 0;
        while (accumulated_update_time >= fixed_time_step and update_count <= max_updates_per_loop) {
            update(simulation_time, delta_time);
            accumulated_update_time -= fixed_time_step;
            simulation_time += fixed_time_step;
            update_count += 1;
        }

        render(accumulated_update_time / fixed_time_step);

        prev_time = curr_time;
    }
}
