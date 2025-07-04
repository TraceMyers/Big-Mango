#version 450

layout (local_size_x=32, local_size_y=32) in;
layout(rgba16f, set=0, binding=0) uniform image2D render_target;
layout(push_constant) uniform constants {
    float segment_point_a_x;
    float segment_point_a_y;
    float segment_point_a_z;
    float segment_point_b_x;
    float segment_point_b_y;
    float segment_point_b_z;
    float norm_radius;
    float color_r;
    float color_g;
    float color_b;
    float color_a;
} pconst;

float dist_sq_from_line_segment(vec2 point, vec2 segment_a, vec2 segment_b) {
    vec2 to_point = point - segment_a; 
    vec2 to_b = segment_b - segment_a;

    float t = clamp(dot(to_point, to_b) / dot(to_b, to_b), 0, 1);
    vec2 closest_point = segment_a + to_b * t;
    vec2 point_to_projection = closest_point - point;
    return dot(point_to_projection, point_to_projection);
}

void main() {
    ivec2 size = imageSize(render_target);
    float radius = pconst.norm_radius; 
    radius *= float(size.x);

    vec2 point_a = vec2(pconst.segment_point_a_x, pconst.segment_point_a_y) * size;
    vec2 point_b = vec2(pconst.segment_point_b_x, pconst.segment_point_b_y) * size;
    vec2 top_left_pos = vec2(min(point_a.x, point_b.x) - radius, min(point_a.y, point_b.y) - radius);

    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy) + ivec2(top_left_pos);

    if (texel_coord.x < 0 || texel_coord.y < 0 || texel_coord.x >= size.x || texel_coord.y >= size.y) {
        return;
    }

    vec2 texel_coord_f = vec2(texel_coord);
    float dist_sq = dist_sq_from_line_segment(texel_coord_f, point_a, point_b);

    // TODO: calculate real radius w/ real input
    if (dist_sq > radius * radius) {
        return;
    }

    vec4 cur_color = imageLoad(render_target, texel_coord);
    vec4 capsule_color = vec4(pconst.color_r, pconst.color_g, pconst.color_b, pconst.color_a);
    vec4 store_color = vec4(capsule_color.rgb * capsule_color.a + cur_color.rgb * (1.0-capsule_color.a), 1.0);
    imageStore(render_target, texel_coord, store_color);
}