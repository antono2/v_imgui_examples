// Runs the real raw/accessible Android UI in headless ImGui frames.
module main

import antono2.imgui
import antono2.imgui.appui
import tests.geometry

// The desktop geometry test never edits through Android's IME bridge.
fn apply_android_text_edit(mut _ imgui.InputTextCallbackData) {
	panic('Android IME is outside this headless geometry test')
}

struct TouchState {
mut:
	zoom    f32 = 1
	taps    int
	text    [128]char
	preview [1024]char
}

fn touch_frame(width f32, mut state TouchState) {
	imgui.new_frame()
	draw_ui(&state.zoom, &state.taps, &state.text[0], state.text.len, &state.preview[0],
		state.preview.len, width, 10000)
	imgui.render()
}

fn touch_bounds(width f32, mut state TouchState, clear_preview bool) geometry.Bounds {
	for _ in 0 .. 3 {
		$if release_accessibility ? {
			appui.focus(if clear_preview { u64(17) } else { u64(20) })
		} $else {
			geometry.focus('V ImGui: touch and text', if clear_preview {
				'Clear preview'
			} else {
				'##zoom'
			})
		}
		touch_frame(width, mut state)
	}
	return geometry.focused_bounds()
}

fn test_touch_feedback_preserves_following_controls() {
	for scale in [f32(1), 2] {
		for width in [f32(360), 560, 1000] {
			ctx := geometry.context(width, scale)
			$if release_accessibility ? {
				appui.initialize('Touch geometry') or { panic(err) }
				appui.theme(true, false, scale, true)
			}
			mut state := TouchState{}
			for _ in 0 .. 3 {
				touch_frame(width, mut state)
			}
			baselines := [touch_bounds(width, mut state, true),
				touch_bounds(width, mut state, false)]
			for payload in ['', 'Short preview', 'First\nSecond\nThird\nFourth\nFifth\nSixth',
				'Wrapped clipboard text. '.repeat(20)] {
				state.preview = [1024]char{}
				unsafe { vmemcpy(&state.preview[0], payload.str, payload.len) }
				for status in 0 .. 7 {
					window_name := $if release_accessibility ? {
						'Touch geometry'
					} $else {
						'V ImGui: touch and text'
					}
					window := imgui.find_window_by_name(window_name.str)
					id := imgui.im_hash_str(c'##clipboard-status', 0, window.ID)
					imgui.storage_set_int(unsafe { &window.StateStorage }, id, status)
					for index, clear_preview in [true, false] {
						observed := touch_bounds(width, mut state, clear_preview)
						geometry.unchanged(baselines[index], observed,
							'touch scale=${scale} width=${width} status=${status} preview=${payload.len} clear=${clear_preview}')
					}
				}
			}
			for taps in [9, 10, 99, 100, 999, 1000, 1000000] {
				state.taps = taps
				geometry.unchanged(baselines[1], touch_bounds(width, mut state, false),
					'touch scale=${scale} width=${width} taps=${taps}')
			}
			$if release_accessibility ? { appui.shutdown() }
			imgui.destroy_context(ctx)
		}
	}
}
