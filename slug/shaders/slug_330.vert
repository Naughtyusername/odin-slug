// ===================================================
// Slug vertex shader — GLSL 3.30 (OpenGL 3.3)
// Ported from GLSL 4.50 / HLSL by Eric Lengyel (MIT)
// ===================================================

#version 330 core

// --- Vertex attributes ---
// Per-vertex input data: 5 vec4 attributes
// Locations are set from CPU side via glBindAttribLocation or queried with glGetAttribLocation.

in vec4 inPos;     // .xy = object-space position, .zw = dilation normal
in vec4 inTex;     // .xy = em-space texcoord, .zw = packed glyph data (as float bits)
in vec4 inJac;     // Inverse Jacobian matrix entries (00, 01, 10, 11)
in vec4 inBnd;     // Band scale and offset (sx, sy, ox, oy)
in vec4 inCol;     // Vertex color (RGBA)

// --- Uniforms (replaces push constants) ---
uniform mat4 mvp;           // Model-View-Projection matrix
uniform vec2 viewport;      // Viewport dimensions in pixels

// --- Outputs to fragment shader ---
// Matched by name with fragment shader inputs (no layout locations in 3.30 varyings).
     out vec4  outColor;
     out vec2  outTexcoord;
flat out vec4  outBanding;
flat out ivec4 outGlyph;


void SlugUnpack(vec4 tex, vec4 bnd, out vec4 vbnd, out ivec4 vgly)
{
    uvec2 g = floatBitsToUint(tex.zw);
    vgly = ivec4(g.x & 0xFFFFu, g.x >> 16u, g.y & 0xFFFFu, g.y >> 16u);
    vbnd = bnd;
}

vec2 SlugDilate(vec4 pos, vec4 tex, vec4 jac, vec4 m0, vec4 m1, vec4 m3, vec2 dim, out vec2 vpos)
{
    vec2 n = normalize(pos.zw);
    float s = dot(m3.xy, pos.xy) + m3.w;
    float t = dot(m3.xy, n);

    float u = (s * dot(m0.xy, n) - t * (dot(m0.xy, pos.xy) + m0.w)) * dim.x;
    float v = (s * dot(m1.xy, n) - t * (dot(m1.xy, pos.xy) + m1.w)) * dim.y;

    float s2 = s * s;
    float st = s * t;
    float uv = u * u + v * v;
    vec2 d = pos.zw * (s2 * (st + sqrt(uv)) / (uv - st * st));

    vpos = pos.xy + d;
    return vec2(tex.x + dot(d, jac.xy), tex.y + dot(d, jac.zw));
}

void main()
{
    vec2 p;

    // Extract MVP matrix rows for the dilation calculation.
    // The uniform mvp is column-major in GLSL, but the HLSL reference
    // uses row-major slug_matrix[4] where [i] is row i.
    // mvp[col][row] in GLSL. We need rows:
    vec4 m0 = vec4(mvp[0][0], mvp[1][0], mvp[2][0], mvp[3][0]); // row 0
    vec4 m1 = vec4(mvp[0][1], mvp[1][1], mvp[2][1], mvp[3][1]); // row 1
    vec4 m2 = vec4(mvp[0][2], mvp[1][2], mvp[2][2], mvp[3][2]); // row 2
    vec4 m3 = vec4(mvp[0][3], mvp[1][3], mvp[2][3], mvp[3][3]); // row 3

    // Apply dynamic dilation to vertex position. Returns new em-space sample position.
    outTexcoord = SlugDilate(inPos, inTex, inJac, m0, m1, m3, viewport, p);

    // Apply MVP matrix to dilated vertex position.
    gl_Position.x = p.x * m0.x + p.y * m0.y + m0.w;
    gl_Position.y = p.x * m1.x + p.y * m1.y + m1.w;
    gl_Position.z = p.x * m2.x + p.y * m2.y + m2.w;
    gl_Position.w = p.x * m3.x + p.y * m3.y + m3.w;

    // Unpack remaining vertex data.
    SlugUnpack(inTex, inBnd, outBanding, outGlyph);
    outColor = inCol;
}
