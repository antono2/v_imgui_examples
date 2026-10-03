module main

import examples.glfw_vulkan
import math
import antono2.imgui
import antono2.imgui.appui

#flag -I @VMODROOT/examples/widget_gallery

#include "accessibility_bridge.h"

fn C.v_imgui_gallery_attach(voidptr) bool

fn C.v_imgui_gallery_update(voidptr)

fn C.v_imgui_gallery_detach()

fn C.vimgui_app_input(u64, &char, &char, usize) bool

fn draw_accessible(mut app glfw_vulkan.App, mut state Gallery) {
	if !state.accessible_initialized {
		appui.initialize('Widget gallery') or { panic(err) }
		if !C.v_imgui_gallery_attach(app.native_window) {
			panic('Could not attach native accessibility adapter')
		}
		appui.list_reset(40)
		for i in 0 .. 1000 {
			appui.list_add(40, u64(1000 + i), 'Photo ${i:04}.jpg') or { panic(err) }
		}
		appui.theme(true, false, 1, false)
		state.accessible_initialized = true
	}
	appui.begin_frame()
	if state.raw_widgets && appui.back_requested() { state.raw_widgets = false }
	appui.text(2, 'Widget gallery')
	appui.text(3, 'Use Tab and arrow keys, or your screen reader. Controls have stable names and native actions.')
	if appui.radio(4, 'Accessible controls', !state.raw_widgets) {
		state.raw_widgets = false
	}
	appui.same_line_for('Raw ImGui widgets', true)
	if appui.radio(5, 'Raw ImGui widgets', state.raw_widgets) {
		state.raw_widgets = true
	}
	mut theme_changed := appui.checkbox(6, 'High contrast', &state.high_contrast)
	appui.same_line_for('200% text', true)
	theme_changed = appui.checkbox(7, '200% text', &state.large_text) || theme_changed
	if state.raw_widgets {
		appui.text(8, 'The raw widget view demonstrates the ImGui API. These controls do not publish screen-reader semantics; use Accessible controls for native accessibility.')
		draw_widgets(mut app, mut state)
	} else {
		appui.begin_columns(50, 240 * imgui.get_style().FontScaleMain, 0)
		appui.set_width(-1)
		C.vimgui_app_input(10, c'Name', &state.name[0], usize(state.name.len))
		appui.next_column(true)
		appui.checkbox(11, 'Enabled', &state.enabled)
		appui.end_columns()
		appui.text(12, 'Priority')
		for index, label in ['Low', 'Medium', 'High'] {
			if index > 0 { appui.same_line_for(label, true) }
			if appui.radio(u64(13 + index), label, state.choice == index) {
				state.choice = index
			}
		}
		if appui.button(16, 'Decrease amount') {
			state.amount = math.max(f32(0), state.amount - f32(0.1))
		}
		appui.same_line_for('Increase amount', false)
		if appui.button(17, 'Increase amount') {
			state.amount = math.min(f32(1), state.amount + f32(0.1))
		}
		appui.progress(18, 'Amount', state.amount, '${int(state.amount * 100)}%')
		appui.progress(19, 'Unknown progress', -1, 'Waiting for work')
		if appui.button(20, 'Count') { state.count++ }
		appui.status(21, 'Count: ${state.count}')
		if appui.button(22, 'Copy name') {
			imgui.set_clipboard_text(&state.name[0])
			state.clipboard_status = if unsafe { state.name[0] == 0 } {
				'Copied an empty name.'
			} else {
				'Copied the name to the clipboard.'
			}
		}
		appui.status(23, state.clipboard_status)
		appui.separator()
		appui.text(30, 'File list: keyboard arrows and screen-reader actions select a row; focus can reach off-screen rows.')
		if appui.button(31, 'Focus last file') {
			appui.reveal(40)
			appui.focus(1999)
		}
		activated := appui.list(40, 'Files', state.selected_file, 240)
		if activated != 0 {
			state.selected_file = activated
		}
		appui.status(41, if state.selected_file == 0 {
			'No file selected.'
		} else {
			'Selected Photo ${state.selected_file - 1000:04}.jpg'
		})
	}
	appui.end_frame() or { panic(err) }
	if theme_changed {
		appui.theme(true, state.high_contrast, if state.large_text { f32(2) } else { f32(1) }, false)
	}
	if state.raw_widgets { draw_auxiliary(mut state) }
	C.v_imgui_gallery_update(app.native_window)
}

fn close_accessibility() {
	C.v_imgui_gallery_detach()
	appui.shutdown()
}
