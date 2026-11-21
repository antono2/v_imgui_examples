// Draws selectable ImPlot series and a rolling sample history in the desktop host.
// Creates and destroys plotting state through the host lifecycle callbacks.
module main

import examples.glfw_vulkan
import desktopsettings
import antono2.imgui
import antono2.imgui.implot
import math

const sample_count = 256
const history_capacity = desktopsettings.dashboard_history_samples
const simulated_samples_per_second = 60
const history_seconds = f64(history_capacity) / simulated_samples_per_second
const history_plot_title = 'Rolling history (${history_capacity} samples)'
const plot_height = 240
const fill_available_plot_width = -1
const signal_axis_limit = 2.1

struct Dashboard {
mut:
	context       &imgui.Context = unsafe { nil }
	spec          &implot.Spec = unsafe { nil }
	x             [sample_count]f32
	sine          [sample_count]f32
	cosine        [sample_count]f32
	history_time  [history_capacity]f32
	history_value [history_capacity]f32
	history_count int
	history_next  int
	tick          int
	amplitude     f32 = 1
	frequency     f32 = 1
	show_sine     bool = true
	show_cosine   bool = true
	paused        bool
}

fn main() {
	mut state := Dashboard{}
	glfw_vulkan.run(glfw_vulkan.Options{
		title: 'V ImGui: ImPlot dashboard'
		initialize: initialize_dashboard
		shutdown: shutdown_dashboard
	}, draw, &state)
}

fn initialize_dashboard(userdata voidptr) {
	mut state := unsafe { &Dashboard(userdata) }
	state.context = implot.create_context()
	// The native constructor supplies auto colors, marker defaults and stride.
	state.spec = implot.spec_spec()
}

fn shutdown_dashboard(userdata voidptr) {
	state := unsafe { &Dashboard(userdata) }
	implot.spec_destroy(state.spec)
	implot.destroy_context(state.context)
}

fn (mut state Dashboard) sample() {
	for i in 0 .. sample_count {
		x := f32(i) * f32(2 * math.pi) / f32(sample_count - 1)
		state.x[i] = x
		state.sine[i] = state.amplitude * f32(math.sin(f64(x * state.frequency)))
		state.cosine[i] = state.amplitude * f32(math.cos(f64(x * state.frequency)))
	}
	if !state.paused {
		// A fixed sample step makes the generated data reproducible on every machine.
		t := f32(state.tick) / simulated_samples_per_second
		state.history_time[state.history_next] = t
		state.history_value[state.history_next] = state.amplitude * f32(math.sin(f64(t * state.frequency)))
		state.history_next = (state.history_next + 1) % history_capacity
		state.history_count = int(math.min(state.history_count + 1, history_capacity))
		state.tick++
	}
}

fn draw(mut app glfw_vulkan.App, userdata voidptr) {
	mut state := unsafe { &Dashboard(userdata) }
	state.sample()
	imgui.set_next_window_size(imgui.ImVec2{ x: 850, y: 700 }, imgui.Cond(imgui.Cond_.first_use_ever))
	if imgui.begin(c'ImPlot dashboard', unsafe { nil }, 0) {
		imgui.text_unformatted(c'Synthetic data. Drag to pan, wheel to zoom, click legend items to hide series.', unsafe { nil })
		imgui.slider_float(c'Amplitude', &state.amplitude, 0.1, 2, c'%.2f', 0)
		imgui.slider_float(c'Frequency', &state.frequency, 0.25, 4, c'%.2f', 0)
		imgui.checkbox(c'Sine line', &state.show_sine)
		imgui.same_line(0, -1)
		imgui.checkbox(c'Cosine scatter', &state.show_cosine)
		imgui.same_line(0, -1)
		imgui.checkbox(c'Pause history', &state.paused)
		if imgui.button(c'Reset history', imgui.ImVec2{}) {
			state.history_count = 0
			state.history_next = 0
			state.tick = 0
		}
		if implot.begin_plot(c'Waveforms', imgui.ImVec2{ x: fill_available_plot_width, y: plot_height }, 0) {
			implot.setup_axes(c'Phase', c'Value', 0, 0)
			implot.setup_axes_limits(0, 2 * math.pi, -signal_axis_limit, signal_axis_limit, implot.Cond(imgui.Cond_.once))
			if state.show_sine {
				implot.plot_line_float_ptr_float_ptr(c'Sine', &state.x[0], &state.sine[0], sample_count, *state.spec)
			}
			if state.show_cosine {
				implot.plot_scatter_float_ptr_float_ptr(c'Cosine', &state.x[0], &state.cosine[0], sample_count, *state.spec)
			}
			implot.end_plot()
		}
		latest := f64(state.tick) / simulated_samples_per_second
		implot.set_next_axes_limits(math.max(f64(0), latest - history_seconds), math.max(history_seconds, latest), -signal_axis_limit, signal_axis_limit, implot.Cond(imgui.Cond_.always))
		if implot.begin_plot(history_plot_title.str, imgui.ImVec2{ x: fill_available_plot_width, y: plot_height }, 0) {
			implot.setup_axes(c'Simulated seconds', c'Value', 0, 0)
			mut ring_spec := implot.Spec_c(*state.spec)
			// ImPlot wraps the offset at count. Before the buffer fills it starts at 0.
			ring_spec.Offset = if state.history_count == history_capacity {
				state.history_next
			} else {
				0
			}
			if state.history_count > 0 {
				implot.plot_line_float_ptr_float_ptr(c'History', &state.history_time[0], &state.history_value[0], state.history_count, ring_spec)
			}
			implot.end_plot()
		}
		if app.docking_available { imgui.checkbox(c'Main dockspace', &app.dockspace_enabled) }
	}
	imgui.end()
}
