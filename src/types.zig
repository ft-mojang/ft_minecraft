/// C-ABI compatible matrix type.
pub fn Matrix4(comptime T: type) type {
    return extern struct {
        data: [16]T,

        // TODO: need to check if this conversion is properly optimized away
        pub fn fromMat4f(other: Mat4f) @This() {
            return .{ .data = other.data };
        }
    };
}

pub const UniformBufferObject = extern struct {
    model: Matrix4(f32) align(16),
    view: Matrix4(f32) align(16),
    proj: Matrix4(f32) align(16),
};

const std = @import("std");
const mem = std.mem;

const Mat4f = @import("zm").Mat4f;
