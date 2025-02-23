// TODO: Thread safety?

/// Vulkan allocator.
pub const Allocator = struct {
    allocator: mem.Allocator,
    ctx: vulkan.Context,
    dedicated: DedicatedAllocator,
    // TODO: Pooled allocator

    const Self = @This();

    pub fn init(allocator: mem.Allocator, ctx: vulkan.Context) Self {
        return Self{
            .allocator = allocator,
            .ctx = ctx,
            .dedicated = DedicatedAllocator.init(allocator, ctx),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dedicated.deinit();
    }

    /// Creates a buffer and binds memory to it. Buffer should be destroyed with `Allocator.destroyBuffer`.
    pub fn createBuffer(
        self: *Self,
        buffer_info: vk.BufferCreateInfo,
        memory_property_flags: vk.MemoryPropertyFlags,
    ) !Buffer {
        const buffer = try self.ctx.device.createBuffer(&buffer_info, null);
        errdefer self.ctx.device.destroyBuffer(buffer, null);

        const memory_requirements = self.ctx.device.getBufferMemoryRequirements(buffer);

        const allocation = try self.allocate(memory_requirements, memory_property_flags);
        errdefer self.free(allocation);

        const memory = self.getMemory(allocation);
        try self.ctx.device.bindBufferMemory(buffer, memory, 0);

        return .{
            .vk_handle = buffer,
            .allocation = allocation,
        };
    }

    /// Destroys a buffer created with `Allocator.createBuffer`.
    pub fn destroyBuffer(self: *Self, buffer: Buffer) void {
        self.ctx.device.destroyBuffer(buffer.vk_handle, null);
        self.free(buffer.allocation);
    }

    /// Creates an image and binds memory to it. Image should be destroyed with `Allocator.destroyImage`.
    pub fn createImage(
        self: *Self,
        image_info: vk.ImageCreateInfo,
        memory_propery_flags: vk.MemoryPropertyFlags,
    ) !Image {
        const image = try self.ctx.device.createImage(&image_info, null);
        errdefer self.ctx.device.destroyImage(image, null);

        const memory_requirements = self.ctx.device.getImageMemoryRequirements(image);

        const allocation = try self.allocate(memory_requirements, memory_propery_flags);
        errdefer self.free(allocation);

        const memory = self.getMemory(allocation);
        try self.ctx.device.bindImageMemory(image, memory, 0);

        return .{
            .vk_handle = image,
            .allocation = allocation,
        };
    }

    /// Destroys an image created with `Allocator.createImage`.
    pub fn destroyImage(self: *Self, image: Image) void {
        self.ctx.device.destroyImage(image.vk_handle, null);
        self.free(image.allocation);
    }

    pub fn allocate(
        self: *Self,
        requirements: vk.MemoryRequirements,
        property_flags: vk.MemoryPropertyFlags,
    ) !Allocation {
        const index = try self.dedicated.allocate(requirements, property_flags);

        return .{ .index = index, .kind = .dedicated };
    }

    pub fn free(self: *Self, allocation: Allocation) void {
        switch (allocation.kind) {
            .dedicated => self.dedicated.free(allocation.index),
            else => debug.panic("unimplemented", .{}),
        }
    }

    /// Maps memory for the given allocation and returns a pointer to it.
    pub fn map(self: Self, allocation: Allocation) !*anyopaque {
        return switch (allocation.kind) {
            .dedicated => try self.dedicated.map(allocation.index),
            else => debug.panic("unimplemented", .{}),
        };
    }

    /// Unmaps memory previously mapped with `Allocator.map`. Invalidates the mapped pointer.
    pub fn unmap(self: Self, allocation: Allocation) void {
        return switch (allocation.kind) {
            .dedicated => self.dedicated.unmap(allocation.index),
            else => debug.panic("unimplemented", .{}),
        };
    }

    /// Returns the raw vk.DeviceMemory for the allocation. Avoid calling this if possible.
    pub fn getMemory(self: Self, allocation: Allocation) vk.DeviceMemory {
        return switch (allocation.kind) {
            .dedicated => self.dedicated.getAllocation(allocation.index).memory,
            else => debug.panic("unimplemented", .{}),
        };
    }

    pub fn getSize(self: Self, allocation: Allocation) vk.DeviceSize {
        return switch (allocation.kind) {
            .dedicated => self.dedicated.getAllocation(allocation.index).size,
            else => debug.panic("unimplemented", .{}),
        };
    }

    pub fn copySliceToAllocation(
        self: Self,
        comptime T: type,
        slice: []const T,
        allocation: Allocation,
    ) !void {
        debug.assert(self.getSize(allocation) >= @sizeOf(T) * slice.len);

        const data_ptr: [*]T = @alignCast(@ptrCast(try self.map(allocation)));
        defer self.unmap(allocation);

        mem.copyForwards(T, data_ptr[0..slice.len], slice);
    }
};

/// An index to an allocation.
pub const AllocationIndex = enum(u31) {
    _,

    const Self = @This();

    pub fn increment(self: *Self) void {
        self.* = @enumFromInt(@intFromEnum(self.*) + 1);
    }
};

/// Handle to an allocation.
pub const Allocation = struct {
    index: AllocationIndex,
    kind: AllocationKind,
};

/// A buffer handle.
pub const Buffer = struct {
    vk_handle: vk.Buffer,
    allocation: Allocation,
};

/// An image handle.
pub const Image = struct {
    vk_handle: vk.Image,
    allocation: Allocation,
};

const AllocationKind = enum(u1) {
    dedicated,
    pooled,
};

const vulkan = @import("../vulkan.zig");
const DedicatedAllocator = @import("allocator/DedicatedAllocator.zig");

const std = @import("std");
const mem = std.mem;
const debug = std.debug;

const vk = @import("vulkan");
