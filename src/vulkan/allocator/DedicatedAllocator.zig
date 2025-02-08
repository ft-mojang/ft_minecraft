/// Dedicated memory allocator.
const std = @import("std");
const vk = @import("vulkan");
const vulkan = @import("../../vulkan.zig");
const vka = vulkan.allocator;

const debug = std.debug;
const mem = std.mem;

const ArrayListUnmanaged = std.ArrayListUnmanaged;
const AllocationIndex = vka.AllocationIndex;
const Self = @This();

pub const Allocation = struct {
    size: vk.DeviceSize,
    memory: vk.DeviceMemory = vk.DeviceMemory.null_handle,
    map_count: u32 = 0,
    data: ?*anyopaque = null,
};

const Transaction = struct {
    index: AllocationIndex,
    index_kind: IndexKind,

    const IndexKind = enum {
        /// Using the next available index.
        next,
        /// Using an index from the free list.
        freed,
    };
};

allocator: mem.Allocator,
context: vulkan.Context,
allocations: ArrayListUnmanaged(Allocation) = ArrayListUnmanaged(Allocation).empty,
freed_indices: ArrayListUnmanaged(AllocationIndex) = ArrayListUnmanaged(AllocationIndex).empty,
next_index: AllocationIndex = @enumFromInt(0),

pub fn init(allocator: mem.Allocator, context: vulkan.Context) Self {
    return Self{
        .allocator = allocator,
        .context = context,
    };
}

pub fn deinit(self: *Self) void {
    self.allocations.deinit(self.allocator);
    self.freed_indices.deinit(self.allocator);
}

pub fn allocate(
    self: *Self,
    requirements: vk.MemoryRequirements,
    property_flags: vk.MemoryPropertyFlags,
) !AllocationIndex {
    const transaction = self.beginTransaction();

    const memory_type = try self.context.findMemoryType(requirements.memory_type_bits, property_flags);

    const allocate_info = vk.MemoryAllocateInfo{
        .allocation_size = requirements.size,
        .memory_type_index = memory_type,
    };

    const memory = try self.context.device.allocateMemory(&allocate_info, null);

    const allocation = Allocation{
        .size = requirements.size,
        .memory = memory,
    };

    switch (transaction.index_kind) {
        .next => try self.allocations.append(self.allocator, allocation),
        .freed => self.getAllocationPtr(transaction.index).* = allocation,
    }

    self.commitTransaction(transaction);

    return transaction.index;
}

pub fn free(self: *Self, index: AllocationIndex) void {
    const allocation = self.getAllocationPtr(index);

    debug.assert(allocation.memory != vk.DeviceMemory.null_handle);

    self.context.device.freeMemory(allocation.memory, null);
    allocation.* = .{ .size = 0 };

    self.freed_indices.append(self.allocator, index) catch {
        debug.print("vka: unable to append to dedicated allocations free indices, allocation will not be reused.", .{});
    };
}

pub fn map(self: Self, index: AllocationIndex) !*anyopaque {
    const allocation = self.getAllocationPtr(index);

    if (allocation.map_count == 0) {
        allocation.data = try self.context.device.mapMemory(allocation.memory, 0, vk.WHOLE_SIZE, .{});
    }

    allocation.map_count += 1;
    debug.assert(allocation.data != null);

    return allocation.data.?;
}

pub fn unmap(self: Self, index: AllocationIndex) void {
    const allocation = self.getAllocationPtr(index);

    if (allocation.map_count == 0) {
        return;
    }

    allocation.map_count -= 1;

    if (allocation.map_count == 0) {
        self.context.device.unmapMemory(allocation.memory);
    }
}

pub fn getAllocation(self: Self, index: AllocationIndex) Allocation {
    return self.getAllocationPtr(index).*;
}

pub fn getAllocationPtr(self: Self, index: AllocationIndex) *Allocation {
    debug.assert(@intFromEnum(index) < self.allocations.items.len);

    return &self.allocations.items[@intFromEnum(index)];
}

fn beginTransaction(self: Self) Transaction {
    var transaction: Transaction = undefined;

    transaction.index_kind = .freed;
    transaction.index = self.freed_indices.getLastOrNull() orelse blk: {
        transaction.index_kind = .next;
        break :blk self.next_index;
    };

    return transaction;
}

fn commitTransaction(self: *Self, transaction: Transaction) void {
    switch (transaction.index_kind) {
        .next => self.next_index.increment(),
        .freed => _ = self.freed_indices.pop(),
    }
}
