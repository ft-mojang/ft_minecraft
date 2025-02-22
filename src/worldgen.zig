/// World height measured in blocks. Must be a multiple of the size of a chunk.
pub const world_height = 256;

/// Enum variants for all unique block types
pub const Block = enum(u8) {
    air,
    stone,

    /// Valid range of block coordinates
    pub const Coord = i32;
};

pub const Chunk = struct {
    blocks: [volume]Block,

    /// Side length of a chunk. Chunks have a uniform side length on each axis.
    pub const size = blk: {
        const bit_width = @bitSizeOf(Block.Coord) - @bitSizeOf(Coord);
        debug.assert(bit_width > 0);
        const result = bit_width * bit_width;
        debug.assert(world_height % result == 0);
        break :blk result;
    };

    /// The number of blocks in a chunk
    pub const volume = size * size * size;

    pub fn generate(chunk_x: Coord, chunk_y: Coord, chunk_z: Coord) Chunk {
        const seed = 0xdead;

        var chunk: Chunk = undefined;
        for (0..size) |x| {
            for (0..size) |z| {
                const block_x = @as(Block.Coord, chunk_x) * size + @as(Block.Coord, @intCast(x));
                const block_z = @as(Block.Coord, chunk_z) * size + @as(Block.Coord, @intCast(z));
                // Sample from the block center to avoid using integer coordinates as they collapse the perlin noise algorithm.
                const sample_x: Fp = 0.5 + @as(Fp, @floatFromInt(block_x));
                const sample_z: Fp = 0.5 + @as(Fp, @floatFromInt(block_z));

                const continentalness = sampleLayeredNoise2d(seed, sample_x, sample_z, 1.0, 0.01, 8, 0.5, 2.0);

                const block_height = @as(Block.Coord, @intFromFloat(continentalness * 0.5 * world_height)) - 1;
                for (0..size) |y| {
                    const block_y = @as(Block.Coord, chunk_y) * size + @as(Block.Coord, @intCast(y));
                    chunk.blocks[(z * size + y) * size + x] = if (block_y <= block_height) .stone else .air;
                }
            }
        }

        return chunk;
    }

    pub fn print(chunk: Chunk) void {
        for (0..size) |y| {
            for (0..size) |x| {
                for (0..size) |z| {
                    const block = chunk.blocks[(z * size + y) * size + x];
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

        for (0..size) |x| {
            for (0..size) |y| {
                for (0..size) |z| {
                    const index: u32 = @intCast((z * size + y) * size + x);

                    if (chunk.blocks[index] == .air) {
                        continue;
                    }

                    const fx: f32 = @floatFromInt(x);
                    const fy: f32 = @floatFromInt(y);
                    const fz: f32 = @floatFromInt(z);

                    vertices[index * 8 + 0] = Vec3f{ fx + 0.0, fy + 0.0, fz + 0.0 }; // LEFT BOTT BACK
                    vertices[index * 8 + 1] = Vec3f{ fx + 1.0, fy + 0.0, fz + 0.0 }; // RGHT BOTT BACK
                    vertices[index * 8 + 2] = Vec3f{ fx + 0.0, fy + 1.0, fz + 0.0 }; // LEFT TOPP BACK
                    vertices[index * 8 + 3] = Vec3f{ fx + 1.0, fy + 1.0, fz + 0.0 }; // RGHT TOPP BACK
                    vertices[index * 8 + 4] = Vec3f{ fx + 0.0, fy + 0.0, fz + 1.0 }; // LEFT BOTT FRNT
                    vertices[index * 8 + 5] = Vec3f{ fx + 1.0, fy + 0.0, fz + 1.0 }; // RGHT BOTT FRNT
                    vertices[index * 8 + 6] = Vec3f{ fx + 0.0, fy + 1.0, fz + 1.0 }; // LEFT TOPP FRNT
                    vertices[index * 8 + 7] = Vec3f{ fx + 1.0, fy + 1.0, fz + 1.0 }; // RGHT TOPP FRNT

                    indices[index * 36 + 0] = index * 8 + 0; // BACK FACE
                    indices[index * 36 + 1] = index * 8 + 1;
                    indices[index * 36 + 2] = index * 8 + 2;
                    indices[index * 36 + 3] = index * 8 + 1;
                    indices[index * 36 + 4] = index * 8 + 3;
                    indices[index * 36 + 5] = index * 8 + 2;
                    indices[index * 36 + 6] = index * 8 + 4; // FRNT FACE
                    indices[index * 36 + 7] = index * 8 + 5;
                    indices[index * 36 + 8] = index * 8 + 6;
                    indices[index * 36 + 9] = index * 8 + 5;
                    indices[index * 36 + 10] = index * 8 + 7;
                    indices[index * 36 + 11] = index * 8 + 6;
                    indices[index * 36 + 12] = index * 8 + 0; // BOTT FACE
                    indices[index * 36 + 13] = index * 8 + 4;
                    indices[index * 36 + 14] = index * 8 + 5;
                    indices[index * 36 + 15] = index * 8 + 0;
                    indices[index * 36 + 16] = index * 8 + 5;
                    indices[index * 36 + 17] = index * 8 + 1;
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

    /// Sums octaves of noise and returns a normalized result in range -1 to 1 (inclusive)
    fn sampleLayeredNoise2d(
        seed: i32,
        x: Fp,
        y: Fp,
        amplitude: Fp,
        frequency: Fp,
        octave_count: u8,
        persistence: Fp,
        lacunarity: Fp,
    ) Fp {
        // Offset to avoid interference patterns between octaves when near zero
        const octave_offset: Fp = @as(Fp, @floatFromInt(math.maxInt(@TypeOf(octave_count)))) / @as(Fp, @floatFromInt(octave_count));
        var _amplitude: Fp = amplitude;
        var _frequency: Fp = frequency;
        var height_max: Fp = 0.0;
        var height_sum: Fp = 0.0;
        for (0..octave_count) |i| {
            const offset = octave_offset * @as(Fp, @floatFromInt(i));
            height_max += _amplitude;
            height_sum += _amplitude * Noise.singleSimplexS2D(seed, _frequency * (x + offset), _frequency * (y + offset));
            _amplitude *= persistence;
            _frequency *= lacunarity;
        }
        return height_sum / height_max;
    }

    /// Valid range of chunk coordinates
    pub const Coord = i28;
};

const Fp = f64;

const fastnoise = @import("worldgen/fastnoise.zig");
const Noise = fastnoise.Noise(Fp);

const std = @import("std");
const debug = std.debug;
const math = std.math;
const Allocator = std.mem.Allocator;

const zm = @import("zm");
const Vec3f = zm.Vec3f;
