const UniformBufferObject = struct {
    model: Mat4f,
    view: Mat4f,
    proj: Mat4f,
};

const Mat4f = @import("zm").Mat4f;
