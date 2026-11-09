// Builds responsive ImGui controls and the spatial sound diagram.
module main

import antono2.imgui
import examples.audio_playground.model
import math

fn vec(x f32, y f32) imgui.ImVec2 {
	return imgui.ImVec2{ x: x, y: y }
}

fn color(r f32, g f32, b f32) imgui.ImVec4 {
	return imgui.ImVec4{ x: r / 255, y: g / 255, z: b / 255, w: 1 }
}

fn ink(r u32, g u32, b u32) u32 {
	return r | (g << 8) | (b << 16) | 0xff000000
}

fn apply_theme(scale f32) {
	mut s := imgui.get_style()
	s.FontSizeBase = 16
	s.FontScaleMain = 1
	s.FontScaleDpi = scale
	s.WindowPadding = vec(18 * scale, 16 * scale)
	s.FramePadding = vec(12 * scale, 8 * scale)
	s.ItemSpacing = vec(10 * scale, 9 * scale)
	s.ItemInnerSpacing = vec(8 * scale, 6 * scale)
	s.CellPadding = vec(12 * scale, 8 * scale)
	s.ScrollbarSize = 18 * scale
	s.GrabMinSize = 18 * scale
	s.WindowRounding = 0
	s.FrameRounding = 5 * scale
	s.GrabRounding = 4 * scale
	s.WindowBorderSize = 0
	s.Colors[int(imgui.Col_.window_bg)] = color(14, 24, 32)
	s.Colors[int(imgui.Col_.text)] = color(237, 244, 247)
	s.Colors[int(imgui.Col_.text_disabled)] = color(163, 184, 195)
	s.Colors[int(imgui.Col_.button)] = color(39, 60, 73)
	s.Colors[int(imgui.Col_.button_hovered)] = color(51, 83, 96)
	s.Colors[int(imgui.Col_.button_active)] = color(65, 104, 116)
	s.Colors[int(imgui.Col_.frame_bg)] = color(28, 48, 61)
	s.Colors[int(imgui.Col_.frame_bg_hovered)] = color(39, 65, 78)
	s.Colors[int(imgui.Col_.frame_bg_active)] = color(45, 75, 88)
	s.Colors[int(imgui.Col_.slider_grab)] = color(108, 224, 207)
	s.Colors[int(imgui.Col_.slider_grab_active)] = color(142, 241, 222)
	s.Colors[int(imgui.Col_.header)] = color(24, 40, 52)
	s.Colors[int(imgui.Col_.header_hovered)] = color(39, 65, 78)
	s.Colors[int(imgui.Col_.header_active)] = color(45, 75, 88)
}

// Text is never used as a printf format string (the API call may contain '%').
fn text(value string) {
	imgui.push_text_wrap_pos(0)
	imgui.text_unformatted(value.str, unsafe { nil })
	imgui.pop_text_wrap_pos()
}

fn (mut d Demo) remember(name string) {
	a, b := imgui.get_item_rect_min(), imgui.get_item_rect_max()
	d.items[name] = Item{ x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y, visible: imgui.is_item_visible(), focused: imgui.is_item_focused() }
}

fn (mut d Demo) draw() {
	io := imgui.get_io_nil()
	imgui.set_next_window_pos(vec(0, 0), int(imgui.Cond_.always), vec(0, 0))
	imgui.set_next_window_size(io.DisplaySize, int(imgui.Cond_.always))
	flags := int(imgui.WindowFlags_.no_title_bar) | int(imgui.WindowFlags_.no_resize) | int(imgui.WindowFlags_.no_move) | int(imgui.WindowFlags_.no_saved_settings) | int(imgui.WindowFlags_.no_collapse)
	d.items.clear()
	if imgui.begin(c'Audio playground', unsafe { nil }, flags) {
		imgui.push_font(unsafe { nil }, 26)
		text('Audio playground')
		imgui.pop_font()
		text('Move the sound. Hear the position. Follow the V call.')
		imgui.spacing()
		// Reserve real readable space per column. Narrow/zoomed windows reflow;
		// ImGui's root scrollbar keeps overflow reachable even on tiny screens.
		d.stacked = imgui.get_content_region_avail().x / d.scale < 900
		if d.stacked {
			d.draw_controls()
			imgui.separator()
			d.draw_field(true)
		} else if imgui.begin_table(c'audio-layout', 2, int(imgui.TableFlags_.sizing_stretch_prop), vec(0, 0), 0) {
			imgui.table_setup_column(c'Position', int(imgui.TableColumnFlags_.width_stretch), 1, 0)
			imgui.table_setup_column(c'Controls', int(imgui.TableColumnFlags_.width_fixed), 340 * d.scale, 0)
			imgui.table_next_column()
			d.draw_field(false)
			imgui.table_next_column()
			d.draw_controls()
			imgui.end_table()
		}
		if d.error_message != '' { text('Audio error: ' + d.error_message) }
		help_open := imgui.collapsing_header_tree_node_flags(c'Keyboard & playback notes', 0)
		d.remember('help')
		if help_open {
			text('Tab / Shift+Tab navigate. Space activates the focused control. P plays or stops. 1 / 2 / 3 choose a position. +/- adjusts volume; M mutes; R resets; Esc stops. Sound stops when this window loses focus.')
			text('The original mono chime loops. Start low; stereo headphones make positioning easier to hear. The diagram shows position, not a measured waveform.')
		}
		d.scroll_y = imgui.get_scroll_y()
		d.scroll_max = imgui.get_scroll_max_y()
	}
	imgui.end()
}

fn (mut d Demo) draw_controls() {
	status := if d.silent {
		'Silent test mode'
	} else if d.session.state.playing { 'Playing' } else { 'Ready to play' }
	text(status)
	available := imgui.get_content_region_avail().x
	mut used := f32(0)
	labels := [if d.session.state.playing { 'Restart' } else { 'Play' }, 'Stop',
		if d.session.state.gain == 0 { 'Unmute' } else { 'Mute' }, 'Reset']
	for i, label in labels {
		width := f32(math.max(64 * d.scale, imgui.calc_text_size(label.str, unsafe { nil }, false, 0).x + 24 * d.scale))
		if used > 0 && used + 10 * d.scale + width <= available {
			imgui.same_line(0, -1)
			used += 10 * d.scale
		} else {
			used = 0
		}
		if imgui.button(label.str, vec(width, 0)) {
			d.apply(match i {
				0 { model.Action.play }
				1 { model.Action.stop }
				2 { d.session.state.mute() }
				else { d.session.state.reset() }
			})
		}
		d.remember(['play', 'stop', 'mute', 'reset'][i])
		used += width
	}
	text('Volume')
	mut percent := d.session.state.gain * 100
	imgui.set_next_item_width(-1)
	if imgui.slider_float(c'##volume', &percent, 0, 100, c'%.0f%%', 0) {
		d.apply(d.session.state.set_gain(percent / 100))
	}
	d.remember('volume')
	text('Position presets')
	used = 0
	for i, label in ['Left', 'Centre', 'Right'] {
		width := f32(math.min(88 * d.scale, available))
		if used > 0 && used + 10 * d.scale + width <= available {
			imgui.same_line(0, -1)
			used += 10 * d.scale
		} else {
			used = 0
		}
		if imgui.button(label.str, vec(width, 0)) {
			d.apply(d.session.state.set_position(f32((i - 1) * 4), -1))
		}
		d.remember(['left', 'centre', 'right'][i])
		used += width
	}
	text('X ${d.session.state.x:.2f}   Y 0.00   Z ${d.session.state.z:.2f}')
	details_open := imgui.collapsing_header_tree_node_flags(c'Position values & V call', if d.stacked {
		0
	} else {
		int(imgui.TreeNodeFlags_.default_open)
	})
	d.remember('details')
	if details_open {
		mut x, mut z := d.session.state.x, d.session.state.z
		imgui.set_next_item_width(-1)
		if imgui.slider_float(c'##x', &x, -6, 6, c'X %.2f', 0) {
			d.apply(d.session.state.set_position(x, z))
		}
		d.remember('x')
		imgui.set_next_item_width(-1)
		if imgui.slider_float(c'##z', &z, -6, 6, c'Z %.2f', 0) {
			d.apply(d.session.state.set_position(x, z))
		}
		d.remember('z')
		text(d.session.last_call)
	}
}

fn (mut d Demo) draw_field(compact bool) {
	text('Sound position · front is -Z')
	available := imgui.get_content_region_avail()
	preferred := if compact {
		f32(math.max(140 * d.scale, math.min(280 * d.scale, imgui.get_io_nil().DisplaySize.y * 0.3)))
	} else {
		f32(math.max(180 * d.scale, math.min(490 * d.scale, imgui.get_io_nil().DisplaySize.y - 260 * d.scale)))
	}
	side := f32(math.max(f32(1), math.min(available.x, preferred)))
	imgui.set_cursor_pos_x(imgui.get_cursor_pos_x() + f32(math.max(f32(0), (available.x - side) / 2)))
	imgui.invisible_button(c'sound-position', vec(side, side), int(imgui.ButtonFlags_.mouse_button_left))
	d.remember('field')
	r := d.items['field']
	if imgui.is_item_active() && imgui.is_mouse_down_nil(0) {
		mouse := imgui.get_mouse_pos()
		d.apply(d.session.state.set_position((mouse.x - r.x) / r.w * 12 - 6, (mouse.y - r.y) / r.h * 12 - 6))
	}
	draw := imgui.get_window_draw_list()
	imgui.im_draw_list_add_rect_filled(draw, vec(r.x, r.y), vec(r.x + r.w, r.y + r.h), ink(24, 40, 52), 5 * d.scale, 0)
	for tick in 0 .. 7 {
		x, y := r.x + r.w * f32(tick) / 6, r.y + r.h * f32(tick) / 6
		imgui.im_draw_list_add_line(draw, vec(x, r.y), vec(x, r.y + r.h), ink(39, 60, 73), d.scale)
		imgui.im_draw_list_add_line(draw, vec(r.x, y), vec(r.x + r.w, y), ink(39, 60, 73), d.scale)
	}
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	px, py := r.x + (d.session.state.x + 6) / 12 * r.w, r.y + (d.session.state.z + 6) / 12 * r.h
	imgui.im_draw_list_add_circle(draw, vec(cx, cy), r.w / 6, ink(55, 80, 94), 64, d.scale)
	imgui.im_draw_list_add_circle(draw, vec(cx, cy), r.w / 3, ink(55, 80, 94), 64, d.scale)
	imgui.im_draw_list_add_line(draw, vec(cx, cy), vec(px, py), ink(131, 174, 245), 1.5 * d.scale)
	imgui.im_draw_list_add_triangle_filled(draw, vec(cx, cy - 12 * d.scale), vec(cx - 8 * d.scale, cy + 7 * d.scale), vec(cx + 8 * d.scale, cy + 7 * d.scale), ink(131, 174, 245))
	imgui.im_draw_list_add_circle_filled(draw, vec(px, py), 8 * d.scale, ink(108, 224, 207), 32)
	imgui.im_draw_list_add_circle(draw, vec(px, py), 14 * d.scale, ink(108, 224, 207), 40, d.scale)
	text('Drag the green sound around the blue listener.')
	text('Inner ring: distance attenuation begins.')
}
