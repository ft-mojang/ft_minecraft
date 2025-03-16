/// Sums octaves of 2D noise and returns a normalized result in range -1 to 1 (inclusive)
pub fn sampleLayeredNoise2d(
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

/// Sums octaves of 3D noise and returns a normalized result in range -1 to 1 (inclusive)
pub fn sampleLayeredNoise3d(
    seed: i32,
    x: Fp,
    y: Fp,
    z: Fp,
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
        height_sum += _amplitude * Noise.singleSimplexS3D(seed, _frequency * (x + offset), _frequency * (y + offset), _frequency * (z + offset));
        _amplitude *= persistence;
        _frequency *= lacunarity;
    }
    return height_sum / height_max;
}

pub const Fp = f64;

const std = @import("std");
const math = std.math;

const fastnoise = @import("noise/fastnoise.zig");
const Noise = fastnoise.Noise(Fp);
