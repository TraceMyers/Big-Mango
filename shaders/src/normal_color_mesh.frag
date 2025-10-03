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
    //float luminance = max(dot(lights.sun_direction, -in_face_normal), 0.1);
    // color = vec4((in_face_normal.rgb * lights.sun_tint.rgb) * luminance, in_color.a);
    color = vec4(in_face_normal.rgb, in_color.a);
}