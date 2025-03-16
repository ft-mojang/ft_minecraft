/// World height measured in blocks. Must be a multiple of the size of a chunk.
pub const world_height: Block.Coord = 320;

pub const WorldPosition = struct {
    /// Absolute position in block coordinates
    abs: ftm.VecXYZ(Block.Coord),
    /// Relative position within a block
    rel: ftm.VecXYZ(f32),
};

/// Enum variants for all unique block types
pub const Block = enum(u8) {
    air,
    stone,

    /// Valid range of block coordinates
    pub const Coord = u32;
};

pub const Chunk = struct {
    blocks: [volume]Block,

    /// Side length of a chunk. Chunks have a uniform side length on each axis.
    pub const size = blk: {
        var bit_width = @bitSizeOf(Block.Coord) - @bitSizeOf(Coord);
        debug.assert(bit_width > 0);
        var result = 1;
        while (bit_width > 0) : (bit_width -= 1) {
            result *= 2;
        }
        debug.assert(world_height % result == 0);
        break :blk result;
    };

    /// The number of blocks in a chunk
    pub const volume = size * size * size;

    pub fn generate(chunk_x: Coord, chunk_y: Coord, chunk_z: Coord) Chunk {
        const seed = 0xdead;
        const chunk_x_block = @as(Block.Coord, chunk_x) * size;
        const chunk_y_block = @as(Block.Coord, chunk_y) * size;
        const chunk_z_block = @as(Block.Coord, chunk_z) * size;

        var chunk: Chunk = undefined;
        for (0..size) |z| {
            for (0..size) |x| {
                const block_x = chunk_x_block + x;
                const block_z = chunk_z_block + z;
                // Sample from the block center to avoid using integer coordinates as they collapse the perlin noise algorithm.
                const sample_x: noise.Fp = 0.5 + @as(noise.Fp, @floatFromInt(block_x));
                const sample_z: noise.Fp = 0.5 + @as(noise.Fp, @floatFromInt(block_z));

                const continentalness = noise.sampleLayeredNoise2d(seed, sample_x, sample_z, 1.0, 0.002, 16, 0.5, 2.0);

                const squashing_factor = 0.01;
                const height_offset = (continentalness + 1) * world_height * 0.5;

                for (0..size) |y| {
                    const block_y = chunk_y_block + y;
                    const sample_y: noise.Fp = 0.5 + @as(noise.Fp, @floatFromInt(block_y));
                    var density = noise.sampleLayeredNoise3d(seed, sample_x, sample_y, sample_z, 1.0, 0.001, 16, 0.5, 2.0);
                    density -= squashing_factor * (sample_y - height_offset);
                    chunk.blocks[(z * size + x) * size + y] = if (density > 0) .stone else .air;
                }
            }
        }

        return chunk;
    }

    pub fn print(chunk: Chunk) void {
        for (0..size) |z| {
            for (0..size) |x| {
                for (0..size) |y| {
                    const block = chunk.blocks[(z * size + x) * size + y];
                    debug.print("{}", .{@intFromEnum(block)});
                }
                debug.print("\n", .{});
            }
            debug.print("----------------\n", .{});
        }
    }

    pub fn toMesh(chunk: Chunk, allocator: Allocator) !struct { []Vec3f, []u32 } {
        const vertices = try allocator.alloc(Vec3f, volume * 8);
        const indices = try allocator.alloc(u32, volume * 36);

        for (0..size) |z| {
            for (0..size) |x| {
                for (0..size) |y| {
                    const index: u32 = @intCast((z * size + x) * size + y);

                    if (chunk.blocks[index] == .air) {
                        continue;
                    }

                    if (x > 0 and x < size - 1 and y > 0 and y < size - 1 and z > 0 and z < size - 1) {
                        inline for (.{
                            (z * size + x) * size + (y + 1),
                            (z * size + x) * size + (y - 1),
                            (z * size + (x + 1)) * size + y,
                            (z * size + (x - 1)) * size + y,
                            ((z + 1) * size + x) * size + y,
                            ((z - 1) * size + x) * size + y,
                        }) |neighbour_index| {
                            if (chunk.blocks[neighbour_index] == .air) {
                                break;
                            }
                        } else {
                            continue;
                        }
                    }

                    const fx: f32 = @floatFromInt(x);
                    const fy: f32 = @floatFromInt(y);
                    const fz: f32 = @floatFromInt(z);

                    vertices[index * 8 + 0] = Vec3f.xyz(fx + 0.0, fy + 0.0, fz + 0.0); // LEFT BOTT BACK
                    vertices[index * 8 + 1] = Vec3f.xyz(fx + 1.0, fy + 0.0, fz + 0.0); // RGHT BOTT BACK
                    vertices[index * 8 + 2] = Vec3f.xyz(fx + 0.0, fy + 1.0, fz + 0.0); // LEFT TOPP BACK
                    vertices[index * 8 + 3] = Vec3f.xyz(fx + 1.0, fy + 1.0, fz + 0.0); // RGHT TOPP BACK
                    vertices[index * 8 + 4] = Vec3f.xyz(fx + 0.0, fy + 0.0, fz + 1.0); // LEFT BOTT FRNT
                    vertices[index * 8 + 5] = Vec3f.xyz(fx + 1.0, fy + 0.0, fz + 1.0); // RGHT BOTT FRNT
                    vertices[index * 8 + 6] = Vec3f.xyz(fx + 0.0, fy + 1.0, fz + 1.0); // LEFT TOPP FRNT
                    vertices[index * 8 + 7] = Vec3f.xyz(fx + 1.0, fy + 1.0, fz + 1.0); // RGHT TOPP FRNT

                    indices[index * 36 + 0] = index * 8 + 2; // BACK FACE
                    indices[index * 36 + 1] = index * 8 + 1;
                    indices[index * 36 + 2] = index * 8 + 0;
                    indices[index * 36 + 3] = index * 8 + 2;
                    indices[index * 36 + 4] = index * 8 + 3;
                    indices[index * 36 + 5] = index * 8 + 1;
                    indices[index * 36 + 6] = index * 8 + 4; // FRNT FACE
                    indices[index * 36 + 7] = index * 8 + 5;
                    indices[index * 36 + 8] = index * 8 + 6;
                    indices[index * 36 + 9] = index * 8 + 5;
                    indices[index * 36 + 10] = index * 8 + 7;
                    indices[index * 36 + 11] = index * 8 + 6;
                    indices[index * 36 + 12] = index * 8 + 5; // BOTT FACE
                    indices[index * 36 + 13] = index * 8 + 4;
                    indices[index * 36 + 14] = index * 8 + 0;
                    indices[index * 36 + 15] = index * 8 + 1;
                    indices[index * 36 + 16] = index * 8 + 5;
                    indices[index * 36 + 17] = index * 8 + 0;
                    indices[index * 36 + 18] = index * 8 + 2; // TOPP FACE
                    indices[index * 36 + 19] = index * 8 + 6;
                    indices[index * 36 + 20] = index * 8 + 7;
                    indices[index * 36 + 21] = index * 8 + 2;
                    indices[index * 36 + 22] = index * 8 + 7;
                    indices[index * 36 + 23] = index * 8 + 3;
                    indices[index * 36 + 24] = index * 8 + 0; // LEFT FACE
                    indices[index * 36 + 25] = index * 8 + 4;
                    indices[index * 36 + 26] = index * 8 + 2;
                    indices[index * 36 + 27] = index * 8 + 4;
                    indices[index * 36 + 28] = index * 8 + 6;
                    indices[index * 36 + 29] = index * 8 + 2;
                    indices[index * 36 + 30] = index * 8 + 3; // RGHT FACE
                    indices[index * 36 + 31] = index * 8 + 7;
                    indices[index * 36 + 32] = index * 8 + 5;
                    indices[index * 36 + 33] = index * 8 + 3;
                    indices[index * 36 + 34] = index * 8 + 5;
                    indices[index * 36 + 35] = index * 8 + 1;
                }
            }
        }

        return .{ vertices, indices };
    }

    /// Valid range of chunk coordinates
    pub const Coord = u28;
};

const noise = @import("worldgen/noise.zig");
const ftm = @import("math.zig");
const Vec3f = ftm.Vec3fx;

const std = @import("std");
const debug = std.debug;
const Allocator = std.mem.Allocator;
