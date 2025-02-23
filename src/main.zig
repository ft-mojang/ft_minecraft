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

    window.setInputModeCursor(.disabled);
    window.setInputModeRawMouseMotion(true);

    const fn_get_proc_addr = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    var vk_ctx = try vulkan.Context.init(arena, fn_get_proc_addr, glfw_extensions, window);
    defer vk_ctx.deinit();

    var vk_allocator = vulkan.Allocator.init(arena, vk_ctx);
    defer vk_allocator.deinit();

    var vertices_list = ArrayList(Vec3f).init(arena);
    defer vertices_list.deinit();
    var indices_list = ArrayList(u32).init(arena);
    defer indices_list.deinit();

    const world_size = 8;
    for (0..world_size) |x| {
        for (0..world_size) |y| {
            for (0..world_size) |z| {
                const chunk_x = @as(Chunk.Coord, @intCast(x)) - world_size / 2;
                const chunk_y = @as(Chunk.Coord, @intCast(y)) - world_size / 2;
                const chunk_z = @as(Chunk.Coord, @intCast(z)) - world_size / 2;
                const chunk = Chunk.generate(chunk_x, chunk_y, chunk_z);

                var vertices, var indices = try chunk.toMesh(arena);
                for (vertices, 0..) |_, i| {
                    vertices[i] += Vec3f{
                        @floatFromInt(@as(Block.Coord, chunk_x) * Chunk.size),
                        @floatFromInt(@as(Block.Coord, chunk_y) * Chunk.size),
                        @floatFromInt(@as(Block.Coord, chunk_z) * Chunk.size),
                    };
                }
                for (indices, 0..) |_, i| {
                    indices[i] += @intCast(vertices_list.items.len);
                }

                try vertices_list.appendSlice(vertices);
                try indices_list.appendSlice(indices);
            }
        }
    }

    const vertices = vertices_list.items;
    const indices = indices_list.items;

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

    var game_state = GameState{
        .player_position = Vec3f{ 0.0, 0.0, 32.0 },
        .player_rotation = Vec3f{ 0.0, 0.0, 0.0 },
        .camera_forward = Vec3f{ 0.0, 0.0, 1.0 },
    };

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
            update(&game_state, &window, simulation_time, delta_time);
            accumulated_update_time -= fixed_time_step;
            simulation_time += fixed_time_step;
            update_count += 1;
        }

        const alpha = accumulated_update_time / fixed_time_step;
        try render(&game_state, vk_ctx, &renderer, alpha);

        prev_time = curr_time;
    }
    try vk_ctx.device.deviceWaitIdle();
}

// Funny temporary input impl
var input_mouse_last = Vec2f{ 0.0, 0.0 };

fn keyToAxis(window: *const glfw.Window, key: glfw.Key) f32 {
    return if (window.getKey(key) == .press) 1.0 else 0.0;
}

fn update(state: *GameState, window: *const glfw.Window, t: f64, dt: f64) void {
    //const camera_y = zm.vec.normalize(camera_x, camera_z);

    const mouse_sensitivity = 0.5;
    const mouse_pos_glfw = window.getCursorPos();
    const mouse_position = Vec2f{ @floatCast(mouse_pos_glfw.xpos), @floatCast(mouse_pos_glfw.ypos) };
    const mouse_delta = zm.vec.scale(mouse_position - input_mouse_last, @as(f32, @floatCast(dt)) * mouse_sensitivity);
    input_mouse_last = mouse_position;

    state.player_rotation[0] += mouse_delta[1]; // Pitch
    state.player_rotation[1] += mouse_delta[0]; // Yaw

    state.camera_forward = zm.vec.normalize(Vec3f{
        std.math.cos(state.player_rotation[1]) * std.math.cos(state.player_rotation[0]),
        std.math.sin(state.player_rotation[0]),
        std.math.sin(state.player_rotation[1]) * std.math.cos(state.player_rotation[0]),
    });
    const camera_right = zm.vec.normalize(zm.vec.cross(zm.vec.up(f32), state.camera_forward));
    const camera_up = zm.vec.normalize(zm.vec.cross(state.camera_forward, camera_right));

    const movement_speed: f32 = 100.0;
    const delta_velocity = zm.vec.scale(Vec3f{
        -keyToAxis(window, .a) + keyToAxis(window, .d),
        -keyToAxis(window, .left_control) + keyToAxis(window, .space),
        -keyToAxis(window, .s) + keyToAxis(window, .w),
    }, @as(f32, @floatCast(dt)) * movement_speed);

    state.player_position += zm.vec.scale(camera_right, delta_velocity[0]);
    state.player_position += zm.vec.scale(camera_up, delta_velocity[1]);
    state.player_position += zm.vec.scale(state.camera_forward, -delta_velocity[2]);
    _ = t;
}

fn render(
    game_state: *const GameState,
    ctx: vulkan.Context,
    renderer: *vulkan.Renderer,
    interpolation_alpha: f64,
) !void {
    _ = interpolation_alpha;

    // TODO: Blocks until frame acquired, maybe should be in or before non-fixed update?
    const frame = try renderer.acquireFrame(ctx);

    const up = Vec3f{ 0.0, 1.0, 0.0 };
    const look_at = game_state.player_position - game_state.camera_forward;
    // const fov_y = 45.0;
    const width: f32 = @floatFromInt(renderer.extent.width);
    const height: f32 = @floatFromInt(renderer.extent.height);
    const aspect_ratio = width / height;
    const near = 0.1;
    const far = 1000.0;

    frame.uniform_buffer_mapped.* = .{
        .model = Matrix4(f32).fromMat4f(Mat4f.identity().transpose()),
        .view = Matrix4(f32).fromMat4f(Mat4f.lookAt(game_state.player_position, look_at, up).transpose()),
        .proj = Matrix4(f32).fromMat4f(Mat4f.perspective(std.math.pi / 4.0, aspect_ratio, near, far).transpose()),
    };

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
            .y = @floatFromInt(renderer.extent.height),
            .width = @floatFromInt(renderer.extent.width),
            .height = -1.0 * @as(f32, @floatFromInt(renderer.extent.height)),
            .min_depth = 0.0,
            .max_depth = 1.0,
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

test {
    std.testing.refAllDecls(@import("math.zig"));
}

const vulkan = @import("vulkan.zig");
const CommandBufferSingleUse = vulkan.CommandBufferSingleUse;
const worldgen = @import("worldgen.zig");
const Block = worldgen.Block;
const Chunk = worldgen.Chunk;
const types = @import("types.zig");
const GameState = types.GameState;
const Matrix4 = types.Matrix4;

const std = @import("std");
const ArrayList = std.ArrayList;
const log = std.log.scoped(.main);
const heap = std.heap;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");
const zm = @import("zm");
const Vec2f = zm.Vec2f;
const Vec3f = zm.Vec3f;
const Vec4f = zm.Vec4f;
const Mat4f = zm.Mat4f;
const Quaternion = zm.Quaternion;
