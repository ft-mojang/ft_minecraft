const window_title = "ft_minecraft";
const window_width = 640;
const window_height = 480;

pub fn main() !void {
    var general_purpose_allocator = heap.GeneralPurposeAllocator(.{}).init;
    defer _ = general_purpose_allocator.deinit();
    const gpa = general_purpose_allocator.allocator();

    var arena_allocator = heap.ArenaAllocator.init(gpa);
    defer _ = arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    glfw.setErrorCallback(logGLFWError);

    if (!glfw.init(.{})) {
        log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    defer glfw.terminate();

    if (!glfw.vulkanSupported()) {
        log.err("host does not support Vulkan", .{});
        return error.GLFWInitFailed;
    }

    const glfw_extensions = glfw.getRequiredInstanceExtensions() orelse {
        log.err("failed to get required vulkan instance extensions: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    };

    const window = glfw.Window.create(window_width, window_height, window_title, null, null, .{
        .client_api = .no_api,
        .resizable = false,
    }) orelse {
        log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.CreateWindowFailed;
    };
    defer window.destroy();

    const fn_get_proc_addr = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    var vk_ctx = try vulkan.Context.init(arena, fn_get_proc_addr, glfw_extensions, window);
    defer vk_ctx.deinit();

    var renderer = try vulkan.Renderer.init(arena, vk_ctx);
    defer renderer.deinit(vk_ctx);

    var vk_allocator = vulkan.Allocator.init(arena, vk_ctx);
    defer vk_allocator.deinit();

    const chunk = worldgen.generateChunk(0, 0);
    _ = chunk;

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

        const alpha = accumulated_update_time / fixed_time_step;
        try render(vk_ctx, &renderer, alpha);

        prev_time = curr_time;
    }
    try vk_ctx.device.deviceWaitIdle();
}

fn update(t: f64, dt: f64) void {
    _ = t;
    _ = dt;
}

fn render(
    ctx: vulkan.Context,
    renderer: *vulkan.Renderer,
    interpolation_alpha: f64,
) !void {
    _ = interpolation_alpha;

    // TODO: Blocks until frame acquired, maybe should be in or before non-fixed update?
    const frame = try renderer.acquireFrame(ctx);
    try ctx.device.resetCommandBuffer(frame.command_buffer, .{});
    try ctx.device.beginCommandBuffer(frame.command_buffer, &.{});

    vulkan.cmdTransitionImageLayout(.{
        .device = ctx.device,
        .command_buffer = frame.command_buffer,
        .image = frame.image,
        .old_layout = .undefined,
        .new_layout = .present_src_khr,
    });

    ctx.device.cmdBeginRenderingKHR(
        frame.command_buffer,
        &vk.RenderingInfoKHR{
            .render_area = vk.Rect2D{
                .extent = renderer.extent,
                .offset = vk.Offset2D{ .x = 0, .y = 0 },
            },
            .view_mask = 0,
            .layer_count = 1,
            //.color_attachment_count = 1,
            //.p_color_attachments = @alignCast(@ptrCast(&.{
            //    vk.RenderingAttachmentInfoKHR {
            //        .image_view = frame.view,
            //        .image_layout = .present_src_khr,
            //        .resolve_image_layout = .present_src_khr,
            //        .resolve_mode = .{},
            //        .load_op = .clear,
            //        .store_op = .store,
            //        .clear_value = vk.ClearValue {
            //            .color = .{ .float_32 = .{0.0, 0.0, 0.0, 0.0} },
            //        },
            //    },
            //})),
        },
    );

    ctx.device.cmdEndRenderingKHR(frame.command_buffer);
    try ctx.device.endCommandBuffer(frame.command_buffer);
    try renderer.submitAndPresentAcquiredFrame(ctx);
}

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    log.err("{}: {s}\n", .{ error_code, description });
}

const vulkan = @import("vulkan.zig");
const worldgen = @import("worldgen.zig");

const std = @import("std");
const log = std.log;
const heap = std.heap;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");
