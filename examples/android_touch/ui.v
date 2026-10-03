module main

import antono2.imgui
import antono2.imgui.impl_android
import math

struct Selection {
mut:
	cursor int
	start  int
	end    int
}

fn edit_text(mut data imgui.InputTextCallbackData) i32 {
	impl_android.apply_text_edit(mut data)
	unsafe {
		mut selection := &Selection(data.UserData)
		selection.cursor = data.CursorPos
		selection.start = data.SelectionStart
		selection.end = data.SelectionEnd
	}
	return 0
}

// The upstream host owns these buffers and preserves them across window recreation.
// It calls this export between NewFrame and Render on its rendering thread.
@[export: 'vimgui_android_demo_draw_ui']
fn draw_ui(zoom &f32, taps &int, text &char, text_capacity int, clipboard &char, clipboard_capacity int, width f32, height f32) bool {
	imgui.set_next_window_pos(imgui.get_main_viewport().WorkPos, imgui.Cond(imgui.Cond_.always), imgui.ImVec2_c{})
	imgui.set_next_window_size(imgui.ImVec2_c{ x: width, y: height }, imgui.Cond(imgui.Cond_.always))
	flags := imgui.WindowFlags(int(imgui.WindowFlags_.no_move) | int(imgui.WindowFlags_.no_resize) | int(imgui.WindowFlags_.no_collapse))
	mut zoom_changed := false
	if imgui.begin(c'V ImGui: touch and text', unsafe { nil }, flags) {
		imgui.text_wrapped(c'Swipe on text or empty space to scroll. Tap and edit controls normally. Rotate or resume the app to check that your edits survive window recreation.')
		if imgui.button(c'Tap counter', imgui.ImVec2_c{ x: -1, y: imgui.get_font_size() * 3 }) {
			unsafe { *taps += 1 }
		}
		count := 'Taps: ${unsafe { *taps }}'
		imgui.text_unformatted(count.str, unsafe { nil })
		unsafe { count.free() }
		imgui.progress_bar(f32(unsafe { *taps } % 100) / 100, imgui.ImVec2_c{ x: -1 }, c'Next hundred taps')
		imgui.separator()
		imgui.text_unformatted(c'Editable text', unsafe { nil })
		imgui.set_next_item_width(-1)
		mut selection := Selection{}
		storage := imgui.get_state_storage()
		status_id := imgui.get_id_str(c'##clipboard-status')
		if imgui.input_text_with_hint(c'##text', c'Enter text here', text, usize(text_capacity), imgui.InputTextFlags(imgui.InputTextFlags_.callback_always), edit_text, voidptr(&selection)) {
			imgui.storage_set_int(storage, status_id, 0)
		}
		imgui.text_wrapped(c'The native keyboard and ImGui synchronize text and selection. Cursor positions below are UTF-8 byte offsets.')
		offsets := 'Cursor ${selection.cursor}; selection ${selection.start}..${selection.end}'
		imgui.text_unformatted(offsets.str, unsafe { nil })
		unsafe { offsets.free() }
		imgui.text_wrapped(c'Copy uses the entire editable field; no selection is needed. Read displays the clipboard below.')
		if imgui.button(c'Copy all text', imgui.ImVec2_c{ x: -1 }) {
			if unsafe { text[0] == 0 } {
				imgui.storage_set_int(storage, status_id, 1)
			} else {
				imgui.set_clipboard_text(text)
				source := imgui.get_clipboard_text()
				copy_preview(clipboard, clipboard_capacity, source)
				imgui.storage_set_int(storage, status_id, if same_text(text, source) {
					2
				} else {
					3
				})
			}
		}
		if imgui.button(c'Read clipboard', imgui.ImVec2_c{ x: -1 }) && clipboard_capacity > 0 {
			copy_preview(clipboard, clipboard_capacity, imgui.get_clipboard_text())
			imgui.storage_set_int(storage, status_id, if unsafe { clipboard[0] == 0 } {
				4
			} else {
				5
			})
		}
		match imgui.storage_get_int(storage, status_id, 0) {
			1 { imgui.text_wrapped(c'The field is empty. Enter text before copying.') }
			2 { imgui.text_wrapped(c'Copied all text. The clipboard preview is shown below.') }
			3 {
				imgui.text_wrapped(c'Copy could not be confirmed. Try again while the app is in the foreground.')
			}
			4 { imgui.text_wrapped(c'The clipboard is empty or unavailable.') }
			5 { imgui.text_wrapped(c'Read clipboard. The preview is shown below.') }
			6 { imgui.text_wrapped(c'Preview cleared. The system clipboard is unchanged.') }
			else {}
		}
		if clipboard_capacity > 0 {
			imgui.text_unformatted(c'Clipboard preview:', unsafe { nil })
			imgui.push_text_wrap_pos(0)
			imgui.text_unformatted(clipboard, unsafe { nil })
			imgui.pop_text_wrap_pos()
			if imgui.button(c'Clear preview', imgui.ImVec2_c{ x: -1 }) {
				unsafe { clipboard[0] = 0 }
				imgui.storage_set_int(storage, status_id, 6)
			}
		}
		imgui.separator()
		imgui.text_unformatted(c'UI zoom', unsafe { nil })
		imgui.set_next_item_width(-1)
		zoom_changed = imgui.slider_float(c'##zoom', zoom, 0.75, 2, c'%.2fx', 0)
		imgui.text_wrapped(c'Zoom scales fonts and controls together. Use portrait and landscape orientations to check the scrollable layout.')
		if imgui.collapsing_header_tree_node_flags(c'Testing checklist', 0) {
			imgui.text_wrapped(c'1. Type non-ASCII text and replace a selection.\n2. Hide the keyboard with Back, then tap the field again.\n3. Copy and read text.\n4. Rotate, background, and resume.\n5. Change zoom and reach the bottom controls.')
		}
		touch_scroll()
	}
	imgui.end()
	return zoom_changed
}

fn copy_preview(destination &char, capacity int, source &char) {
	if capacity <= 0 {
		return
	}
	unsafe {
		mut length := 0
		if source != nil {
			for length < capacity - 1 && source[length] != 0 {
				length++
			}
			// If truncation cuts a UTF-8 code point, omit that partial code point.
			if source[length] != 0 {
				for length > 0 && (u8(source[length]) & 0xc0) == 0x80 {
					length--
				}
			}
			vmemcpy(destination, source, length)
		}
		destination[length] = 0
	}
}

fn same_text(left &char, right &char) bool {
	unsafe {
		if left == nil || right == nil {
			return false
		}
		mut index := 0
		for left[index] == right[index] {
			if left[index] == 0 {
				return true
			}
			index++
		}
	}
	return false
}

// Call after drawing the window's items so presses on widgets keep their normal
// behavior. ImGui's window storage owns the gesture state, including its lifetime.
fn touch_scroll() {
	io := imgui.get_io_nil()
	if io.MouseSource != .touch_screen {
		return
	}
	context := imgui.get_current_context()
	window := imgui.get_current_window()
	storage := imgui.get_state_storage()
	tracking := imgui.get_id_str(c'##swipe-tracking')
	dragging := imgui.get_id_str(c'##swipe-dragging')
	start_y := imgui.get_id_str(c'##swipe-start-y')
	start_scroll := imgui.get_id_str(c'##swipe-start-scroll')
	active := imgui.get_id_str(c'##swipe-scroll')
	if imgui.is_mouse_clicked_bool(0, false) && context.HoveredWindow == window
		&& context.HoveredId == 0 && context.ActiveId == 0 && imgui.get_scroll_max_y() > 0 {
		imgui.storage_set_bool(storage, tracking, true)
		imgui.storage_set_bool(storage, dragging, false)
		imgui.storage_set_float(storage, start_y, io.MousePos.y)
		imgui.storage_set_float(storage, start_scroll, imgui.get_scroll_y())
	}
	if !imgui.storage_get_bool(storage, tracking, false) {
		return
	}
	if imgui.is_mouse_down_nil(0) {
		delta := io.MousePos.y - imgui.storage_get_float(storage, start_y, io.MousePos.y)
		if math.abs(delta) > imgui.get_font_size() * 0.3 {
			imgui.storage_set_bool(storage, dragging, true)
		}
		if imgui.storage_get_bool(storage, dragging, false) {
			imgui.set_active_id(active, window)
			imgui.keep_alive_id(active)
			imgui.set_scroll_y_float(math.max(f32(0), math.min(imgui.get_scroll_max_y(), imgui.storage_get_float(storage, start_scroll, 0) - delta)))
		}
	} else {
		if context.ActiveId == active { imgui.clear_active_id() }
		imgui.storage_set_bool(storage, tracking, false)
		imgui.storage_set_bool(storage, dragging, false)
	}
}
