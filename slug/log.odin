package slug

import "core:mem"

// ===================================================
// Message log widget — scrolling, fading message list.
//
// Fixed-size ring buffer of text entries with timestamps.
// Newest messages appear at the bottom; older messages
// fade out based on age. No dynamic allocation.
//
// Usage:
//   // At init:
//   log: slug.Message_Log
//   slug.log_init(&log, fade_time = 4.0, fade_duration = 2.0)
//
//   // When something happens:
//   slug.log_push(&log, "Goblin attacks for 5 damage!", {1.0, 0.3, 0.3, 1.0}, elapsed)
//
//   // Every frame:
//   slug.draw_message_log(ctx, &log, x, y, font_size, elapsed)
// ===================================================

// Maximum entries in the ring buffer. Oldest entries are overwritten.
MAX_LOG_MESSAGES :: 64

// Maximum text length per entry (bytes). Longer strings are truncated.
MAX_LOG_TEXT_LEN :: 256

// A single log entry with inline text storage.
Log_Entry :: struct {
	buf:       [MAX_LOG_TEXT_LEN]byte,
	len:       int,
	color:     Color,
	timestamp: f32,
}

// Fixed-size ring buffer message log.
// fade_time:     seconds after which a message starts fading.
// fade_duration: seconds over which the fade completes (0 → 1 alpha drop).
Message_Log :: struct {
	entries:       [MAX_LOG_MESSAGES]Log_Entry,
	head:          int, // index of the oldest entry
	count:         int, // number of valid entries
	fade_time:     f32,
	fade_duration: f32,
	max_visible:   int, // max lines to draw (0 = use count)
}

// Initialize a message log with fade timing.
// max_visible controls how many lines are drawn (0 = all valid entries).
log_init :: proc(log: ^Message_Log, fade_time: f32 = 4.0, fade_duration: f32 = 2.0, max_visible: int = 8) {
	log^ = {}
	log.fade_time = fade_time
	log.fade_duration = fade_duration
	log.max_visible = max_visible
}

// Push a new message into the log. Copies text into the entry's fixed buffer.
// timestamp should be the current elapsed time (seconds since start).
log_push :: proc(log: ^Message_Log, text: string, color: Color, timestamp: f32) {
	// Write position: next slot after the newest entry
	idx: int
	if log.count < MAX_LOG_MESSAGES {
		idx = (log.head + log.count) % MAX_LOG_MESSAGES
		log.count += 1
	} else {
		// Buffer full — overwrite oldest, advance head
		idx = log.head
		log.head = (log.head + 1) % MAX_LOG_MESSAGES
	}

	entry := &log.entries[idx]
	copy_len := min(len(text), MAX_LOG_TEXT_LEN)
	mem.copy(&entry.buf[0], raw_data(text), copy_len)
	entry.len = copy_len
	entry.color = color
	entry.timestamp = timestamp
}

// Draw the message log. Newest message at y, older messages stacked above.
// Messages older than fade_time start fading; fully faded messages are skipped.
// x, y:        bottom-left corner of the newest message line.
// font_size:   em-square height for all log text.
// current_time: elapsed seconds — used to compute per-message age/alpha.
draw_message_log :: proc(
	ctx: ^Context,
	log: ^Message_Log,
	x, y: f32,
	font_size: f32,
	current_time: f32,
) {
	if log.count == 0 do return

	font := active_font(ctx)
	if font == nil do return

	line_h := line_height(font, font_size)
	visible := log.count
	if log.max_visible > 0 && visible > log.max_visible {
		visible = log.max_visible
	}

	// Walk from newest to oldest, drawing upward
	for i in 0 ..< visible {
		// newest entry is at (head + count - 1) % MAX, then walk backward
		entry_idx := (log.head + log.count - 1 - i) % MAX_LOG_MESSAGES
		entry := &log.entries[entry_idx]
		if entry.len == 0 do continue

		age := current_time - entry.timestamp
		alpha: f32 = 1.0
		if log.fade_duration > 0 && age > log.fade_time {
			alpha = clamp(1.0 - (age - log.fade_time) / log.fade_duration, 0, 1)
		}
		if alpha <= 0 do continue

		color := entry.color
		color[3] = color[3] * alpha

		text := string(entry.buf[:entry.len])
		line_y := y - f32(i) * line_h

		draw_text(ctx, text, x, line_y, font_size, color)
	}
}

// Number of currently visible (non-fully-faded) messages.
log_visible_count :: proc(log: ^Message_Log, current_time: f32) -> int {
	n := 0
	for i in 0 ..< log.count {
		entry_idx := (log.head + log.count - 1 - i) % MAX_LOG_MESSAGES
		entry := &log.entries[entry_idx]
		age := current_time - entry.timestamp
		if log.fade_duration > 0 && age > log.fade_time + log.fade_duration do continue
		n += 1
	}
	return n
}
