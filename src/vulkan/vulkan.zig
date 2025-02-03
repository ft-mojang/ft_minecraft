const vk = @import("vulkan");
pub const BaseDispatch = vk.BaseWrapper(apis);
pub const InstanceDispatch = vk.InstanceWrapper(apis);
pub const DeviceDispatch = vk.DeviceWrapper(apis);
pub const InstanceProxy = vk.InstanceProxy(apis);
pub const DeviceProxy = vk.DeviceProxy(apis);
pub const QueueProxy = vk.QueueProxy(apis);
pub const CommandBufferProxy = vk.CommandBufferProxy(apis);

pub usingnamespace @import("allocator/allocator.zig");
pub const Context = @import("Context.zig");

pub const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

pub const app_info: vk.ApplicationInfo = .{
    .api_version = vk.API_VERSION_1_2,
    .application_version = 0,
    .engine_version = 0,
    .p_application_name = "ft_minecraft",
};
