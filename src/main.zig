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

    var vk_allocator = vulkan.Allocator.init(arena, vk_ctx);
    defer vk_allocator.deinit();

    const chunk = worldgen.Chunk.generate(0, 0);
    const vertices, const indices = try chunk.toMesh(arena);

    // Triangul
    //const vertices: []const Vec3f = &.{ .{ -0.8, 0.8, 0.0 }, .{ 0.8, 0.8, 0.0 }, .{ 0.0, -0.8, 0.0 } };
    //const indices: []const u32 = &.{ 0, 1, 2 };

    const vertex_buffer_size = @sizeOf(Vec3f) * vertices.len;
    const index_buffer_size = @sizeOf(u32) * indices.len;

    var renderer = try vulkan.Renderer.init(arena, &vk_allocator, vk_ctx, vertices, indices);
    defer renderer.deinit(vk_ctx);

    try vk_allocator.copySliceToAllocation(Vec3f, vertices, renderer.vertex_staging_buffer.allocation);
    try vk_allocator.copySliceToAllocation(u32, indices, renderer.index_staging_buffer.allocation);

    var cmd_buf_single_use = try CommandBufferSingleUse.create(vk_ctx.device, renderer.command_pool);
    vk_ctx.device.cmdCopyBuffer(
        cmd_buf_single_use.vk_handle,
        renderer.vertex_staging_buffer.vk_handle,
        renderer.vertex_buffer.vk_handle,
        1,
        @alignCast(@ptrCast(&vk.BufferCopy{
            .size = vertex_buffer_size,
            .src_offset = 0,
            .dst_offset = 0,
        })),
    );
    vk_ctx.device.cmdCopyBuffer(
        cmd_buf_single_use.vk_handle,
        renderer.index_staging_buffer.vk_handle,
        renderer.index_buffer.vk_handle,
        1,
        @alignCast(@ptrCast(&vk.BufferCopy{
            .size = index_buffer_size,
            .src_offset = 0,
            .dst_offset = 0,
        })),
    );
    vulkan.cmdTransitionImageLayout(.{
        .device = vk_ctx.device,
        .command_buffer = cmd_buf_single_use.vk_handle,
        .image = renderer.depth_image.vk_handle,
        .old_layout = .undefined,
        .new_layout = .depth_stencil_attachment_optimal,
    });
    try cmd_buf_single_use.submitAndDestroy(vk_ctx.queue.handle);

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

    const eyes = Vec3f{ 8.0, 150.0, 128.0 };
    const up = Vec3f{ 0.0, 1.0, 0.0 };
    const look_at = Vec3f{ 8.0, 150.0, 0.0 };
    const fov_y = 45.0;
    const width: f32 = @floatFromInt(renderer.extent.width);
    const height: f32 = @floatFromInt(renderer.extent.height);
    const aspect_ratio = width / height;
    const near = 0.1;
    const far = 1000.0;

    frame.uniform_buffer_mapped.* = .{
        .model = Matrix4(f32).fromMat4f(Mat4f.identity().transpose()),
        .view = Matrix4(f32).fromMat4f(Mat4f.lookAt(eyes, look_at, up).transpose()),
        .proj = Matrix4(f32).fromMat4f(Mat4f.perspective(fov_y, aspect_ratio, near, far).transpose()),
    };
    frame.uniform_buffer_mapped.proj.data[5] *= -1;

    try ctx.device.resetCommandBuffer(frame.command_buffer, .{});
    try ctx.device.beginCommandBuffer(frame.command_buffer, &.{});

    vulkan.cmdTransitionImageLayout(.{
        .device = ctx.device,
        .command_buffer = frame.command_buffer,
        .image = frame.image,
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
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
            .color_attachment_count = 1,
            .p_color_attachments = @alignCast(@ptrCast(&.{
                vk.RenderingAttachmentInfoKHR{
                    .image_view = frame.view,
                    .image_layout = vk.ImageLayout.color_attachment_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = .clear,
                    .store_op = .store,
                    .clear_value = vk.ClearValue{
                        .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 0.0 } },
                    },
                },
            })),
            .p_depth_attachment = &vk.RenderingAttachmentInfoKHR{
                .store_op = .dont_care,
                .load_op = .clear,
                .resolve_mode = .{},
                .resolve_image_layout = .undefined,
                .image_layout = .depth_stencil_attachment_optimal,
                .image_view = renderer.depth_view,
                .clear_value = vk.ClearValue{
                    .depth_stencil = .{
                        .depth = 1.0,
                        .stencil = 0.0,
                    },
                },
            },
        },
    );

    ctx.device.cmdBindPipeline(frame.command_buffer, .graphics, renderer.pipeline);

    ctx.device.cmdSetScissor(
        frame.command_buffer,
        0,
        1,
        &.{vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = renderer.extent,
        }},
    );

    ctx.device.cmdSetViewport(
        frame.command_buffer,
        0,
        1,
        &.{vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(renderer.extent.width),
            .height = @floatFromInt(renderer.extent.height),
            .min_depth = 0,
            .max_depth = 0,
        }},
    );

    ctx.device.cmdBindVertexBuffers(
        frame.command_buffer,
        0,
        1,
        &.{renderer.vertex_buffer.vk_handle},
        &.{0},
    );

    ctx.device.cmdBindIndexBuffer(
        frame.command_buffer,
        renderer.index_buffer.vk_handle,
        0,
        .uint32,
    );

    ctx.device.cmdBindDescriptorSets(
        frame.command_buffer,
        vk.PipelineBindPoint.graphics,
        renderer.pipeline_layout,
        0, // first set
        1, // descriptor set count
        &.{frame.descriptor_set},
        0, // dynamic offset count
        null, // p dynamic offsets
    );

    ctx.device.cmdDrawIndexed(frame.command_buffer, @truncate(renderer.indices.len), 1, 0, 0, 0);

    ctx.device.cmdEndRenderingKHR(frame.command_buffer);

    vulkan.cmdTransitionImageLayout(.{
        .device = ctx.device,
        .command_buffer = frame.command_buffer,
        .image = frame.image,
        .old_layout = .color_attachment_optimal,
        .new_layout = .present_src_khr,
    });

    try ctx.device.endCommandBuffer(frame.command_buffer);
    try renderer.submitAndPresentAcquiredFrame(ctx);
}

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    log.err("{}: {s}\n", .{ error_code, description });
}

const vulkan = @import("vulkan.zig");
const worldgen = @import("worldgen.zig");
const CommandBufferSingleUse = vulkan.CommandBufferSingleUse;
const types = @import("types.zig");
const Matrix4 = types.Matrix4;

const std = @import("std");
const log = std.log.scoped(.main);
const heap = std.heap;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");
const zm = @import("zm");
const Vec3f = zm.Vec3f;
const Vec4f = zm.Vec4f;
const Mat4f = zm.Mat4f;
