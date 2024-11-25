const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

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

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const instance_extensions = [_][*:0]const u8{};

allocator: Allocator = undefined,
vkb: BaseDispatch = undefined,
vki: InstanceDispatch = undefined,
instance: Instance = undefined,

pub fn init(
    allocator: Allocator,
    fn_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    platform_instance_extensions: [][*:0]const u8,
) !*Self {
    var self: *Self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;

    self.vkb = try BaseDispatch.load(fn_get_instance_proc_addr);

    if (try self.vkb.enumerateInstanceVersion() < app_info.api_version)
        return error.InitializationFailed;

    var enabled_instance_extensions = try std.ArrayList([*:0]const u8)
        .initCapacity(allocator, instance_extensions.len + platform_instance_extensions.len);
    defer enabled_instance_extensions.deinit();
    try enabled_instance_extensions.appendSlice(platform_instance_extensions);
    try enabled_instance_extensions.appendSlice(&instance_extensions);
    if (builtin.os.tag == .macos)
        try enabled_instance_extensions.append(vk.extensions.khr_portability_enumeration.name);

    const instance_create_info: vk.InstanceCreateInfo = .{
        .flags = .{ .enumerate_portability_bit_khr = (builtin.os.tag == .macos) },
        .p_application_info = &app_info,
        .enabled_layer_count = if (builtin.mode == .Debug) validation_layers.len else 0,
        .pp_enabled_layer_names = &validation_layers,
        .enabled_extension_count = @intCast(enabled_instance_extensions.items.len),
        .pp_enabled_extension_names = enabled_instance_extensions.items.ptr,
    };

    const instance_handle = try self.vkb.createInstance(&instance_create_info, null);
    self.vki = try InstanceDispatch.load(instance_handle, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance_handle, &self.vki);

    return self;
}

pub fn deinit(self: *Self) void {
    self.instance.destroyInstance(null);
    self.allocator.destroy(self);
}

// scores the devices based on supported extensions, surfaces and queues
fn pickPhysicalDevice(surface: vk.SurfaceKHR, allocator: Allocator) !vk.PhysicalDevice {
    const available_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(available_devices);

    var max_score = undefined;
    var max_device = undefined;

    for (available_devices) |pdev| {
        const extension_score = checkExtensionSupport(pdev, allocator) catch continue;
        const surface_score = checkSurfaceSupport(pdev, surface, allocator) catch continue;
        const queue_score = checkDeviceQueueSupport(pdev, surface, allocator) catch continue;
        if (!max_score or max_score < extension_score + surface_score + queue_score) {
            max_score = extension_score + surface_score + queue_score;
            max_device = pdev;
        }
    }
    if (max_device) {
        allocDeviceQueues(max_device, surface, allocator);
        return max_device;
    }
    return error.NoSuitableDevice;
}

fn checkExtensionSupport(pdev: vk.PhysicalDevice, allocator: Allocator) !u32 {
    const device_properties = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(device_properties);

    for (instance_extensions) |extension| {
        for (device_properties) |property| {
            if (std.mem.eql(u8, property.extension_name, extension))
                break;
        } else {
            return error.ExtensionNotPresent;
        }
    }
    return device_properties.len;
}

fn checkSurfaceSupport(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: Allocator) !u32 {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);
    var present_modes = allocator.alloc(vk.PresentModeKHR, present_mode_count);
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, &present_modes);
    // check if the device supports vk::PresentModeKHR::eFifo, according to https://docs.vulkan.org/samples/latest/samples/performance/hpp_swapchain_images/README.html
    for (present_modes) |mode| {
        if (mode.efifo)
            break;
    } else {
        return error.FeatureNotPresent;
    }

    if (format_count > 0 and present_mode_count > 0)
        return format_count + present_mode_count;
    return error.FeatureNotPresent;
}

fn checkDeviceQueueSupport(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: Allocator) !i32 {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return families.len;
    }

    return error.FeatureNotPresent;
}

fn allocDeviceQueues(pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: Allocator) !void {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        queue_families = .{ .graphics_queue = graphics_family, .present_family = present_family };
    }

    // sanity check
    return error.FeatureNotPresent;
}
