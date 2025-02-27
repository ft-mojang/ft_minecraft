const window_title = "ft_minecraft";
const window_width = 640;
const window_height = 480;

const zm = @import("zm");

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

    window.setCursorPos(0.0, 0.0);
    window.setInputModeCursor(.disabled);
    window.setInputModeRawMouseMotion(true);

    const fn_get_proc_addr = @as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress));
    var vk_ctx = try vulkan.Context.init(arena, fn_get_proc_addr, glfw_extensions, window);
    defer vk_ctx.deinit();

    var vk_allocator = vulkan.Allocator.init(arena, vk_ctx);
    defer vk_allocator.deinit();

    const world_size = 8;
    var chunk_list = try ArrayList(Chunk).initCapacity(arena, world_size * world_size * world_size);
    defer chunk_list.deinit();

    var vertices_list = ArrayList(Vec3f).init(arena);
    defer vertices_list.deinit();
    var indices_list = ArrayList(u32).init(arena);
    defer indices_list.deinit();

    for (0..world_size) |x| {
        for (0..world_size) |y| {
            for (0..world_size) |z| {
                const chunk_x = @as(Chunk.Coord, @intCast(x)) - world_size / 2;
                const chunk_y = @as(Chunk.Coord, @intCast(y)) - world_size / 2;
                const chunk_z = @as(Chunk.Coord, @intCast(z)) - world_size / 2;
                chunk_list.appendAssumeCapacity(Chunk.generate(chunk_x, chunk_y, chunk_z));

                var vertices, var indices = try chunk_list.items[chunk_list.items.len - 1].toMesh(arena);
                for (vertices, 0..) |_, i| {
                    vertices[i].addAssign(Vec3f.xyz(
                        @floatFromInt(@as(Block.Coord, chunk_x) * Chunk.size),
                        @floatFromInt(@as(Block.Coord, chunk_y) * Chunk.size),
                        @floatFromInt(@as(Block.Coord, chunk_z) * Chunk.size),
                    ));
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
        .format = renderer.depth_format,
    });
    try cmd_buf_single_use.submitAndDestroy(vk_ctx.queue.handle);

    var game_state = GameState{
        .player_position = Vec3f.xyz(0.0, 32.0, 0.0),
        .player_rotation = Vec3f.xyz(0.0, std.math.pi / 2.0, 0.0),

        .camera_x = Vec3f.scalar(0.0),
        .camera_y = Vec3f.scalar(0.0),
        .camera_z = Vec3f.scalar(0.0),
    };

    const max_updates_per_loop = 8;
    const fixed_time_step = 1.0 / 60.0;
    var simulation_time: f64 = 0.0;
    var accumulated_update_time: f64 = 0.0;
    var prev_time: f64 = glfw.getTime();
    const cursor = window.getCursorPos();
    var input_mouse_last = Vec2f.xy(@floatCast(cursor.xpos), @floatCast(cursor.ypos));
    while (!window.shouldClose()) {
        const curr_time = glfw.getTime();
        const delta_time = curr_time - prev_time;
        accumulated_update_time += delta_time;

        glfw.pollEvents();

        var update_count: u8 = 0;
        while (accumulated_update_time >= fixed_time_step and update_count <= max_updates_per_loop) {
            update(&game_state, &window, simulation_time, delta_time, &input_mouse_last);
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
var input_mouse_cursor = false;

fn keyToAxis(window: *const glfw.Window, key: glfw.Key) f32 {
    return if (window.getKey(key) == .press) 1.0 else 0.0;
}

fn update(state: *GameState, window: *const glfw.Window, t: f64, dt: f64, input_mouse_last: *Vec2f) void {
    if (window.getKey(.one) == .press) {
        window.setCursorPos(0.0, 0.0);
        input_mouse_last.* = Vec2f.xy(0.0, 0.0);
        window.setInputModeCursor(.disabled);
        input_mouse_cursor = false;
    } else if (window.getKey(.two) == .press) {
        window.setInputModeCursor(.normal);
        input_mouse_cursor = true;
    }

    if (input_mouse_cursor) return;

    const mouse_sensitivity = 0.3;
    const mouse_pos_glfw = window.getCursorPos();
    const mouse_position = Vec2f.xy(@floatCast(mouse_pos_glfw.xpos), @floatCast(mouse_pos_glfw.ypos));
    const mouse_delta = mouse_position.sub(input_mouse_last)
        .mul(@as(f32, @floatCast(dt)) * mouse_sensitivity);
    input_mouse_last.* = mouse_position;

    state.player_rotation.x += mouse_delta.y; // Pitch
    state.player_rotation.y += mouse_delta.x; // Yaw

    const pitch_min = -std.math.pi * 0.5;
    const pitch_max = std.math.pi * 0.5;
    state.player_rotation.x = std.math.clamp(state.player_rotation.x, pitch_min, pitch_max);

    state.camera_z = Vec3f.xyz(
        math.cos(state.player_rotation.y) * math.cos(state.player_rotation.x),
        math.sin(state.player_rotation.x),
        math.sin(state.player_rotation.y) * math.cos(state.player_rotation.x),
    ).normalize();

    state.camera_x = Vec3f.xyz(
        math.sin(state.player_rotation.y),
        0,
        -math.cos(state.player_rotation.y),
    ).normalize();

    state.camera_y = state.camera_z.cross(state.camera_x).normalize();

    const movement_speed: f32 = 100.0;
    const delta_velocity = Vec3f.xyz(
        -keyToAxis(window, .a) + keyToAxis(window, .d),
        -keyToAxis(window, .left_control) + keyToAxis(window, .space),
        -keyToAxis(window, .s) + keyToAxis(window, .w),
    ).mul(@as(f32, @floatCast(dt)) * movement_speed);

    state.player_position.addAssign(state.camera_x.mul(delta_velocity.x));
    state.player_position.addAssign(state.camera_y.mul(delta_velocity.y));
    state.player_position.addAssign(state.camera_z.mul(-delta_velocity.z));
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

    const up = game_state.camera_y;
    const look_at = game_state.player_position.sub(game_state.camera_z);
    // const fov_y = 45.0;
    const width: f32 = @floatFromInt(renderer.extent.width);
    const height: f32 = @floatFromInt(renderer.extent.height);
    const aspect_ratio = width / height;
    const near = 0.1;
    const far = 1000.0;

    frame.uniform_buffer_mapped.* = .{
        .model = Mat4f.translate(Vec3f.xyz(0, 0, -100)),
        .view = Mat4f.lookAt(game_state.player_position, look_at, up),
        .proj = Mat4f.perspective(math.pi / 4.0, aspect_ratio, near, far),
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
                        .depth = 0.0,
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

const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;
const log = std.log.scoped(.main);
const heap = std.heap;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");
const ftm = @import("math.zig");
const Vec2f = ftm.Vec2fx;
const Vec3f = ftm.Vec3fx;
const Vec4f = ftm.Vec4fx;
const Mat4f = ftm.Mat4f;
