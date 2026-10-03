module main

import os
import release_tools

fn find_file(root string, names []string, containing string) !string {
	mut files := os.walk_ext(root, '')
	files.sort()
	for file in files {
		if os.file_name(file) in names && file.contains(containing) {
			return file
		}
	}
	return error('Missing build output ${names} in ${root}')
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

fn run() ! {
	if os.args.len != 2 || os.args[1] !in ['docking', 'standard'] {
		return error('Usage: v run scripts/build_release.v docking|standard')
	}
	variant := os.args[1]
	root := os.dir(os.dir(@FILE))
	imgui := if os.getenv('IMGUI_DIR') != '' {
		os.getenv('IMGUI_DIR')
	} else {
		os.join_path(root, 'build', 'modules', 'antono2', 'imgui')
	}
	if os.getenv('VMODULES') == '' {
		os.setenv('VMODULES', os.join_path(root, 'build', 'modules'), true)
	}
	mut compiler := os.getenv('V_BIN')
	if compiler == '' {
		$if windows {
			compiler = os.join_path(@VEXEROOT, 'v.exe')
		} $else {
			compiler = os.join_path(@VEXEROOT, 'v')
		}
	}
	mut native_options := ['run', os.join_path(imgui, 'build_vimgui.vsh'), '--linkage', 'shared']
	mut native_directory := ''
	$if windows {
		native_options << ['--glfw', 'bundled', '--glfw-version', '3.4']
		native_directory = os.join_path(imgui, 'build', 'shared-bundled-3.4')
		if os.getenv('VCToolsRedistDir') == '' {
			return error('Load scripts/setup_windows_build.ps1 before running the builder')
		}
	} $else $if linux {
		native_options << ['--glfw', 'system']
		native_directory = os.join_path(imgui, 'build', 'shared-system-3.3')
		os.setenv('VULKAN_SDK', '/usr', true)
		os.setenv('GLFW_INCLUDE', '/usr/include', true)
		os.setenv('GLFW_LIB', '/usr/lib/x86_64-linux-gnu', true)
	} $else {
		return error('Release builder currently supports Linux and Windows')
	}
	release_tools.command(compiler, native_options)!
	release_tools.command('cmake', ['-S', imgui, '-B', native_directory, '-DVIMGUI_APPLICATION_UI=ON',
		'-DVIMGUI_OUTPUT_DIR=' + os.join_path(imgui, 'lib')])!
	release_tools.command('cmake', ['--build', native_directory, '--config', 'Release', '--parallel',
		'4'])!
	binaries := os.join_path(root, 'build', 'release-binaries-' + variant)
	os.mkdir_all(binaries)!
	mut flags := ['-d', 'release_accessibility', '-d', 'appui_embedded', '-no-memory-limit']
	mut extension := ''
	mut platform := ''
	$if windows {
		header := find_file(native_directory, ['glfw3.h'], 'glfw-src')!
		library := find_file(native_directory, ['glfw3dll.lib', 'glfw3.lib'], '')!
		links := os.join_path(os.getenv('RUNNER_TEMP'), 'link')
		os.mkdir_all(links)!
		release_tools.copy(library, os.join_path(links, 'glfw3.lib'))!
		os.setenv('GLFW_INCLUDE', os.dir(os.dir(header)), true)
		os.setenv('GLFW_LIB', links, true)
		flags << ['-path', os.join_path(root, 'build', 'modules', 'antono2') + '|@vlib|@vmodules',
			'-cc', 'msvc']
		release_tools.copy(find_file(native_directory, ['glfw3.dll'], '')!, os.join_path(binaries, 'glfw3.dll'))!
		release_tools.copy(find_file(os.join_path(imgui, 'lib'), ['vimgui.dll'], '')!, os.join_path(binaries, 'vimgui.dll'))!
		extension = '.exe'
		platform = 'windows'
	} $else {
		flags << ['-cc', 'gcc']
		platform = 'linux'
	}
	for example in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard'] {
		source := if example == 'glfw_vulkan' {
			root
		} else {
			os.join_path(root, 'examples', example)
		}
		mut args := flags.clone()
		args << ['-o', os.join_path(binaries, example + extension), source]
		release_tools.command(compiler, args)!
	}
	output := os.join_path(root, 'build', 'v-imgui-examples-${platform}-x64-${variant}')
	release_tools.package_release(root, binaries, imgui, output, variant)!
	$if linux {
		release_tools.command('bash', [
			os.join_path(root, 'scripts', 'smoke_desktop.sh'),
			output,
		])!
	}
}
