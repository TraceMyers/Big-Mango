#version 450

layout(binding=0) uniform sampler2D texture_sampler;

layout(location=0) in vec2 tex_coords;

layout(location=0) out vec4 color;

void main() {
    color = texture(texture_sampler, tex_coords);
    // color = vec4(1,0,0,1);
}