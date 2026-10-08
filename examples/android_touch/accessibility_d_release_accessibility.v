// Draws the Android touch demo through labelled appui accessibility controls.
// Selected by release_accessibility; the native host owns the persistent UI buffers.
module main

import math
import antono2.imgui
import antono2.imgui.appui

#flag -I @VMODROOT/examples/android_touch

#include "accessibility_state.h"

fn C.v_imgui_touch_contrast() &bool

fn C.vimgui_app_input(u64, &char, &char, usize) bool

// The native host initializes the appui context and Java accessibility adapter.
// The borrowed text/count/zoom buffers retain their existing lifecycle behavior.
fn draw_accessible_touch(zoom &f32, taps &int, text &char, text_capacity int, clipboard &char, clipboard_capacity int) bool {
	appui.begin_frame()
	storage := imgui.get_state_storage()
	base_id := imgui.get_id_str(c'##accessible-base-scale')
	mut base_scale := imgui.storage_get_float(storage, base_id, 0)
	if base_scale == 0 {
		base_scale = imgui.get_style().FontScaleMain / unsafe { *zoom }
		imgui.storage_set_float(storage, base_id, base_scale)
	}
	contrast := C.v_imgui_touch_contrast()
	appui.text(2, 'V ImGui: touch and text')
	appui.text(3, 'Swipe text or empty space to scroll. Use touch, a keyboard or your screen reader.')
	appui.checkbox(4, 'High contrast', contrast)
	if appui.button(5, 'Tap counter') {
		unsafe { *taps += 1 }
	}
	count := 'Taps: ${unsafe { *taps }}'
	appui.status(6, count)
	appui.progress(7, 'Next hundred taps', f32(unsafe { *taps } % 100) / 100, count)
	unsafe { count.free() }
	appui.set_width(-1)
	status_id := imgui.get_id_str(c'##clipboard-status')
	if C.vimgui_app_input(10, c'Editable text', text, usize(text_capacity)) {
		imgui.storage_set_int(storage, status_id, 0)
	}
	appui.text(11, 'Copy uses the entire editable field; no selection is needed. Read displays the clipboard below.')
	if appui.button(12, 'Copy all text') {
		if unsafe { text[0] == 0 } {
			imgui.storage_set_int(storage, status_id, 1)
		} else {
			imgui.set_clipboard_text(text)
			source := imgui.get_clipboard_text()
			copy_preview(clipboard, clipboard_capacity, source)
			imgui.storage_set_int(storage, status_id, if same_text(text, source) { 2 } else { 3 })
		}
	}
	if appui.button(13, 'Read clipboard') {
		copy_preview(clipboard, clipboard_capacity, imgui.get_clipboard_text())
		imgui.storage_set_int(storage, status_id, if unsafe { clipboard[0] == 0 } { 4 } else { 5 })
	}
	status := match imgui.storage_get_int(storage, status_id, 0) {
		1 { 'The field is empty. Enter text before copying.' }
		2 { 'Copied all text. The clipboard preview is shown below.' }
		3 { 'Copy could not be confirmed. Try again while the app is in the foreground.' }
		4 { 'The clipboard is empty or unavailable.' }
		5 { 'Read clipboard. The preview is shown below.' }
		6 { 'Preview cleared. The system clipboard is unchanged.' }
		else { '' }
	}
	appui.status(14, status)
	appui.text(15, 'Clipboard preview:')
	preview := unsafe { cstring_to_vstring(clipboard) }
	appui.text(16, preview)
	unsafe { preview.free() }
	if appui.button(17, 'Clear preview') {
		unsafe { clipboard[0] = 0 }
		imgui.storage_set_int(storage, status_id, 6)
	}
	appui.separator()
	if appui.button(20, 'Smaller text') {
		unsafe { *zoom = math.max(f32(0.75), *zoom - f32(0.1)) }
	}
	appui.same_line_for('Larger text', false)
	if appui.button(21, 'Larger text') {
		unsafe { *zoom = math.min(f32(2), *zoom + f32(0.1)) }
	}
	if appui.button(22, 'Reset text size') {
		unsafe { *zoom = 1 }
	}
	scale := 'Text size: ${unsafe { *zoom }:.2f}x'
	appui.status(23, scale)
	unsafe { scale.free() }
	appui.text(24, 'Rotate or resume to check retained text, taps and text size. Navigation bars and the keyboard reserve their space automatically.')
	appui.end_frame() or { panic(err) }
	// This view owns its accessible theme, including touch target sizing.
	appui.theme(true, unsafe { *contrast }, base_scale * unsafe { *zoom }, true)
	return false
}
