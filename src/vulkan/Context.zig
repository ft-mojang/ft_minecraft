allocator: Allocator,
vkb: BaseDispatch,
instance: Instance,
instance_extensions: AutoArrayHashMap([*:0]const u8, void),
validation_layers: AutoArrayHashMap([*:0]const u8, void),
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
device: Device,
device_extensions: AutoArrayHashMap([*:0]const u8, void),
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

    self.validation_layers = AutoArrayHashMap([*:0]const u8, void).init(allocator);
    errdefer self.validation_layers.deinit();
    try self.validation_layers.ensureTotalCapacity(vulkan.validation_layers_req.len + vulkan.validation_layers_opt.len);
    const layer_props = try self.vkb.enumerateInstanceLayerPropertiesAlloc(allocator);
    try appendValidationLayers(&self.validation_layers, &vulkan.validation_layers_req, layer_props);
    appendValidationLayers(&self.validation_layers, &vulkan.validation_layers_opt, layer_props) catch {};

    self.instance_extensions = AutoArrayHashMap([*:0]const u8, void).init(allocator);
    errdefer self.instance_extensions.deinit();
    try self.instance_extensions.ensureTotalCapacity(platform_instance_exts.len + vulkan.instance_exts_req.len + vulkan.instance_exts_opt.len);
    const instance_ext_props = try self.vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    try appendExtensions(&self.instance_extensions, platform_instance_exts, instance_ext_props);
    try appendExtensions(&self.instance_extensions, &vulkan.instance_exts_req, instance_ext_props);
    appendExtensions(&self.instance_extensions, &vulkan.instance_exts_opt, instance_ext_props) catch {};

    self.instance = try initInstance(self.vkb, self.validation_layers, self.instance_extensions);
    errdefer self.instance.destroyInstance(null);

    if (glfw.createWindowSurface(self.instance.handle, window, null, &self.surface) != 0) {
        log.err("failed to create Vulkan surface: {?s}", .{glfw.getErrorString()});
        return error.CreateSurfaceFailed;
    }
    errdefer self.instance.destroySurfaceKHR(self.surface, null);

    self.physical_device, self.physical_device_properties = try pickPhysicalDevice(allocator, self.instance);
    self.queue_family_index, self.queue_family_properties = try pickQueueFamily(allocator, self.instance, self.physical_device, self.surface);

    self.device_extensions = AutoArrayHashMap([*:0]const u8, void).init(allocator);
    errdefer self.device_extensions.deinit();
    try self.device_extensions.ensureTotalCapacity(vulkan.device_exts_req.len + vulkan.device_exts_opt.len);
    const device_ext_props = try self.instance.enumerateDeviceExtensionPropertiesAlloc(self.physical_device, null, allocator);
    try appendExtensions(&self.device_extensions, &vulkan.device_exts_req, device_ext_props);
    appendExtensions(&self.device_extensions, &vulkan.device_exts_opt, device_ext_props) catch {};

    self.device = try initDevice(self.instance, self.physical_device, self.queue_family_index, self.device_extensions);
    errdefer self.device.destroyDevice(null);

    const queue_handle = self.device.getDeviceQueue(self.queue_family_index, 0);
    self.queue = Queue.init(queue_handle, self.device.wrapper);

    return self;
}

pub fn deinit(self: *Self) void {
    self.instance_extensions.deinit();
    self.device_extensions.deinit();
    self.validation_layers.deinit();

    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
}

fn initInstance(vkb: BaseDispatch, validation_layers: AutoArrayHashMap([*:0]const u8, void), extensions: AutoArrayHashMap([*:0]const u8, void)) !Instance {
    const create_info: vk.InstanceCreateInfo = .{
        .flags = .{ .enumerate_portability_bit_khr = (builtin.os.tag == .macos) },
        .p_application_info = &vulkan.app_info,
        .enabled_layer_count = @intCast(validation_layers.count()),
        .pp_enabled_layer_names = validation_layers.keys().ptr,
        .enabled_extension_count = @intCast(extensions.count()),
        .pp_enabled_extension_names = extensions.keys().ptr,
    };

    const handle = try vkb.createInstance(&create_info, null);
    const vki = try InstanceDispatch.load(handle, vkb.dispatch.vkGetInstanceProcAddr);
    return Instance.init(handle, vki);
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
    extensions: AutoArrayHashMap([*:0]const u8, void),
) !Device {
    const create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
            .{
                .p_queue_priorities = &.{1.0},
                .queue_count = 1,
                .queue_family_index = queue_family_index,
            },
        },
        .enabled_extension_count = @intCast(extensions.count()),
        .pp_enabled_extension_names = extensions.keys().ptr,
        .p_enabled_features = &.{},
        .p_next = &vk.PhysicalDeviceDynamicRenderingFeaturesKHR{
            .dynamic_rendering = vk.TRUE,
        },
    };

    const handle = try instance.createDevice(physical_device, &create_info, null);
    const vkd = try DeviceDispatch.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr);
    return Device.init(handle, vkd);
}

fn appendExtensions(enabled_exts: *AutoArrayHashMap([*:0]const u8, void), exts: []const [*:0]const u8, ext_props: []vk.ExtensionProperties) !void {
    for (exts) |ext| {
        for (ext_props) |prop| {
            if (mem.eql(u8, mem.sliceTo(&prop.extension_name, 0), mem.span(ext))) {
                enabled_exts.putAssumeCapacity(ext, {});
                break;
            }
        } else {
            log.warn("instance extension missing: {s}", .{ext});
            return error.ExtensionNotPresent;
        }
    }
}

fn appendValidationLayers(enabled_layers: *AutoArrayHashMap([*:0]const u8, void), layers: []const [*:0]const u8, layer_props: []vk.LayerProperties) !void {
    for (layers) |layer| {
        for (layer_props) |prop| {
            if (mem.eql(u8, mem.sliceTo(&prop.layer_name, 0), mem.span(layer))) {
                enabled_layers.putAssumeCapacity(layer, {});
                break;
            }
        } else {
            log.warn("validation layer missing: {s}", .{layer});
            return error.ExtensionNotPresent;
        }
    }
}

const Self = @This();

const vulkan = @import("../vulkan.zig");
const BaseDispatch = vulkan.BaseDispatch;
const InstanceDispatch = vulkan.InstanceDispatch;
const DeviceDispatch = vulkan.DeviceDispatch;
const Instance = vulkan.Instance;
const Device = vulkan.Device;
const Queue = vulkan.Queue;

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.vulkan_context);
const mem = std.mem;
const Allocator = mem.Allocator;
const AutoArrayHashMap = std.AutoArrayHashMap;

const vk = @import("vulkan");
const glfw = @import("mach-glfw");
