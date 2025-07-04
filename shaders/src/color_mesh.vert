#version 450

layout(push_constant) uniform constants {
    mat4 mvp;
    vec4 color;
    vec4 orientation;
} pconst;

layout(location=0) in vec4 in_position;
layout(location=1) in vec2 in_tex_coords;
layout(location=2) in vec3 in_normal;

layout(location=0) out vec4 out_color;
layout(location=1) flat out vec3 out_normal;

// q is the quaternion (x, y, z, w)
vec3 qtransform(vec4 q, vec3 v) {
    vec3 u = q.xyz;
    float s = q.w;
    return 2.0 * dot(u, v) * u
         + (s * s - dot(u, u)) * v
         + 2.0 * s * cross(u, v);
}

void main() {
    // tile nonsense
    vec4 pos = in_position + vec4(2.0,0,0,0) * float(gl_InstanceIndex);
    gl_Position = pos * pconst.mvp;
    out_color = pconst.color;
    out_normal = qtransform(pconst.orientation, in_normal);
}