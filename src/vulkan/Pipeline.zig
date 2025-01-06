const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");
const VulkanContext = vulkan.Context;
const Swapchain = vulkan.Swapchain;
const Self = @This();

pipeline: vk.Pipeline,
commandpool: vk.CommandPool,
commandbuffers: vk.CommandBuffer[3], // one command buffer per frame (max 3 for triple buffered)

pub fn init(
    allocator: Allocator,
    context: VulkanContext,
    swapchain: Swapchain,
) !Self {
    const self: Self = undefined;
    // TODO load shader modules
    const pipelineinfo: vk.PipelineRenderingCreateInfoKHR = .{
        .p_next = &.null_handle,
        .color_attachment_count = 1,
        .p_color_attachment_formats = &[_]vk.Format{
            swapchain.surface_format.format,
        },
        // not permanent, didnt remember the proper attachment format
        .depth_attachment_format = .r8g8b8a8_unorm,
        .stencil_attachment_format = .r8g8b8a8_unorm,
        .view_mask = 0,
    };
    context.device.createGraphicsPipelines(
        .null_handle,
        1,
        &vk.GraphicsPipelineCreateInfo{
            .flags = {},
            .p_stages = &[_]vk.PipelineShaderStageCreateInfo{
                .{
                    .stage = .{ .vertex_bit = true },
                    .module = null,
                    .p_name = "main",
                },
            },
            .p_next = &pipelineinfo,
            .render_pass = .null_handle,
        },
        allocator,
        self.pipeline,
    );
    self.commandpool = try createCommandPool(context);
    errdefer context.device.destroyCommandPool(self.commandpool, null);

    self.commandbuffers = try createCommandBuffers(context, self.commandpool);

    self.createCommandBuffers(context);
    return self;
}

fn createCommandPool(
    context: VulkanContext,
) !vk.CommandPool {
    return context.device.createCommandPool(
        &.{ .queue_family_index = context.graphics_queue.queue_family_index, .flags = 2, .p_next = .null_handle },
        null,
    );
}

fn createCommandBuffers(
    self: Self,
    context: VulkanContext,
) !void {
    context.device.allocateCommandBuffers(
        &.{
            .command_buffer_count = 3,
            .level = vk.CommandBufferLevel.primary,
            .command_pool = self.commandpool,
        },
        &self.commandbuffers,
    );
}
