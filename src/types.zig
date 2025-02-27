pub const UniformBufferObject = extern struct {
    model: Mat4f align(16),
    view: Mat4f align(16),
    proj: Mat4f align(16),
};

pub const GameState = struct {
    player_position: Vec3f,
    player_rotation: Vec3f,

    camera_x: Vec3f,
    camera_y: Vec3f,
    camera_z: Vec3f,
};

const std = @import("std");
const mem = std.mem;

const ftm = @import("math.zig");
const Vec3f = ftm.Vec3fx;
const Vec4f = ftm.Vec4fx;
const Mat4f = ftm.Mat4f;
