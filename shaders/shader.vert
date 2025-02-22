#version 450

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in vec3 in_vertex;
layout(location = 0) out vec3 out_color;

void main() {
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(in_vertex, 1.0);
    out_color = vec3(0.0, 0.3, 0.7);
}
