#version 450

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(float(gl_FragCoord.x) / 800, float(gl_FragCoord.y) / 800, 1.0, 0.2);
}