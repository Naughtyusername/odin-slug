package slug

// ===================================================
// Rich text — inline color, background, and icon markup.
//
// Foreground color:   {color_name:text} or {#rrggbb:text}
// Background color:   {bg:color_name:text} or {bg:#rrggbb:text}
// Inline icon:        {icon:N}  or  {icon:N:color}  or  {icon:N:#rrggbb}
// Untagged text uses the default color passed to draw_rich_text.
//
// Supported named colors: red, green, blue, yellow, cyan, magenta,
// orange, white, black, gray, light_gray, dark_gray.
//
// Icons are drawn at font_size, vertically centered on the text line,
// and advance the pen by the icon's bbox width plus a small gap.
// The icon glyph must be loaded into the active font (or its fallback chain)
// via svg_load_into_font before drawing. Conventional slots: 128 and above.
//
// Examples:
//   "You deal {red:15} damage!"
//   "Found a {yellow:Golden Sword} in the chest."
//   "{#ff8800:Warning:} low health!"
//   "Status: {bg:red:POISONED}"
//   "{bg:#003300:{green:STEALTH}}"          -- bg + fg on same text (bg tag wraps fg tag — not nesting)
//   "You found a {icon:128} Sword!"         -- inline icon in default color
//   "You found a {icon:128:yellow} Sword!"  -- inline icon tinted yellow
//   "HP {icon:129:#ff4444} 42"              -- inline icon tinted via hex
//   "Plain text with no markup works too."
//
// Nesting is NOT supported. Braces inside tagged text are literal.
// To draw a literal '{', use '{{'.
// ===================================================

// A parsed segment of rich text — either plain or colored.
@(private = "file")
Rich_Segment :: struct {
	text:  string, // Slice into original string (no allocation)
	color: Color,
}

// Draw rich text with inline color and background markup at the given position.
// Parses markup on the fly and draws each segment with its colors.
// Returns the total width drawn (for positioning content after it).
draw_rich_text :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	default_color: Color,
	use_kerning: bool = true,
) -> f32 {
	font := active_font(ctx)
	pen_x := x

	i := 0
	for i < len(text) {
		// Look for start of markup
		if text[i] == '{' {
			// Escaped brace: {{ => literal {
			if i + 1 < len(text) && text[i + 1] == '{' {
				draw_text(ctx, "{", pen_x, y, font_size, default_color, use_kerning)
				w, _ := measure_text(font, "{", font_size, use_kerning)
				pen_x += w
				i += 2
				continue
			}

			// Try to parse {icon:N} or {icon:N:color} — inline SVG icon at glyph slot N
			icon_slot, icon_color, icon_color_set, icon_end, icon_ok := parse_icon_tag(text, i)
			if icon_ok {
				g := get_glyph_fallback(ctx, rune(icon_slot))
				if g != nil && len(g.curves) > 0 {
					icon_w := (g.bbox_max.x - g.bbox_min.x) * font_size
					icon_h := (g.bbox_max.y - g.bbox_min.y) * font_size
					// Center icon vertically on the text line
					line_mid_y := y - (font.ascent + font.descent) * font_size * 0.5
					glyph_x := pen_x
					glyph_y := line_mid_y - icon_h * 0.5
					draw_color := icon_color if icon_color_set else default_color
					if ctx.quad_count < MAX_GLYPH_QUADS {
						emit_glyph_quad(ctx, g, glyph_x, glyph_y, icon_w, icon_h, draw_color)
					}
					pen_x += icon_w + font_size * 0.1 // small gap after icon
				}
				i = icon_end
				continue
			}

			// Try to parse {bg:color:text} first
			bg_color, seg_text, end_pos, bg_ok := parse_bg_tag(text, i)
			if bg_ok {
				w, h := measure_text(font, seg_text, font_size, use_kerning)
				rect_y := y - font.ascent * font_size
				draw_rect(ctx, pen_x, rect_y, w, h, bg_color)
				draw_text(ctx, seg_text, pen_x, y, font_size, default_color, use_kerning)
				pen_x += w
				i = end_pos
				continue
			}

			// Try to parse {color:text}
			seg_color, seg_text2, end_pos2, fg_ok := parse_rich_tag(text, i)
			if fg_ok {
				draw_text(ctx, seg_text2, pen_x, y, font_size, seg_color, use_kerning)
				w, _ := measure_text(font, seg_text2, font_size, use_kerning)
				pen_x += w
				i = end_pos2
				continue
			}
		}

		// Plain text: consume until next '{' or end
		plain_start := i
		for i < len(text) && text[i] != '{' {
			i += 1
		}
		plain := text[plain_start:i]
		if len(plain) > 0 {
			draw_text(ctx, plain, pen_x, y, font_size, default_color, use_kerning)
			w, _ := measure_text(font, plain, font_size, use_kerning)
			pen_x += w
		}
	}

	return pen_x - x
}

// Measure rich text width without drawing.
// Parses the same markup as draw_rich_text but only accumulates advance widths.
measure_rich_text :: proc(
	font: ^Font,
	text: string,
	font_size: f32,
	use_kerning: bool = true,
) -> (
	width: f32,
	height: f32,
) {
	pen_x: f32 = 0

	i := 0
	for i < len(text) {
		if text[i] == '{' {
			if i + 1 < len(text) && text[i + 1] == '{' {
				w, _ := measure_text(font, "{", font_size, use_kerning)
				pen_x += w
				i += 2
				continue
			}

			icon_slot, _, _, icon_end, icon_ok := parse_icon_tag(text, i)
			if icon_ok {
				g := get_glyph(font, rune(icon_slot))
				if g != nil {
					pen_x += (g.bbox_max.x - g.bbox_min.x) * font_size + font_size * 0.1
				}
				i = icon_end
				continue
			}

			_, seg_text, end_pos, ok := parse_rich_tag(text, i)
			if ok {
				w, _ := measure_text(font, seg_text, font_size, use_kerning)
				pen_x += w
				i = end_pos
				continue
			}
		}

		plain_start := i
		for i < len(text) && text[i] != '{' {
			i += 1
		}
		plain := text[plain_start:i]
		if len(plain) > 0 {
			w, _ := measure_text(font, plain, font_size, use_kerning)
			pen_x += w
		}
	}

	return pen_x, (font.ascent - font.descent) * font_size
}

// Draw rich text centered at x.
draw_rich_text_centered :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	default_color: Color,
	use_kerning: bool = true,
) -> f32 {
	font := active_font(ctx)
	w, _ := measure_rich_text(font, text, font_size, use_kerning)
	return draw_rich_text(ctx, text, x - w * 0.5, y, font_size, default_color, use_kerning)
}

// Draw rich text with word wrapping at max_width.
// Returns (total_height, line_count) — same as draw_text_wrapped.
// Supports all rich text markup: {color:text}, {bg:color:text}, {icon:N:color}, {{.
draw_rich_text_wrapped :: proc(
	ctx: ^Context,
	text: string,
	x, y: f32,
	font_size: f32,
	max_width: f32,
	default_color: Color,
	use_kerning: bool = true,
	line_spacing: f32 = 1.0,
) -> (height: f32, lines: int) {
	font := active_font(ctx)
	lh := line_height(font, font_size) * line_spacing
	space_w := char_advance(font, ' ', font_size)
	text_line_h := (font.ascent - font.descent) * font_size
	ascent_px := font.ascent * font_size

	pen_x: f32 = 0
	pen_y: f32 = ascent_px
	line_count := 1

	i := 0
	for i < len(text) {
		// Newline
		if text[i] == '\n' {
			pen_x = 0
			pen_y += lh
			line_count += 1
			i += 1
			continue
		}

		// Skip spaces at line start
		if text[i] == ' ' && pen_x == 0 {
			i += 1
			continue
		}

		// Skip space — spacing is reconstructed at draw time via space_w
		if text[i] == ' ' {
			i += 1
			continue
		}

		// Markup or plain text — consume one "visual token"
		// A token is either a markup tag or a run of plain text up to space/newline/markup
		token_start := i
		token_color := default_color
		token_bg: Color = {}
		token_has_bg := false
		token_text := ""
		token_is_icon := false
		icon_slot := 0
		icon_color := default_color
		icon_color_set := false

		if text[i] == '{' {
			// Escaped brace
			if i + 1 < len(text) && text[i + 1] == '{' {
				token_text = "{"
				i += 2
			} else {
				// Try icon tag
				s, ic, ics, ie, iok := parse_icon_tag(text, i)
				if iok {
					token_is_icon = true
					icon_slot = s
					icon_color = ic
					icon_color_set = ics
					i = ie
				} else {
					// Try bg tag
					bgc, bgt, bge, bgok := parse_bg_tag(text, i)
					if bgok {
						token_text = bgt
						token_bg = bgc
						token_has_bg = true
						i = bge
					} else {
						// Try color tag
						fc, ft, fe, fok := parse_rich_tag(text, i)
						if fok {
							token_text = ft
							token_color = fc
							i = fe
						} else {
							// Not a valid tag — treat '{' as plain text
							token_text = "{"
							i += 1
						}
					}
				}
			}
		} else {
			// Plain text up to next space, newline, or markup
			for i < len(text) && text[i] != ' ' && text[i] != '\n' && text[i] != '{' {
				i += 1
			}
			token_text = text[token_start:i]
		}

		if token_is_icon {
			g := get_glyph_fallback(ctx, rune(icon_slot))
			if g != nil && len(g.curves) > 0 {
				icon_w := (g.bbox_max.x - g.bbox_min.x) * font_size
				icon_h := (g.bbox_max.y - g.bbox_min.y) * font_size

				// Wrap if needed
				if pen_x > 0 && pen_x + icon_w > max_width {
					pen_x = 0
					pen_y += lh
					line_count += 1
				}
				if pen_x > 0 {
					pen_x += space_w
				}

				line_mid_y := (y + pen_y) - (font.ascent + font.descent) * font_size * 0.5
				glyph_y := line_mid_y - icon_h * 0.5
				draw_color := icon_color if icon_color_set else default_color
				if ctx.quad_count < MAX_GLYPH_QUADS {
					emit_glyph_quad(ctx, g, x + pen_x, glyph_y, icon_w, icon_h, draw_color)
				}
				pen_x += icon_w + font_size * 0.1
			}
			continue
		}

		if len(token_text) == 0 do continue

		// The token may contain spaces within a tag (e.g. {red:hello world}).
		// Split into words and wrap each.
		ti := 0
		for ti < len(token_text) {
			// Skip spaces at word start within token
			if token_text[ti] == ' ' {
				ti += 1
				continue
			}
			// Find word boundary
			ws := ti
			for ti < len(token_text) && token_text[ti] != ' ' {
				ti += 1
			}
			word := token_text[ws:ti]
			word_w, _ := measure_text(font, word, font_size, use_kerning)

			// Wrap
			if pen_x > 0 && pen_x + space_w + word_w > max_width {
				pen_x = 0
				pen_y += lh
				line_count += 1
			}
			if pen_x > 0 {
				pen_x += space_w
			}

			// Draw bg rect if needed
			if token_has_bg {
				_, wh := measure_text(font, word, font_size, use_kerning)
				rect_y := (y + pen_y) - font.ascent * font_size
				draw_rect(ctx, x + pen_x, rect_y, word_w, wh, token_bg)
			}

			draw_text(ctx, word, x + pen_x, y + pen_y, font_size, token_color, use_kerning)
			pen_x += word_w

			// Skip spaces after word
			if ti < len(token_text) && token_text[ti] == ' ' {
				ti += 1
			}
		}
	}

	return pen_y - ascent_px + text_line_h, line_count
}

// Measure rich text wrapped height without drawing.
// Returns (total_height, line_count).
measure_rich_text_wrapped :: proc(
	ctx: ^Context,
	text: string,
	font_size: f32,
	max_width: f32,
	default_color: Color = {},
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
		if text[i] == ' ' {
			i += 1
			continue
		}

		// Consume token (same logic as draw, but only measure)
		token_start := i
		token_text := ""
		token_is_icon := false
		icon_slot := 0

		if text[i] == '{' {
			if i + 1 < len(text) && text[i + 1] == '{' {
				token_text = "{"
				i += 2
			} else {
				s, _, _, ie, iok := parse_icon_tag(text, i)
				if iok {
					token_is_icon = true
					icon_slot = s
					i = ie
				} else {
					_, bgt, bge, bgok := parse_bg_tag(text, i)
					if bgok {
						token_text = bgt
						i = bge
					} else {
						_, ft, fe, fok := parse_rich_tag(text, i)
						if fok {
							token_text = ft
							i = fe
						} else {
							token_text = "{"
							i += 1
						}
					}
				}
			}
		} else {
			for i < len(text) && text[i] != ' ' && text[i] != '\n' && text[i] != '{' {
				i += 1
			}
			token_text = text[token_start:i]
		}

		if token_is_icon {
			g := get_glyph(font, rune(icon_slot))
			if g != nil {
				icon_w := (g.bbox_max.x - g.bbox_min.x) * font_size
				if pen_x > 0 && pen_x + icon_w > max_width {
					pen_x = 0
					pen_y += lh
					line_count += 1
				}
				if pen_x > 0 {
					pen_x += space_w
				}
				pen_x += icon_w + font_size * 0.1
			}
			continue
		}

		if len(token_text) == 0 do continue

		ti := 0
		for ti < len(token_text) {
			if token_text[ti] == ' ' {
				ti += 1
				continue
			}
			ws := ti
			for ti < len(token_text) && token_text[ti] != ' ' {
				ti += 1
			}
			word := token_text[ws:ti]
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

			if ti < len(token_text) && token_text[ti] == ' ' {
				ti += 1
			}
		}
	}

	return pen_y + text_line_h, line_count
}

// Strip all rich text markup, returning plain text length in bytes.
// Useful for cursor positioning: convert rich text positions to plain positions.
rich_text_plain_length :: proc(text: string) -> int {
	count := 0
	i := 0
	for i < len(text) {
		if text[i] == '{' {
			if i + 1 < len(text) && text[i + 1] == '{' {
				count += 1 // escaped brace = 1 char
				i += 2
				continue
			}
			_, _, _, icon_end, icon_ok := parse_icon_tag(text, i)
			if icon_ok {
				count += 1 // icon counts as one character in plain-text terms
				i = icon_end
				continue
			}
			_, seg_text, end_pos, ok := parse_rich_tag(text, i)
			if ok {
				count += len(seg_text)
				i = end_pos
				continue
			}
		}
		count += 1
		i += 1
	}
	return count
}

// --- Internal parsing ---

// Parse a {bg:color:text} background tag starting at `start`.
// Returns the background color, the inner text, position after '}', and success.
// The inner text is drawn with the caller's default foreground color —
// nest a {color:...} tag inside if you also want a custom foreground.
@(private = "package")
parse_bg_tag :: proc(text: string, start: int) -> (bg_color: Color, inner: string, end_pos: int, ok: bool) {
	if start >= len(text) || text[start] != '{' do return {}, "", start, false

	// Must start with "{bg:"
	prefix :: "{bg:"
	if start + len(prefix) > len(text) do return {}, "", start, false
	if text[start:start + len(prefix)] != prefix do return {}, "", start, false

	// Find the second colon (separating color from text)
	colon2 := -1
	for j := start + len(prefix); j < len(text); j += 1 {
		if text[j] == ':' {
			colon2 = j
			break
		}
		if text[j] == '}' || text[j] == '{' {
			return {}, "", start, false
		}
	}
	if colon2 < 0 do return {}, "", start, false

	color_name := text[start + len(prefix):colon2]

	// Find closing brace
	close := -1
	for j := colon2 + 1; j < len(text); j += 1 {
		if text[j] == '}' {
			close = j
			break
		}
	}
	if close < 0 do return {}, "", start, false

	inner_text := text[colon2 + 1:close]

	resolved, color_ok := resolve_color_name(color_name)
	if !color_ok do return {}, "", start, false

	return resolved, inner_text, close + 1, true
}

// Parse a {color:text} tag starting at position `start` (which should be '{').
// Returns the color, the inner text (as a slice of the original string),
// the position after the closing '}', and whether parsing succeeded.
@(private = "package")
parse_rich_tag :: proc(text: string, start: int) -> (color: Color, inner: string, end_pos: int, ok: bool) {
	if start >= len(text) || text[start] != '{' do return {}, "", start, false

	// Find the colon separator
	colon := -1
	for j := start + 1; j < len(text); j += 1 {
		if text[j] == ':' {
			colon = j
			break
		}
		if text[j] == '}' || text[j] == '{' {
			// No colon before end — not a valid tag
			return {}, "", start, false
		}
	}
	if colon < 0 do return {}, "", start, false

	color_name := text[start + 1:colon]

	// Find closing brace
	close := -1
	for j := colon + 1; j < len(text); j += 1 {
		if text[j] == '}' {
			close = j
			break
		}
	}
	if close < 0 do return {}, "", start, false

	inner_text := text[colon + 1:close]

	// Resolve color
	resolved, color_ok := resolve_color_name(color_name)
	if !color_ok do return {}, "", start, false

	return resolved, inner_text, close + 1, true
}

// Resolve a color name or hex code to a Color value.
@(private = "package")
resolve_color_name :: proc(name: string) -> (Color, bool) {
	// Named colors
	switch name {
	case "red":
		return RED, true
	case "green":
		return GREEN, true
	case "blue":
		return BLUE, true
	case "yellow":
		return YELLOW, true
	case "cyan":
		return CYAN, true
	case "magenta":
		return MAGENTA, true
	case "orange":
		return ORANGE, true
	case "white":
		return WHITE, true
	case "black":
		return BLACK, true
	case "gray", "grey":
		return GRAY, true
	case "light_gray", "light_grey":
		return LIGHT_GRAY, true
	case "dark_gray", "dark_grey":
		return DARK_GRAY, true
	}

	// Hex color: #rrggbb or #rgb
	if len(name) > 0 && name[0] == '#' {
		hex := name[1:]
		if len(hex) == 6 {
			r := hex_byte(hex[0:2])
			g := hex_byte(hex[2:4])
			b := hex_byte(hex[4:6])
			return Color{f32(r) / 255.0, f32(g) / 255.0, f32(b) / 255.0, 1.0}, true
		}
		if len(hex) == 3 {
			r := hex_nibble(hex[0])
			g := hex_nibble(hex[1])
			b := hex_nibble(hex[2])
			return Color{f32(r) / 255.0, f32(g) / 255.0, f32(b) / 255.0, 1.0}, true
		}
	}

	return {}, false
}

// Parse an {icon:N} or {icon:N:color} tag starting at `start`.
// N is a non-negative integer glyph slot (conventionally 128+).
// The optional third segment accepts the same color names and hex codes
// as foreground/background tags (e.g. {icon:128:red}, {icon:128:#ff8800}).
// If no color is specified, color_set is false and the caller uses default_color.
// Returns false if the tag is malformed or N contains non-digit characters.
@(private = "package")
parse_icon_tag :: proc(text: string, start: int) -> (slot: int, color: Color, color_set: bool, end_pos: int, ok: bool) {
	if start >= len(text) || text[start] != '{' do return 0, {}, false, start, false

	prefix :: "{icon:"
	if start + len(prefix) > len(text) do return 0, {}, false, start, false
	if text[start:start + len(prefix)] != prefix do return 0, {}, false, start, false

	close := -1
	for j := start + len(prefix); j < len(text); j += 1 {
		if text[j] == '}' {
			close = j
			break
		}
	}
	if close < 0 do return 0, {}, false, start, false

	inner := text[start + len(prefix):close]
	if len(inner) == 0 do return 0, {}, false, start, false

	// Split on optional colon: "128" or "128:red" or "128:#ff8800"
	colon := -1
	for j in 0 ..< len(inner) {
		if inner[j] == ':' {
			colon = j
			break
		}
	}

	num_str := inner if colon < 0 else inner[:colon]
	n := 0
	for c in num_str {
		if c < '0' || c > '9' do return 0, {}, false, start, false
		n = n * 10 + int(c - '0')
	}

	if colon >= 0 {
		color_name := inner[colon + 1:]
		resolved, resolved_ok := resolve_color_name(color_name)
		if resolved_ok {
			return n, resolved, true, close + 1, true
		}
	}

	return n, {}, false, close + 1, true
}

// Parse a 2-character hex string to a byte value (0-255).
@(private = "file")
hex_byte :: proc(s: string) -> u8 {
	if len(s) != 2 do return 0
	return hex_nibble(s[0]) * 16 + hex_nibble(s[1])
}

// Parse a single hex character to a value (0-15), doubled for #rgb shorthand.
@(private = "file")
hex_nibble :: proc(c: u8) -> u8 {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10
	}
	return 0
}
