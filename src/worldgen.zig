const fastnoise = @import("worldgen/fastnoise.zig");

const std = @import("std");
const math = std.math;
const debug = std.debug;

/// Enum with a variant for each unique block type
pub const Block = enum(u8) {
    /// Valid range of block coordinates
    pub const Coord = i32;

    air,
    stone,
};

pub const Chunk = struct {
    /// Valid range of chunk coordinates
    pub const Coord = i28;

    /// Side length of a chunk. Chunks are uniform in size (same length on each axis).
    pub const size = blk: {
        const bit_width = @bitSizeOf(Block.Coord) - @bitSizeOf(Coord);
        debug.assert(bit_width > 0);
        break :blk bit_width * bit_width;
    };
    /// The number of blocks in a chunk
    pub const volume = size * size * size;

    blocks: [volume]Block,
};

pub const world_height_chunks = 16;
pub const world_height_blocks = Chunk.size * world_height_chunks;

const noise = fastnoise.Noise(f64){};

pub fn generateChunk(chunk_x: Chunk.Coord, chunk_z: Chunk.Coord) Chunk {
    var chunk: Chunk = undefined;
    for (0..Chunk.size) |x| {
        for (0..Chunk.size) |z| {
            const block_x = @as(Block.Coord, chunk_x) * Chunk.size + @as(Block.Coord, @intCast(x));
            const block_z = @as(Block.Coord, chunk_z) * Chunk.size + @as(Block.Coord, @intCast(z));
            const height: Block.Coord = @intFromFloat(noise.genNoise2D(@floatFromInt(block_x), @floatFromInt(block_z)) * world_height_chunks);
            // TODO(Hans): Figure out how we handle "chunk pillars" when chunks are uniform in size.
            for (0..Chunk.size) |y| {
                chunk.blocks[(z * Chunk.size + y) * Chunk.size + x] = if (y < height) .stone else .air;
            }
        }
    }
    return chunk;
}

pub fn printChunk(chunk: Chunk) void {
    for (0..Chunk.size) |y| {
        for (0..Chunk.size) |x| {
            for (0..Chunk.size) |z| {
                const block = chunk.blocks[(z * Chunk.size + y) * Chunk.size + x];
                debug.print("{}", .{@intFromEnum(block)});
            }
            debug.print("\n", .{});
        }
        debug.print("----------------\n", .{});
    }
}
