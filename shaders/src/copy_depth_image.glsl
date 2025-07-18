#version 450
layout (binding = 0) uniform sampler2D depthImage;
layout (binding = 1, rgba16f) writeonly uniform image2D colorImage;

layout (local_size_x = 32, local_size_y = 32) in;

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(colorImage);
    //if (coord.x < 0 || coord.y < 0 || coord.x >= size.x || coord.y >= size.y) {
    //    return;
    //}
    float depth = texelFetch(depthImage, coord, 0).r;
    vec4 color = vec4(depth, depth, depth, 1.0); // Visualize depth as grayscale
    imageStore(colorImage, coord, color);
}