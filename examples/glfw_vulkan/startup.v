// Complete native window mapping before Vulkan's first FIFO presentation.
module glfw_vulkan

import antono2.glfw

fn show_startup_window(window &glfw.Window) ! {
	// Drain unrelated startup events before GLFW 3.3's X11 visibility wait.
	glfw.poll_events()
	mut x11_mapping := false
	$if linux { x11_mapping = request_x11_mapping(window) }
	if !x11_mapping { glfw.show_window(window) }
	deadline := glfw.get_time() + 5.0
	mut next_request := glfw.get_time() + 0.25
	mut requests := 1
	for glfw.get_window_attrib(window, glfw.visible) == 0 {
		if glfw.get_time() >= deadline {
			iconified := glfw.get_window_attrib(window, glfw.iconified)
			return error('Window did not become visible within 5 seconds (show requests=${requests}, iconified=${iconified})')
		}
		glfw.wait_events_timeout(0.01)
		$if linux {
			// A redirected X11 map request can be lost during a window-manager
			// transition. Polling alone never requests mapping again. Retry only
			// while still hidden; do not restore an explicitly minimized window.
			if x11_mapping && glfw.get_time() >= next_request && glfw.get_time() < deadline
				&& glfw.get_window_attrib(window, glfw.visible) == 0
				&& glfw.get_window_attrib(window, glfw.iconified) == 0 {
				glfw.poll_events()
				request_x11_mapping(window)
				requests++
				next_request = glfw.get_time() + 0.25
			}
		}
	}
	// Match GLFW's default focus-on-show behavior after asynchronous mapping.
	if x11_mapping { glfw.focus_window(window) }
}
