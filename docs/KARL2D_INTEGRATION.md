# Karl2D Integration Notes

Research notes on integrating odin-slug with [Karl2D](https://github.com/karl-zylinski/karl2d), Karl Zylinski's pure-Odin 2D game library.

## What Karl2D Is

Karl2D is a 2D game library written in pure Odin with zero C dependencies -- no GLFW, no SDL for windowing. It talks directly to OS windowing APIs and graphics APIs. MIT licensed, currently in beta.

- **Repository**: [github.com/karl-zylinski/karl2d](https://github.com/karl-zylinski/karl2d)
- **Author**: Karl Zylinski (author of the Odin game development book)
- **Status**: Beta 2 (as of March 2026)

## Karl2D Graphics Backends

Karl2D has three rendering backends, selected at compile time:

| Backend | Platform | Shader Language |
|---------|----------|-----------------|
| D3D11 | Windows | HLSL |
| OpenGL | Windows, Mac, Linux | GLSL |
| WebGL | Web (Odin JS runtime, no emscripten) | GLSL ES |

There is **no Vulkan backend**. All backends implement a `Render_Backend_Interface` struct with ~20 procedure fields (`draw`, `load_shader`, `create_texture`, `update_texture`, `clear`, `present`, etc.).

## Karl2D's Text Rendering

Karl2D uses FontStash for text -- a traditional bitmap atlas approach. Glyphs are rasterized at specific sizes into a texture atlas, then drawn as textured quads. This is the same approach Raylib uses. It works for fixed-size UI text but gets blurry when scaled/rotated and needs re-baking at different sizes.

This is exactly what odin-slug replaces with GPU Bezier evaluation.

## Karl2D Custom Shader Support

Karl2D supports custom shaders:
- `load_shader_from_bytes` loads vertex/fragment source
- Custom vertex input layouts via `layout_formats`
- Per-vertex attribute overrides via `override_shader_input`
- Uniform setting via `set_shader_constant` with name-based lookup
- The backend reflects shader programs to discover attributes and uniforms

Shaders must be written in each backend's native language (GLSL for OpenGL, HLSL for D3D11, GLSL ES for WebGL).

## Integration Options

### Option A: Bypass Karl2D Batching (Easiest, Works Now)

Since Karl2D uses OpenGL on Linux, you can use odin-slug's existing OpenGL backend alongside Karl2D in the same application. This is the same approach used for Raylib integration:

1. Flush Karl2D's internal batch before slug draws
2. Issue slug GL draw calls using odin-slug's OpenGL backend
3. Resume Karl2D rendering

This requires **zero changes** to either library. The main question is how Karl2D exposes batch flushing -- look for the equivalent of Raylib's `rlgl.DrawRenderBatchActive()` in Karl2D's renderer. Karl2D's `Render_Backend_Interface` has a `present` proc and likely a flush mechanism.

You would also need to ensure Odin's `vendor:OpenGL` function pointers are loaded (same gotcha as Raylib -- Karl2D may use its own GL loader internally).

**Pros**: Works today, no library modifications needed.
**Cons**: Two separate rendering systems managing GL state, not integrated into Karl2D's batching.

### Option B: Dedicated Karl2D Backend (Cleaner, Needs Karl2D Changes)

Write a proper `slug/backends/karl2d/karl2d.odin` backend that uses Karl2D's shader and texture APIs. This would be the cleanest integration but requires Karl2D to add support for two texture formats that odin-slug needs.

**Required Karl2D changes:**

1. **RGBA16F texture format** -- odin-slug's curve texture stores Bezier control points as half-floats. Karl2D's OpenGL backend currently supports `RGBA_32_Float`, `RGB_32_Float`, `RG_32_Float`, `R_32_Float`, `RGBA_8_Norm`, `RG_8_Norm`, `R_8_Norm`, `R_8_UInt` -- but not `RGBA_16_Float`. This is a small addition to Karl2D's `gl_describe_pixel_format` and format enum.

2. **RG16UI texture format** -- odin-slug's band texture stores curve indices as unsigned 16-bit integers. This requires `GL_RG_INTEGER` format with `GL_UNSIGNED_SHORT` type and `usampler2D` in the shader. Karl2D's texture system appears designed for normalized/float textures, so integer texture sampling would be a new code path.

Both are standard OpenGL 3.0+ formats. Karl Zylinski would likely be receptive to adding them -- any serious GPU text rendering or compute feature would need them.

**Additional work for cross-platform:**
- The Slug fragment shader would need HLSL and GLSL ES ports for D3D11 and WebGL backends
- The GLSL 3.30 shaders in odin-slug could be adapted to GLSL ES with modest changes
- An HLSL port would be more work but straightforward (same algorithm, different syntax)

**Pros**: Clean integration, works with Karl2D's batching, cross-platform potential.
**Cons**: Requires Karl2D texture format additions, shader ports for non-OpenGL backends.

## Key odin-slug Files for Reference

| File | Contents |
|------|----------|
| `slug/slug.odin` | Core types, Context, Vertex format (graphics-API-agnostic) |
| `slug/backends/opengl/opengl.odin` | OpenGL 3.3 backend (~580 lines) -- template for a Karl2D backend |
| `slug/backends/raylib/raylib.odin` | Raylib wrapper (~85 lines) -- example of the "bypass batching" approach |

## Texture Format Summary

| Texture | Format | GL Enum | Purpose |
|---------|--------|---------|---------|
| Curve | RGBA16F | `GL_RGBA16F` / `GL_RGBA` / `GL_HALF_FLOAT` | Bezier control points (2 texels per curve) |
| Band | RG16UI | `GL_RG16UI` / `GL_RG_INTEGER` / `GL_UNSIGNED_SHORT` | Band headers + curve index lists |

Both are sampled with `texelFetch` (integer coordinates, no filtering). The band texture uses `usampler2D` (unsigned integer sampler) in GLSL.

## Next Steps

1. Try Option A first -- get odin-slug rendering alongside Karl2D with the raw OpenGL bypass
2. Identify Karl2D's batch flush mechanism
3. If it works well, propose the texture format additions to Karl Zylinski
4. Write the dedicated backend once Karl2D supports the formats
