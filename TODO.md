# odin-slug — TODO

Tracks both the feature roadmap and polish/cleanup work.
Update after each session.

Last updated: 2026-03-23 (session 7)

---

## Completed

- [x] Text highlighting / background color rects (`draw_rect`, `draw_text_highlighted`)
- [x] Ellipsis truncation (`draw_text_truncated`)
- [x] Underline / strikethrough (`draw_text_underlined`, `draw_text_strikethrough`)
- [x] Font fallback chains (`font_set_fallback`, `get_glyph_fallback`)
- [x] Per-character transform callback (`Glyph_Xform`, `draw_text_transformed`)
- [x] Inline icons in rich text flow (`{icon:N}` and `{icon:N:color}` markup tags)
- [x] Hit testing (`text_hit_test`)
- [x] Named styles / `Text_Style` struct (`draw_text_styled`, `measure_text_styled`)
- [x] Justified alignment (`draw_text_justified`)
- [x] Subscript / superscript (`draw_text_sub`, `draw_text_super`, `SUB_SCALE/SHIFT/SUPER_SHIFT` constants)
- [x] GPU scissor clipping (`Scissor_Rect`, optional `scissor` param on `flush` / `present_frame`; multi-pass per frame)
- [x] Camera pan (`camera_x/y` in `Context`, `set_camera(ctx, x, y)`; WASD + middle-mouse drag in demos, R to reset, scissor adjusted by cam offset)
- [x] Zoom toggle + mouse wheel zoom (Tab snaps 1.0x↔0.6x; wheel zooms when not over scroll region; clamped to [0.25, 3.0]x)
- [x] Grid rendering mode / CP437 (`draw_text_grid`; fixed-width cells, bbox-centered; `\n` row advance)
- [x] Message log widget (`Message_Log`, `log_push`, `draw_message_log`; fixed-size ring buffer, age-based fade, no dynamic allocation)

---

## Polish / Cleanup
*Fix these opportunistically — before or alongside features.*

### Documentation *(all done session 6)*
- [x] `draw_icon` — precondition comment added
- [x] `cache_text` — precondition comment added (`begin()` required)
- [x] `measure_text` — fallback chain caveat added
- [x] `font_set_fallback` — shared atlas cross-reference added

### API additions
- [x] `active_font_index(ctx) -> int` — added session 6

---

## Feature Roadmap

### Up Next
- [ ] **#22 — Camera/viewport bugs (Raylib + OpenGL demos)**
      Raylib-drawn shapes (panel bg, circle, box outlines, scroll region bg, scissor box)
      use raw screen coords and don't move with camera pan. Slug text does move because
      camera offset is applied in vertex emitters. Fix: offset all Raylib/GL shape draw
      calls by cam_x/cam_y so the entire canvas pans together.
      Also: scroll region mouse-hover check doesn't account for camera offset — scrolling
      inside a text box moves the viewport instead when panned. Fix: subtract cam offset
      from mouse coords before the scroll-region bounds check, or capture cursor context
      when hovering over interactive regions so scroll always wins inside bounds.
      Vulkan demo is correct (reference implementation). Port fixes to Raylib + OpenGL.

- [ ] **#21 — Viewport zoom (zoom toward cursor)**
      Currently `ui_scale` only scales font sizes — positions are fixed, so zoom doesn't
      follow the cursor. True viewport zoom needs a `zoom` factor in `Context` applied to
      both positions AND font sizes in the vertex emitters, plus a camera offset adjustment
      on each zoom step to keep the point under the cursor fixed in screen space.

- [ ] **#15 — Tooltip system**
      Positioned text box that follows the mouse and auto-flips at screen edges.

### Near-Term Backends
- [ ] **#16 — Sokol backend** (`slug_sokol`)
      Sokol GFX is a popular Odin/C cross-platform graphics layer. Good portability story.
      Needs `flush(scissor)` support via `sg_apply_scissor_rect`.

- [ ] **#17 — SDL3 GPU backend** (`slug_sdl3`)
      SDL3's new GPU API. Pairs naturally with the existing Vulkan demo's SDL3 windowing.
      Needs `flush(scissor)` support via `sdl.GPUSetScissor`.

- [ ] **#18 — Karl2D backend** (`slug_karl2d`)
      Karl Zylinski's pure-Odin 2D library (zero C deps). Primary target for the roguelike project.
      Integration notes in `docs/KARL2D_INTEGRATION.md`. Has OpenGL, D3D11, and Metal backends.
      Needs `flush(scissor)` support via the underlying GL/D3D11/Metal scissor APIs.

### Later / Stretch Goals
- [ ] **#1 — Instanced rendering**
      Replace one-quad-per-glyph with GPU instancing. Big perf win for dense text. Requires
      shader changes in all backends. Defer until the API is stable (post-v1.0).

---

## Known Limitations (by design, not bugs)

- `measure_text` / cursor procs take `^Font` and don't follow fallback chains. This is intentional —
  fallback-aware measurement would require `^Context`, changing the public API.
- `MAX_GLYPH_QUADS = 4096`, `MAX_RECTS = 512`, `MAX_FONT_SLOTS = 4` are compile-time constants
  baked into `Context`. No dynamic allocation. Exceeding the limits silently drops glyphs.
- Font fallback only works in shared atlas mode (`fonts_process_shared`). In per-font mode the
  fallback chain is registered but silently ignored to avoid cross-texture quad corruption.
- `draw_rect` / background rects are always drawn *before* glyphs regardless of call order — rects
  can never appear on top of text in the same frame.
- `ui_scale` only scales font sizes, not layout positions. For true viewport zoom (scale + pan
  toward cursor), see #21.
