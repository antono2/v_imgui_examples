// Android build directories and SDK pins shared by the example and CI.
module androidci

import os

pub const ndk_release = '27.3.13750724'
pub const build_tools_release = '36.0.0'
pub const android_platform = 'android-36'

pub fn setting(name string, default_value string) string {
	value := os.getenv(name)
	return if value == '' { default_value } else { value }
}

pub fn host_directory(root string) string {
	return os.abs_path(setting('IMGUI_DIR', os.join_path(root, 'build', 'android-host', 'antono2',
		'imgui')))
}

pub fn build_directory(root string) string {
	return os.abs_path(setting('VIMGUI_ANDROID_BUILD_DIR', os.join_path(root, 'build',

		'android-touch-' + setting('ANDROID_ABI', 'device'))))
}

pub fn sdk_directory() !string {
	configured := setting('ANDROID_SDK_ROOT', os.getenv('ANDROID_HOME'))
	if configured == '' || !os.is_dir(configured) {
		return error('Set ANDROID_SDK_ROOT to an installed Android SDK.')
	}
	return os.abs_path(configured)
}
