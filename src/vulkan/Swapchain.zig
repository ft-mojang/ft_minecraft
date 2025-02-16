const std = @import("std");
const log = std.log.scoped(.vulkan);
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const vulkan = @import("../vulkan.zig");
const VulkanContext = vulkan.Context;
const Device = vulkan.Device;

const Self = @This();

const preferred_present_mode = [_]vk.PresentModeKHR{
    .fifo_khr,
    .mailbox_khr,
};

const preferred_surface_format = vk.SurfaceFormatKHR{
    .format = .b8g8r8_unorm,
    .color_space = .srgb_nonlinear_khr,
};

const max_frames_in_flight: u32 = 2;

const Frame = struct {
    in_flight: vk.Fence,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    command_buffer: vk.CommandBuffer,
};

command_pool: vk.CommandPool,
surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
handle: vk.SwapchainKHR,
image_index: u32,
frame_index: u32,
images: []vk.Image,
views: []vk.ImageView,
frames: []Frame,

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

    const present_modes = try context.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
        context.physical_device,
        context.surface,
        allocator,
    );
    defer allocator.free(present_modes);

    for (preferred_present_mode) |pref| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, pref) != null) {
            self.present_mode = pref;
            break;
        }
    } else self.present_mode = .fifo_khr;

    var image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0) {
        image_count = @min(image_count, capabilities.max_image_count);
    }

    self.handle = try context.device.createSwapchainKHR(&.{
        .surface = context.surface,
        .min_image_count = image_count,
        .image_format = self.surface_format.format,
        .image_color_space = self.surface_format.color_space,
        .image_extent = capabilities.current_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = &.{context.queue_family_index},
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = self.present_mode,
        .clipped = vk.TRUE,
    }, null);
    errdefer context.device.destroySwapchainKHR(self.handle, null);

    self.images = try context.device.getSwapchainImagesAllocKHR(
        self.handle,
        allocator,
    );
    errdefer allocator.free(self.images);

    self.views = try vulkan.createImageViewsForImages(
        allocator,
        context.device,
        .{
            .image = vk.Image.null_handle,
            .view_type = .@"2d",
            .format = self.surface_format.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        },
        self.images,
    );
    errdefer vulkan.destroyImageViews(allocator, context.device, self.views);

    self.frame_index = 0;

    self.command_pool = try context.device.createCommandPool(
        &.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = context.queue_family_index,
        },
        null,
    );
    errdefer context.device.destroyCommandPool(self.command_pool, null);

    self.frames = try createFrames(allocator, context.device, self.command_pool, max_frames_in_flight);

    return self;
}

pub fn deinit(self: Self, allocator: Allocator, device: Device) void {
    device.destroyCommandPool(self.command_pool, null);
    destroyFrames(allocator, device, self.frames);
    vulkan.destroyImageViews(allocator, device, self.views);
    allocator.free(self.images);
    device.destroySwapchainKHR(self.handle, null);
}

pub fn acquireFrame(self: *Self, context: vulkan.Context) !Frame {
    self.frame_index = self.frame_index + 1 % max_frames_in_flight;
    const current = self.frames[self.frame_index];

    _ = context.device.waitForFences(
        1,
        @ptrCast(&current.in_flight),
        vk.TRUE,
        std.math.maxInt(u64),
    ) catch return error.dafuq; // FIXME:

    try context.device.resetFences(1, @ptrCast(&current.in_flight));

    const result = try context.device.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        current.image_acquired,
        .null_handle,
    );

    self.image_index = result.image_index;

    return current;
}

pub fn submitAndPresentAcquiredFrame(self: *Self, context: vulkan.Context) !void {
    const current = self.frames[self.frame_index];

    try context.queue.submit(
        1,
        &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired),
            .p_wait_dst_stage_mask = &.{
                .{ .top_of_pipe_bit = true },
            },
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&current.command_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished),
        }},
        current.in_flight,
    );

    // present current context
    _ = try context.device.queuePresentKHR(
        context.queue.handle,
        &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
        },
    );
}

fn createFrames(allocator: Allocator, device: Device, command_pool: vk.CommandPool, count: u32) ![]Frame {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, count);
    defer allocator.free(command_buffers);
    try device.allocateCommandBuffers(
        &.{
            .command_pool = command_pool,
            .level = .primary,
            .command_buffer_count = count,
        },
        command_buffers.ptr,
    );

    const frames = try allocator.alloc(Frame, count);
    var ok = true;

    for (frames, command_buffers) |*frame, command_buffer| {
        const fence_info = vk.FenceCreateInfo{
            .flags = .{ .signaled_bit = true },
        };
        frame.* = .{
            .command_buffer = command_buffer,
            .in_flight = device.createFence(&fence_info, null) catch |e| blk: {
                ok = false;
                log.err("failed to create fence: {!}", .{e});
                break :blk vk.Fence.null_handle;
            },
            .image_acquired = device.createSemaphore(&.{}, null) catch |e| blk: {
                ok = false;
                log.err("failed to create semaphore: {!}", .{e});
                break :blk vk.Semaphore.null_handle;
            },
            .render_finished = device.createSemaphore(&.{}, null) catch |e| blk: {
                ok = false;
                log.err("failed to create semaphore: {!}", .{e});
                break :blk vk.Semaphore.null_handle;
            },
        };
    }

    if (ok) {
        return frames;
    }

    destroyFrames(allocator, device, frames);
    return error.FailedToCreateFrames;
}

fn destroyFrames(allocator: Allocator, device: Device, frames: []Frame) void {
    for (frames) |frame| {
        device.destroyFence(frame.in_flight, null);
        device.destroySemaphore(frame.image_acquired, null);
        device.destroySemaphore(frame.render_finished, null);
    }
    allocator.free(frames);
}
