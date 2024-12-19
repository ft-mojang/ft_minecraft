const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");

const Self = @This();
const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);
const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);
const Queue = vk.QueueProxy(apis);
const CommandBuffer = vk.CommandBufferProxy(apis);

const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

const app_info: vk.ApplicationInfo = .{
    .api_version = vk.API_VERSION_1_2,
    .application_version = 0,
    .engine_version = 0,
    .p_application_name = "ft_minecraft",
};

const validation_layers = if (builtin.mode == .Debug) [_][*:0]const u8{
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

vkb: BaseDispatch,
instance: Instance,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
queue_family_index: u32,
queue_family_properties: vk.QueueFamilyProperties,
device: Device,
queue: Queue,

pub fn init(
    allocator: Allocator,
    fn_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    platform_instance_extensions: [][*:0]const u8,
    window: glfw.Window,
) !Self {
    var self: Self = undefined;
    self.vkb = try BaseDispatch.load(fn_get_instance_proc_addr);
    if (try self.vkb.enumerateInstanceVersion() < app_info.api_version) {
        return error.InsufficientInstanceVersion;
    }

    try self.initInstance(allocator, platform_instance_extensions);
    errdefer self.instance.destroyInstance(null);

    if (glfw.createWindowSurface(self.instance.handle, window, null, &self.surface) != 0) {
        return error.SurfaceCreationFailed;
    }
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    try self.initDevice(allocator);
    errdefer self.device.destroyDevice(null);

    const queue_handle = self.device.getDeviceQueue(self.queue_family_index, 0);
    self.queue = Queue.init(queue_handle, self.device.wrapper);

    return self;
}

pub fn deinit(self: Self) void {
    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
}

fn initInstance(
    self: *Self,
    allocator: Allocator,
    platform_instance_extensions: [][*:0]const u8,
) !void {
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
        .p_application_info = &app_info,
        .enabled_layer_count = validation_layers.len,
        .pp_enabled_layer_names = &validation_layers,
        .enabled_extension_count = @intCast(enabled_instance_extensions.items.len),
        .pp_enabled_extension_names = enabled_instance_extensions.items.ptr,
    };

    const instance_handle = try self.vkb.createInstance(&instance_create_info, null);
    const vki = try InstanceDispatch.load(instance_handle, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance_handle, vki);
}

fn pickPhysicalDevice(
    self: *Self,
    allocator: Allocator,
) !void {
    var physical_device_count: u32 = undefined;
    if (try self.instance.enumeratePhysicalDevices(&physical_device_count, null) != vk.Result.success) {
        return error.PhysicalDeviceEnumerationFailed;
    }
    if (physical_device_count == 0) {
        return error.ZeroPhysicalDevicesFound;
    }
    const physical_devices = try allocator.alloc(vk.PhysicalDevice, physical_device_count);
    defer allocator.free(physical_devices);
    if (try self.instance.enumeratePhysicalDevices(&physical_device_count, physical_devices.ptr) != vk.Result.success) {
        return error.PhysicalDeviceEnumerationFailed;
    }

    self.physical_device = physical_devices[0];
    self.physical_device_properties = self.instance.getPhysicalDeviceProperties(self.physical_device);
    if (self.physical_device_properties.api_version < app_info.api_version) {
        return error.InsufficientDeviceVersion;
    }
}

fn pickQueueFamily(
    self: *Self,
    allocator: Allocator,
) !void {
    var queue_family_count: u32 = undefined;
    self.instance.getPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, null);
    if (queue_family_count == 0) {
        return error.ZeroQueueFamiliesFound;
    }
    const queue_family_properties = try allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_family_properties);
    self.instance.getPhysicalDeviceQueueFamilyProperties(self.physical_device, &queue_family_count, queue_family_properties.ptr);
    for (queue_family_properties, 0..) |properties, i| {
        if (!properties.queue_flags.graphics_bit) {
            continue;
        }
        const index: u32 = @intCast(i);
        if (try self.instance.getPhysicalDeviceSurfaceSupportKHR(self.physical_device, index, self.surface) == vk.FALSE) {
            continue;
        }
        self.queue_family_properties = properties;
        self.queue_family_index = index;
        break;
    } else {
        return error.NoSuitableQueueFamily;
    }
}

fn initDevice(
    self: *Self,
    allocator: Allocator,
) !void {
    try self.pickPhysicalDevice(allocator);
    try self.pickQueueFamily(allocator);

    const device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
            .{
                .p_queue_priorities = &.{1.0},
                .queue_count = 1,
                .queue_family_index = self.queue_family_index,
            },
        },
        .enabled_layer_count = validation_layers.len,
        .pp_enabled_layer_names = &validation_layers,
        .enabled_extension_count = device_extensions.len,
        .pp_enabled_extension_names = &device_extensions,
        .p_enabled_features = &.{},
    };

    const device_handle = try self.instance.createDevice(self.physical_device, &device_create_info, null);
    const vkd = try DeviceDispatch.load(device_handle, self.instance.wrapper.dispatch.vkGetDeviceProcAddr);
    self.device = Device.init(device_handle, vkd);
}
