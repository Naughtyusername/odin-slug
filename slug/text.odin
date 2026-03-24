package slug

import "core:math"
import "core:unicode/utf8"

// ===================================================
// Text drawing and measurement — CPU-side vertex packing.
//
// These procs write glyph quads into ctx.vertices[]. No GPU calls.
// The backend reads the vertex data and uploads/draws it.
// ===================================================

// Snap a coordinate to the nearest pixel boundary.
// Use this for grid-aligned UIs where you want pixel-perfect text:
//   slug.draw_text(ctx, "HP: 100", slug.coord_snap(x), slug.coord_snap(y), size, color)
// Slug renders Bezier curves per-pixel, so subpixel positioning works
// naturally without quality loss. Snapping is optional and purely for
// alignment with pixel-grid elements like tile maps or UI panels.
coord_snap :: proc(v: f32) -> f32 {
	return math.round(v)
}

// Advance width of a single character in pixels.
// This is how far the pen moves after drawing the character — use it
// for manual text layout and positioning. Returns 0 if the glyph isn't loaded.
// For kerning between character pairs, use font_get_kerning separately.
char_advance :: proc(font: ^Font, ch: rune, font_size: f32) -> f32 {
	g := get_glyph(font, ch)
	if g == nil do return 0
	return g.advance_width * font_size
}

// Vertical distance between text lines in pixels.
// Includes the font's line gap for proper inter-line spacing.
// Computed from the font's ascent, descent, and line gap metrics —
// consistent regardless of which characters are drawn.
line_height :: proc(font: ^Font, font_size: f32) -> f32 {
	return (font.ascent - font.descent + font.line_gap) * font_size
}

// Fixed cell width for monospace-style layouts in pixels.
// Returns the widest loaded glyph's advance width, which can be
// used as a uniform cell width for grid-aligned text (roguelike maps,
// stat columns, fixed-width UI). Works with any font — proportional
// fonts just get wider cells.
mono_width :: proc(font: ^Font, font_size: f32) -> f32 {
	max_advance: f32 = 0
	for _, &g in font.glyphs {
		if g.valid && g.advance_width > max_advance {
			max_advance = g.advance_width
		}
	}
	return max_advance * font_size
}

// Measure a string's pixel dimensions at the given font size.
// Uses the specified font only — does not follow fallback chains.
// Results will not account for glyphs resolved via font_set_fallback.
// For fallback-aware layout, measure each font segment separately.
// tracking adds extra horizontal space (in pixels) after each character.
measure_text :: proc(
	font: ^Font,
	text: string,
	font_size: f32,
	use_kerning: bool = true,
	tracking: f32 = 0,
) -> (
	width: f32,
	height: f32,
) {
	pen_x: f32 = 0
	prev_rune: rune = 0

	// Tab stop width: 4 space advances
	space_g := get_glyph(font, ' ')
	tab_width := (space_g.advance_width if space_g != nil else 0.5) * font_size * 4

	for ch in text {
		if ch == '\t' {
			pen_x = f32(int(pen_x / tab_width) + 1) * tab_width
			prev_rune = 0
			continue
		}
		g := get_glyph(font, ch)
		if g == nil {
			prev_rune = ch
			continue
		}
		if use_kerning && prev_rune != 0 {
			pen_x += font_get_kerning(font, prev_rune, ch) * font_size
		}
		pen_x += g.advance_width * font_size + tracking
		prev_rune = ch
	}
	return pen_x, (font.ascent - font.descent) * font_size
}

// Pixel x-offset of the cursor at the given character index.
// index 0 = before the first character (left edge of the string).
// index == rune_count = after the last character (right edge).
// Returns 0 for out-of-range indices. Use with draw_text's x parameter:
//   cursor_px := x + slug.cursor_x_from_index(font, text, size, cursor_idx)
cursor_x_from_index :: proc(
	font: ^Font,
	text: string,
	font_size: f32,
	index: int,
	use_kerning: bool = true,
) -> f32 {
	pen_x: f32 = 0
	prev_rune: rune = 0
	i := 0
	for ch in text {
		if i >= index do break
		g := get_glyph(font, ch)
		if g != nil {
			if use_kerning && prev_rune != 0 {
				pen_x += font_get_kerning(font, prev_rune, ch) * font_size
			}
			pen_x += g.advance_width * font_size
		}
		prev_rune = ch
		i += 1
	}
	return pen_x
}

// Character index closest to a pixel x-offset within rendered text.
// Returns the index (0-based rune position) where a cursor should be
// placed if the user clicks at target_x pixels from the string's left edge.
// Snaps to the nearest character boundary (halfway = next character).
index_from_x :: proc(
	font: ^Font,
	text: string,
	font_size: f32,
	target_x: f32,
	use_kerning: bool = true,
) -> int {
	if target_x <= 0 do return 0

	pen_x: f32 = 0
	prev_rune: rune = 0
	i := 0
	for ch in text {
		g := get_glyph(font, ch)
		if g == nil {
			prev_rune = ch
			i += 1
			continue
		}

		advance: f32 = 0
		if use_kerning && prev_rune != 0 {
			advance += font_get_kerning(font, prev_rune, ch) * font_size
		}
		advance += g.advance_width * font_size

		// If target is within the first half of this character, cursor goes before it
		if target_x < pen_x + advance * 0.5 {
			return i
		}

		pen_x += advance
		prev_rune = ch
		i += 1
	}
	return i // past the end
}

// Test whether a screen point falls within a rendered text string.
// Returns the nearest rune index and true when the point hits the text's
// bounding rect; returns 0, false otherwise.
//
// The bounding rect spans x to x+text_width horizontally, and
// y-ascent*font_size to y-descent*font_size vertically (the full line height).
// index follows the same convention as index_from_x: 0 = before the first
// character, len(runes) = after the last character.
//
// Typical use — click-to-position a cursor:
//   if idx, hit := slug.text_hit_test(font, text, x, y, size, mouse_x, mouse_y); hit {
//       cursor_idx = idx
//   }
text_hit_test :: proc(
	font: ^Font,
	text: string,
	x, y: f32,
	font_size: f32,
	mouse_x, mouse_y: f32,
	use_kerning: bool = true,
) -> (index: int, hit: bool) {
	top    := y - font.ascent  * font_size
	bottom := y - font.descent * font_size
	if mouse_y < top || mouse_y > bottom do return 0, false

	w, _ := measure_text(font, text, font_size, use_kerning)
	if mouse_x < x || mouse_x > x + w do return 0, false

	return index_from_x(font, text, font_size, mouse_x - x, use_kerning), true
}

// Draw a string of text at the given position and size.
// x, y is the baseline-left position. font_size is the em-square height in pixels.
// Tab characters (\t) snap the pen to the next tab stop (every 4 space widths).
// tracking adds extra horizontal space (in pixels) after each character.
draw_text :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	use_kerning: bool = true,
	tracking: f32 = 0,
) {
	font := active_font(ctx)
	pen_x := x

	// Tab stop width: 4 space advances
	space_g := get_glyph(font, ' ')
	tab_width := (space_g.advance_width if space_g != nil else 0.5) * font_size * 4

	prev_rune: rune = 0

	for ch in text {
		// Tab: snap pen to next tab stop
		if ch == '\t' {
			rel := pen_x - x
			pen_x = x + (f32(int(rel / tab_width) + 1) * tab_width)
			prev_rune = 0
			continue
		}

		g := get_glyph_fallback(ctx, ch)
		if g == nil {
			prev_rune = ch
			continue
		}

		if use_kerning && prev_rune != 0 {
			kern := font_get_kerning(font, prev_rune, ch)
			pen_x += kern * font_size
		}

		glyph_x := pen_x + g.bbox_min.x * font_size
		glyph_y := y - g.bbox_max.y * font_size

		glyph_w := (g.bbox_max.x - g.bbox_min.x) * font_size
		glyph_h := (g.bbox_max.y - g.bbox_min.y) * font_size

		if len(g.curves) > 0 && ctx.quad_count < MAX_GLYPH_QUADS {
			emit_glyph_quad(ctx, g, glyph_x, glyph_y, glyph_w, glyph_h, color)
		}

		pen_x += g.advance_width * font_size + tracking
		prev_rune = ch
	}
}

// Draw text horizontally centered at x.
// x is the center point, not the left edge.
draw_text_centered :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	w, _ := measure_text(font, text, font_size, use_kerning)
	draw_text(ctx, text, x - w * 0.5, y, font_size, color, use_kerning)
}

// Draw text right-aligned so the last character ends at x.
// x is the right edge, not the left edge.
draw_text_right :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	w, _ := measure_text(font, text, font_size, use_kerning)
	draw_text(ctx, text, x - w, y, font_size, color, use_kerning)
}

// Scale applied to the parent em-square for subscript and superscript text.
// Pass font_size * SUB_SCALE to measure_text to get the sub/super advance width.
SUB_SCALE :: f32(0.60)

// Baseline shift for subscript text, as a fraction of the parent font_size.
// draw_text_sub shifts the baseline DOWN by SUB_SHIFT * font_size.
SUB_SHIFT :: f32(0.35)

// Baseline shift for superscript text, as a fraction of the parent font_size.
// draw_text_super shifts the baseline UP by SUPER_SHIFT * font_size.
SUPER_SHIFT :: f32(0.40)

// Draw text as subscript: SUB_SCALE × font_size, shifted down by SUB_SHIFT × font_size.
// x, y is the parent baseline — the same y you pass to draw_text for the surrounding text.
// Use measure_text with font_size * SUB_SCALE to compute the advance and position
// whatever follows. Example — "H₂O":
//   hw, _ := slug.measure_text(font, "H", size)
//   slug.draw_text(ctx, "H", x, y, size, c)
//   slug.draw_text_sub(ctx, "2", x+hw, y, size, c)
//   x2w, _ := slug.measure_text(font, "2", size * slug.SUB_SCALE)
//   slug.draw_text(ctx, "O", x+hw+x2w, y, size, c)
draw_text_sub :: proc(ctx: ^Context, text: string, x, y, font_size: f32, color: Color) {
	draw_text(ctx, text, x, y + font_size * SUB_SHIFT, font_size * SUB_SCALE, color)
}

// Draw text as superscript: SUB_SCALE × font_size, shifted up by SUPER_SHIFT × font_size.
// x, y is the parent baseline. Use measure_text with font_size * SUB_SCALE for advance width.
// Example — "x²":
//   xw, _ := slug.measure_text(font, "x", size)
//   slug.draw_text(ctx, "x", x, y, size, c)
//   slug.draw_text_super(ctx, "2", x+xw, y, size, c)
draw_text_super :: proc(ctx: ^Context, text: string, x, y, font_size: f32, color: Color) {
	draw_text(ctx, text, x, y - font_size * SUPER_SHIFT, font_size * SUB_SCALE, color)
}

// Draw text clipped to max_width pixels, appending an ellipsis when truncated.
// The ellipsis width is reserved from the budget first, so the total rendered
// width always fits within max_width. If there is no room for any characters
// before the ellipsis, the ellipsis alone is drawn.
// ellipsis defaults to "..." but can be customized (e.g. "…", "- ", or "" for hard clip).
// Returns the pixel width actually drawn (useful for follow-on layout).
//
// Example:
//   // Clip a long item name to fit inside a UI panel column
//   slug.draw_text_truncated(ctx, item.name, x, y, size, column_width, color)
draw_text_truncated :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	max_width: f32,
	color: Color,
	use_kerning: bool = true,
	ellipsis: string = "...",
) -> f32 {
	font := active_font(ctx)

	// Fast path: text fits as-is
	full_w, _ := measure_text(font, text, font_size, use_kerning)
	if full_w <= max_width {
		draw_text(ctx, text, x, y, font_size, color, use_kerning)
		return full_w
	}

	ellipsis_w: f32 = 0
	if len(ellipsis) > 0 {
		ellipsis_w, _ = measure_text(font, ellipsis, font_size)
	}
	budget := max_width - ellipsis_w

	if budget <= 0 {
		// No room for any chars before the ellipsis
		if len(ellipsis) > 0 {
			draw_text(ctx, ellipsis, x, y, font_size, color)
		}
		return ellipsis_w
	}

	// Walk characters accumulating width until we exceed budget
	pen_x: f32 = 0
	prev_rune: rune = 0
	byte_end := 0

	for ch, i in text {
		g := get_glyph_fallback(ctx, ch)
		kern: f32 = 0
		if g != nil && use_kerning && prev_rune != 0 {
			kern = font_get_kerning(font, prev_rune, ch) * font_size
		}
		advance := kern + (g.advance_width * font_size if g != nil else 0)
		if pen_x + advance > budget do break
		pen_x += advance
		_, ch_size := utf8.decode_rune_in_string(text[i:])
		byte_end = i + ch_size
		prev_rune = ch
	}

	draw_text(ctx, text[:byte_end], x, y, font_size, color, use_kerning)
	draw_text(ctx, ellipsis, x + pen_x, y, font_size, color)
	return pen_x + ellipsis_w
}

// Draw truncated text that breaks at word boundaries instead of mid-character.
// Same as draw_text_truncated but backs up to the last space before the budget.
// If the first word alone exceeds the budget, falls back to character truncation
// to avoid showing an empty string with just an ellipsis.
//
// Example:
//   slug.draw_text_truncated_word(ctx, "The quick brown fox", x, y, size, 200, color)
//   // Might render: "The quick brown..." instead of "The quick bro..."
draw_text_truncated_word :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	max_width: f32,
	color: Color,
	use_kerning: bool = true,
	ellipsis: string = "...",
) -> f32 {
	font := active_font(ctx)

	// Fast path: text fits as-is
	full_w, _ := measure_text(font, text, font_size, use_kerning)
	if full_w <= max_width {
		draw_text(ctx, text, x, y, font_size, color, use_kerning)
		return full_w
	}

	ellipsis_w: f32 = 0
	if len(ellipsis) > 0 {
		ellipsis_w, _ = measure_text(font, ellipsis, font_size)
	}
	budget := max_width - ellipsis_w

	if budget <= 0 {
		if len(ellipsis) > 0 {
			draw_text(ctx, ellipsis, x, y, font_size, color)
		}
		return ellipsis_w
	}

	// Walk characters, tracking the last space boundary
	pen_x: f32 = 0
	prev_rune: rune = 0
	byte_end := 0
	last_space_byte := -1
	last_space_pen: f32 = 0

	for ch, i in text {
		g := get_glyph_fallback(ctx, ch)
		kern: f32 = 0
		if g != nil && use_kerning && prev_rune != 0 {
			kern = font_get_kerning(font, prev_rune, ch) * font_size
		}
		advance := kern + (g.advance_width * font_size if g != nil else 0)
		if pen_x + advance > budget do break
		pen_x += advance
		_, ch_size := utf8.decode_rune_in_string(text[i:])
		byte_end = i + ch_size
		if ch == ' ' {
			last_space_byte = i
			last_space_pen = pen_x
		}
		prev_rune = ch
	}

	// If we found a word boundary, use it; otherwise fall back to char truncation
	draw_end := byte_end
	draw_pen := pen_x
	if last_space_byte > 0 {
		draw_end = last_space_byte
		draw_pen = last_space_pen
		// Trim trailing spaces before the ellipsis
		for draw_end > 0 && text[draw_end - 1] == ' ' {
			draw_end -= 1
			// Re-measure trimmed text for accurate pen position
		}
		draw_pen, _ = measure_text(font, text[:draw_end], font_size, use_kerning)
	}

	draw_text(ctx, text[:draw_end], x, y, font_size, color, use_kerning)
	draw_text(ctx, ellipsis, x + draw_pen, y, font_size, color)
	return draw_pen + ellipsis_w
}

// Draw text with automatic word wrapping within max_width pixels.
// Breaks on spaces and newlines. Words wider than max_width are
// drawn on their own line without breaking mid-word.
// x, y is the top-left corner of the text block (not the baseline).
// Returns the total height used, so the caller can position
// content below: next_y = y + draw_text_wrapped(...).
draw_text_wrapped :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	max_width: f32,
	color: Color,
	use_kerning: bool = true,
	line_spacing: f32 = 1.0,
) -> f32 {
	font := active_font(ctx)
	lh := line_height(font, font_size) * line_spacing
	space_w := char_advance(font, ' ', font_size)

	// Height of a single text line (ascent - descent), without inter-line gap.
	// Used for the return value — the total bounding height of the text block.
	text_line_h := (font.ascent - font.descent) * font_size

	// Offset so y is the top of the text block, not the baseline.
	// draw_text expects y at the top of the glyph's em square, which
	// is ascent above the baseline.
	ascent_px := font.ascent * font_size

	pen_x: f32 = 0
	pen_y: f32 = ascent_px

	// Walk through the text, splitting on spaces and newlines
	i := 0
	for i < len(text) {
		// Handle newlines
		if text[i] == '\n' {
			pen_x = 0
			pen_y += lh
			i += 1
			continue
		}

		// Skip spaces at line start
		if text[i] == ' ' && pen_x == 0 {
			i += 1
			continue
		}

		// Find the next word (run of non-space, non-newline characters)
		word_start := i
		for i < len(text) && text[i] != ' ' && text[i] != '\n' {
			i += 1
		}
		word := text[word_start:i]

		word_w, _ := measure_text(font, word, font_size, use_kerning)

		// Wrap if this word would exceed max_width (unless it's the first word on the line)
		if pen_x > 0 && pen_x + space_w + word_w > max_width {
			pen_x = 0
			pen_y += lh
		}

		// Add space between words on the same line
		if pen_x > 0 {
			pen_x += space_w
		}

		// Draw the word
		draw_text(ctx, word, x + pen_x, y + pen_y, font_size, color, use_kerning)
		pen_x += word_w

		// Skip trailing space after word
		if i < len(text) && text[i] == ' ' {
			i += 1
		}
	}

	// Return total height from the top of the text block.
	// pen_y already includes the initial ascent offset, so subtract it
	// and add back the full text line height for the last line.
	return pen_y - ascent_px + text_line_h
}

// Measure wrapped text height without drawing.
// Returns (total_height, line_count). Use line_count for panel sizing, pagination,
// and deciding whether to show scroll indicators.
measure_text_wrapped :: proc(
	ctx: ^Context,
	text: string,
	font_size: f32,
	max_width: f32,
	use_kerning: bool = true,
	line_spacing: f32 = 1.0,
) -> (height: f32, lines: int) {
	font := active_font(ctx)
	lh := line_height(font, font_size) * line_spacing
	space_w := char_advance(font, ' ', font_size)
	text_line_h := (font.ascent - font.descent) * font_size

	pen_x: f32 = 0
	pen_y: f32 = 0
	line_count := 1

	i := 0
	for i < len(text) {
		if text[i] == '\n' {
			pen_x = 0
			pen_y += lh
			line_count += 1
			i += 1
			continue
		}
		if text[i] == ' ' && pen_x == 0 {
			i += 1
			continue
		}
		word_start := i
		for i < len(text) && text[i] != ' ' && text[i] != '\n' {
			i += 1
		}
		word := text[word_start:i]
		word_w, _ := measure_text(font, word, font_size, use_kerning)

		if pen_x > 0 && pen_x + space_w + word_w > max_width {
			pen_x = 0
			pen_y += lh
			line_count += 1
		}
		if pen_x > 0 {
			pen_x += space_w
		}
		pen_x += word_w
		if i < len(text) && text[i] == ' ' {
			i += 1
		}
	}

	return pen_y + text_line_h, line_count
}

// Draw an SVG icon centered at the given screen position.
// icon_index is the glyph slot (use 128+ to avoid ASCII collision).
//
// Preconditions:
//   - The active font must be set via use_font() before calling this.
//   - The icon must have been loaded into that font's slot via svg_load_into_font()
//     before font processing (font_process / fonts_process_shared).
draw_icon :: proc(ctx: ^Context, icon_index: int, x, y: f32, size: f32, color: Color) {
	font := active_font(ctx)
	g := get_glyph(font, rune(icon_index))
	if g == nil || len(g.curves) == 0 do return

	glyph_w := (g.bbox_max.x - g.bbox_min.x) * size
	glyph_h := (g.bbox_max.y - g.bbox_min.y) * size

	glyph_x := x - glyph_w * 0.5
	glyph_y := y - glyph_h * 0.5

	if ctx.quad_count < MAX_GLYPH_QUADS {
		emit_glyph_quad(ctx, g, glyph_x, glyph_y, glyph_w, glyph_h, color)
	}
}

// Draw a solid colored rectangle.
// x, y is the top-left corner in screen space. w, h are in pixels.
// The rect is added to ctx.rect_vertices[], which backends draw with a
// flat-color shader BEFORE the Slug text pass — so rects always appear
// behind any text drawn in the same frame.
//
// Typical use: call draw_rect before draw_text to highlight a region:
//   slug.draw_rect(ctx, x, y - ascent, w, line_h, slug.Color{0.2, 0.2, 0.8, 0.5})
//   slug.draw_text(ctx, "selected item", x, y, size, slug.WHITE)
draw_rect :: proc(ctx: ^Context, x, y, w, h: f32, color: Color) {
	if ctx.rect_count >= MAX_RECTS do return

	base := ctx.rect_count * VERTICES_PER_QUAD
	cx := x + ctx.camera_x
	cy := y + ctx.camera_y

	ctx.rect_vertices[base + 0] = Rect_Vertex{{cx,     cy    }, color}
	ctx.rect_vertices[base + 1] = Rect_Vertex{{cx + w, cy    }, color}
	ctx.rect_vertices[base + 2] = Rect_Vertex{{cx + w, cy + h}, color}
	ctx.rect_vertices[base + 3] = Rect_Vertex{{cx,     cy + h}, color}

	ctx.rect_count += 1
}

// Draw a rectangle outline (border only, no fill).
// Thickness is in pixels — the border is drawn inward from the specified bounds.
draw_rect_outline :: proc(ctx: ^Context, x, y, w, h: f32, color: Color, thickness: f32 = 1) {
	draw_rect(ctx, x, y, w, thickness, color)             // top
	draw_rect(ctx, x, y + h - thickness, w, thickness, color) // bottom
	draw_rect(ctx, x, y + thickness, thickness, h - thickness * 2, color) // left
	draw_rect(ctx, x + w - thickness, y + thickness, thickness, h - thickness * 2, color) // right
}

// Draw a filled rectangle with a border of a different color.
// Border is drawn inward from the specified bounds, fill occupies the interior.
draw_rect_bordered :: proc(ctx: ^Context, x, y, w, h: f32, fill_color, border_color: Color, border: f32 = 1) {
	draw_rect_outline(ctx, x, y, w, h, border_color, border)
	draw_rect(ctx, x + border, y + border, w - border * 2, h - border * 2, fill_color)
}

// Draw a horizontal progress bar with an optional centered text label.
// value/max_value determines fill ratio. Background is drawn at full width,
// filled portion at proportional width. Label (if non-empty) is centered on the bar.
draw_bar :: proc(
	ctx: ^Context,
	x, y, w, h: f32,
	value, max_value: f32,
	fill_color, bg_color: Color,
	label: string = "",
	label_size: f32 = 0,
	label_color: Color = WHITE,
	border_color: Color = TRANSPARENT,
	border: f32 = 0,
) {
	// Background
	draw_rect(ctx, x, y, w, h, bg_color)

	// Fill
	ratio := clamp(value / max_value, 0, 1) if max_value > 0 else 0
	fill_w := w * ratio
	if fill_w > 0 {
		draw_rect(ctx, x, y, fill_w, h, fill_color)
	}

	// Border (on top of bg+fill, still behind text)
	if border > 0 && border_color.a > 0 {
		draw_rect_outline(ctx, x, y, w, h, border_color, border)
	}

	// Centered label
	if len(label) > 0 {
		font := active_font(ctx)
		sz := label_size if label_size > 0 else h * 0.7
		tw, _ := measure_text(font, label, sz)
		lx := x + (w - tw) * 0.5
		ly := y + (h - (font.ascent - font.descent) * sz) * 0.5 + font.ascent * sz
		draw_text(ctx, label, lx, ly, sz, label_color)
	}
}

// Draw a blinking text cursor (vertical line) at the given position.
// time is the current elapsed time in seconds; blink_rate is full cycles per second.
// The cursor is drawn as a thin rect, so it appears behind text (same as all rects).
draw_cursor :: proc(
	ctx: ^Context,
	x, y: f32,
	font_size: f32,
	color: Color,
	time: f64 = 0,
	blink_rate: f32 = 1.5,
	width: f32 = 2,
) {
	// Blink: visible for first half of each cycle
	if blink_rate > 0 {
		cycle := f32(time) * blink_rate
		if cycle - f32(int(cycle)) > 0.5 do return
	}
	font := active_font(ctx)
	h := (font.ascent - font.descent) * font_size
	cursor_y := y - font.ascent * font_size
	draw_rect(ctx, x, cursor_y, width, h, color)
}

// Column alignment for draw_text_columns.
Column_Align :: enum {
	Left,
	Center,
	Right,
}

// Column specification for tabular text layout.
Column :: struct {
	text:  string,
	width: f32,
	align: Column_Align,
	color: Color,
}

// Draw a row of columns at the given position.
// Each column is drawn within its width, aligned per its spec.
// Columns are laid out left-to-right starting at x.
draw_text_columns :: proc(
	ctx: ^Context,
	columns: []Column,
	x, y: f32,
	font_size: f32,
	default_color: Color = WHITE,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	col_x := x
	for &col in columns {
		c := col.color if col.color.a > 0 else default_color
		switch col.align {
		case .Left:
			draw_text(ctx, col.text, col_x, y, font_size, c, use_kerning)
		case .Center:
			tw, _ := measure_text(font, col.text, font_size, use_kerning)
			draw_text(ctx, col.text, col_x + (col.width - tw) * 0.5, y, font_size, c, use_kerning)
		case .Right:
			tw, _ := measure_text(font, col.text, font_size, use_kerning)
			draw_text(ctx, col.text, col_x + col.width - tw, y, font_size, c, use_kerning)
		}
		col_x += col.width
	}
}

// Draw text justified to exactly fill column_width pixels.
// Inter-word spacing is expanded uniformly so the first word starts at x and
// the last word ends at x+column_width. If the text already meets or exceeds
// column_width, it is drawn left-aligned without modification (no compression).
// Single spaces in the source text mark word boundaries; multiple spaces are
// collapsed. A string with no spaces (one word) is drawn left-aligned.
//
// This completes the alignment family alongside draw_text_centered and
// draw_text_right. For multi-line justified text, see draw_text_wrapped.
//
// Example — fill a fixed-width UI column:
//   slug.draw_text_justified(ctx, line, x, y, size, column_w, color)
draw_text_justified :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	column_width: f32,
	color: Color,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	space_w := char_advance(font, ' ', font_size)

	// Collect words (split on spaces)
	Word :: struct { text: string, width: f32 }
	words: [dynamic]Word
	defer delete(words)

	i := 0
	for i < len(text) {
		// Skip spaces
		for i < len(text) && text[i] == ' ' { i += 1 }
		if i >= len(text) { break }

		// Find word end
		word_start := i
		for i < len(text) && text[i] != ' ' { i += 1 }
		word := text[word_start:i]
		w, _ := measure_text(font, word, font_size, use_kerning)
		append(&words, Word{word, w})
	}

	if len(words) == 0 { return }

	// Natural width: sum of word widths + spaces between them
	total_word_w: f32
	for word in words { total_word_w += word.width }
	natural_w := total_word_w + space_w * f32(len(words) - 1)

	// If text fills or overflows, draw left-aligned
	gaps := len(words) - 1
	if gaps <= 0 || natural_w >= column_width {
		pen_x := x
		for word in words {
			draw_text(ctx, word.text, pen_x, y, font_size, color, use_kerning)
			pen_x += word.width + space_w
		}
		return
	}

	// Distribute extra space across the gaps
	extra_per_gap := (column_width - natural_w) / f32(gaps)
	expanded_space := space_w + extra_per_gap

	pen_x := x
	for word, wi in words {
		draw_text(ctx, word.text, pen_x, y, font_size, color, use_kerning)
		pen_x += word.width
		if wi < gaps { pen_x += expanded_space }
	}
}

// Draw text with a solid background color behind it.
// x, y is the baseline-left position (same convention as draw_text).
// The background rect spans the full line height (ascent to descent) and
// the full text width. The rect is drawn before the text, so it always
// appears behind the glyphs.
//
// Example:
//   // Highlight a stat value in a roguelike HUD
//   slug.draw_text_highlighted(ctx, "POISONED", x, y, size, slug.BLACK, slug.Color{0.2, 0.8, 0.2, 1})
draw_text_highlighted :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	text_color: Color,
	bg_color: Color,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	w, h := measure_text(font, text, font_size, use_kerning)
	rect_y := y - font.ascent * font_size
	draw_rect(ctx, x, rect_y, w, h, bg_color)
	draw_text(ctx, text, x, y, font_size, text_color, use_kerning)
}

// Draw text with a highlight rectangle behind a sub-range of characters.
// sel_start and sel_end are 0-based rune indices — the highlight covers
// characters [sel_start, sel_end). If the range is empty or invalid, draws
// plain text with no highlight.
//
// Uses cursor_x_from_index to compute pixel offsets, so kerning is respected.
// The highlight rect spans the full line height (ascent to descent).
//
// Example — highlight characters 5..10 in a string:
//   slug.draw_text_selection(ctx, "Hello World!", x, y, size, slug.WHITE, 5, 10, slug.Color{0.2, 0.2, 0.8, 0.5})
draw_text_selection :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	text_color: Color,
	sel_start, sel_end: int,
	sel_color: Color,
	use_kerning: bool = true,
) {
	if sel_start < sel_end {
		font := active_font(ctx)
		x0 := cursor_x_from_index(font, text, font_size, sel_start, use_kerning)
		x1 := cursor_x_from_index(font, text, font_size, sel_end, use_kerning)
		h := (font.ascent - font.descent) * font_size
		rect_y := y - font.ascent * font_size
		draw_rect(ctx, x + x0, rect_y, x1 - x0, h, sel_color)
	}
	draw_text(ctx, text, x, y, font_size, text_color, use_kerning)
}

// Draw text with an underline at the standard typographic position.
// The underline sits ~10% of the em-square below the baseline, with a
// thickness of ~5% of the em-square (minimum 1px, snapped to nearest pixel
// for crispness). The decoration color matches the text color.
//
// Example:
//   slug.draw_text_underlined(ctx, "Visit our wiki", x, y, size, slug.CYAN)
draw_text_underlined :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	use_kerning: bool = true,
	line_color: Color = TRANSPARENT,
) {
	font := active_font(ctx)
	w, _      := measure_text(font, text, font_size, use_kerning)
	thickness := max(math.round(font_size * 0.05), 1.0)
	line_y    := y + font_size * 0.1
	lc := line_color if line_color.a > 0 else color
	draw_rect(ctx, x, line_y, w, thickness, lc)
	draw_text(ctx, text, x, y, font_size, color, use_kerning)
}

// Draw text with a horizontal strikethrough at mid-height.
// The line sits ~30% of the em-square above the baseline (roughly the
// x-height midpoint), with the same thickness as draw_text_underlined.
//
// Example:
//   slug.draw_text_strikethrough(ctx, "Old price: 500g", x, y, size, slug.RED)
draw_text_strikethrough :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	use_kerning: bool = true,
	line_color: Color = TRANSPARENT,
) {
	font := active_font(ctx)
	w, _      := measure_text(font, text, font_size, use_kerning)
	thickness := max(math.round(font_size * 0.05), 1.0)
	line_y    := y - font_size * 0.3
	lc := line_color if line_color.a > 0 else color
	draw_rect(ctx, x, line_y, w, thickness, lc)
	draw_text(ctx, text, x, y, font_size, color, use_kerning)
}

// Draw text using a Text_Style bundle.
// Switches to style.font_slot for the duration of the call, then restores the
// previous active font. Underline and strikethrough are drawn in a single pass
// so both can be active simultaneously.
// Returns the pixel width drawn, for follow-on layout.
draw_text_styled :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	style: Text_Style,
	use_kerning: bool = true,
) -> f32 {
	prev_slot := ctx.active_font_idx
	if style.font_slot != prev_slot {
		use_font(ctx, style.font_slot)
	}

	font := active_font(ctx)
	w, _ := measure_text(font, text, style.size, use_kerning)
	thickness := max(math.round(style.size * 0.05), 1.0)

	if style.underline {
		uc := style.underline_color if style.underline_color.a > 0 else style.color
		draw_rect(ctx, x, y + style.size * 0.1, w, thickness, uc)
	}
	if style.strikethrough {
		sc := style.strikethrough_color if style.strikethrough_color.a > 0 else style.color
		draw_rect(ctx, x, y - style.size * 0.3, w, thickness, sc)
	}
	draw_text(ctx, text, x, y, style.size, style.color, use_kerning)

	if style.font_slot != prev_slot {
		use_font(ctx, prev_slot)
	}
	return w
}

// Measure a string as it would be drawn by draw_text_styled.
// Accesses the font for style.font_slot directly without switching the active
// font, so it can be called freely during a frame without affecting draw batches.
measure_text_styled :: proc(
	ctx: ^Context,
	text: string,
	style: Text_Style,
	use_kerning: bool = true,
) -> (width, height: f32) {
	if style.font_slot < 0 || style.font_slot >= MAX_FONT_SLOTS do return 0, 0
	font := &ctx.fonts[style.font_slot]
	return measure_text(font, text, style.size, use_kerning)
}

// Draw text with a per-glyph transform callback.
// xform_proc is called once per glyph and returns a Glyph_Xform that modifies
// offset, scale, rotation, and color independently per character. Pass any
// animation state (time, counters, etc.) through userdata.
//
// The identity transform (return {}) renders identically to draw_text.
// Rotation and scale are applied around the glyph's visual center (bbox midpoint),
// not the advance-slot center, so the layout stays correct at any scale.
//
// Example — a simple wave effect:
//   Wave :: struct { time: f32 }
//   my_wave :: proc(i: int, ch: rune, px, y: f32, ud: rawptr) -> slug.Glyph_Xform {
//       w := (^Wave)(ud)
//       return slug.Glyph_Xform{ offset = {0, -math.sin(w.time * 4 + f32(i) * 0.6) * 8} }
//   }
//   wave := Wave{elapsed}
//   slug.draw_text_transformed(ctx, "Hello!", x, y, size, color, my_wave, &wave)
draw_text_transformed :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	color: Color,
	xform_proc: Glyph_Xform_Proc,
	userdata: rawptr = nil,
	use_kerning: bool = true,
) {
	font := active_font(ctx)
	pen_x := x
	prev_rune: rune = 0
	char_idx := 0

	for ch in text {
		g := get_glyph_fallback(ctx, ch)
		if g == nil {
			prev_rune = ch
			char_idx += 1
			continue
		}

		if use_kerning && prev_rune != 0 {
			pen_x += font_get_kerning(font, prev_rune, ch) * font_size
		}

		xform := xform_proc(char_idx, ch, pen_x, y, userdata)

		// Resolve identity defaults: scale=0 → 1.0, color.a=0 → parent color
		effective_scale := xform.scale if xform.scale != 0 else 1.0
		effective_color := xform.color if xform.color.a > 0 else color
		scaled_size := font_size * effective_scale

		// Glyph visual center in screen space (at base font_size, before scaling).
		// Scale and rotation are applied around this point so glyphs grow/rotate
		// in place rather than drifting away from the baseline.
		em_cx := (g.bbox_min.x + g.bbox_max.x) * 0.5
		em_cy := (g.bbox_min.y + g.bbox_max.y) * 0.5

		if xform.angle != 0 {
			// Rotated path: use the transformed quad emitter.
			cos_a := math.cos(xform.angle)
			sin_a := math.sin(xform.angle)
			xf := matrix[2, 2]f32{
				cos_a * scaled_size, -sin_a * scaled_size,
				sin_a * scaled_size,  cos_a * scaled_size,
			}
			center_x := pen_x + em_cx * font_size + xform.offset.x
			center_y := y - em_cy * font_size + xform.offset.y
			if len(g.curves) > 0 && ctx.quad_count < MAX_GLYPH_QUADS {
				emit_glyph_quad_transformed(ctx, g, center_x, center_y, xf, effective_color)
			}
		} else {
			// Axis-aligned path: scale around visual center, apply offset.
			// At effective_scale=1 and offset={0,0} this is identical to draw_text.
			glyph_w := (g.bbox_max.x - g.bbox_min.x) * scaled_size
			glyph_h := (g.bbox_max.y - g.bbox_min.y) * scaled_size
			glyph_x := pen_x + em_cx * font_size - glyph_w * 0.5 + xform.offset.x
			glyph_y := y - em_cy * font_size - glyph_h * 0.5 + xform.offset.y
			if len(g.curves) > 0 && ctx.quad_count < MAX_GLYPH_QUADS {
				emit_glyph_quad(ctx, g, glyph_x, glyph_y, glyph_w, glyph_h, effective_color)
			}
		}

		pen_x += g.advance_width * font_size
		prev_rune = ch
		char_idx += 1
	}
}

// Helper: return the background rect dimensions for a text string.
// Use this when you need to position the rect yourself (e.g. with padding):
//   rx, ry, rw, rh := slug.text_bg_rect(font, text, x, y, size)
//   slug.draw_rect(ctx, rx - pad, ry - pad, rw + pad*2, rh + pad*2, bg_color)
//   slug.draw_text(ctx, text, x, y, size, fg_color)
text_bg_rect :: proc(
	font: ^Font,
	text: string,
	x, y: f32,
	font_size: f32,
	use_kerning: bool = true,
) -> (
	rect_x, rect_y, rect_w, rect_h: f32,
) {
	w, h := measure_text(font, text, font_size, use_kerning)
	return x, y - font.ascent * font_size, w, h
}

// Draw text in a fixed-width grid. Each character's visual bounding box is
// centered in a cell of cell_w × cell_h pixels, regardless of its natural
// advance width — giving uniform tile spacing for any font.
//
// Newlines ('\n') advance to the next row; all other runes consume one cell.
// No kerning is applied (grid layout ignores character pairs).
//
// Typical cell sizing using the active font's natural metrics:
//   cell_w := slug.mono_width(font, font_size)  // widest glyph advance
//   cell_h := slug.line_height(font, font_size) // ascent + descent + gap
//
// Typical uses: roguelike map tiles, stat columns, terminal-style output.
draw_text_grid :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	cell_w, cell_h: f32,
	color: Color,
) {
	col: int = 0
	row: int = 0

	for ch in text {
		if ch == '\n' {
			row += 1
			col = 0
			continue
		}

		g := get_glyph_fallback(ctx, ch)
		if g == nil {
			col += 1
			continue
		}

		// Center the glyph's visual bbox within the cell.
		cell_cx := x + f32(col) * cell_w + cell_w * 0.5
		cell_cy := y + f32(row) * cell_h + cell_h * 0.5
		glyph_w := (g.bbox_max.x - g.bbox_min.x) * font_size
		glyph_h := (g.bbox_max.y - g.bbox_min.y) * font_size
		glyph_x := cell_cx - glyph_w * 0.5
		glyph_y := cell_cy - glyph_h * 0.5

		if len(g.curves) > 0 && ctx.quad_count < MAX_GLYPH_QUADS {
			emit_glyph_quad(ctx, g, glyph_x, glyph_y, glyph_w, glyph_h, color)
		}

		col += 1
	}
}

// --- Vertex packing ---

// Emit a single glyph quad into the vertex buffer (axis-aligned).
@(private = "package")
emit_glyph_quad :: proc(ctx: ^Context, g: ^Glyph_Data, x, y, w, h: f32, color: Color) {
	base := ctx.quad_count * VERTICES_PER_QUAD
	if base + VERTICES_PER_QUAD > MAX_GLYPH_VERTICES do return

	em_min := g.bbox_min
	em_max := g.bbox_max

	glyph_loc := transmute(f32)(u32(g.band_tex_x) | (u32(g.band_tex_y) << 16))
	band_max := transmute(f32)(u32(g.band_max_x) | (u32(g.band_max_y) << 16))

	em_w := em_max.x - em_min.x
	em_h := em_max.y - em_min.y
	jac_00 := em_w / w if w > 0 else 0
	jac_11 := -(em_h / h) if h > 0 else 0

	corners := [4][2]f32 {
		{x + ctx.camera_x,     y + ctx.camera_y},     // TL
		{x + w + ctx.camera_x, y + ctx.camera_y},     // TR
		{x + w + ctx.camera_x, y + h + ctx.camera_y}, // BR
		{x + ctx.camera_x,     y + h + ctx.camera_y}, // BL
	}

	normals := [4][2]f32 {
		{-DILATION_SCALE, -DILATION_SCALE},
		{DILATION_SCALE, -DILATION_SCALE},
		{DILATION_SCALE, DILATION_SCALE},
		{-DILATION_SCALE, DILATION_SCALE},
	}

	em_coords := [4][2]f32 {
		{em_min.x, em_max.y}, // TL in em-space (Y-up)
		{em_max.x, em_max.y}, // TR
		{em_max.x, em_min.y}, // BR
		{em_min.x, em_min.y}, // BL
	}

	for vi in 0 ..< 4 {
		ctx.vertices[base + u32(vi)] = Vertex {
			pos = {corners[vi].x, corners[vi].y, normals[vi].x, normals[vi].y},
			tex = {em_coords[vi].x, em_coords[vi].y, glyph_loc, band_max},
			jac = {jac_00, 0, 0, jac_11},
			bnd = {g.band_scale.x, g.band_scale.y, g.band_offset.x, g.band_offset.y},
			col = color,
		}
	}

	ctx.quad_count += 1
}

// Emit a glyph quad with an arbitrary 2x2 transform (rotation + scale).
// center_x, center_y is the glyph center in screen space.
@(private = "package")
emit_glyph_quad_transformed :: proc(
	ctx: ^Context,
	g: ^Glyph_Data,
	center_x, center_y: f32,
	xform: matrix[2, 2]f32,
	color: Color,
) {
	base := ctx.quad_count * VERTICES_PER_QUAD
	if base + VERTICES_PER_QUAD > MAX_GLYPH_VERTICES do return

	em_min := g.bbox_min
	em_max := g.bbox_max
	em_cx := (em_min.x + em_max.x) * 0.5
	em_cy := (em_min.y + em_max.y) * 0.5

	glyph_loc := transmute(f32)(u32(g.band_tex_x) | (u32(g.band_tex_y) << 16))
	band_max := transmute(f32)(u32(g.band_max_x) | (u32(g.band_max_y) << 16))

	em_offsets := [4][2]f32 {
		{em_min.x - em_cx, em_max.y - em_cy},
		{em_max.x - em_cx, em_max.y - em_cy},
		{em_max.x - em_cx, em_min.y - em_cy},
		{em_min.x - em_cx, em_min.y - em_cy},
	}

	em_coords := [4][2]f32 {
		{em_min.x, em_max.y},
		{em_max.x, em_max.y},
		{em_max.x, em_min.y},
		{em_min.x, em_min.y},
	}

	det := xform[0, 0] * xform[1, 1] - xform[0, 1] * xform[1, 0]
	inv_det := 1.0 / det if abs(det) > 1e-10 else 0.0
	inv_jac := matrix[2, 2]f32{
		xform[1, 1] * inv_det, -xform[0, 1] * inv_det, 
		xform[1, 0] * inv_det, -xform[0, 0] * inv_det, 
	}

	for vi in 0 ..< 4 {
		off := em_offsets[vi]
		screen_off := [2]f32 {
			xform[0, 0] * off.x + xform[0, 1] * (-off.y),
			xform[1, 0] * off.x + xform[1, 1] * (-off.y),
		}

		nx := screen_off.x
		ny := screen_off.y
		len_n := math.sqrt(nx * nx + ny * ny)
		if len_n > 0 {
			nx = nx / len_n * DILATION_SCALE
			ny = ny / len_n * DILATION_SCALE
		}

		// Inverse Jacobian stored in row-major order matching the fragment shader's
		// expected layout. Encodes the screen-to-em-space transform so the shader
		// can compute correct antialiasing distances under rotation/skew.
		ctx.vertices[base + u32(vi)] = Vertex {
			pos = {center_x + ctx.camera_x + screen_off.x, center_y + ctx.camera_y + screen_off.y, nx, ny},
			tex = {em_coords[vi].x, em_coords[vi].y, glyph_loc, band_max},
			jac = {inv_jac[0, 0], inv_jac[0, 1], inv_jac[1, 0], inv_jac[1, 1]},
			bnd = {g.band_scale.x, g.band_scale.y, g.band_offset.x, g.band_offset.y},
			col = color,
		}
	}

	ctx.quad_count += 1
}
