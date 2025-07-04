#version 460

layout (local_size_x=32, local_size_y=32) in;
// 1 descriptor set at image 0, containing a binding at set index 0
layout(rgba16f, set=0, binding=0) uniform image2D image;
layout(set=1, binding=0) uniform sampler2D read_tex;
layout(push_constant) uniform constants {
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
        vec2 norm_coords = vec2(gl_GlobalInvocationID.xy) / vec2(gl_NumWorkGroups.xy * 32);
        vec4 sample_texel = texture(read_tex, norm_coords);
        sample_texel.rgb = pow(sample_texel.rgb, vec3(2.2));
        imageStore(image, texel_coord, sample_texel);
    }
}