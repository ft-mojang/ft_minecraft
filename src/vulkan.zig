const builtin = @import("builtin");
const config = @import("config");

const vk = @import("vulkan");
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
pub const InstanceProxy = vk.InstanceProxy(apis);
pub const DeviceProxy = vk.DeviceProxy(apis);
pub const QueueProxy = vk.QueueProxy(apis);

pub const Context = @import("vulkan/Context.zig");
pub const allocator = @import("vulkan/allocator.zig");

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
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_subset.name,
    },
    else => [_][*:0]const u8{},
};

pub const device_exts_opt = [_][*:0]const u8{};
