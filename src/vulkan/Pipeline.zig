const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const vulkan = @import("vulkan.zig");
const VulkanContext = vulkan.Context;
const Swapchain = vulkan.Swapchain;
const Self = @This();

const vert_spv align(@alignOf(u32)) = @embedFile("../vert.spv").*;
const frag_spv align(@alignOf(u32)) = @embedFile("../frag.spv").*;

pipeline: vk.Pipeline,
commandpool: vk.CommandPool,
commandbuffers: [3]vk.CommandBuffer, // one command buffer per frame (max 3 for triple buffered)

pub fn init(
    allocator: Allocator,
    context: VulkanContext,
    swapchain: Swapchain,
) !Self {
    const self: Self = undefined;
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
    const vert = try context.device.createShaderModule(
        &.{
            .code_size = vert_spv.len,
            .p_code = @ptrCast(vert_spv),
        },
        null,
    );
    defer context.device.destroyShaderModule(vert, null);
    const frag = try context.device.createShaderModule(
        &.{
            .code_size = frag_spv.len,
            .p_code = @ptrCast(frag_spv),
        },
        null,
    );
    defer context.device.destroyShaderModule(frag, null);
    context.device.createGraphicsPipelines(
        .null_handle,
        1,
        &vk.GraphicsPipelineCreateInfo{
            .flags = .{},
            .p_stages = &[_]vk.PipelineShaderStageCreateInfo{
                .{
                    .stage = .{ .vertex_bit = true },
                    .module = vert,
                    .p_name = "main",
                },
                .{
                    .stage = .{ .fragment_bit = true },
                    .module = frag,
                    .p_name = "main",
                },
            },
            .p_next = &pipelineinfo,
            .render_pass = .null_handle,
            .subpass = 0,
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
