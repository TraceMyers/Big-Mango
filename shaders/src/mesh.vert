#version 450

layout(push_constant) uniform constants {
    mat4 mvp;
} pconst;

layout(location=0) in vec4 position;
layout(location=1) in vec2 in_tex_coords;

layout(location=0) out vec2 tex_coords;

void main() {
    gl_Position = pconst.mvp * position;
    tex_coords = in_tex_coords;
}