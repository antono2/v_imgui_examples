// Keep the native IME bridge at the Android platform boundary.
module main

import antono2.imgui
import antono2.imgui.impl_android

fn apply_android_text_edit(mut data imgui.InputTextCallbackData) {
	impl_android.apply_text_edit(mut data)
}
