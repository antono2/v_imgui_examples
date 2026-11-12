// Reports observed widget bounds and state for external input tests.
module main

import antono2.glfw
import examples.glfw_vulkan as host
import examples.audio_playground.model
import json2
import os

struct Item {
	x       f32
	y       f32
	w       f32
	h       f32
	visible bool
	focused bool
	active  bool
}

struct Snapshot {
	frame        int
	backend      string = 'antono2.imgui + antono2.glfw + antono2.vulkan'
	scale        f32
	width        int
	height       int
	pixel_width  int
	pixel_height int
	stacked      bool
	state        model.State
	items        map[string]Item
	scroll_y     f32
	scroll_max   f32
	error        string
}

fn (mut d Demo) write_snapshot(app host.App) {
	window := unsafe { &glfw.Window(app.native_window) }
	size, pixels := glfw.window_size(window), glfw.framebuffer_size(window)
	value := json2.encode(Snapshot{
		frame: d.frames
		scale: d.scale
		width: size.width
		height: size.height
		pixel_width: pixels.width
		pixel_height: pixels.height
		stacked: d.stacked
		state: d.session.state
		items: d.items
		scroll_y: d.scroll_y
		scroll_max: d.scroll_max
		error: d.error_message
	})
	// Every observed frame lets native-input tests acknowledge event processing.
	os.write_file(d.report, value) or { panic(err) }
}
