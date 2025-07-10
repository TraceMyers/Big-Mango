#version 450

layout(binding=0) uniform Lights {
    vec3 sun_direction;
    float insane_padding;
    vec4 sun_tint;
} lights;

layout(location=0) in vec4 in_color;
layout(location=1) flat in vec3 in_face_normal;

layout(location=0) out vec4 color;

void main() {
    color = in_color;
}