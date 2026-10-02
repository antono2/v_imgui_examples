module main

import antono2.imgui
import antono2.imgui.impl_android

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
	imgui.set_next_window_pos(imgui.ImVec2_c{}, imgui.Cond(imgui.Cond_.always), imgui.ImVec2_c{})
	imgui.set_next_window_size(imgui.ImVec2_c{ x: width, y: height }, imgui.Cond(imgui.Cond_.always))
	flags := imgui.WindowFlags(int(imgui.WindowFlags_.no_move) | int(imgui.WindowFlags_.no_resize) | int(imgui.WindowFlags_.no_collapse))
	mut zoom_changed := false
	if imgui.begin(c'V ImGui: touch and text', unsafe { nil }, flags) {
		imgui.text_wrapped(c'Tap, type, select text, and scroll. Rotate or resume the app to check that your edits survive window recreation.')
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
		imgui.input_text(c'##text', text, usize(text_capacity), imgui.InputTextFlags(imgui.InputTextFlags_.callback_always), edit_text, voidptr(&selection))
		imgui.text_wrapped(c'The native keyboard and ImGui synchronize text and selection. Cursor positions below are UTF-8 byte offsets.')
		offsets := 'Cursor ${selection.cursor}; selection ${selection.start}..${selection.end}'
		imgui.text_unformatted(offsets.str, unsafe { nil })
		unsafe { offsets.free() }
		if imgui.button(c'Copy text', imgui.ImVec2_c{ x: -1 }) { imgui.set_clipboard_text(text) }
		if imgui.button(c'Read clipboard', imgui.ImVec2_c{ x: -1 }) && clipboard_capacity > 0 {
			copy_preview(clipboard, clipboard_capacity, imgui.get_clipboard_text())
		}
		if clipboard_capacity > 0 {
			imgui.text_unformatted(c'Clipboard preview:', unsafe { nil })
			imgui.push_text_wrap_pos(0)
			imgui.text_unformatted(clipboard, unsafe { nil })
			imgui.pop_text_wrap_pos()
			if imgui.button(c'Clear preview', imgui.ImVec2_c{ x: -1 }) {
				unsafe { clipboard[0] = 0 }
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
	}
	imgui.end()
	return zoom_changed
}

fn copy_preview(destination &char, capacity int, source &char) {
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
