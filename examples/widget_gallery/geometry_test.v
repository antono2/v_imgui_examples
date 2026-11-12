module main

import antono2.imgui
import antono2.imgui.appui
import examples.glfw_vulkan
import tests.geometry

fn gallery_frame(mut app glfw_vulkan.App, mut state Gallery) {
	imgui.new_frame()
	$if release_accessibility ? {
		draw_accessible_frame(mut app, mut state)
	} $else {
		draw(mut app, &state)
	}
	imgui.render()
}

fn gallery_bounds(mut app glfw_vulkan.App, mut state Gallery) geometry.Bounds {
	for _ in 0 .. 3 {
		$if release_accessibility ? {
			appui.focus(31)
		} $else {
			geometry.focus('Widget gallery', 'Open popup')
		}
		gallery_frame(mut app, mut state)
	}
	return geometry.focused_bounds()
}

fn test_gallery_feedback_preserves_following_controls() {
	for scale in [f32(1), 2] {
		for width in [f32(360), 560, 1000] {
			ctx := geometry.context(width, scale)
			$if release_accessibility ? {
				appui.initialize('Gallery geometry') or { panic(err) }
				appui.theme(true, false, scale, false)
				appui.list_reset(40)
				for i in 0 .. 1000 {
					appui.list_add(40, u64(1000 + i), 'Photo ${i:04}.jpg') or { panic(err) }
				}
			}
			mut app := glfw_vulkan.App{}
			mut state := Gallery{}
			for _ in 0 .. 3 {
				gallery_frame(mut app, mut state)
			}
			baseline := gallery_bounds(mut app, mut state)
			for status in ['', 'Copied an empty name.', 'Copied the name to the clipboard.'] {
				state.clipboard_status = status
				state.count = 1000
				state.amount = 1
				state.choice = 1
				observed := gallery_bounds(mut app, mut state)
				geometry.unchanged(baseline, observed,
					'gallery scale=${scale} width=${width} status=${status}')
			}
			for count in [9, 10, 99, 100, 999, 1000, 1000000] {
				state.count = count
				geometry.unchanged(baseline, gallery_bounds(mut app, mut state),
					'gallery scale=${scale} width=${width} count=${count}')
			}
			$if release_accessibility ? { appui.shutdown() }
			imgui.destroy_context(ctx)
		}
	}
}
