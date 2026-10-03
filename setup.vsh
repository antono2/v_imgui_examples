#!/usr/bin/env -S v run

// Guided setup, build and run; explicit flags also support automation.
import os

fn run(command string) ! {
	println('\n> ${command}')
	code := os.system(command)
	if code != 0 {
		return error('command failed with exit code ${code}; see the output above')
	}
}

fn ask(prompt string) !string {
	return (os.input_opt(prompt) or { return error('Input closed. Use explicit flags for noninteractive runs.') }).trim_space()
}

fn confirm(prompt string) !bool {
	return (ask(prompt + ' [y/N]: ')!).to_lower() in ['y', 'yes']
}

fn android_environment(interactive bool) ! {
	mut sdk := os.getenv('ANDROID_SDK_ROOT')
	if sdk == '' {
		sdk = os.getenv('ANDROID_HOME')
	}
	if sdk == '' {
		for candidate in [os.join_path(os.home_dir(), 'Android', 'Sdk'),
			os.join_path(os.home_dir(), 'Library', 'Android', 'sdk'),
			os.join_path(os.getenv('LOCALAPPDATA'), 'Android', 'Sdk')] {
			if os.is_dir(candidate) {
				sdk = candidate
				break
			}
		}
	}
	if sdk == '' && interactive {
		sdk = ask('Android SDK directory: ')!
	}
	if !os.is_dir(sdk) {
		return error('Android SDK not found. Set ANDROID_SDK_ROOT to an installed SDK; see examples/android_touch/README.md.')
	}
	if !os.is_file(os.join_path(sdk, 'platforms', 'android-36', 'android.jar')) || !os.is_dir(os.join_path(sdk, 'build-tools', '36.0.0')) {
		return error('Install Android SDK Platform 36 and Build-Tools 36.0.0 using the SDK Manager, then retry.')
	}
	os.setenv('ANDROID_SDK_ROOT', sdk, true)
	mut ndk := os.getenv('ANDROID_NDK_HOME')
	if ndk == '' {
		ndk = os.getenv('ANDROID_NDK_ROOT')
	}
	if ndk == '' {
		ndk_directory := os.join_path(sdk, 'ndk')
		if os.is_dir(ndk_directory) {
			mut versions := os.ls(ndk_directory)!
			versions = versions.filter(os.is_file(os.join_path(ndk_directory, it, 'build', 'cmake', 'android.toolchain.cmake')))
			versions.sort()
			if versions.len == 1 {
				ndk = os.join_path(ndk_directory, versions[0])
			} else if versions.len > 1 && interactive {
				println('Installed NDKs:')
				for i, version in versions {
					println('${i + 1}. ${version}')
				}
				choice := ask('Choose an NDK number: ')!
				if choice.int() < 1 || choice.int() > versions.len {
					return error('Invalid NDK choice')
				}
				ndk = os.join_path(ndk_directory, versions[choice.int() - 1])
			}
		}
	}
	if ndk == '' && interactive {
		ndk = ask('Android NDK directory: ')!
	}
	if !os.is_file(os.join_path(ndk, 'build', 'cmake', 'android.toolchain.cmake')) {
		return error('Android NDK not found. Set ANDROID_NDK_HOME to an installed NDK.')
	}
	os.setenv('ANDROID_NDK_HOME', ndk, true)
	os.setenv('PATH', os.join_path(sdk, 'platform-tools') + os.path_delimiter + os.getenv('PATH'), true)
}

fn android_device(interactive bool) ! {
	if !os.exists_in_system_path('adb') {
		return error('Install Android SDK Platform-Tools before installing on a device.')
	}
	result := os.execute('adb devices')
	if result.exit_code != 0 {
		return error('Could not list Android devices: ${result.output}')
	}
	mut devices := []string{}
	for line in result.output.split_into_lines() {
		parts := line.fields()
		if parts.len == 2 && parts[1] == 'device' { devices << parts[0] }
	}
	if devices.len == 0 {
		return error('No authorized device. Connect it, enable USB debugging and accept its authorization prompt, then retry.')
	}
	mut serial := os.getenv('ANDROID_SERIAL')
	if serial != '' && serial !in devices {
		return error('ANDROID_SERIAL is not an authorized connected device.')
	}
	if serial == '' && devices.len == 1 {
		serial = devices[0]
	}
	if serial == '' && interactive {
		for i, device in devices {
			println('${i + 1}. ${device}')
		}
		choice := ask('Choose a device number: ')!
		if choice.int() < 1 || choice.int() > devices.len {
			return error('Invalid device choice')
		}
		serial = devices[choice.int() - 1]
	}
	if serial == '' {
		return error('Several devices are connected. Set ANDROID_SERIAL to choose one.')
	}
	os.setenv('ANDROID_SERIAL', serial, true)
	println('Device: ${serial}')
}

fn guided_main() ! {
	project_dir := os.dir(os.real_path(@FILE))
	// Keep upstream setup and compilation on the same V compiler as this runner.
	os.setenv('PATH', @VEXEROOT + os.path_delimiter + os.getenv('PATH'), true)
	mut mode := '--install'
	mut example := 'glfw_vulkan'
	interactive := os.args.len == 1
	mut launch := false
	if interactive {
		println('V ImGui examples\n\n1. Widget gallery — controls, tables and popups (default)\n2. ImPlot dashboard — interactive plots\n3. GLFW/Vulkan — windows and backend demonstration\n4. Android touch and text — device app\nQ. Quit\n')
		choice := (ask('Choose an example [1]: ')!).to_lower()
		match choice {
			'', '1' { example = 'widget_gallery' }
			'2' { example = 'implot_dashboard' }
			'3' { example = 'glfw_vulkan' }
			'4' { example = 'android_touch' }
			'q' { return }
			else { return error('Choose 1, 2, 3, 4 or Q.') }
		}
		launch = true
	}
	mut index := 1
	for index < os.args.len {
		arg := os.args[index]
		if arg in ['--install', '--check', '--build-only'] {
			mode = arg
		} else if arg == '--run' {
			launch = true
		} else if arg == '--example' && index + 1 < os.args.len {
			index++
			example = os.args[index]
		} else if arg in ['-h', '--help'] {
			println('Usage: v run setup.vsh [--install|--check|--build-only] [--run] [--example glfw_vulkan|widget_gallery|implot_dashboard|android_touch]\nNo arguments: guided setup, build and launch. Explicit flags skip menus; system installers may request administrator authorization. --check makes no changes.')
			return
		} else {
			eprintln('Unknown or incomplete option: ${arg}')
			exit(2)
		}
		index++
	}
	if example !in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard', 'android_touch'] {
		return error('Unknown example: ${example}. Use --help for choices.')
	}
	if mode == '--check' && launch {
		return error('--check cannot be combined with --run.')
	}
	source := if example == 'glfw_vulkan' {
		project_dir
	} else {
		os.join_path(project_dir, 'examples', example)
	}
	module_dir := if os.getenv('VMODULES') == '' {
		os.join_path(project_dir, 'build', 'modules')
	} else {
		os.vmodules_dir()
	}
	os.setenv('VMODULES', module_dir, true)
	imgui_root := os.join_path(module_dir, 'antono2', 'imgui')
	revision := (os.read_file(os.join_path(project_dir, 'IMGUI_REVISION')) or { return err }).trim_space()
	if revision.len != 40 || !revision.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('IMGUI_REVISION must contain a full lowercase Git commit SHA')
	}
	mut example_binary := os.join_path(project_dir, 'build', example)
	$if windows {
		example_binary = os.join_path(imgui_root, 'build', 'windows-demo', example + '.exe')
	}
	if interactive && example != 'android_touch' && os.is_file(example_binary) {
		choice := (ask('Existing build: run [Enter], rebuild [b], prepare dependencies again [s], or quit [q]: ')!).to_lower()
		match choice {
			'' {
				run(os.quoted_path(example_binary))!
				return
			}
			'b' { mode = '--build-only' }
			's' {}
			'q' { return }
			else { return error('Choose Enter, b, s or q.') }
		}
	}
	if example == 'android_touch' {
		android_environment(interactive)!
		for tool in ['bash', 'git', 'cmake', 'ninja', 'java', 'javac'] {
			if !os.exists_in_system_path(tool) {
				return error('Missing ${tool}. Install it and retry; see examples/android_touch/README.md.')
			}
		}
		if launch { android_device(interactive)! }
		if mode == '--check' {
			println('Android tools and SDK/NDK paths are available.')
			return
		}
		if !launch && os.getenv('ANDROID_ABI') == '' {
			return error('Set ANDROID_ABI to armeabi-v7a, arm64-v8a or x86_64 for a build without a device.')
		}
		if interactive && !confirm('Build a debug APK and install/open it on this device? Dependencies may be downloaded; an installed app with a different signing key must be removed manually.')! {
			return
		}
		os.setenv('IMGUI_DIR', imgui_root, true)
		os.setenv('VIMGUI_ANDROID_APPLICATION_UI', '1', true)
		run('bash ${os.quoted_path(os.join_path(project_dir, 'scripts', 'build_android.sh'))} ${if launch {
			'run'
		} else {
			'--build-only'
		}}')!
		return
	}
	if !os.exists_in_system_path('git') {
		return error('Git is required. Install Git, then run setup again.')
	}
	if interactive && mode == '--install' {
		println('Prerequisites: V and Git are available.')
		if !os.exists_in_system_path('cmake') {
			println('CMake is missing. The upstream setup will install it on supported systems or show installation instructions.')
		}
		println('Setup will download pinned dependencies into ${module_dir} and build ${example}.\nThe upstream setup may install system packages (and request administrator access). Compilation can require about 11 GiB of RAM or swap.')
		if !confirm('Continue with setup, build and launch?')! {
			return
		}
	}
	if mode == '--check' && !os.is_file(os.join_path(imgui_root, 'v.mod')) {
		return error('Pinned dependencies are not prepared. Run the guided setup or --install first; no files were changed.')
	}
	if mode == '--install' {
		os.mkdir_all(os.dir(imgui_root)) or { return err }
		if !os.is_file(os.join_path(imgui_root, 'v.mod')) {
			run('git clone https://github.com/antono2/imgui.git ${os.quoted_path(imgui_root)}') or { return err }
		}
		// Never discard changes in an existing dependency checkout.
		status := os.execute('git -C ${os.quoted_path(imgui_root)} status --porcelain')
		if status.exit_code != 0 || status.output.trim_space() != '' {
			return error('ImGui dependency checkout contains changes; commit them or use a fresh VMODULES directory')
		}
		run('git -C ${os.quoted_path(imgui_root)} fetch origin ${revision.trim_space()}') or { return err }
		run('git -C ${os.quoted_path(imgui_root)} checkout --detach ${revision.trim_space()}') or { return err }
	}
	current := os.execute('git -C ${os.quoted_path(imgui_root)} rev-parse HEAD')
	if current.exit_code != 0 || current.output.trim_space() != revision.trim_space() {
		return error('ImGui must match IMGUI_REVISION; run --install with a clean dependency checkout')
	}
	imgui_setup := os.join_path(imgui_root, 'setup.vsh')
	if !os.is_file(imgui_setup) {
		return error('Run setup.vsh --install first to prepare the pinned ImGui dependency')
	}
	if mode != '--build-only' {
		run('v run ${os.quoted_path(imgui_setup)} ${mode}') or { return err }
	}
	if mode == '--check' {
		return
	}
	os.mkdir_all(os.join_path(project_dir, 'build')) or { return err }
	$if windows {
		vulkan_sdk :=
			os.execute('powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable(\'VULKAN_SDK\', \'Machine\')"')
		if vulkan_sdk.exit_code == 0 && vulkan_sdk.output.trim_space() != '' {
			os.setenv('VULKAN_SDK', vulkan_sdk.output.trim_space(), true)
		}
		runner := os.join_path(imgui_root, 'scripts', 'run_demo_windows.ps1')
		run('powershell -NoProfile -ExecutionPolicy Bypass -File ${os.quoted_path(runner)} -BuildOnly -DemoDirectory ${os.quoted_path(project_dir)} -DemoSource ${os.quoted_path(source)}') or {
			return err
		}
		os.cp(os.join_path(imgui_root, 'build', 'windows-demo', 'v_imgui_demo.exe'), example_binary)!
	} $else {
		$if linux {
			os.setenv('VULKAN_SDK', '/usr', false)
			os.setenv('GLFW_INCLUDE', '/usr/include', false)
			if os.getenv('GLFW_LIB') == '' && os.is_dir('/usr/lib/x86_64-linux-gnu') {
				os.setenv('GLFW_LIB', '/usr/lib/x86_64-linux-gnu', false)
			} else if os.getenv('GLFW_LIB') == '' {
				os.setenv('GLFW_LIB', '/usr/lib64', false)
			}
		} $else $if macos {
			prefix := os.execute('brew --prefix glfw').output.trim_space()
			os.setenv('GLFW_INCLUDE', os.join_path(prefix, 'include'), true)
			os.setenv('GLFW_LIB', os.join_path(prefix, 'lib'), true)
		}
		module_path := '${module_dir}/antono2|@vlib|@vmodules'
		staged_binary := example_binary + '.building'
		if os.exists(staged_binary) { os.rm(staged_binary)! }
		run('v -no-memory-limit -path ${os.quoted_path(module_path)} -o ${os.quoted_path(staged_binary)} ${os.quoted_path(source)}') or {
			return err
		}
		if !os.is_file(staged_binary) {
			return error('The compiler did not produce an executable. Review its output above.')
		}
		os.mv(staged_binary, example_binary)!
	}
	println('\nBuilt ${example_binary}')
	if launch { run(os.quoted_path(example_binary))! }
}

fn main() {
	guided_main() or {
		eprintln('\n${err}')
		exit(1)
	}
}
