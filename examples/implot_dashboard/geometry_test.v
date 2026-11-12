module main

import antono2.imgui
import examples.glfw_vulkan
import tests.geometry

fn dashboard_geometry_frame(mut app glfw_vulkan.App, mut state Dashboard) {
	imgui.new_frame()
	draw(mut app, &state)
	imgui.render()
}

fn test_plot_visibility_and_history_preserve_controls() {
	for scale in [f32(1), 2] {
		ctx := geometry.context(1000, scale)
		mut app := glfw_vulkan.App{
			docking_available: true
		}
		mut state := Dashboard{}
		initialize_dashboard(&state)
		for _ in 0 .. 3 {
			dashboard_geometry_frame(mut app, mut state)
		}
		for label in ['Reset history', 'Main dockspace'] {
			geometry.focus('ImPlot dashboard', label)
			dashboard_geometry_frame(mut app, mut state)
			baseline := geometry.focused_bounds()
			for visible in [false, true] {
				state.show_sine = visible
				state.show_cosine = visible
				state.paused = visible
				state.history_count = 0
				state.history_next = 0
				state.tick = 0
				for _ in 0 .. 3 {
					geometry.focus('ImPlot dashboard', label)
					dashboard_geometry_frame(mut app, mut state)
				}
				geometry.unchanged(baseline, geometry.focused_bounds(),
					'ImPlot ${label} visible=${visible}')
			}
		}
		shutdown_dashboard(&state)
		imgui.destroy_context(ctx)
	}
}
