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

pub const GameState = struct {
    player_position: Vec3f,
    player_rotation: Vec3f,
    camera_forward: Vec3f,
};

const std = @import("std");
const mem = std.mem;

const zm = @import("zm");
const Vec3f = zm.Vec3f;
const Vec4f = zm.Vec4f;
const Mat4f = zm.Mat4f;
