module glfw_vulkan

import antono2.glfw
import math

// Use the monitor's current video mode for GLFW's windowed fullscreen mode.
struct WindowMode {
mut:
	fullscreen bool
	x          i32
	y          i32
	width      i32
	height     i32
	decorated  i32
	maximized  bool
}

fn (mut mode WindowMode) remember_bounds(window &glfw.Window) {
	if mode.fullscreen || glfw.get_window_attrib(window, glfw.maximized) != 0
		|| glfw.get_window_attrib(window, glfw.iconified) != 0 {
		return
	}
	glfw.get_window_pos(window, &mode.x, &mode.y)
	size := glfw.window_size(window)
	mode.width = size.width
	mode.height = size.height
}

fn (mut mode WindowMode) toggle(window &glfw.Window) {
	if mode.fullscreen {
		glfw.set_window_attrib(window, glfw.decorated, mode.decorated)
		glfw.set_window_monitor(window, unsafe { nil }, mode.x, mode.y, mode.width, mode.height, glfw.dont_care)
		if mode.maximized { glfw.maximize_window(window) }
		mode.fullscreen = false
		return
	}
	mut x := i32(0)
	mut y := i32(0)
	glfw.get_window_pos(window, &x, &y)
	size := glfw.window_size(window)
	mut count := i32(0)
	monitors := glfw.get_monitors(&count)
	mut selected := glfw.get_primary_monitor()
	mut largest := i64(-1)
	for i in 0 .. count {
		mut monitor := unsafe { monitors[i] }
		video := glfw.get_video_mode(monitor)
		if isnil(video) {
			continue
		}
		mut mx := i32(0)
		mut my := i32(0)
		glfw.get_monitor_pos(monitor, &mx, &my)
		overlap_width := i32(math.max(0, math.min(x + size.width, mx + video.width) - math.max(x, mx)))
		overlap_height := i32(math.max(0, math.min(y + size.height, my + video.height) - math.max(y, my)))
		overlap := i64(overlap_width) * overlap_height
		if overlap > largest {
			largest = overlap
			selected = monitor
		}
	}
	if isnil(selected) {
		return
	}
	video := glfw.get_video_mode(selected)
	if isnil(video) {
		return
	}
	mode.decorated = glfw.get_window_attrib(window, glfw.decorated)
	mode.maximized = glfw.get_window_attrib(window, glfw.maximized) != 0
	if mode.maximized { glfw.restore_window(window) }
	glfw.set_window_attrib(window, glfw.decorated, 0)
	glfw.set_window_monitor(window, selected, 0, 0, video.width, video.height, video.refreshRate)
	mode.fullscreen = true
}
