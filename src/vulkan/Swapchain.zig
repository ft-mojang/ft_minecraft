const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");
const VulkanContext = vulkan.Context;

const Self = @This();

const preferred_present_mode = []vk.PresentModeKHR{
    .fifo_khr,
    .mailbox_khr,
};

const preferred_surface_format = vk.SurfaceFormatKHR{
    .format = .b8g8r8_unorm,
    .color_space = .srgb_nonlinear_khr,
};

const FrameInfo = struct {
    image: vk.Image,
    view: vk.ImageView,
    swapchain_semaphore: vk.Semaphore,
    render_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
};

surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,
swap_images: []FrameInfo,
image_index: u32,
next_image_acquired: vk.Semaphore,

pub fn init(
    allocator: Allocator,
    context: VulkanContext,
) !Self {
    var self: Self = undefined;
    const capabilities = try context.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        context.physical_device,
        context.surface,
    );
    if (capabilities.current_extent.width == 0 or capabilities.current_extent.height == 0)
        return error.SurfaceLostKHR;
    const surface_formats = try context.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
        context.physical_device,
        context.surface,
        allocator,
    );
    defer allocator.free(surface_formats);

    for (surface_formats) |sfmt| {
        if (std.meta.eql(sfmt, preferred_surface_format)) {
            self.surface_format = preferred_surface_format;
            break;
        }
    } else self.surface_format = surface_formats[0]; // There must always be at least one supported surface format

    return self;
}

pub fn deinit(self: Self) void {
    _ = self;
}