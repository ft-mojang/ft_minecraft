const vk = @import("vulkan");

pub const AllocatorCreateInfo = struct {
    // Instance, PhysicalDevice, Device, etc..
};

pub const AllocationIndex = enum(u32) {
    _,
};

/// A buffer handle.
pub const Buffer = struct {
    vk_handle: vk.Buffer,
    allocation: AllocationIndex,
};

/// An image handle.
pub const Image = struct {
    vk_handle: vk.Image,
    allocation: AllocationIndex,
};

const AllocateInfo = struct {
    // ...
};

const Allocator = struct {
    pub fn createBuffer(self: *Allocator, _: *const vk.BufferCreateInfo, _: *const AllocateInfo) !Buffer {
        _ = self;
        // ...
    }
    pub fn destroyBuffer(self: *Allocator, _: Buffer) void {
        _ = self;
        // ...
    }
    pub fn createImage(self: *Allocator, _: *const vk.ImageCreateInfo, _: *const AllocateInfo) !Image {
        _ = self;
        // ...
    }
    pub fn destroyImage(self: *Allocator, _: Image) void {
        _ = self;
        // ...
    }
};
