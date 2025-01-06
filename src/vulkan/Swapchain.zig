const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");
const VulkanContext = vulkan.Context;

const Self = @This();

const preferred_present_mode = [_]vk.PresentModeKHR{
    .fifo_khr,
    .mailbox_khr,
};

const preferred_surface_format = vk.SurfaceFormatKHR{
    .format = .b8g8r8_unorm,
    .color_space = .srgb_nonlinear_khr,
};

// TODO when dynamic rendering has to hold attachmentinfos
const FrameInfo = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(
        self: *FrameInfo,
        context: VulkanContext,
        image: vk.Image,
        format: vk.Format,
    ) !FrameInfo {
        self.view = try context.device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer context.device.destroyImageView(self.view, null);

        self.image = image;

        self.image_acquired = try context.device.createSemaphore(&.{}, null);
        errdefer context.device.destroySemaphore(self.image_acquired, null);

        self.render_finished = try context.device.createSemaphore(&.{}, null);
        errdefer context.device.destroySemaphore(self.render_finished, null);

        self.frame_fence = try context.device.createFence(
            &.{
                .flags = .{ .signaled_bit = true },
            },
            null,
        );
        errdefer context.device.destroyFence(self.frame_fence, null);

        return self.*;
    }

    fn deinit(self: FrameInfo, context: VulkanContext) void {
        _ = context.device.waitForFences(
            1,
            @ptrCast(&self.frame_fence),
            vk.TRUE,
            std.math.maxInt(u64),
        ) catch return;
        context.device.destroyImageView(self.view, null);
        context.device.destroySemaphore(self.image_acquired, null);
        context.device.destroySemaphore(self.render_finished, null);
        context.device.destroyFence(self.frame_fence, null);
    }
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
        .image_sharing_mode = .concurrent,
        .queue_family_index_count = 1,
        .p_queue_family_indices = &.{context.queue_family_index},
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = self.present_mode,
        .clipped = vk.TRUE,
    }, null);
    errdefer context.device.destroySwapchainKHR(self.handle, null);

    const images = try context.device.getSwapchainImagesAllocKHR(
        self.handle,
        allocator,
    );

    self.swap_images = try allocator.alloc(FrameInfo, images.len);
    errdefer {
        for (self.swap_images[0..images.len]) |si|
            si.deinit(context);
        allocator.free(self.swap_images);
    }

    for (0..image_count) |index| {
        self.swap_images[index] = try self.swap_images[index].init(
            context,
            images[index],
            self.surface_format.format,
        );
    }
    self.image_index = 0;
    return self;
}

pub fn deinit(self: Self, context: VulkanContext) void {
    for (self.swap_images[0..self.swap_images.len]) |si|
        si.deinit(context);
    context.device.destroySwapchainKHR(self.handle, null);
}

// double buffered, could be made to sync 3 frames
pub fn presentNextFrame(self: *Self, context: VulkanContext, cmdbuf: vk.CommandBuffer) !void {
    const current = self.swap_images[self.image_index];
    _ = context.device.waitForFences(
        1,
        @ptrCast(&current.frame_fence),
        vk.TRUE,
        std.math.maxInt(u64),
    ) catch return;
    try context.device.resetFences(1, @ptrCast(&current.frame_fence));

    // const wait_stage = [_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }};
    // TODO this has to go to the render function
    // try context.device.queueSubmit(context.graphics_queue, 1, &[_]vk.SubmitInfo{.{
    //     .wait_semaphore_count = 1,
    //     .p_wait_semaphores = @ptrCast(&current.image_acquired),
    //     .p_wait_dst_stage_mask = &wait_stage,
    //     .command_buffer_count = 1,
    //     .p_command_buffers = @ptrCast(&cmdbuf),
    //     .signal_semaphore_count = 1,
    //     .p_signal_semaphores = @ptrCast(&current.render_finished),
    // }}, current.frame_fence);
    _ = cmdbuf;

    // present current context
    _ = try context.device.queuePresentKHR(context.queue.handle, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&current.render_finished),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&self.handle),
        .p_image_indices = @ptrCast(&self.image_index),
    });

    // set next presentation context
    const result = try context.device.acquireNextImageKHR(
        self.handle,
        std.math.maxInt(u64),
        self.next_image_acquired,
        .null_handle,
    );

    std.mem.swap(vk.Semaphore, &self.swap_images[result.image_index].image_acquired, &self.next_image_acquired);
    self.image_index = result.image_index;
}
