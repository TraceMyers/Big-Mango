#version 460

layout (local_size_x=32, local_size_y=32) in;
// 1 descriptor set at image 0, containing a binding at set index 0
layout(rgba16f, set=0, binding=0) uniform image2D image;
layout(push_constant) uniform constants {
    float pos_x;
    float pos_y;
    float pos_z;
    float radius;
    float norm_t;
    float norm_rand;
} pconst;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void main() {
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    vec3 sphere_pos = vec3(pconst.pos_x, pconst.pos_y, pconst.pos_z);
    float sphere_rad = pconst.radius;

    vec2 texel_coord_flt = vec2(texel_coord);
    texel_coord_flt += sphere_pos.xy - vec2(sphere_rad);

    vec2 circle_pos_diff = vec2(texel_coord) - vec2(sphere_rad);
    float circle_pos_dist_sq = dot(circle_pos_diff, circle_pos_diff);
    float sphere_rad_sq = sphere_rad * sphere_rad;

    texel_coord = ivec2(int(texel_coord_flt.x), int(texel_coord_flt.y));
    ivec2 size = imageSize(image);
    if (texel_coord.x < 0 || texel_coord.y < 0 || texel_coord.x >= size.x || texel_coord.y >= size.y) {
        return;
    }
    float dist_sq_diff = circle_pos_dist_sq - sphere_rad_sq;
    if (dist_sq_diff > 0.0) {
        return;
    }

    float dx = circle_pos_diff.x;
    float dy = circle_pos_diff.y;
    float rprime = sqrt(sphere_rad * sphere_rad - dy * dy);
    float dz = sqrt(rprime * rprime - dx * dx);
    vec3 px_sphere_norm = normalize(vec3(dx, dy, dz));

    float light_factor = 0.0;
    vec3 value = vec3(0);
    for (int i = 0; i < 2; i += 1) {
        float light_z_val = sqrt(1.0 - pconst.norm_t * pconst.norm_t);
        vec3 light_inv_normal;
        if (i == 0) {
            light_inv_normal = vec3(0,pconst.norm_t,light_z_val);
        } else {
            light_inv_normal = vec3(pconst.norm_t,light_z_val,0);
        }
        float light_factor_iter = dot(px_sphere_norm, light_inv_normal);
        light_factor_iter *= abs(light_factor_iter);
        if (-dist_sq_diff < 1000.0f) {
            light_factor_iter *= 1.2;
        }
        // light_factor += light_factor_iter;
        // value += vec3(1) * light_factor_iter;
        value += vec3(0.9) * max(light_factor_iter, 0.02);
    }
    // vec3 value = vec3(1) * max(light_factor, 0.02);

    if (-dist_sq_diff < 1000.0f) {
        value *= 1.1;
    }

    float value_size = length(value) * 0.8;
    float px_rnd_factor = rand(texel_coord_flt * vec2(pconst.norm_rand) + vec2(pconst.norm_rand) * 103.0);
    float rnd_factor = value_size + px_rnd_factor * (1.0-value_size);
    value *= rnd_factor;

    imageStore(image, texel_coord, vec4(value,1));
}