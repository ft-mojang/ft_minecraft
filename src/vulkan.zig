const builtin = @import("builtin");
const config = @import("config");
const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.vulkan);

const vk = @import("vulkan");
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
pub const Instance = vk.InstanceProxy(apis);
pub const Device = vk.DeviceProxy(apis);
pub const Queue = vk.QueueProxy(apis);

pub const Context = @import("vulkan/Context.zig");
pub const vk_allocator = @import("vulkan/allocator.zig");
pub const Allocator = vk_allocator.Allocator;
pub const Swapchain = @import("vulkan/Swapchain.zig");

pub const app_info: vk.ApplicationInfo = .{
    .api_version = vk.API_VERSION_1_2,
    .application_version = 0,
    .engine_version = 0,
};

pub const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
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
    vk.extensions.ext_validation_features.name,
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_enumeration.name,
    },
    else => [_][*:0]const u8{},
};

pub const instance_exts_opt = [_][*:0]const u8{
    vk.extensions.ext_debug_utils,
};

pub const device_exts_req = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_dynamic_rendering.name,
    // NOTE: Not available in apple aarch64
    // vk.extensions.ext_vertex_input_dynamic_state.name
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
