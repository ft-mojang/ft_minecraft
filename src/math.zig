// 4x4 float matrix.
pub const Mat4f = Mat(f32, 4);
/// Float vector with xyzw components.
pub const Vec4fx = VecXYZW(f32);
/// Float vector with xyz components.
pub const Vec3fx = VecXYZ(f32);
/// Float vector with xy components.
pub const Vec2fx = VecXY(f32);
/// Generic float vector with 4 components.
pub const Vec4f = Vec(f32, 4);
/// Generic float vector with 3 components.
pub const Vec3f = Vec(f32, 3);
/// Generic float vector with 2 components.
pub const Vec2f = Vec(f32, 2);

pub fn VecXY(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        /// Casts the vector into it's more generic representation.
        pub fn asGeneric(self: Self) GenericRepr {
            return @bitCast(self);
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        pub fn zero() Self {
            return GenericRepr.scalar(0).asComponent();
        }

        pub fn scalar(value: T) Self {
            return GenericRepr.scalar(value).asComponent();
        }

        pub fn magnitude(self: Self) T {
            return self.asGeneric().magnitude().asComponent();
        }

        pub fn dot(lhs: Self, rhs: anytype) T {
            return lhs.asGeneric().dot(rhs.asGeneric());
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs.asGeneric()).asComponent();
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs.asGeneric()).asComponent();
        }

        pub fn div(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().div(rhs.asGeneric()).asComponent();
        }

        pub fn mul(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn normalize(self: Self) Self {
            return self.asGeneric().normalize().asComponent();
        }

        const GenericRepr = Vec(T, 2);
        const Self = VecXYZ(T);
    };
}

pub fn VecXYZ(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,

        // Specialized

        pub fn cross(lhs: Self, rhs: anytype) Self {
            const _rhs = rhs.asComponent();

            return .{
                .x = lhs.y * _rhs.z - _rhs.y * lhs.z,
                .y = lhs.z * _rhs.x - _rhs.z * lhs.x,
                .z = lhs.x * _rhs.y - _rhs.x * lhs.y,
            };
        }

        // Generic & forwards

        /// Casts the vector into it's more generic representation.
        pub fn asGeneric(self: Self) GenericRepr {
            return @bitCast(self);
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        pub fn zero() Self {
            return GenericRepr.scalar(0).asComponent();
        }

        pub fn scalar(value: T) Self {
            return GenericRepr.scalar(value).asComponent();
        }

        pub fn magnitude(self: Self) T {
            return self.asGeneric().magnitude().asComponent();
        }

        pub fn dot(lhs: Self, rhs: anytype) T {
            return lhs.asGeneric().dot(rhs.asGeneric());
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs.asGeneric()).asComponent();
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs.asGeneric()).asComponent();
        }

        pub fn div(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().div(rhs.asGeneric()).asComponent();
        }

        pub fn mul(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn normalize(self: Self) Self {
            return self.asGeneric().normalize().asComponent();
        }

        const GenericRepr = Vec(T, 3);
        const Self = VecXYZ(T);
    };
}

pub fn VecXYZW(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,
        w: T,

        /// Casts the vector into it's more generic representation.
        pub fn asGeneric(self: Self) GenericRepr {
            return @bitCast(self);
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        pub fn zero() Self {
            return GenericRepr.scalar(0).asComponent();
        }

        pub fn scalar(value: T) Self {
            return GenericRepr.scalar(value).asComponent();
        }

        pub fn magnitude(self: Self) T {
            return self.asGeneric().magnitude().asComponent();
        }

        pub fn dot(lhs: Self, rhs: anytype) T {
            return lhs.asGeneric().dot(rhs.asGeneric());
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs.asGeneric()).asComponent();
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs.asGeneric()).asComponent();
        }

        pub fn div(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().div(rhs.asGeneric()).asComponent();
        }

        pub fn mul(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn normalize(self: Self) Self {
            return self.asGeneric().normalize().asComponent();
        }

        const GenericRepr = Vec(T, 3);
        const Self = VecXYZW(T);
    };
}

pub fn Vec(comptime T: type, comptime N: usize) type {
    return extern struct {
        d: [N]T,

        pub fn zero() Self {
            return Self.scalar(0);
        }

        pub fn scalar(val: T) Self {
            var self: Self = undefined;

            inline for (&self.d) |*d| {
                d.* = val;
            }

            return self;
        }

        pub fn xyz(x: T, y: T, z: T) Self {
            comptime debug.assert(N == 3);

            return (VecXYZ(T){
                .x = x,
                .y = y,
                .z = z,
            }).asGeneric();
        }

        pub fn xyzw(x: T, y: T, z: T, w: T) Self {
            comptime debug.assert(N == 4);

            return (VecXYZW(T){
                .x = x,
                .y = y,
                .z = z,
                .w = w,
            }).asGeneric();
        }

        /// Returns self. Exists for generics.
        pub fn asGeneric(self: Self) Self {
            return self;
        }

        /// Casts the vector into it's xyz[w] component representation.
        pub fn asComponent(self: Self) ComponentRepr {
            return switch (comptime N) {
                2 => @as(VecXYZ(T), @bitCast(self)),
                3 => @as(VecXYZ(T), @bitCast(self)),
                4 => @as(VecXYZW(T), @bitCast(self)),
                else => @panic("compontent repr not defined"),
            };
        }

        pub fn dot(lhs: Self, rhs: anytype) T {
            return @reduce(
                .Add,
                @as(VectorRepr, @bitCast(lhs)) * @as(VectorRepr, @bitCast(rhs.asGeneric())),
            );
        }

        pub fn magnitude(self: Self) T {
            return @sqrt(self.dot(self));
        }

        pub fn normalize(self: Self) Self {
            return self.div(self.magnitude());
        }

        pub fn cross(lhs: Self, rhs: Self) Self {
            if (comptime N != 3) {
                @compileError("cross product is only defined for 3 dimensional vectors");
            }

            return lhs.asComponent()
                .cross(rhs.asComponent())
                .asGeneric();
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            const use_simd = comptime @sizeOf(Self) == @sizeOf(VectorRepr);
            var out: [N]T = undefined;

            if (comptime @TypeOf(rhs.asGeneric()) == Self) {
                if (comptime use_simd) {
                    return @bitCast(@as(VectorRepr, @bitCast(lhs)) - @as(VectorRepr, @bitCast(rhs)));
                }

                inline for (&out, lhs.d, rhs.d) |*o, l, r| {
                    o.* = l - r;
                }

                return @bitCast(out);
            }

            if (comptime use_simd) {
                return @bitCast(@as(VectorRepr, @bitCast(lhs)) - @as(VectorRepr, @splat(rhs)));
            }

            inline for (&out, lhs.d) |*o, l| {
                o.* = l - rhs;
            }

            return @bitCast(out);
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            const use_simd = comptime @sizeOf(Self) == @sizeOf(VectorRepr);
            var out: [N]T = undefined;

            if (comptime @TypeOf(rhs.asGeneric()) == Self) {
                if (comptime use_simd) {
                    return @bitCast(@as(VectorRepr, @bitCast(lhs)) + @as(VectorRepr, @bitCast(rhs)));
                }

                inline for (&out, lhs.d, rhs.d) |*o, l, r| {
                    o.* = l + r;
                }

                return @bitCast(out);
            }

            if (comptime use_simd) {
                return @bitCast(@as(VectorRepr, @bitCast(lhs)) + @as(VectorRepr, @splat(rhs)));
            }

            inline for (&out, lhs.d) |*o, l| {
                o.* = l + rhs;
            }

            return @bitCast(out);
        }

        pub fn div(lhs: Self, rhs: T) Self {
            if (comptime @sizeOf(VectorRepr) == @sizeOf(Self)) {
                return @bitCast(@as(VectorRepr, @bitCast(lhs)) / @as(VectorRepr, @splat(rhs)));
            }

            var out: [N]T = undefined;
            inline for (&out, lhs.d) |*o, l| {
                o.* = l / rhs;
            }

            return @bitCast(out);
        }

        pub fn mul(lhs: Self, rhs: T) Self {
            if (comptime @sizeOf(Self) == @sizeOf(VectorRepr)) {
                return @as(VectorRepr, @bitCast(lhs)) * @as(VectorRepr, @splat(rhs));
            }

            var out: [N]T = undefined;
            inline for (&out, lhs.d) |*o, l| {
                o.* = l * rhs;
            }

            return @bitCast(out);
        }

        const ComponentRepr = switch (N) {
            2 => VecXY(T),
            3 => VecXYZ(T),
            4 => VecXYZW(T),
            else => Self,
        };

        const Self = Vec(T, N);
        const VectorRepr = @Vector(N, T);
    };
}

pub fn Mat(comptime T: type, comptime N: usize) type {
    return extern struct {
        data: [N][N]T,

        pub fn scalar(value: T) Self {
            var self: Self = undefined;

            inline for (@as(*[N * N]T, @ptrCast(&self.data))) |*data| {
                data.* = value;
            }

            return self;
        }

        pub fn zero() Self {
            return Self.scalar(0);
        }

        pub fn diagonal(value: T) Self {
            var self = Self.zero();

            inline for (0..N) |i| {
                self.data[i][i] = value;
            }

            return self;
        }

        pub fn identity() Self {
            return Self.diagonal(1);
        }

        pub fn perspective(fov_y: T, aspect_ratio: T, near: T, far: T) Self {
            if (comptime N != 4) {
                @compileError("perspective projection must be a 4x4 Matrix");
            }

            var data = Self.zero().data;
            const tan_half_fov_y = @tan(fov_y / 2);

            data[0][0] = 1 / (aspect_ratio * tan_half_fov_y);
            data[1][1] = 1 / (tan_half_fov_y);
            data[2][2] = far / (near - far);
            data[2][3] = -1;
            data[3][2] = -(far * near) / (far - near);

            return Self{ .data = data };
        }

        pub fn lookAt(eyes: anytype, target: anytype, up: anytype) Self {
            const f = target.sub(eyes).normalize().asComponent();
            const s = f.cross(up).normalize().asComponent();
            const u = s.cross(f).asComponent();

            var data = Self.identity().data;

            data[0][0] = s.x;
            data[1][0] = s.y;
            data[2][0] = s.z;
            data[0][1] = u.x;
            data[1][1] = u.y;
            data[2][1] = u.z;
            data[0][2] = -f.x;
            data[1][2] = -f.y;
            data[2][2] = -f.z;
            data[3][0] = -s.dot(eyes);
            data[3][1] = -u.dot(eyes);
            data[3][2] = f.dot(eyes);

            return Self{ .data = data };
        }

        pub fn mul(self: Self, rhs: Self) Self {
            debug.assert(comptime N == 4);

            var data: [4][4]T = undefined;

            const a0: VecXYZW(T) = @bitCast(self.data[0]);
            const a1: VecXYZW(T) = @bitCast(self.data[1]);
            const a2: VecXYZW(T) = @bitCast(self.data[2]);
            const a3: VecXYZW(T) = @bitCast(self.data[3]);

            const b0: VecXYZW(T) = @bitCast(rhs.data[0]);
            const b1: VecXYZW(T) = @bitCast(rhs.data[1]);
            const b2: VecXYZW(T) = @bitCast(rhs.data[2]);
            const b3: VecXYZW(T) = @bitCast(rhs.data[3]);

            data[0] = @bitCast(a3.mul(b0.w).add(a2.mul(b0.z)).add(a1.mul(b0.y)).add(a0.mul(b0.x)));
            data[1] = @bitCast(a3.mul(b1.w).add(a2.mul(b1.z)).add(a1.mul(b1.y)).add(a0.mul(b1.x)));
            data[2] = @bitCast(a3.mul(b2.w).add(a2.mul(b2.z)).add(a1.mul(b2.y)).add(a0.mul(b2.x)));
            data[3] = @bitCast(a3.mul(b3.w).add(a2.mul(b3.z)).add(a1.mul(b3.y)).add(a0.mul(b3.x)));

            return @bitCast(data);
        }

        const Self = Mat(T, N);
    };
}

test "matrix scalar initialization" {
    const matrix = Mat(u32, 4).scalar(42);

    for (0..4, 0..4) |i, j| {
        try testing.expectEqual(matrix.data[i][j], 42);
    }
}

test "vector dot product" {
    const a = Vec(f32, 4).xyzw(1, 2, 3, 4);
    const b = Vec(f32, 4).xyzw(5, 6, 7, 8);

    try testing.expectEqual(a.dot(b), 70);

    const c = Vec(f32, 3).xyz(1, 2, 3);
    const d = Vec(f32, 3).xyz(4, 5, 6);

    try testing.expectEqual(c.dot(d), 32);
}

const std = @import("std");
const math = std.math;
const debug = std.debug;
const builtin = std.builtin;
const Type = builtin.Type;
const StructField = Type.StructField;
const testing = std.testing;
