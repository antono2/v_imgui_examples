module main

import examples.glfw_vulkan
import antono2.imgui

struct Gallery {
mut:
	name         [128]char
	enabled      bool = true
	amount       f32 = 0.5
	choice       int
	count        int
	show_demo    bool
	show_details bool
}

fn main() {
	mut gallery := Gallery{}
	glfw_vulkan.run(glfw_vulkan.Options{ title: 'V ImGui: widget gallery' }, draw, &gallery)
}

fn draw(mut app glfw_vulkan.App, userdata voidptr) {
	mut state := unsafe { &Gallery(userdata) }
	imgui.set_next_window_size(imgui.ImVec2{ x: 640, y: 620 }, imgui.Cond(imgui.Cond_.first_use_ever))
	if imgui.begin(c'Widget gallery', unsafe { nil }, 0) {
		imgui.text_unformatted(c'Each widget edits persistent V state.', unsafe { nil })
		imgui.input_text(c'Name', &state.name[0], usize(state.name.len), 0, unsafe { nil }, unsafe { nil })
		imgui.checkbox(c'Enabled', &state.enabled)
		imgui.slider_float(c'Amount', &state.amount, 0, 1, c'%.2f', 0)
		imgui.progress_bar(state.amount, imgui.ImVec2{ x: -1 }, c'Slider value')
		choices := [c'Low', c'Medium', c'High']
		if imgui.begin_combo(c'Priority', choices[state.choice], 0) {
			for index, label in choices {
				if imgui.selectable_bool(label, index == state.choice, 0, imgui.ImVec2{}) {
					state.choice = index
				}
			}
			imgui.end_combo()
		}
		if imgui.button(c'Count', imgui.ImVec2{}) { state.count++ }
		imgui.same_line(0, -1)
		count := 'Count: ${state.count}'
		imgui.text_unformatted(count.str, unsafe { nil })
		if imgui.button(c'Open popup', imgui.ImVec2{}) { imgui.open_popup_str(c'Example popup', 0) }
		if imgui.begin_popup(c'Example popup', 0) {
			imgui.text_unformatted(c'Popups open from an event and keep their own visibility.', unsafe { nil })
			if imgui.button(c'Close popup', imgui.ImVec2{}) { imgui.close_current_popup() }
			imgui.end_popup()
		}
		imgui.separator()
		flags := imgui.TableFlags(int(imgui.TableFlags_.borders) | int(imgui.TableFlags_.row_bg) | int(imgui.TableFlags_.resizable))
		if imgui.begin_table(c'Widgets', 2, flags, imgui.ImVec2{}, 0) {
			imgui.table_setup_column(c'Widget', 0, 0, 0)
			imgui.table_setup_column(c'Use', 0, 0, 0)
			imgui.table_headers_row()
			labels := [c'InputText', c'Checkbox', c'SliderFloat', c'BeginCombo']
			uses := [c'Edit a fixed buffer', c'Toggle a bool', c'Edit a bounded value',
				c'Select one item']
			for i, label in labels {
				imgui.table_next_row(0, 0)
				imgui.table_next_column()
				imgui.text_unformatted(label, unsafe { nil })
				imgui.table_next_column()
				imgui.text_unformatted(uses[i], unsafe { nil })
			}
			imgui.end_table()
		}
		imgui.checkbox(c'Details window', &state.show_details)
		imgui.checkbox(c'Upstream demo', &state.show_demo)
		if app.docking_available { imgui.checkbox(c'Main dockspace', &app.dockspace_enabled) }
	}
	// End is required even when Begin reports a collapsed window.
	imgui.end()
	if state.show_details {
		if imgui.begin(c'Details', &state.show_details, 0) {
			imgui.text_unformatted(c'Your name:', unsafe { nil })
			imgui.same_line(0, -1)
			imgui.text_unformatted(&state.name[0], unsafe { nil })
		}
		imgui.end()
	}
	if state.show_demo { imgui.show_demo_window(&state.show_demo) }
}
