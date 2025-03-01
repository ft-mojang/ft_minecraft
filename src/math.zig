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

        pub fn xy(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        /// Casts the vector into it's more generic representation.
        pub fn asGeneric(self: Self) GenericRepr {
            return @bitCast(self);
        }

        /// Casts the vector pointer into it's more generic representation.
        pub fn asGenericPtr(self: *Self) *GenericRepr {
            return @alignCast(@ptrCast(self));
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        /// Returns self. Exists for generics.
        pub fn asComponentPtr(self: *Self) *Self {
            return self;
        }

        pub fn asVector(self: Self) GenericRepr.VectorRepr {
            return self.asGeneric().asVector();
        }

        pub fn fromVector(vector: GenericRepr.VectorRepr) Self {
            return GenericRepr{ .d = vector };
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
            return lhs.asGeneric().dot(rhs);
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs).asComponent();
        }

        pub fn addAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().addAssign(rhs);
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs).asComponent();
        }

        pub fn subAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().subAssign(rhs);
        }

        pub fn div(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().div(rhs).asComponent();
        }

        pub fn divAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().divAssign(rhs);
        }

        pub fn mul(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn mulAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().mulAssign(rhs);
        }

        pub fn normalize(self: Self) Self {
            return self.asGeneric().normalize().asComponent();
        }

        const GenericRepr = Vec(T, 2);
        const Self = VecXY(T);
    };
}

pub fn VecXYZ(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        z: T,

        // Specialized
        pub const up = Self.xyz(0, 1, 0);

        pub fn xyz(x: T, y: T, z: T) Self {
            return .{ .x = x, .y = y, .z = z };
        }

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

        /// Casts the vector pointer into it's more generic representation.
        pub fn asGenericPtr(self: *Self) *GenericRepr {
            return @alignCast(@ptrCast(self));
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        /// Returns self. Exists for generics.
        pub fn asComponentPtr(self: *Self) *Self {
            return self;
        }

        pub fn asVector(self: Self) GenericRepr.VectorRepr {
            return self.asGeneric().asVector();
        }

        pub fn fromVector(vector: GenericRepr.VectorRepr) Self {
            return GenericRepr{ .d = vector };
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
            return lhs.asGeneric().dot(rhs);
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs).asComponent();
        }

        pub fn addAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().addAssign(rhs);
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs).asComponent();
        }

        pub fn subAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().subAssign(rhs);
        }

        pub fn div(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().div(rhs).asComponent();
        }

        pub fn divAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().divAssign(rhs);
        }

        pub fn mul(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn mulAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().mulAssign(rhs);
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

        pub fn xyzw(x: T, y: T, z: T, w: T) Self {
            return .{
                .x = x,
                .y = y,
                .z = z,
                .w = w,
            };
        }

        /// Casts the vector into it's more generic representation.
        pub fn asGeneric(self: Self) GenericRepr {
            return @bitCast(self);
        }

        /// Casts the vector pointer into it's more generic representation.
        pub fn asGenericPtr(self: *Self) *GenericRepr {
            return @alignCast(@ptrCast(self));
        }

        /// Returns self. Exists for generics.
        pub fn asComponent(self: Self) Self {
            return self;
        }

        /// Returns self. Exists for generics.
        pub fn asComponentPtr(self: *Self) *Self {
            return self;
        }

        pub fn asVector(self: Self) GenericRepr.VectorRepr {
            return self.asGeneric().asVector();
        }

        pub fn fromVector(vector: GenericRepr.VectorRepr) Self {
            return GenericRepr{ .d = vector };
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
            return lhs.asGeneric().dot(rhs);
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().add(rhs).asComponent();
        }

        pub fn addAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().addAssign(rhs);
        }

        pub fn sub(lhs: Self, rhs: anytype) Self {
            return lhs.asGeneric().sub(rhs).asComponent();
        }

        pub fn subAssign(lhs: *Self, rhs: anytype) void {
            lhs.asGenericPtr().subAssign(rhs);
        }

        pub fn div(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().div(rhs).asComponent();
        }

        pub fn divAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().divAssign(rhs);
        }

        pub fn mul(lhs: Self, rhs: T) Self {
            return lhs.asGeneric().mul(rhs).asComponent();
        }

        pub fn mulAssign(lhs: *Self, rhs: T) void {
            lhs.asGenericPtr().mulAssign(rhs);
        }

        pub fn normalize(self: Self) Self {
            return self.asGeneric().normalize().asComponent();
        }

        const GenericRepr = Vec(T, 4);
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

        pub fn xy(x: T, y: T) Self {
            return ComponentRepr.xy(x, y).asGeneric();
        }

        pub fn xyz(x: T, y: T, z: T) Self {
            return ComponentRepr.xyz(x, y, z).asGeneric();
        }

        pub fn xyzw(x: T, y: T, z: T, w: T) Self {
            return ComponentRepr.xyzw(x, y, z, w).asGeneric();
        }

        /// Returns self. Exists for generics.
        pub fn asGeneric(self: Self) Self {
            return self;
        }

        /// Returns self. Exists for generics.
        pub fn asGenericPtr(self: *Self) *Self {
            return self;
        }

        /// Casts the vector into it's xy[zw] component representation.
        pub fn asComponent(self: Self) ComponentRepr {
            return switch (comptime N) {
                2 => @as(VecXY(T), @bitCast(self)),
                3 => @as(VecXYZ(T), @bitCast(self)),
                4 => @as(VecXYZW(T), @bitCast(self)),
                else => @panic("compontent repr not defined"),
            };
        }

        /// Casts the vector pointer into it's xy[zw] component representation.
        pub fn asComponentPtr(self: *Self) *ComponentRepr {
            return switch (comptime N) {
                2 => @as(VecXY(T), @alignCast(@ptrCast(self))),
                3 => @as(VecXYZ(T), @alignCast(@ptrCast(self))),
                4 => @as(VecXYZW(T), @alignCast(@ptrCast(self))),
                else => @panic("compontent repr not defined"),
            };
        }

        pub fn asVector(self: Self) VectorRepr {
            return self.d;
        }

        pub fn fromVector(vector: @Vector(N, T)) Self {
            return .{ .d = vector };
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

            if (comptime isVector(@TypeOf(rhs))) {
                const _rhs = rhs.asGeneric();
                if (comptime use_simd) {
                    return @bitCast(@as(VectorRepr, @bitCast(lhs)) - @as(VectorRepr, @bitCast(_rhs)));
                }

                inline for (&out, lhs.d, _rhs.d) |*o, l, r| {
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

        pub fn subAssign(lhs: *Self, rhs: anytype) void {
            lhs.* = lhs.sub(rhs);
        }

        pub fn add(lhs: Self, rhs: anytype) Self {
            const use_simd = comptime @sizeOf(Self) == @sizeOf(VectorRepr);
            var out: [N]T = undefined;

            if (comptime isVector(@TypeOf(rhs))) {
                const _rhs = rhs.asGeneric();
                if (comptime use_simd) {
                    return @bitCast(@as(VectorRepr, @bitCast(lhs)) + @as(VectorRepr, @bitCast(_rhs)));
                }

                inline for (&out, lhs.d, _rhs.d) |*o, l, r| {
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

        pub fn addAssign(lhs: *Self, rhs: anytype) void {
            lhs.* = lhs.add(rhs);
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

        pub fn divAssign(lhs: *Self, rhs: T) void {
            lhs.* = lhs.div(rhs);
        }

        pub fn mul(lhs: Self, rhs: T) Self {
            if (comptime @sizeOf(Self) == @sizeOf(VectorRepr)) {
                return @bitCast(@as(VectorRepr, @bitCast(lhs)) * @as(VectorRepr, @splat(rhs)));
            }

            var out: [N]T = undefined;
            inline for (&out, lhs.d) |*o, l| {
                o.* = l * rhs;
            }

            return @bitCast(out);
        }

        pub fn mulAssign(lhs: *Self, rhs: T) void {
            lhs.* = lhs.mul(rhs);
        }

        fn isVector(comptime U: type) bool {
            const _U = switch (@typeInfo(U)) {
                .pointer => @typeInfo(U).pointer.child,
                else => U,
            };
            if (comptime !meta.hasMethod(_U, "asGeneric")) {
                return false;
            }
            if (comptime @typeInfo(@TypeOf(_U.asGeneric)).@"fn".return_type != Self) {
                return false;
            }
            return true;
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

        pub fn translate(offset: anytype) Self {
            const _offset = offset.asComponent();
            var data = Self.identity().data;

            data[3][0] = _offset.x;
            data[3][1] = _offset.y;
            data[3][2] = _offset.z;

            return .{ .data = data };
        }

        pub fn scaleUniform(value: T) Self {
            var data = Self.identity().data;

            data[0][1] = value;
            data[1][1] = value;
            data[2][2] = value;

            return .{ .data = data };
        }

        pub fn scale(values: anytype) Self {
            const _values = values.asComponent();
            var data = Self.identity().data;

            data[0][1] = _values.x;
            data[1][1] = _values.y;
            data[2][2] = _values.z;

            return .{ .data = data };
        }

        pub fn rotate(radians: f32, axis: anytype) Self {
            const a = radians;
            const c = @cos(a);
            const s = @sin(a);
            const _axis = axis.asComponent().normalize();
            const temp = _axis.mul(1.0 - c);

            var rot = Self.zero().data;
            rot[0][0] = c + temp.x * axis.x;
            rot[0][1] = temp.x * axis.y + s * axis.z;
            rot[0][2] = temp.x * axis.z - s * axis.y;

            rot[1][0] = temp.y * axis.x - s * axis.z;
            rot[1][1] = c + temp.y * axis.y;
            rot[1][2] = temp.y * axis.z + s * axis.x;

            rot[2][0] = temp.z * axis.x + s * axis.y;
            rot[2][1] = temp.z * axis.y - s * axis.x;
            rot[2][2] = c + temp.z * axis.z;

            const ident: [N]VecXYZW(T) = @bitCast(Self.identity().data);
            var result = Self.zero().data;

            result[0] = @bitCast(ident[0].mul(rot[0][0]).add(ident[1].mul(rot[0][1])).add(ident[2].mul(rot[0][2])));
            result[1] = @bitCast(ident[0].mul(rot[1][0]).add(ident[1].mul(rot[1][1])).add(ident[2].mul(rot[1][2])));
            result[2] = @bitCast(ident[0].mul(rot[2][0]).add(ident[1].mul(rot[2][1])).add(ident[2].mul(rot[2][2])));
            result[3] = @bitCast(ident[3]);

            return .{ .data = result };
        }

        /// Right-handed perspective projection with one to zero depth range.
        pub fn perspective(fov_y_radians: T, aspect_ratio: T, near: T, far: T) Self {
            if (comptime N != 4) {
                @compileError("perspective projection must be a 4x4 Matrix");
            }

            var data = Self.zero().data;
            const tan_half_fov_y = @tan(fov_y_radians / 2);

            data[0][0] = 1 / (aspect_ratio * tan_half_fov_y);
            data[1][1] = 1 / (tan_half_fov_y);
            data[2][2] = -near / (near - far);
            data[2][3] = -1;
            data[3][2] = (far * near) / (far - near);

            return .{ .data = data };
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

            return .{ .data = data };
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

            return .{ .data = data };
        }

        pub fn asZm(self: Self) ZmRepr {
            return (ZmRepr{ .data = @as([16]T, @bitCast(self.data)) }).transpose();
        }

        pub fn fromZm(matrix: anytype) Self {
            return .{ .data = @as([4][4]T, @bitCast(matrix.transpose().data)) };
        }

        const Self = Mat(T, N);
        const ZmRepr = switch (T) {
            f64 => zm.Mat4,
            f32 => zm.Mat4f,
            else => @panic("unsupported zm conversion"),
        };
    };
}

test "matrix scalar initialization" {
    const matrix = Mat(u32, 4).scalar(42);

    for (0..4, 0..4) |i, j| {
        try testing.expectEqual(matrix.data[i][j], 42);
    }
}

test "vector dot product" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);
    const b = Vec4fx.xyzw(5, 6, 7, 8);

    try testing.expectEqual(a.dot(b), 70);

    const c = Vec3fx.xyz(1, 2, 3);
    const d = Vec3fx.xyz(4, 5, 6);

    try testing.expectEqual(c.dot(d), 32);
}

test "vector addition" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);
    const b = Vec4fx.xyzw(1, 2, 3, 4);

    try testing.expect(meta.eql(a.add(b), Vec4fx.xyzw(2, 4, 6, 8)));
}

test "vector scalar addition" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);

    try testing.expect(meta.eql(a.add(1), Vec4fx.xyzw(2, 3, 4, 5)));
}

test "vector substraction" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);
    const b = Vec4fx.xyzw(1, 2, 3, 4);

    try testing.expect(meta.eql(a.sub(b), Vec4fx.xyzw(0, 0, 0, 0)));
}

test "vector scalar substraction" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);

    try testing.expect(meta.eql(a.sub(1), Vec4fx.xyzw(0, 1, 2, 3)));
}

test "vector multiplication" {
    const a = Vec4fx.xyzw(1, 2, 3, 4);

    try testing.expect(meta.eql(a.mul(2), Vec4fx.xyzw(2, 4, 6, 8)));
}

test "vector division" {
    const a = Vec4fx.xyzw(2, 4, 6, 8);

    try testing.expect(meta.eql(a.div(2), Vec4fx.xyzw(1, 2, 3, 4)));
}

test "as / from vector" {
    _ = Vec4f.fromVector(Vec4f.zero().asVector());
    _ = Vec3f.fromVector(Vec3f.zero().asVector());
    _ = Vec2f.fromVector(Vec2f.zero().asVector());
}

test "as / from zm matrix" {
    _ = Mat4f.fromZm(Mat4f.zero().asZm());
}

const std = @import("std");
const zm = @import("zm");
const math = std.math;
const meta = std.meta;
const debug = std.debug;
const builtin = std.builtin;
const Type = builtin.Type;
const StructField = Type.StructField;
const testing = std.testing;
