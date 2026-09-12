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
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] !in ['--install', '--check', '-h', '--help']) {
		eprintln('Usage: v run setup.vsh [--install|--check]')
		exit(2)
	}
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('Usage: v run setup.vsh [--install|--check]\n\nDefault: install and build ImGui, then compile this example.\n--check: run read-only dependency diagnostics.')
		return
	}
	install := os.args.len == 1 || os.args[1] == '--install'
	if install {
		run('v install antono2.imgui') or { panic(err) }
	}
	imgui_root := os.join_path(os.vmodules_dir(), 'antono2', 'imgui')
	imgui_setup := os.join_path(imgui_root, 'setup.vsh')
	if !os.is_file(imgui_setup) {
		eprintln('antono2.imgui does not include setup.vsh; install or update it first')
		exit(1)
	}
	mode := if install { '--install' } else { '--check' }
	run('v run ${os.quoted_path(imgui_setup)} ${mode}') or { panic(err) }
	if !install {
		return
	}
	project_dir := os.dir(os.real_path(@FILE))
	$if windows {
		vulkan_sdk := os.execute(
			'powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable(\'VULKAN_SDK\', \'Machine\')"',
		)
		if vulkan_sdk.exit_code == 0 && vulkan_sdk.output.trim_space() != '' {
			os.setenv('VULKAN_SDK', vulkan_sdk.output.trim_space(), true)
		}
		runner := os.join_path(imgui_root, 'scripts', 'run_demo_windows.ps1')
		run('powershell -NoProfile -ExecutionPolicy Bypass -File ${os.quoted_path(runner)} -BuildOnly -DemoDirectory ${os.quoted_path(project_dir)}') or {
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
		executable := os.join_path(os.temp_dir(), 'v_imgui_demo_setup')
		module_path := '${os.vmodules_dir()}/antono2|@vlib|@vmodules'
		run('v -no-memory-limit -path ${os.quoted_path(module_path)} -o ${os.quoted_path(executable)} ${os.quoted_path(project_dir)}') or {
			panic(err)
		}
	}
	println('\nThe ImGui example compiled successfully. Run `v -no-memory-limit run .` from this checkout to open it.')
}
