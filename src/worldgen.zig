/// Enum variants for all unique block types
pub const Block = enum(u8) {
    air,
    stone,

    /// Valid range of block coordinates
    pub const Coord = i32;
};

pub const Chunk = struct {
    blocks: [volume]Block,

    /// Side length of a chunk on the vertical y axis
    pub const size_y = 256;

    /// Side length of a chunk on the horizontal x and z axes
    pub const size_xz = blk: {
        const bit_width = @bitSizeOf(Block.Coord) - @bitSizeOf(Coord);
        debug.assert(bit_width > 0);
        break :blk bit_width * bit_width;
    };

    /// The number of blocks in a chunk
    pub const volume = size_xz * size_y * size_xz;

    pub fn generate(chunk_x: Coord, chunk_z: Coord) Chunk {
        const seed = 0xdead;

        var chunk: Chunk = undefined;
        for (0..size_xz) |x| {
            for (0..size_xz) |z| {
                // We sample from the center of blocks to avoid using integer coordinates as they collapse the perlin noise algorithm.
                const block_x: Fp = 0.5 + @as(Fp, @floatFromInt(@as(Block.Coord, chunk_x) * size_xz + @as(Block.Coord, @intCast(x))));
                const block_z: Fp = 0.5 + @as(Fp, @floatFromInt(@as(Block.Coord, chunk_z) * size_xz + @as(Block.Coord, @intCast(z))));

                const continentalness = sampleLayeredNoise2d(seed, block_x, block_z, 1.0, 1.0, 8, 0.5, 2.0);

                const block_height = @as(Block.Coord, @intFromFloat(0.5 * size_y + continentalness * 0.5 * size_y)) - 1;
                for (0..size_y) |y| {
                    chunk.blocks[(z * size_y + y) * size_xz + x] = if (y <= block_height) .stone else .air;
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

                    block_ids[index] = chunk.blocks[index];
                }
            }
        }

        return .{ vertices, indices, block_ids };
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
        const octave_offset: Fp = std.math.maxInt(@TypeOf(octave_count)) / octave_count;
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
const Allocator = std.mem.Allocator;

const zm = @import("zm");
