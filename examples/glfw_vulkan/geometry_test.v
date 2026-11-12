module glfw_vulkan

import antono2.imgui
import tests.geometry

fn demo_geometry_frame(mut app App, mut state DemoState) {
	imgui.new_frame()
	draw_demo(mut app, &state)
	imgui.render()
}

fn test_counter_and_window_toggles_preserve_demo_controls() {
	for scale in [f32(1), 2] {
		ctx := geometry.context(1000, scale)
		mut app := App{}
		mut state := DemoState{
			show_demo: false
		}
		for _ in 0 .. 3 {
			demo_geometry_frame(mut app, mut state)
		}
		geometry.focus('Hello, world!', 'Count')
		demo_geometry_frame(mut app, mut state)
		baseline := geometry.focused_bounds()
		for count in [9, 10, 1000, 1000000] {
			state.count = count
			state.show_another = count % 2 == 0
			for _ in 0 .. 3 {
				geometry.focus('Hello, world!', 'Count')
				demo_geometry_frame(mut app, mut state)
			}
			geometry.unchanged(baseline, geometry.focused_bounds(), 'GLFW demo count=${count}')
		}
		imgui.destroy_context(ctx)
	}
}
