// Reserve the layout height of a finite set of wrapped feedback messages.
module feedback

import antono2.imgui
import math

// Call immediately after drawing current, including its empty-string line.
// Keep the actual text and accessibility bounds; reserve only the unused space.
pub fn reserve_wrapped_text(current string, alternatives []string) {
	width := math.max(f32(1), imgui.get_content_region_avail().x)
	actual := imgui.calc_text_size(current.str, unsafe { nil }, false, width).y
	mut reserved := actual
	for text in alternatives {
		reserved = math.max(reserved,
			imgui.calc_text_size(text.str, unsafe { nil }, false, width).y)
	}
	if reserved > actual { imgui.set_cursor_pos_y(imgui.get_cursor_pos_y() + reserved - actual) }
}
