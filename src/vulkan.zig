pub const app_info: vk.ApplicationInfo = .{
    .api_version = vk.API_VERSION_1_2,
    .application_version = 0,
    .engine_version = 0,
};

pub const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_portability_enumeration,
    vk.extensions.khr_portability_subset,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
    vk.extensions.ext_debug_utils,
    vk.extensions.ext_validation_features,
    vk.extensions.khr_dynamic_rendering,
};

pub const validation_layers_req = if (config.validation_layers) [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
} else [_][*:0]const u8{};

pub const validation_layers_opt = if (config.validation_layers) [_][*:0]const u8{} else [_][*:0]const u8{};

pub const enabled_validation_features = if (config.validation_layers) [_]vk.ValidationFeatureEnableEXT{
    .best_practices_ext,
    .gpu_assisted_ext,
    .gpu_assisted_reserve_binding_slot_ext,
    .synchronization_validation_ext,
} else [_]vk.ValidationFeatureEnableEXT{};

pub const disabled_validation_features = [_]vk.ValidationFeatureDisableEXT{};

pub const instance_exts_req = [_][*:0]const u8{
    vk.extensions.khr_surface.name,
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_enumeration.name,
    },
    else => [_][*:0]const u8{},
};

pub const instance_exts_opt = [_][*:0]const u8{
    vk.extensions.ext_debug_utils.name,
    vk.extensions.ext_validation_features.name,
};

pub const device_exts_req = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_dynamic_rendering.name,
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_subset.name,
    },
    else => [_][*:0]const u8{},
};

pub const device_exts_opt = [_][*:0]const u8{};

pub const identity_component_mapping = vk.ComponentMapping{
    .r = .identity,
    .g = .identity,
    .b = .identity,
    .a = .identity,
};

pub fn findMemoryType(
    instance: Instance,
    physical_device: vk.PhysicalDevice,
    type_filter: u32,
    flags: vk.MemoryPropertyFlags,
) !u32 {
    const properties = instance.getPhysicalDeviceMemoryProperties(physical_device);

    for (0..properties.memory_type_count) |memory_type| {
        if (type_filter & (@as(u32, 1) << @intCast(memory_type)) == 0) {
            continue;
        }

        const property_flags = properties.memory_types[memory_type].property_flags;

        if (flags.intersect(property_flags) == flags) {
            return @intCast(memory_type);
        }
    }

    return error.MemoryTypeNotFound;
}

/// Safely create a vk.ImageView slice with same same base info for a slice of vk.Images.
/// Use `destroyImageViews` to destroy.
pub fn createImageViewsForImages(
    allocator: mem.Allocator,
    device: Device,
    create_info: vk.ImageViewCreateInfo,
    images: []const vk.Image,
) ![]vk.ImageView {
    const views = try allocator.alloc(vk.ImageView, images.len);
    var _create_info = create_info;
    var ok = true;

    for (views, images) |*view, image| {
        _create_info.image = image;
        view.* = device.createImageView(&_create_info, null) catch |e| blk: {
            ok = false;
            log.err("failed to create image view: {!}", .{e});
            break :blk vk.ImageView.null_handle;
        };
    }

    if (ok) {
        return views;
    }

    destroyImageViews(allocator, device, views);
    return error.FailedToCreateImageViews;
}

/// Destroys a vk.ImageView slice created with `createImageViewsForImages`.
pub fn destroyImageViews(allocator: mem.Allocator, device: Device, views: []vk.ImageView) void {
    for (views) |view| {
        device.destroyImageView(view, null);
    }
    allocator.free(views);
}

pub fn cmdTransitionImageLayout(options: CmdTransitionImageLayoutOptions) void {
    const Transition = struct {
        src_stage: vk.PipelineStageFlags,
        dst_stage: vk.PipelineStageFlags,
        src_access_mask: vk.AccessFlags,
        dst_access_mask: vk.AccessFlags,
        aspect_mask: vk.ImageAspectFlags = .{ .color_bit = true },
    };

    // Really scuffed auto formatting
    // zig fmt: off
    const transition = if (
        options.old_layout == vk.ImageLayout.undefined and
        options.new_layout == vk.ImageLayout.color_attachment_optimal)
    // zig fmt: on
    blk: {
        break :blk Transition{
            .src_stage = .{ .top_of_pipe_bit = true },
            .dst_stage = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_write_bit = true },
        };
    } else if (
    // zig fmt: off
        options.old_layout == vk.ImageLayout.color_attachment_optimal and
        options.new_layout == vk.ImageLayout.present_src_khr)
    // zig fmt: on
    blk: {
        break :blk Transition{
            .src_stage = .{ .color_attachment_output_bit = true },
            .dst_stage = .{ .bottom_of_pipe_bit = true },
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},
        };
    } else if (
    // zig fmt: off
        options.old_layout == vk.ImageLayout.undefined and
        options.new_layout == vk.ImageLayout.depth_stencil_attachment_optimal)
    // zig fmt: on
    blk: {
        break :blk Transition{
            .src_stage = .{ .top_of_pipe_bit = true },
            .dst_stage = .{ .early_fragment_tests_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{
                .depth_stencil_attachment_read_bit = true,
                .depth_stencil_attachment_write_bit = true,
            },
            .aspect_mask = .{ .depth_bit = true },
            // TODO: Stencil component?
        };
    } else {
        @panic("layout transition not defined");
    };

    const barrier = vk.ImageMemoryBarrier{
        .old_layout = options.old_layout,
        .new_layout = options.new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .src_access_mask = transition.src_access_mask,
        .dst_access_mask = transition.dst_access_mask,
        .image = options.image,
        .subresource_range = vk.ImageSubresourceRange{
            .aspect_mask = transition.aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    const dependency_flags = .{};
    const memory_barrier_count = 0;
    const memory_barriers = null;
    const buffer_memory_barrier_count = 0;
    const buffer_memory_barriers = null;
    const image_memory_barrier_count = 1;

    options.device.cmdPipelineBarrier(
        options.command_buffer,
        transition.src_stage,
        transition.dst_stage,
        dependency_flags,
        memory_barrier_count,
        memory_barriers,
        buffer_memory_barrier_count,
        buffer_memory_barriers,
        image_memory_barrier_count,
        @alignCast(@ptrCast(&barrier)),
    );
}

pub fn createCommandBuffer(device: Device, pool: vk.CommandPool) !vk.CommandBuffer {
    var command_buffer = vk.CommandBuffer.null_handle;

    try device.allocateCommandBuffers(
        &vk.CommandBufferAllocateInfo{
            .command_pool = pool,
            .level = vk.CommandBufferLevel.primary,
            .command_buffer_count = 1,
        },
        @alignCast(@ptrCast(&command_buffer)),
    );

    return command_buffer;
}

pub fn destroyCommandBuffer(device: Device, pool: vk.CommandPool, buffer: vk.CommandBuffer) void {
    device.freeCommandBuffers(pool, 1, @alignCast(@ptrCast(&buffer)));
}

pub fn cmdCopySimpleBuffer(ctx: Context, command_buffer: vk.CommandBuffer, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) void {
    const region_count = 1;
    ctx.device.cmdCopyBuffer(
        command_buffer,
        src,
        dst,
        region_count,
        @alignCast(@ptrCast(&.{
            .src_offset = 0,
            .dst_offset = 0,
            .size = size,
        })),
    );
}

pub const CommandBufferSingleUse = struct {
    device: Device,
    pool: vk.CommandPool,
    vk_handle: vk.CommandBuffer,

    pub fn create(device: Device, pool: vk.CommandPool) !CommandBufferSingleUse {
        var self: CommandBufferSingleUse = undefined;
        self.vk_handle = try createCommandBuffer(device, pool);
        errdefer destroyCommandBuffer(device, pool, self.vk_handle);
        self.pool = pool;
        self.device = device;
        try self.device.beginCommandBuffer(self.vk_handle, &.{});
        return self;
    }

    pub fn submitAndDestroy(self: *CommandBufferSingleUse, queue: vk.Queue) !void {
        debug.assert(self.vk_handle != .null_handle);

        var err: ?anyerror = null;

        if (self.device.endCommandBuffer(self.vk_handle)) {
            const submit_count = 1;
            self.device.queueSubmit(
                queue,
                submit_count,
                @alignCast(@ptrCast(&vk.SubmitInfo{
                    .command_buffer_count = 1,
                    .p_command_buffers = @alignCast(@ptrCast(&self.vk_handle)),
                })),
                vk.Fence.null_handle,
            ) catch |e| {
                err = e;
            };
        } else |e| {
            err = e;
        }

        // TODO: Proper sync
        self.device.queueWaitIdle(queue) catch |e| {
            err = e;
        };

        destroyCommandBuffer(self.device, self.pool, self.vk_handle);
        self.vk_handle = .null_handle;

        if (err) |e| {
            return e;
        }
    }
};

pub const CmdTransitionImageLayoutOptions = struct {
    device: Device,
    command_buffer: vk.CommandBuffer,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
};

pub const vk_allocator = @import("vulkan/allocator.zig");
pub const Allocator = vk_allocator.Allocator;
pub const Context = @import("vulkan/Context.zig");
pub const Renderer = @import("vulkan/Renderer.zig");

const config = @import("config");
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.vulkan);
const debug = std.debug;

pub const vk = @import("vulkan");
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
pub const Queue = vk.QueueProxy(apis);
