#version 460

layout (local_size_x=32, local_size_y=32) in;
// 1 descriptor set at image 0, containing a binding at set index 0
layout(rgba16f, set=0, binding=0) uniform image2D image;
layout(push_constant) uniform constants {
    vec4 color;
    vec2 upper_left;
    vec2 lower_right;
} pconst;

void main() {
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    texel_coord.x += int(pconst.upper_left.x);
    texel_coord.y += int(pconst.upper_left.y);

    ivec2 size = imageSize(image);
    if (texel_coord.x < 0 || texel_coord.y < 0 || texel_coord.x >= size.x || texel_coord.y >= size.y) {
        return;
    }
    if (texel_coord.x <= pconst.lower_right.x && texel_coord.y <= pconst.lower_right.y) {
        vec4 bg_col = imageLoad(image, texel_coord);
        vec3 mixed = bg_col.rgb * (1.0 - pconst.color.a) + pconst.color.rgb * pconst.color.a;
        imageStore(image, texel_coord, vec4(mixed, 1.0));
    }
}