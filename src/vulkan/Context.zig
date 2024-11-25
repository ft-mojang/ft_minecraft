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

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const instance_extensions = [_][*:0]const u8{};

const QueueFamilies = struct { graphics_queue: u32 = 0, present_queue: u32 = 0 };

allocator: Allocator = undefined,
vkb: BaseDispatch = undefined,
vki: InstanceDispatch = undefined,
instance: Instance = undefined,
physical_device: vk.PhysicalDevice = undefined,
queue_families: QueueFamilies = undefined,
surface: vk.SurfaceKHR = undefined,

pub fn init(
    allocator: Allocator,
    fn_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    platform_instance_extensions: [][*:0]const u8,
    window: glfw.Window,
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
    errdefer self.instance.destroyInstance(null);

    _ = glfw.createWindowSurface(instance_handle, window, null, &self.surface);
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    self.physical_device = try self.pickPhysicalDevice(allocator);
    return self;
}

pub fn deinit(self: *Self) void {
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
    self.allocator.destroy(self);
}

fn pickPhysicalDevice(self: *Self, allocator: Allocator) !vk.PhysicalDevice {
    const available_devices = try self.instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(available_devices);

    // score cant be less then 0 anyway
    var max_score: u64 = 0;
    var max_device: vk.PhysicalDevice = undefined;

    for (available_devices) |pdev| {
        const extension_score = self.checkExtensionSupport(allocator, pdev) catch continue;
        const surface_score = self.checkSurfaceSupport(allocator, pdev) catch continue;
        const queue_score = self.checkDeviceQueueSupport(allocator, pdev) catch continue;
        const score = extension_score + surface_score + queue_score;
        if (max_score < score) {
            max_score = score;
            max_device = pdev;
        }
    }
    if (max_score != 0) {
        _ = try self.allocDeviceQueues(allocator, max_device);
        return max_device;
    }
    return error.NoSuitableDevice;
}

fn checkExtensionSupport(
    self: Self,
    allocator: Allocator,
    pdev: vk.PhysicalDevice,
) !u64 {
    const device_properties = try self.instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
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

fn checkSurfaceSupport(
    self: Self,
    allocator: Allocator,
    pdev: vk.PhysicalDevice,
) !u32 {
    _ = allocator;
    var format_count: u32 = undefined;
    _ = try self.instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, self.surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try self.instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, self.surface, &present_mode_count, null);

    if (format_count > 0 and present_mode_count > 0)
        return format_count + present_mode_count;
    return error.FeatureNotPresent;
}

fn checkDeviceQueueSupport(
    self: Self,
    allocator: Allocator,
    pdev: vk.PhysicalDevice,
) !u64 {
    const families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try self.instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, self.surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return families.len;
    }

    return error.FeatureNotPresent;
}

fn allocDeviceQueues(
    self: *Self,
    allocator: Allocator,
    pdev: vk.PhysicalDevice,
) !void {
    const families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try self.instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, self.surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        self.queue_families = QueueFamilies{ .graphics_queue = graphics_family.?, .present_queue = present_family.? };
    }
}
