// Default desktop demo UI showing upstream variant, docking and backend state.
// Runs inside the shared GLFW/Vulkan host rather than owning a separate render loop.
module glfw_vulkan

import antono2.imgui
import antono2.vulkan as vk

struct DemoState {
mut:
	show_demo          bool = true
	show_another       bool
	platform_viewports bool
	value              f32
	count              int
}

fn draw_demo(mut app App, userdata voidptr) {
	mut state := unsafe { &DemoState(userdata) }
	if state.show_demo {
		imgui.show_demo_window(&state.show_demo)
	}
	if imgui.begin(c'Hello, world!', unsafe { nil }, 0) {
		variant := 'Variant: ${imgui.upstream_variant}'
		imgui.text_unformatted(variant.str, unsafe { nil })
		if app.docking_available {
			imgui.checkbox(c'Main dockspace', &app.dockspace_enabled)
			if imgui.checkbox(c'Platform viewports', &state.platform_viewports) {
				// Disabling viewports destroys their renderer buffers on the next frame.
				// Secondary windows may still have submissions in flight.
				if !state.platform_viewports {
					assert vk.device_wait_idle(app.device) == vk.Result.success
				}
				imgui.configure_platform_viewports(state.platform_viewports)
			}
		} else {
			imgui.text_unformatted(c'Docking is unavailable in the standard variant.', unsafe { nil })
		}
		imgui.checkbox(c'Demo window', &state.show_demo)
		imgui.checkbox(c'Another window', &state.show_another)
		imgui.slider_float(c'Value', &state.value, 0, 1, c'%.2f', 0)
		imgui.color_edit3(c'Clear color', unsafe { &f32(&app.clear_color) }, 0)
		imgui.text_unformatted(c'Disable the main dockspace to see the clear color.', unsafe { nil })
		if imgui.button(c'Count', imgui.ImVec2{}) { state.count++ }
		imgui.same_line(0, -1)
		label := 'Count: ${state.count}'
		imgui.text_unformatted(label.str, unsafe { nil })
	}
	imgui.end()
	if state.show_another {
		if imgui.begin(c'Another window', &state.show_another, 0) {
			imgui.text_unformatted(c'Close and reopen this window from the controls.', unsafe { nil })
			if imgui.button(c'Close', imgui.ImVec2{}) {
				state.show_another = false
			}
		}
		imgui.end()
	}
}
