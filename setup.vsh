#!/usr/bin/env -S v run

// Installs/builds antono2.imgui and compiles this graphical example. It does
// not launch a window; run the example normally after setup to see it.
import os

fn run(command string) ! {
	println('\n> ${command}')
	result := os.execute(command)
	if result.output.trim_space() != '' {
		println(result.output.trim_right('\r\n'))
	}
	if result.exit_code != 0 {
		return error('command failed with exit code ${result.exit_code}')
	}
}

fn main() {
	project_dir := os.dir(os.real_path(@FILE))
	mut mode := '--install'
	mut example := 'glfw_vulkan'
	mut index := 1
	for index < os.args.len {
		arg := os.args[index]
		if arg in ['--install', '--check', '--build-only'] {
			mode = arg
		} else if arg == '--example' && index + 1 < os.args.len {
			index++
			example = os.args[index]
		} else if arg in ['-h', '--help'] {
			println('Usage: v run setup.vsh [--install|--check|--build-only] [--example glfw_vulkan|widget_gallery|implot_dashboard]')
			return
		} else {
			eprintln('Unknown or incomplete option: ${arg}')
			exit(2)
		}
		index++
	}
	if example !in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard'] {
		eprintln('Unknown desktop example: ${example}. For Android, use scripts/build_android.sh.')
		exit(2)
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
	revision := os.read_file(os.join_path(project_dir, 'IMGUI_REVISION')) or { panic(err) }
	if mode == '--install' {
		os.mkdir_all(os.dir(imgui_root)) or { panic(err) }
		if !os.is_file(os.join_path(imgui_root, 'v.mod')) {
			run('git clone https://github.com/antono2/imgui.git ${os.quoted_path(imgui_root)}') or { panic(err) }
		}
		// Never discard changes in an existing dependency checkout.
		status := os.execute('git -C ${os.quoted_path(imgui_root)} status --porcelain')
		if status.exit_code != 0 || status.output.trim_space() != '' {
			panic('ImGui dependency checkout contains changes; commit them or use a fresh VMODULES directory')
		}
		run('git -C ${os.quoted_path(imgui_root)} fetch origin ${revision.trim_space()}') or { panic(err) }
		run('git -C ${os.quoted_path(imgui_root)} checkout --detach ${revision.trim_space()}') or { panic(err) }
	}
	current := os.execute('git -C ${os.quoted_path(imgui_root)} rev-parse HEAD')
	if current.exit_code != 0 || current.output.trim_space() != revision.trim_space() {
		panic('ImGui must match IMGUI_REVISION; run --install with a clean dependency checkout')
	}
	imgui_setup := os.join_path(imgui_root, 'setup.vsh')
	if !os.is_file(imgui_setup) {
		panic('Run setup.vsh --install first to prepare the pinned ImGui dependency')
	}
	if mode != '--build-only' {
		run('v run ${os.quoted_path(imgui_setup)} ${mode}') or { panic(err) }
	}
	if mode == '--check' {
		return
	}
	$if windows {
		vulkan_sdk :=
			os.execute('powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable(\'VULKAN_SDK\', \'Machine\')"')
		if vulkan_sdk.exit_code == 0 && vulkan_sdk.output.trim_space() != '' {
			os.setenv('VULKAN_SDK', vulkan_sdk.output.trim_space(), true)
		}
		runner := os.join_path(imgui_root, 'scripts', 'run_demo_windows.ps1')
		run('powershell -NoProfile -ExecutionPolicy Bypass -File ${os.quoted_path(runner)} -BuildOnly -DemoDirectory ${os.quoted_path(project_dir)} -DemoSource ${os.quoted_path(source)}') or {
			panic(err)
		}
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
		executable := os.join_path(project_dir, 'build', example)
		module_path := '${module_dir}/antono2|@vlib|@vmodules'
		run('v -no-memory-limit -path ${os.quoted_path(module_path)} -o ${os.quoted_path(executable)} ${os.quoted_path(source)}') or {
			panic(err)
		}
	}
	println('\nBuilt ${example}. On Linux/macOS, run build/${example}; on Windows, run the executable reported above.')
}
