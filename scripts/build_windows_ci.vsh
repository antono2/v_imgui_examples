// Build the guided Windows example and the additional desktop CI examples.
import os
import release_tools

const direct_examples = ['widget_gallery', 'implot_dashboard']
const usage = 'Usage: v run scripts/build_windows_ci.vsh ARTIFACT_DIRECTORY'

fn run(args []string) ! {
	if args in [['--help'], ['-h']] {
		println(usage)
		return
	}
	if args.len != 1 || args[0] == '' {
		return error(usage)
	}
	if os.user_os() != 'windows' {
		return error('This check requires Windows and the MSVC x64 toolchain.')
	}
	modules := os.getenv('VMODULES')
	if modules == '' {
		return error('Set VMODULES to the pinned dependency checkout directory.')
	}
	root := os.dir(@DIR)
	output := os.abs_path(args[0])
	imgui := os.join_path(modules, 'antono2', 'imgui')
	glfw := release_tools.glfw_pin(root)!
	setup := os.join_path(root, 'setup.vsh')
	release_tools.command(@VEXE, ['-check-syntax', setup])!
	release_tools.command(@VEXE, ['run', os.join_path(imgui, 'build_vimgui.vsh'), '--linkage',
		'shared', '--glfw', 'bundled', '--glfw-version', glfw])!

	native := os.join_path(imgui, 'build', 'shared-bundled-${glfw}')
	header := release_tools.find_file(native, ['glfw3.h'], 'glfw-src')!
	library := release_tools.find_file(native, ['glfw3dll.lib', 'glfw3.lib'], '')!
	link_directory := os.join_path(os.dir(output), 'link')
	release_tools.copy(library, os.join_path(link_directory, 'glfw3.lib'))!
	os.setenv('GLFW_INCLUDE', os.dir(os.dir(header)), true)
	os.setenv('GLFW_LIB', link_directory, true)

	os.mkdir_all(output)!
	release_tools.command(@VEXE, ['run', setup, '--build-only', '--example', 'glfw_vulkan'])!
	release_tools.copy(os.join_path(imgui, 'build', 'windows-demo', 'glfw_vulkan.exe'),
		os.join_path(output, 'glfw_vulkan.exe'))!
	module_path := '${os.join_path(modules, 'antono2')}|@vlib|@vmodules'
	for example in direct_examples {
		binary := os.join_path(output, '${example}.exe')
		release_tools.command(@VEXE, ['-no-memory-limit', '-path', module_path, '-cc', 'msvc',
			'-o', binary, os.join_path(root, 'examples', example)])!
		if !os.is_file(binary) {
			return error('Missing compiled Windows example: ${binary}')
		}
	}
	release_tools.copy(release_tools.find_file(native, ['glfw3.dll'], '')!,
		os.join_path(output, 'glfw3.dll'))!
	release_tools.copy(release_tools.find_file(os.join_path(imgui, 'lib'), ['vimgui.dll'], '')!,
		os.join_path(output, 'vimgui.dll'))!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
