const fastnoise = @import("worldgen/fastnoise.zig");

const std = @import("std");
const math = std.math;
const debug = std.debug;

/// Enum variants for all unique block types.
pub const Block = enum(u8) {
    air,
    stone,

    /// Valid range of block coordinates.
    pub const Coord = i32;
};

pub const Chunk = struct {
    blocks: [volume]Block,

    /// Valid range of chunk coordinates.
    pub const Coord = i28;

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
};

const noise = fastnoise.Noise(f64){};

pub fn generateChunk(chunk_x: Chunk.Coord, chunk_z: Chunk.Coord) Chunk {
    var chunk: Chunk = undefined;
    for (0..Chunk.size_xz) |x| {
        for (0..Chunk.size_xz) |z| {
            const block_x = @as(Block.Coord, chunk_x) * Chunk.size_xz + @as(Block.Coord, @intCast(x));
            const block_z = @as(Block.Coord, chunk_z) * Chunk.size_xz + @as(Block.Coord, @intCast(z));
            const noise_sample = noise.genNoise2D(@floatFromInt(block_x), @floatFromInt(block_z));
            const height = @as(Block.Coord, @intFromFloat(noise_sample * Chunk.size_y)) - 1;
            for (0..Chunk.size_y) |y| {
                chunk.blocks[(z * Chunk.size_y + y) * Chunk.size_xz + x] = if (y <= height) .stone else .air;
            }
        }
    }
    return chunk;
}

pub fn printChunk(chunk: Chunk) void {
    for (0..Chunk.size_y) |y| {
        for (0..Chunk.size_xz) |x| {
            for (0..Chunk.size_xz) |z| {
                const block = chunk.blocks[(z * Chunk.size_y + y) * Chunk.size_xz + x];
                debug.print("{}", .{@intFromEnum(block)});
            }
            debug.print("\n", .{});
        }
        debug.print("----------------\n", .{});
    }
}
