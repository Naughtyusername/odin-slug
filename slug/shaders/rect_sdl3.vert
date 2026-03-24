// Rect vertex shader — SDL3 GPU variant (UBO instead of push_constant)
#version 450

layout(location = 0) in vec2 inPos;
layout(location = 1) in vec4 inCol;

// SDL3 GPU descriptor set convention: vertex uniforms = set 1
layout(set = 1, binding = 0) uniform UBO {
    mat4 mvp;
} ubo;

layout(location = 0) out vec4 vColor;

void main() {
    gl_Position = ubo.mvp * vec4(inPos, 0.0, 1.0);
    vColor = inCol;
}
