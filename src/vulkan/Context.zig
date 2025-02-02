const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");

const vulkan = @import("vulkan.zig");
const BaseDispatch = vulkan.BaseDispatch;
const InstanceDispatch = vulkan.InstanceDispatch;
const DeviceDispatch = vulkan.DeviceDispatch;
const InstanceProxy = vulkan.InstanceProxy;
const DeviceProxy = vulkan.DeviceProxy;
const QueueProxy = vulkan.QueueProxy;

const Self = @This();

const validation_layers = if (config.validation_layers) [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
} else [_][*:0]const u8{};

const instance_extensions = [_][*:0]const u8{
    vk.extensions.khr_surface.name,
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_enumeration.name,
    },
    else => [_][*:0]const u8{},
};

const device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
} ++ switch (builtin.os.tag) {
    .macos => [_][*:0]const u8{
        vk.extensions.khr_portability_subset.name,
    },
    else => [_][*:0]const u8{},
};

allocator: Allocator,
vkb: BaseDispatch,
vki: InstanceDispatch,
vkd: DeviceDispatch,
instance: InstanceProxy,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
device: DeviceProxy,
queue_family_index: u32,
queue_family_properties: vk.QueueFamilyProperties,
queue: QueueProxy,

pub fn init(
    allocator: Allocator,
    fn_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    platform_instance_extensions: [][*:0]const u8,
    window: glfw.Window,
) !Self {
    var self: Self = undefined;

    self.allocator = allocator;

    self.vkb = try BaseDispatch.load(fn_get_instance_proc_addr);
    if (try self.vkb.enumerateInstanceVersion() < vulkan.app_info.api_version) {
        return error.InsufficientInstanceVersion;
    }

    self.instance = try initInstance(allocator, self.vkb, &self.vki, platform_instance_extensions);
    errdefer self.instance.destroyInstance(null);

    if (glfw.createWindowSurface(self.instance.handle, window, null, &self.surface) != 0) {
        return error.SurfaceCreationFailed;
    }
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    self.physical_device = try pickPhysicalDevice(allocator, self.instance, &self.physical_device_properties);
    self.queue_family_index = try pickQueueFamily(allocator, self.instance, self.physical_device, self.surface, &self.queue_family_properties);

    self.device = try initDevice(self.instance, self.physical_device, self.queue_family_index, &self.vkd);
    errdefer self.device.destroyDevice(null);

    const queue_handle = self.device.getDeviceQueue(self.queue_family_index, 0);
    self.queue = QueueProxy.init(queue_handle, self.device.wrapper);

    return self;
}

pub fn deinit(self: *Self) void {
    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
    self.allocator.destroy(self);
}

pub fn findMemoryType(
    self: *const Self,
    type_filter: u32,
    flags: vk.MemoryPropertyFlags,
) !u32 {
    const properties = self.instance.getPhysicalDeviceMemoryProperties(self.physical_device);

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

fn initInstance(
    allocator: Allocator,
    vkb: BaseDispatch,
    vki: *InstanceDispatch,
    platform_instance_extensions: [][*:0]const u8,
) !InstanceProxy {
    var enabled_instance_extensions = try std.ArrayList([*:0]const u8)
        .initCapacity(allocator, instance_extensions.len + platform_instance_extensions.len);
    defer enabled_instance_extensions.deinit();
    enabled_instance_extensions.appendSliceAssumeCapacity(&instance_extensions);
    for (platform_instance_extensions) |platform_ext| {
        for (enabled_instance_extensions.items) |enabled_ext| {
            if (std.mem.eql(u8, std.mem.span(platform_ext), std.mem.span(enabled_ext))) {
                break;
            }
        } else {
            enabled_instance_extensions.appendAssumeCapacity(platform_ext);
        }
    }

    const instance_create_info: vk.InstanceCreateInfo = .{
        .flags = .{ .enumerate_portability_bit_khr = (builtin.os.tag == .macos) },
        .p_application_info = &vulkan.app_info,
        .enabled_layer_count = validation_layers.len,
        .pp_enabled_layer_names = &validation_layers,
        .enabled_extension_count = @intCast(enabled_instance_extensions.items.len),
        .pp_enabled_extension_names = enabled_instance_extensions.items.ptr,
    };

    const instance_handle = try vkb.createInstance(&instance_create_info, null);
    vki.* = try InstanceDispatch.load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr);
    return InstanceProxy.init(instance_handle, vki.*);
}

fn pickPhysicalDevice(
    allocator: Allocator,
    instance: InstanceProxy,
    physical_device_properties: *vk.PhysicalDeviceProperties,
) !vk.PhysicalDevice {
    var physical_device_count: u32 = undefined;
    if (try instance.enumeratePhysicalDevices(&physical_device_count, null) != vk.Result.success) {
        return error.PhysicalDeviceEnumerationFailed;
    }
    if (physical_device_count == 0) {
        return error.ZeroPhysicalDevicesFound;
    }
    const physical_devices = try allocator.alloc(vk.PhysicalDevice, physical_device_count);
    defer allocator.free(physical_devices);
    if (try instance.enumeratePhysicalDevices(&physical_device_count, physical_devices.ptr) != vk.Result.success) {
        return error.PhysicalDeviceEnumerationFailed;
    }

    const phys_device = physical_devices[0];
    const properties = instance.getPhysicalDeviceProperties(phys_device);
    if (properties.api_version < vulkan.app_info.api_version) {
        return error.InsufficientDeviceVersion;
    }

    physical_device_properties.* = properties;
    return phys_device;
}

fn pickQueueFamily(
    allocator: Allocator,
    instance: InstanceProxy,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    queue_family_properties: *vk.QueueFamilyProperties,
) !u32 {
    var queue_family_count: u32 = undefined;
    instance.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);
    if (queue_family_count == 0) {
        return error.ZeroQueueFamiliesFound;
    }
    const device_queue_family_properties = try allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer allocator.free(device_queue_family_properties);
    instance.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, device_queue_family_properties.ptr);
    for (device_queue_family_properties, 0..) |properties, i| {
        if (!properties.queue_flags.graphics_bit) {
            continue;
        }
        const index: u32 = @intCast(i);
        if (try instance.getPhysicalDeviceSurfaceSupportKHR(physical_device, index, surface) == vk.FALSE) {
            continue;
        }
        queue_family_properties.* = properties;
        return index;
    } else {
        return error.NoSuitableQueueFamily;
    }
}

fn initDevice(
    instance: InstanceProxy,
    physical_device: vk.PhysicalDevice,
    queue_family_index: u32,
    vkd: *DeviceDispatch,
) !DeviceProxy {
    const device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
            .{
                .p_queue_priorities = &.{1.0},
                .queue_count = 1,
                .queue_family_index = queue_family_index,
            },
        },
        .enabled_layer_count = validation_layers.len,
        .pp_enabled_layer_names = &validation_layers,
        .enabled_extension_count = device_extensions.len,
        .pp_enabled_extension_names = &device_extensions,
        .p_enabled_features = &.{},
    };

    const device_handle = try instance.createDevice(physical_device, &device_create_info, null);
    vkd.* = try DeviceDispatch.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr);
    return DeviceProxy.init(device_handle, vkd.*);
}
