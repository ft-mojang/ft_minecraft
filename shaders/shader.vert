#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in vec3 in_vertex;
layout(location = 0) out vec3 out_color;

void main() {
    vec3 vertex_colors[] = {
        vec3(0.2, 0.2, 0.2),
        vec3(0.4, 0.4, 0.4),
        vec3(0.6, 0.6, 0.6),
        vec3(0.8, 0.8, 0.8),
        vec3(1.0, 1.0, 1.0),
        vec3(0.8, 0.8, 0.8),
        vec3(0.6, 0.6, 0.6),
        vec3(0.4, 0.4, 0.4),
    };

    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(in_vertex, 1.0);
    out_color = vertex_colors[gl_VertexIndex / 8 % 8];
}
