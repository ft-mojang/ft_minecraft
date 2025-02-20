#version 450

layout(location = 0) in vec3 in_vertex;
layout(location = 0) out vec3 out_color;

void main() {
    gl_Position = vec4(in_vertex, 1.0);
    out_color = vec3(vec2(0.0), 1.0);
}
