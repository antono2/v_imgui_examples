// Build and run the instrumentation APK against the Android touch example.
import os
import strconv

const application_id = 'io.antono2.vimgui.examples.touch'
const instrument = application_id + '.test/' + application_id + '.test.AccessibilitySmoke'
const minimum_android_api = '24'
const java_bytecode = '8'
const apk_alignment = '4'
const keycode_wakeup = '224'
const usage = 'Usage: v run scripts/test_android_accessibility.vsh'

fn setting(name string, default_value string) string {
	value := os.getenv(name)
	return if value == '' { default_value } else { value }
}

fn version_parts(name string) ![]int {
	version := name.trim_string_left('android-')
	mut result := []int{}
	for part in version.split('.') {
		if part == '' || !part.bytes().all(it.is_digit()) {
			return error('Not a numbered Android SDK entry')
		}
		result << strconv.atoi(part)!
	}
	return result
}

fn newer(candidate []int, current []int) bool {
	count := if candidate.len > current.len { candidate.len } else { current.len }
	for index in 0 .. count {
		left := candidate[index] or { 0 }
		right := current[index] or { 0 }
		if left != right {
			return left > right
		}
	}
	return false
}

fn newest_install(directory string, expected_file string) !string {
	mut best := ''
	mut version := []int{}
	for name in os.ls(directory)! {
		parts := version_parts(name) or { continue }
		path := os.join_path(directory, name)
		if !os.is_file(os.join_path(path, expected_file)) {
			continue
		}
		if best == '' || newer(parts, version) {
			best = path
			version = parts.clone()
		}
	}
	if best == '' {
		return error('No Android SDK installation with ${expected_file} under ${directory}')
	}
	return best
}

fn start(executable string, args []string, cwd string, redirect bool) !&os.Process {
	if !os.is_executable(executable) {
		return error('Expected Android tool at ${executable}')
	}
	mut child := os.new_process(executable)
	child.set_args(args)
	if cwd != '' {
		child.set_work_folder(cwd)
	}
	if redirect {
		child.set_redirect_stdio()
	}
	child.run()
	return child
}

fn command(executable string, args []string, cwd string) ! {
	mut child := start(executable, args, cwd, false)!
	defer { child.close() }
	child.wait()
	if child.code != 0 {
		return error('${os.file_name(executable)} exited with status ${child.code}')
	}
}

fn output(executable string, args []string) !(int, string) {
	mut child := start(executable, args, '', true)!
	defer { child.close() }
	text := child.stdout_slurp()
	diagnostics := child.stderr_slurp()
	child.wait()
	return child.code, text + diagnostics
}

fn device_command(adb string, selector []string, args []string) ! {
	mut arguments := selector.clone()
	arguments << args
	command(adb, arguments, '')!
}

fn run() ! {
	if os.args[1..] in [['--help'], ['-h']] {
		println(usage)
		return
	}
	if os.args.len != 1 {
		return error(usage)
	}
	root := os.dir(@DIR)
	sdk_setting := setting('ANDROID_SDK_ROOT', os.getenv('ANDROID_HOME'))
	if sdk_setting == '' {
		return error('Set ANDROID_SDK_ROOT to an installed Android SDK')
	}
	sdk := os.abs_path(sdk_setting)
	adb := os.join_path(sdk, 'platform-tools', 'adb')
	mut selector := []string{}
	serial := os.getenv('ANDROID_SERIAL')
	if serial != '' {
		selector << ['-s', serial]
	}
	mut abi := os.getenv('ANDROID_ABI')
	if abi == '' {
		mut query := selector.clone()
		query << ['shell', 'getprop', 'ro.product.cpu.abi']
		status, result := output(adb, query)!
		if status != 0 {
			return error('Could not determine the connected Android ABI: ${result.trim_space()}')
		}
		abi = result.trim_space()
	}
	if abi !in ['armeabi-v7a', 'arm64-v8a', 'x86_64'] {
		return error('Unsupported Android ABI: ${abi}')
	}
	build := os.abs_path(setting('VIMGUI_ANDROID_BUILD_DIR',
		os.join_path(root, 'build', 'android-touch-' + abi)))
	tools := newest_install(os.join_path(sdk, 'build-tools'), 'd8')!
	platform := newest_install(os.join_path(sdk, 'platforms'), 'android.jar')!
	android_jar := os.join_path(platform, 'android.jar')
	tests := os.join_path(root, 'tests', 'android', 'accessibility')
	package := os.join_path(build, 'accessibility-test')
	classes := os.join_path(package, 'classes')
	dex := os.join_path(package, 'dex')
	os.mkdir_all(classes)!
	os.mkdir_all(dex)!
	java_compiler := setting('JAVAC', 'javac')
	javac := if os.is_executable(java_compiler) {
		os.abs_path(java_compiler)
	} else {
		os.find_abs_path_of_executable(java_compiler) or {
			return error('Install javac or set JAVAC to a Java compiler')
		}
	}
	command(javac, ['-source', java_bytecode, '-target', java_bytecode, '-Xlint:-options', '-cp',
		android_jar, '-d', classes, os.join_path(tests, 'AccessibilitySmoke.java')], '')!
	mut class_files := os.walk_ext(classes, '.class')
	class_files.sort()
	mut dex_args := ['--min-api', minimum_android_api, '--lib', android_jar, '--output', dex]
	dex_args << class_files
	command(os.join_path(tools, 'd8'), dex_args, '')!
	unsigned := os.join_path(package, 'unsigned.apk')
	aligned := os.join_path(package, 'aligned.apk')
	signed := os.join_path(package, 'test.apk')
	aapt := os.join_path(tools, 'aapt')
	command(aapt, ['package', '-f', '-M', os.join_path(tests, 'AndroidManifest.xml'), '-I',
		android_jar, '-F', unsigned], '')!
	command(aapt, ['add', unsigned, 'classes.dex'], dex)!
	command(os.join_path(tools, 'zipalign'), ['-f', apk_alignment, unsigned, aligned], '')!
	keystore := setting('VIMGUI_ANDROID_TEST_KEYSTORE', os.join_path(build, 'debug.keystore'))
	password_file := os.getenv('VIMGUI_ANDROID_TEST_PASSWORD_FILE')
	password := if password_file == '' { 'pass:android' } else { 'file:' + password_file }
	signer := os.join_path(tools, 'apksigner')
	command(signer, ['sign', '--ks', keystore, '--ks-pass', password, '--out', signed, aligned], '')!
	command(signer, ['verify', signed], '')!
	device_command(adb, selector, ['shell', 'input', 'keyevent', keycode_wakeup])!
	device_command(adb, selector, ['shell', 'wm', 'dismiss-keyguard'])!
	device_command(adb, selector, ['shell', 'am', 'force-stop', application_id])!
	application := setting('VIMGUI_ANDROID_TEST_APK', os.join_path(build, 'vimgui-demo-${abi}.apk'))
	device_command(adb, selector, ['install', '-r', application])!
	device_command(adb, selector, ['install', '-r', signed])!
	mut arguments := selector.clone()
	arguments << ['shell', 'am', 'instrument', '-w', instrument]
	status, captured := output(adb, arguments)!
	log_path := os.join_path(package, 'instrumentation.log')
	os.write_file(log_path, captured)!
	print(captured)
	if status != 0 || !captured.contains('result=PASS:') {
		return error('Android accessibility instrumentation failed. See ${log_path}')
	}
}

run() or {
	eprintln(err)
	exit(1)
}
