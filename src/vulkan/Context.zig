const vk = @import("vulkan");
const glfw = @import("mach-glfw");

const std = @import("std");
const log = std.log;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

const vulkan = @import("../vulkan.zig");
const BaseDispatch = vulkan.BaseDispatch;
const InstanceDispatch = vulkan.InstanceDispatch;
const DeviceDispatch = vulkan.DeviceDispatch;
const Instance = vulkan.Instance;
const Device = vulkan.Device;
const Queue = vulkan.Queue;

const Self = @This();

allocator: Allocator,
vkb: BaseDispatch,
instance: Instance,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
device: Device,
queue_family_index: u32,
queue_family_properties: vk.QueueFamilyProperties,
queue: Queue,

pub fn init(
    allocator: Allocator,
    fn_get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    platform_instance_exts: [][*:0]const u8,
    window: glfw.Window,
) !Self {
    var self: Self = undefined;

    self.allocator = allocator;

    self.vkb = try BaseDispatch.load(fn_get_instance_proc_addr);
    if (try self.vkb.enumerateInstanceVersion() < vulkan.app_info.api_version) {
        return error.InsufficientInstanceVersion;
    }

    self.instance = try initInstance(allocator, self.vkb, platform_instance_exts);
    errdefer self.instance.destroyInstance(null);

    if (glfw.createWindowSurface(self.instance.handle, window, null, &self.surface) != 0) {
        log.err("failed to create Vulkan surface: {?s}", .{glfw.getErrorString()});
        return error.CreateSurfaceFailed;
    }
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    self.physical_device, self.physical_device_properties = try pickPhysicalDevice(allocator, self.instance);
    self.queue_family_index, self.queue_family_properties = try pickQueueFamily(allocator, self.instance, self.physical_device, self.surface);

    self.device = try initDevice(self.instance, self.physical_device, self.queue_family_index);
    errdefer self.device.destroyDevice(null);

    const queue_handle = self.device.getDeviceQueue(self.queue_family_index, 0);
    self.queue = Queue.init(queue_handle, self.device.wrapper);

    return self;
}

pub fn deinit(self: *Self) void {
    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
}

fn initInstance(
    allocator: Allocator,
    vkb: BaseDispatch,
    platform_instance_exts: [][*:0]const u8,
) !Instance {
    var enabled_instance_exts = try ArrayList([*:0]const u8)
        .initCapacity(allocator, vulkan.instance_exts_req.len + platform_instance_exts.len);
    defer enabled_instance_exts.deinit();
    enabled_instance_exts.appendSliceAssumeCapacity(&vulkan.instance_exts_req);
    for (platform_instance_exts) |platform_ext| {
        for (enabled_instance_exts.items) |enabled_ext| {
            if (mem.eql(u8, mem.span(platform_ext), mem.span(enabled_ext))) {
                break;
            }
        } else {
            enabled_instance_exts.appendAssumeCapacity(platform_ext);
        }
    }

    const validation_features = vk.ValidationFeaturesEXT{
        .enabled_validation_feature_count = vulkan.enabled_validation_features.len,
        .p_enabled_validation_features = &vulkan.enabled_validation_features,
        .disabled_validation_feature_count = vulkan.disabled_validation_features.len,
        .p_disabled_validation_features = &vulkan.disabled_validation_features,
    };

    const instance_create_info: vk.InstanceCreateInfo = .{
        .p_next = &validation_features,
        .flags = .{ .enumerate_portability_bit_khr = (builtin.os.tag == .macos) },
        .p_application_info = &vulkan.app_info,
        .enabled_layer_count = vulkan.validation_layers_req.len,
        .pp_enabled_layer_names = &vulkan.validation_layers_req,
        .enabled_extension_count = @intCast(enabled_instance_exts.items.len),
        .pp_enabled_extension_names = enabled_instance_exts.items.ptr,
    };

    const instance_handle = try vkb.createInstance(&instance_create_info, null);
    const vki = try InstanceDispatch.load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr);
    return Instance.init(instance_handle, vki);
}

fn pickPhysicalDevice(allocator: Allocator, instance: Instance) !struct { vk.PhysicalDevice, vk.PhysicalDeviceProperties } {
    const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_devices);
    const phys_device = physical_devices[0];
    const properties = instance.getPhysicalDeviceProperties(phys_device);
    if (properties.api_version < vulkan.app_info.api_version) {
        return error.InsufficientDeviceVersion;
    }

    return .{ phys_device, properties };
}

fn pickQueueFamily(
    allocator: Allocator,
    instance: Instance,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !struct { u32, vk.QueueFamilyProperties } {
    const device_queue_family_properties = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);
    defer allocator.free(device_queue_family_properties);
    for (device_queue_family_properties, 0..) |properties, i| {
        if (!properties.queue_flags.graphics_bit) {
            continue;
        }
        const index: u32 = @intCast(i);
        if (try instance.getPhysicalDeviceSurfaceSupportKHR(physical_device, index, surface) == vk.FALSE) {
            continue;
        }
        return .{ index, properties };
    } else {
        return error.NoSuitableQueueFamily;
    }
}

fn initDevice(
    instance: Instance,
    physical_device: vk.PhysicalDevice,
    queue_family_index: u32,
) !Device {
    const device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
            .{
                .p_queue_priorities = &.{1.0},
                .queue_count = 1,
                .queue_family_index = queue_family_index,
            },
        },
        .enabled_layer_count = vulkan.validation_layers_req.len,
        .pp_enabled_layer_names = &vulkan.validation_layers_req,
        .enabled_extension_count = vulkan.device_exts_req.len,
        .pp_enabled_extension_names = &vulkan.device_exts_req,
        .p_enabled_features = &.{},
    };

    const device_handle = try instance.createDevice(physical_device, &device_create_info, null);
    const vkd = try DeviceDispatch.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr);
    return Device.init(device_handle, vkd);
}
