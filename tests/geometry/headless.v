// Inspect actual ImGui navigation rectangles without a platform window or renderer.
module geometry

import antono2.imgui
import math

pub struct Bounds {
pub:
	x f32
	y f32
	w f32
	h f32
}

pub fn context(width f32, scale f32) &imgui.Context {
	ctx := imgui.create_context(unsafe { nil })
	mut io := imgui.get_io_nil()
	io.DisplaySize = imgui.ImVec2{
		x: width
		// Keep all controls visible while measuring layout, including wrapped
		// 200% accessible text at narrow widths. Scrolling has separate tests.
		y: 10000
	}
	io.DeltaTime = 1.0 / 60.0
	io.BackendFlags = imgui.BackendFlags(imgui.BackendFlags_.renderer_has_textures)
	io.ConfigFlags = imgui.ConfigFlags(imgui.ConfigFlags_.nav_enable_keyboard)
	io.IniFilename = unsafe { nil }
	mut style := imgui.get_style()
	style.FontScaleMain = scale
	return ctx
}

pub fn focus(window_name string, label string) {
	window := imgui.find_window_by_name(window_name.str)
	if isnil(window) { panic('Missing ImGui window: ${window_name}') }
	id := imgui.im_hash_str(label.str, 0, window.ID)
	imgui.set_focus_id(id, window)
}

pub fn focused_bounds() Bounds {
	ctx := imgui.get_current_context()
	window := ctx.NavWindow
	if isnil(window) { panic('No navigation window') }
	rect := window.NavRectRel[0]
	assert rect.Max.x > rect.Min.x && rect.Max.y > rect.Min.y
	// Exclude intentional scrolling from comparisons of content placement.
	return Bounds{rect.Min.x + window.Scroll.x, rect.Min.y + window.Scroll.y, rect.Max.x - rect.Min.x, rect.Max.y - rect.Min.y}
}

pub fn unchanged(before Bounds, after Bounds, label string) {
	assert math.abs(before.x - after.x) < .01 && math.abs(before.y - after.y) < .01
		&& math.abs(before.w - after.w) < .01 && math.abs(before.h - after.h) < .01, '${label}: before=${before}, after=${after}'
}
