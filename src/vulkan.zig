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
    };

    // Really scuffed auto formatting
    // zig fmt: off
    const transition = if (
        options.old_layout == vk.ImageLayout.undefined and
        options.new_layout == vk.ImageLayout.present_src_khr)
    // zig fmt: on
    blk: {
        // FIXME: This is not really a transition you want, just temp
        break :blk Transition{
            .src_stage = .{ .top_of_pipe_bit = true },
            .dst_stage = .{ .fragment_shader_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .shader_read_bit = true },
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
            .aspect_mask = .{ .color_bit = true },
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

const CmdTransitionImageLayoutOptions = struct {
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

pub const vk = @import("vulkan");
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
pub const Queue = vk.QueueProxy(apis);
