const noise = fastnoise.Noise(f64){};

/// Enum variants for all unique block types.
pub const Block = enum(u8) {
    air,
    stone,

    /// Valid range of block coordinates.
    pub const Coord = i32;
};

pub const Chunk = struct {
    blocks: [volume]Block,

    /// Side length of a chunk on the vertical y axis.
    pub const size_y = 256;

    /// Side length of a chunk on the horizontal x and z axes.
    pub const size_xz = blk: {
        const bit_width = @bitSizeOf(Block.Coord) - @bitSizeOf(Coord);
        debug.assert(bit_width > 0);
        break :blk bit_width * bit_width;
    };

    /// The number of blocks in a chunk.
    pub const volume = size_xz * size_y * size_xz;

    pub fn generate(chunk_x: Coord, chunk_z: Coord) Chunk {
        var chunk: Chunk = undefined;
        for (0..size_xz) |x| {
            for (0..size_xz) |z| {
                const block_x = @as(Block.Coord, chunk_x) * size_xz + @as(Block.Coord, @intCast(x));
                const block_z = @as(Block.Coord, chunk_z) * size_xz + @as(Block.Coord, @intCast(z));
                const noise_sample = noise.genNoise2D(@floatFromInt(block_x), @floatFromInt(block_z));
                const height = @as(Block.Coord, @intFromFloat(noise_sample * size_y)) - 1;
                for (0..size_y) |y| {
                    chunk.blocks[(z * size_y + y) * size_xz + x] = if (y <= height) .stone else .air;
                }
            }
        }
        return chunk;
    }

    pub fn print(chunk: Chunk) void {
        for (0..size_y) |y| {
            for (0..size_xz) |x| {
                for (0..size_xz) |z| {
                    const block = chunk.blocks[(z * size_y + y) * size_xz + x];
                    debug.print("{}", .{@intFromEnum(block)});
                }
                debug.print("\n", .{});
            }
            debug.print("----------------\n", .{});
        }
    }

    pub fn toMesh(chunk: Chunk, allocator: Allocator) !struct { []zm.Vec3f, []u32, []Block } {
        const vertices = try allocator.alloc(zm.Vec3f, volume * 8);
        const indices = try allocator.alloc(u32, volume * 36);
        const block_ids = try allocator.alloc(Block, volume);

        for (0..size_y) |y| {
            for (0..size_xz) |x| {
                for (0..size_xz) |z| {
                    const index: u32 = @intCast((z * size_y + y) * size_xz + x);

                    const fx: f32 = @floatFromInt(x);
                    const fy: f32 = @floatFromInt(y);
                    const fz: f32 = @floatFromInt(z);

                    vertices[index * 8 + 0] = zm.Vec3f{ fx + 0.0, fy + 0.0, fz + 0.0 }; // LEFT BOTT BACK
                    vertices[index * 8 + 1] = zm.Vec3f{ fx + 1.0, fy + 0.0, fz + 0.0 }; // RGHT BOTT BACK
                    vertices[index * 8 + 2] = zm.Vec3f{ fx + 0.0, fy + 1.0, fz + 0.0 }; // LEFT TOPP BACK
                    vertices[index * 8 + 3] = zm.Vec3f{ fx + 1.0, fy + 1.0, fz + 0.0 }; // RGHT TOPP BACK
                    vertices[index * 8 + 4] = zm.Vec3f{ fx + 0.0, fy + 0.0, fz + 1.0 }; // LEFT BOTT FRNT
                    vertices[index * 8 + 5] = zm.Vec3f{ fx + 1.0, fy + 0.0, fz + 1.0 }; // RGHT BOTT FRNT
                    vertices[index * 8 + 6] = zm.Vec3f{ fx + 0.0, fy + 1.0, fz + 1.0 }; // LEFT TOPP FRNT
                    vertices[index * 8 + 7] = zm.Vec3f{ fx + 1.0, fy + 1.0, fz + 1.0 }; // RGHT TOPP FRNT

                    // TODO(Hans): Fill out the rest of these..
                    indices[index * 36 + 0] = index * 8 + 0;
                    indices[index * 36 + 1] = index * 8 + 1;
                    indices[index * 36 + 2] = index * 8 + 2;
                    indices[index * 36 + 3] = index * 8 + 1;
                    indices[index * 36 + 4] = index * 8 + 3;
                    indices[index * 36 + 5] = index * 8 + 2;
                    indices[index * 36 + 6] = index * 8 + 0;
                    indices[index * 36 + 7] = index * 8 + 0;
                    indices[index * 36 + 8] = index * 8 + 0;
                    indices[index * 36 + 9] = index * 8 + 0;
                    indices[index * 36 + 10] = index * 8 + 0;
                    indices[index * 36 + 11] = index * 8 + 0;
                    indices[index * 36 + 12] = index * 8 + 0;
                    indices[index * 36 + 13] = index * 8 + 0;
                    indices[index * 36 + 14] = index * 8 + 0;
                    indices[index * 36 + 15] = index * 8 + 0;
                    indices[index * 36 + 16] = index * 8 + 0;
                    indices[index * 36 + 17] = index * 8 + 0;
                    indices[index * 36 + 18] = index * 8 + 0;
                    indices[index * 36 + 19] = index * 8 + 0;
                    indices[index * 36 + 20] = index * 8 + 0;
                    indices[index * 36 + 21] = index * 8 + 0;
                    indices[index * 36 + 22] = index * 8 + 0;
                    indices[index * 36 + 23] = index * 8 + 0;
                    indices[index * 36 + 24] = index * 8 + 0;
                    indices[index * 36 + 25] = index * 8 + 0;
                    indices[index * 36 + 26] = index * 8 + 0;
                    indices[index * 36 + 27] = index * 8 + 0;
                    indices[index * 36 + 28] = index * 8 + 0;
                    indices[index * 36 + 29] = index * 8 + 0;
                    indices[index * 36 + 30] = index * 8 + 0;
                    indices[index * 36 + 31] = index * 8 + 0;
                    indices[index * 36 + 32] = index * 8 + 0;
                    indices[index * 36 + 33] = index * 8 + 0;
                    indices[index * 36 + 34] = index * 8 + 0;
                    indices[index * 36 + 35] = index * 8 + 0;

                    block_ids[index] = chunk.blocks[index];
                }
            }
        }

        return .{ vertices, indices, block_ids };
    }

    /// Valid range of chunk coordinates.
    pub const Coord = i28;
};

const fastnoise = @import("worldgen/fastnoise.zig");

const std = @import("std");
const debug = std.debug;
const Allocator = std.mem.Allocator;

const zm = @import("zm");
