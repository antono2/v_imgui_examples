#!/usr/bin/env -S v run

// Run real demo layouts without a platform window, GPU or accessibility adapter.
// Requires the release build's native imgui library with application UI enabled.
import os

os.chdir(@VMODROOT)!
os.setenv('VFLAGS', '-gc none', true)
for accessible in [false, true] {
	for demo in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard', 'android_touch'] {
		if accessible && demo !in ['widget_gallery', 'android_touch'] {
			continue
		}
		flags := if accessible { '-d release_accessibility' } else { '' }
		command := '${os.quoted_path(@VEXE)} -gc none -cc gcc -d appui_embedded ${flags} test examples/${demo}'
		println('Checking ${demo}, accessible=${accessible}')
		if os.system(command) != 0 { exit(1) }
	}
}
