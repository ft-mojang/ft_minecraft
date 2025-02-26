allocator: Allocator,
vk_allocator: *vulkan.Allocator,
command_pool: vk.CommandPool,
surface_format: vk.SurfaceFormatKHR,
present_mode: vk.PresentModeKHR,
extent: vk.Extent2D,
swapchain: vk.SwapchainKHR,
image_index: u32,
frame_index: u32,
images: []vk.Image,
views: []vk.ImageView,
frames: []Frame,
pipeline_layout: vk.PipelineLayout,
pipeline: vk.Pipeline,
vertex_staging_buffer: Buffer,
vertex_buffer: Buffer,
vertex_buffer_size: vk.DeviceSize,
vertices: []const Vec3f,
index_staging_buffer: Buffer, // TODO: Share with vertex buffer?
index_buffer: Buffer,
indices: []const u32,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,
depth_image: Image,
depth_view: vk.ImageView,
depth_format: vk.Format,

const preferred_present_mode = [_]vk.PresentModeKHR{
    .fifo_khr,
    .mailbox_khr,
};

const preferred_surface_format = vk.SurfaceFormatKHR{
    .format = .b8g8r8_unorm,
    .color_space = .srgb_nonlinear_khr,
};

const max_frames_in_flight: u32 = 2;

pub fn init(
    allocator: Allocator,
    vk_allocator: *vulkan.Allocator,
    ctx: Context,
    vertices: []const Vec3f,
    indices: []const u32,
) !Self {
    var self: Self = undefined;
    self.allocator = allocator;
    self.vk_allocator = vk_allocator;
    self.vertices = vertices;
    self.indices = indices;
    const capabilities = try ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        ctx.physical_device,
        ctx.surface,
    );
    if (capabilities.current_extent.width == 0 or capabilities.current_extent.height == 0)
        return error.SurfaceLostKHR;
    self.extent = capabilities.current_extent;
    const surface_formats = try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
        ctx.physical_device,
        ctx.surface,
        allocator,
    );
    defer allocator.free(surface_formats);

    for (surface_formats) |sfmt| {
        if (meta.eql(sfmt, preferred_surface_format)) {
            self.surface_format = preferred_surface_format;
            break;
        }
    } else self.surface_format = surface_formats[0]; // There must always be at least one supported surface format

    const present_modes = try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
        ctx.physical_device,
        ctx.surface,
        allocator,
    );
    defer allocator.free(present_modes);

    for (preferred_present_mode) |pref| {
        if (mem.indexOfScalar(vk.PresentModeKHR, present_modes, pref) != null) {
            self.present_mode = pref;
            break;
        }
    } else self.present_mode = .fifo_khr;

    var image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0) {
        image_count = @min(image_count, capabilities.max_image_count);
    }

    self.swapchain = try ctx.device.createSwapchainKHR(&.{
        .surface = ctx.surface,
        .min_image_count = image_count,
        .image_format = self.surface_format.format,
        .image_color_space = self.surface_format.color_space,
        .image_extent = capabilities.current_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = &.{ctx.queue_family_index},
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = self.present_mode,
        .clipped = vk.TRUE,
    }, null);
    errdefer ctx.device.destroySwapchainKHR(self.swapchain, null);

    self.images = try ctx.device.getSwapchainImagesAllocKHR(
        self.swapchain,
        allocator,
    );
    errdefer allocator.free(self.images);

    self.views = try vulkan.createImageViewsForImages(
        allocator,
        ctx.device,
        .{
            .image = vk.Image.null_handle,
            .view_type = .@"2d",
            .format = self.surface_format.format,
            .components = vulkan.identity_component_mapping,
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
    errdefer vulkan.destroyImageViews(allocator, ctx.device, self.views);

    self.frame_index = 0;

    self.command_pool = try ctx.device.createCommandPool(
        &.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = ctx.queue_family_index,
        },
        null,
    );
    errdefer ctx.device.destroyCommandPool(self.command_pool, null);

    self.descriptor_set_layout = try createDescriptorSetLayout(ctx.device);
    errdefer ctx.device.destroyDescriptorSetLayout(self.descriptor_set_layout, null);

    self.descriptor_pool = try ctx.device.createDescriptorPool(
        &vk.DescriptorPoolCreateInfo{
            .flags = .{},
            .max_sets = 2,
            .pool_size_count = 1,
            .p_pool_sizes = &.{vk.DescriptorPoolSize{
                .type = .uniform_buffer,
                .descriptor_count = 2,
            }},
        },
        null,
    );
    errdefer ctx.device.destroyDescriptorPool(self.descriptor_pool, null);

    self.frames = try createFrames(
        allocator,
        vk_allocator,
        ctx.device,
        self.command_pool,
        self.descriptor_pool,
        self.descriptor_set_layout,
    );
    errdefer destroyFrames(allocator, vk_allocator, ctx.device, self.frames);

    self.pipeline_layout, self.pipeline = try createPipeline(ctx.device, self.surface_format.format, self.descriptor_set_layout);
    errdefer destroyPipeline(ctx.device, self.pipeline_layout, self.pipeline);

    self.vertex_staging_buffer = try self.vk_allocator.createBuffer(
        .{
            .size = @sizeOf(Vec3f) * vertices.len,
            .sharing_mode = .exclusive,
            .usage = .{ .transfer_src_bit = true },
        },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );
    errdefer self.vk_allocator.destroyBuffer(self.vertex_staging_buffer);

    self.vertex_buffer = try self.vk_allocator.createBuffer(
        .{
            .size = @sizeOf(Vec3f) * vertices.len,
            .sharing_mode = .exclusive,
            .usage = .{
                .transfer_dst_bit = true,
                .vertex_buffer_bit = true,
            },
        },
        .{ .device_local_bit = true },
    );
    errdefer self.vk_allocator.destroyBuffer(self.vertex_buffer);

    self.index_staging_buffer = try self.vk_allocator.createBuffer(
        .{
            .size = @sizeOf(u32) * indices.len,
            .sharing_mode = .exclusive,
            .usage = .{ .transfer_src_bit = true },
        },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );
    errdefer self.vk_allocator.destroyBuffer(self.index_staging_buffer);

    self.index_buffer = try self.vk_allocator.createBuffer(
        .{
            .size = @sizeOf(u32) * indices.len,
            .sharing_mode = .exclusive,
            .usage = .{
                .transfer_dst_bit = true,
                .index_buffer_bit = true,
            },
        },
        .{ .device_local_bit = true },
    );
    errdefer self.vk_allocator.destroyBuffer(self.index_buffer);

    self.depth_image, self.depth_view, self.depth_format = try createDepthImageAndView(
        ctx,
        self.vk_allocator,
        self.extent,
    );
    errdefer ctx.device.destroyImageView(self.depth_view, null);
    errdefer vk_allocator.destroyImage(self.depth_image);

    return self;
}

pub fn deinit(self: Self, ctx: Context) void {
    ctx.device.destroyImageView(self.depth_view, null);
    self.vk_allocator.destroyImage(self.depth_image);
    ctx.device.destroyDescriptorPool(self.descriptor_pool, null);
    ctx.device.destroyDescriptorSetLayout(self.descriptor_set_layout, null);
    self.vk_allocator.destroyBuffer(self.index_buffer);
    self.vk_allocator.destroyBuffer(self.index_staging_buffer);
    self.vk_allocator.destroyBuffer(self.vertex_buffer);
    self.vk_allocator.destroyBuffer(self.vertex_staging_buffer);
    destroyPipeline(ctx.device, self.pipeline_layout, self.pipeline);
    destroyFrames(self.allocator, self.vk_allocator, ctx.device, self.frames);
    ctx.device.destroyCommandPool(self.command_pool, null);
    vulkan.destroyImageViews(self.allocator, ctx.device, self.views);
    self.allocator.free(self.images);
    ctx.device.destroySwapchainKHR(self.swapchain, null);
}

pub fn acquireFrame(self: *Self, ctx: vulkan.Context) !Frame {
    self.frame_index = (self.frame_index + 1) % max_frames_in_flight;
    const current = &self.frames[self.frame_index];

    const wait_result = try ctx.device.waitForFences(
        1,
        @ptrCast(&current.in_flight),
        vk.TRUE,
        math.maxInt(u64),
    );
    debug.assert(wait_result == .success);

    try ctx.device.resetFences(1, @ptrCast(&current.in_flight));

    const acquire_result = try ctx.device.acquireNextImageKHR(
        self.swapchain,
        math.maxInt(u64),
        current.image_acquired,
        .null_handle,
    );
    self.image_index = acquire_result.image_index;

    current.view = self.views[self.image_index];
    current.image = self.images[self.image_index];
    // TODO: Do we want to handle surface suboptimal?

    return current.*;
}

pub fn submitAndPresentAcquiredFrame(self: *Self, ctx: vulkan.Context) !void {
    const current = self.frames[self.frame_index];

    try ctx.queue.submit(
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

    // present current ctx
    _ = try ctx.device.queuePresentKHR(
        ctx.queue.handle,
        &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.swapchain),
            .p_image_indices = @ptrCast(&self.image_index),
        },
    );
    // TODO: Handle out of date / suboptimal
}

fn createPipeline(
    device: Device,
    format: vk.Format,
    descriptor_set_layout: vk.DescriptorSetLayout,
) !struct { vk.PipelineLayout, vk.Pipeline } {
    const vertex_shader_code = @embedFile("shader.vert");
    const vertex_shader = try device.createShaderModule(
        &vk.ShaderModuleCreateInfo{
            .p_code = @alignCast(@ptrCast(vertex_shader_code)),
            .code_size = vertex_shader_code.len,
        },
        null,
    );
    defer device.destroyShaderModule(vertex_shader, null);

    const fragment_shader_code = @embedFile("shader.frag");
    const fragment_shader = try device.createShaderModule(
        &.{
            .p_code = @alignCast(@ptrCast(fragment_shader_code)),
            .code_size = fragment_shader_code.len,
        },
        null,
    );
    defer device.destroyShaderModule(fragment_shader, null);

    const vertex_binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vec3f),
        .input_rate = .vertex,
    };

    const vertex_attribute_description = vk.VertexInputAttributeDescription{
        .binding = 0,
        .location = 0,
        .format = .r32g32b32_sfloat,
        .offset = 0,
    };

    const layout = try device.createPipelineLayout(
        &vk.PipelineLayoutCreateInfo{
            .set_layout_count = 1,
            .p_set_layouts = @alignCast(@ptrCast(&descriptor_set_layout)),
        },
        null,
    );
    errdefer device.destroyPipelineLayout(layout, null);

    var pipeline = vk.Pipeline.null_handle;
    // TODO: Pull out inner structs so wont have to disable formatter here
    // zig fmt: off
    const result = try device.createGraphicsPipelines(
        vk.PipelineCache.null_handle,
        1, // Create info count,
        @alignCast(@ptrCast(&vk.GraphicsPipelineCreateInfo{
            .layout = layout,
            .p_viewport_state = &vk.PipelineViewportStateCreateInfo{
                .viewport_count = 1,
                .scissor_count = 1,
            },
            .p_dynamic_state = &vk.PipelineDynamicStateCreateInfo {
                .dynamic_state_count = 2,
                .p_dynamic_states = &.{
                    vk.DynamicState.viewport,
                    vk.DynamicState.scissor,
                },
            },
            .subpass = 0,
            .base_pipeline_index = 0,
            .p_vertex_input_state = &vk.PipelineVertexInputStateCreateInfo {
                .vertex_binding_description_count = 1,
                .p_vertex_binding_descriptions = @alignCast(@ptrCast(&vertex_binding_description)),
                .vertex_attribute_description_count = 1,
                .p_vertex_attribute_descriptions = @alignCast(@ptrCast(&vertex_attribute_description)),
            },
            .p_input_assembly_state = &vk.PipelineInputAssemblyStateCreateInfo {
                .topology = .triangle_list,
                .primitive_restart_enable = vk.FALSE,
            },
            .stage_count = 2,
            .p_stages = @alignCast(@ptrCast(&.{
                vk.PipelineShaderStageCreateInfo {
                    .module = vertex_shader,
                    .stage = .{ .vertex_bit = true },
                    .p_name = "main",
                },
                vk.PipelineShaderStageCreateInfo {
                    .module = fragment_shader,
                    .stage = .{ .fragment_bit = true },
                    .p_name = "main",
                },
            })),
            .p_multisample_state = &vk.PipelineMultisampleStateCreateInfo {
                .sample_shading_enable = vk.FALSE,
                .rasterization_samples = .{ .@"1_bit" = true },
                .min_sample_shading = 0.0,
                .alpha_to_coverage_enable = vk.FALSE,
                .alpha_to_one_enable = vk.FALSE,
            },
            .p_rasterization_state = &vk.PipelineRasterizationStateCreateInfo {
                .line_width = 1.0,
                .depth_bias_slope_factor = 0.0,
                .depth_bias_clamp = 0.0,
                .depth_bias_constant_factor = 0.0,
                .depth_bias_enable = vk.FALSE,
                .cull_mode = .{ .back_bit = true },
                .front_face = .counter_clockwise,
                .polygon_mode = .fill,
                .rasterizer_discard_enable = vk.FALSE,
                .depth_clamp_enable = vk.FALSE,
            },
            .p_color_blend_state = &vk.PipelineColorBlendStateCreateInfo{
                .logic_op_enable = vk.FALSE,
                .logic_op = .xor,
                .blend_constants = .{0.0, 0.0, 0.0, 0.0},
                .attachment_count = 1,
                .p_attachments = @alignCast(@ptrCast(&
                    vk.PipelineColorBlendAttachmentState {
                        .color_blend_op = vk.BlendOp.add,
                        .src_color_blend_factor = .zero,
                        .dst_color_blend_factor = .zero,
                        .src_alpha_blend_factor = .zero,
                        .dst_alpha_blend_factor = .zero,
                        .alpha_blend_op = vk.BlendOp.add,
                        .color_write_mask = vk.ColorComponentFlags {
                            .r_bit = true,
                            .g_bit = true,
                            .b_bit = true,
                            .a_bit = true,
                        },
                        .blend_enable = vk.FALSE,
                    },
                )),
            },
            .p_depth_stencil_state = &vk.PipelineDepthStencilStateCreateInfo {
                .depth_test_enable = vk.TRUE,
                .depth_write_enable = vk.TRUE,
                .depth_compare_op = .greater,
                .depth_bounds_test_enable = vk.FALSE,
                .min_depth_bounds = 0.0,
                .max_depth_bounds = 1.0,
                .stencil_test_enable = vk.FALSE,
                .front = vk.StencilOpState {
                    .fail_op = vk.StencilOp.zero,
                    .pass_op = vk.StencilOp.zero,
                    .depth_fail_op = vk.StencilOp.zero,
                    .compare_op = .less,
                    .compare_mask = 0,
                    .write_mask = 0,
                    .reference = 0,
                },
                .back = .{
                    .fail_op = vk.StencilOp.zero,
                    .pass_op = vk.StencilOp.zero,
                    .depth_fail_op = vk.StencilOp.zero,
                    .compare_op = .less,
                    .compare_mask = 0,
                    .write_mask = 0,
                    .reference = 0,
                },
            },
            .p_next = &vk.PipelineRenderingCreateInfoKHR {
                .color_attachment_count = 1,
                .p_color_attachment_formats = @alignCast(@ptrCast(&.{format})),
                .depth_attachment_format = .d32_sfloat,
                .stencil_attachment_format = vk.Format.undefined,
                .view_mask = 0,
            }
        })),
        null,
        @alignCast(@ptrCast(&pipeline)),
    );
    // zig fmt: on
    errdefer device.destroyPipeline(pipeline, null);
    debug.assert(result == .success);

    return .{ layout, pipeline };
}

fn destroyPipeline(device: Device, layout: vk.PipelineLayout, pipeline: vk.Pipeline) void {
    device.destroyPipeline(pipeline, null);
    device.destroyPipelineLayout(layout, null);
}

fn createFrames(
    allocator: Allocator,
    vk_allocator: *vulkan.Allocator,
    device: Device,
    command_pool: vk.CommandPool,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_layout: vk.DescriptorSetLayout,
) ![]Frame {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, max_frames_in_flight);
    defer allocator.free(command_buffers);
    try device.allocateCommandBuffers(
        &.{
            .command_pool = command_pool,
            .level = .primary,
            .command_buffer_count = max_frames_in_flight,
        },
        command_buffers.ptr,
    );

    var layouts: [max_frames_in_flight]vk.DescriptorSetLayout = @splat(descriptor_set_layout);
    var descriptor_sets: [max_frames_in_flight]vk.DescriptorSet = @splat(.null_handle);

    try device.allocateDescriptorSets(
        &vk.DescriptorSetAllocateInfo{
            .descriptor_pool = descriptor_pool,
            .descriptor_set_count = max_frames_in_flight,
            .p_set_layouts = &layouts,
        },
        &descriptor_sets,
    );

    const frames = try allocator.alloc(Frame, max_frames_in_flight);
    var ok = true;

    for (frames, command_buffers, descriptor_sets) |*frame, command_buffer, descriptor_set| {
        const fence_info = vk.FenceCreateInfo{
            .flags = .{ .signaled_bit = true },
        };

        const uniform_buffer = vk_allocator.createBuffer(
            vk.BufferCreateInfo{
                .size = @sizeOf(UniformBufferObject),
                .sharing_mode = .exclusive,
                .usage = vk.BufferUsageFlags{
                    .uniform_buffer_bit = true,
                },
            },
            vk.MemoryPropertyFlags{
                .host_visible_bit = true,
                .host_coherent_bit = true,
            },
        ) catch {
            @panic("unimplemented"); // TODO: stub value or builder
        };

        device.updateDescriptorSets(
            1, // descriptor write count
            &.{vk.WriteDescriptorSet{
                .dst_set = descriptor_set,
                .dst_binding = 0,
                .dst_array_element = 0,
                .descriptor_count = 1,
                .descriptor_type = .uniform_buffer,
                .p_buffer_info = @alignCast(@ptrCast(&vk.DescriptorBufferInfo{
                    .buffer = uniform_buffer.vk_handle,
                    .range = vk.WHOLE_SIZE,
                    .offset = 0,
                })),
                .p_image_info = &[_]vk.DescriptorImageInfo{},
                .p_texel_buffer_view = &[_]vk.BufferView{},
            }},
            0, // descriptor copy count
            null, // descriptor copies
        );

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
            .uniform_buffer = uniform_buffer,
            .uniform_buffer_mapped = @alignCast(@ptrCast(
                vk_allocator.map(uniform_buffer.allocation) catch @panic("unimplemented"),
            )),
            .descriptor_set = descriptor_set,
        };
    }

    if (ok) {
        return frames;
    }

    destroyFrames(allocator, vk_allocator, device, frames);
    return error.FailedToCreateFrames;
}

fn destroyFrames(
    allocator: Allocator,
    vk_allocator: *vulkan.Allocator,
    device: Device,
    frames: []Frame,
) void {
    for (frames) |frame| {
        vk_allocator.unmap(frame.uniform_buffer.allocation);
        vk_allocator.destroyBuffer(frame.uniform_buffer);
        device.destroyFence(frame.in_flight, null);
        device.destroySemaphore(frame.image_acquired, null);
        device.destroySemaphore(frame.render_finished, null);
    }
    allocator.free(frames);
}

fn createDescriptorSetLayout(
    device: Device,
) !vk.DescriptorSetLayout {
    const ubo_binding = vk.DescriptorSetLayoutBinding{
        .binding = 0,
        .descriptor_type = .uniform_buffer,
        .stage_flags = .{
            .vertex_bit = true,
            .fragment_bit = true,
        },
        .descriptor_count = 1,
    };

    const layout = try device.createDescriptorSetLayout(&vk.DescriptorSetLayoutCreateInfo{
        .flags = .{},
        .binding_count = 1,
        .p_bindings = @alignCast(@ptrCast(&ubo_binding)),
    }, null);

    return layout;
}

fn createDepthImageAndView(
    ctx: Context,
    vk_allocator: *vulkan.Allocator,
    extent: vk.Extent2D,
) !struct { Image, vk.ImageView, vk.Format } {
    const formats = &.{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint };
    const format_features = vk.FormatFeatureFlags{ .depth_stencil_attachment_bit = true };

    const format = vulkan.selectSupportedOptimalTilingFormat(ctx, formats, format_features) orelse {
        return error.NoSupportedDepthFormats;
    };

    const image = try vk_allocator.createImage(
        vk.ImageCreateInfo{
            .initial_layout = .undefined,
            .sharing_mode = .exclusive,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .tiling = .optimal,
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .extent = vk.Extent3D{
                .width = extent.width,
                .height = extent.height,
                .depth = 1,
            },
            .format = format,
            .image_type = .@"2d",
        },
        .{ .device_local_bit = true },
    );
    errdefer vk_allocator.destroyImage(image);

    const view = try ctx.device.createImageView(
        &vk.ImageViewCreateInfo{
            .components = vulkan.identity_component_mapping,
            .image = image.vk_handle,
            .view_type = .@"2d",
            .format = format,
            .subresource_range = vk.ImageSubresourceRange{
                .aspect_mask = .{ .depth_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        },
        null,
    );

    return .{ image, view, format };
}

const Frame = struct {
    in_flight: vk.Fence,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    command_buffer: vk.CommandBuffer,
    image: vk.Image = vk.Image.null_handle,
    view: vk.ImageView = vk.ImageView.null_handle,
    descriptor_set: vk.DescriptorSet,
    uniform_buffer: Buffer,
    uniform_buffer_mapped: *UniformBufferObject,
};

const Self = @This();
const vulkan = @import("../vulkan.zig");
const Context = vulkan.Context;
const Device = vulkan.Device;
const Buffer = vulkan.vk_allocator.Buffer;
const Image = vulkan.vk_allocator.Image;
const UniformBufferObject = @import("../types.zig").UniformBufferObject;
const ftm = @import("../math.zig");
const Vec3f = ftm.Vec3fx;

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.vulkan_renderer);
const debug = std.debug;
const mem = std.mem;
const math = std.math;
const meta = std.meta;
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
