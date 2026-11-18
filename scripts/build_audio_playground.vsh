// Build the desktop audio example with isolated, pinned V and native dependencies.
import flag
import os
import x.json2

$if windows {
	#include <windows.h>
}

fn C.MoveFileExW(source &u16, destination &u16, flags u32) int

const windows_runtime_dlls = ['libstdc++-6.dll', 'libgcc_s_seh-1.dll', 'libwinpthread-1.dll']
const native_build_jobs = '2'

struct Pins {
	v       string
	vc      string
	modules map[string]string
}

struct Tools {
	cc  string
	cxx string
	ar  string
}

fn env_or(name string, fallback string) string {
	value := os.getenv(name)
	return if value == '' { fallback } else { value }
}

fn prerequisites() !Tools {
	windows := os.user_os() == 'windows'
	tools := Tools{
		cc:  env_or('ANTONO2_AUDIO_V_CC', if windows { 'gcc' } else { 'cc' })
		cxx: env_or('CXX', if windows { 'g++' } else { 'c++' })
		ar:  env_or('ANTONO2_AUDIO_AR', 'ar')
	}
	for tool in ['git', 'cmake', tools.cc, tools.cxx, tools.ar, if windows {
		'ninja'
	} else {
		'pkg-config'
	}] {
		os.find_abs_path_of_executable(tool) or {
			return error('Missing ${tool}. See docs/audio-playground.md.')
		}
	}
	if !windows && os.exec(['pkg-config', '--exists', 'glfw3']).exit_code != 0 {
		return error('Missing GLFW development package. See docs/audio-playground.md.')
	}
	return tools
}

fn run(argv []string, environment map[string]string) ! {
	executable_path := os.find_abs_path_of_executable(argv[0]) or {
		return error('Missing executable: ${argv[0]}')
	}
	mut process := os.new_process(executable_path)
	process.set_args(argv[1..])
	process.set_environment(environment)
	process.wait()
	defer { process.close() }
	if process.code != 0 {
		return error('${argv[0]} exited with status ${process.code}')
	}
}

fn output(argv []string) !string {
	result := os.exec(argv)
	if result.exit_code != 0 {
		return error('${argv[0]} exited with status ${result.exit_code}\n${result.output}')
	}
	return result.output.trim_space()
}

fn checkout(repository string, revision string, directory string, environment map[string]string) ! {
	os.mkdir_all(os.dir(directory))!
	if !os.exists(os.join_path(directory, '.git')) {
		if os.is_dir(directory) && os.ls(directory)!.len > 0 {
			return error('Refusing to overwrite non-Git dependency: ${directory}')
		}
		run(['git', 'init', '--quiet', directory], environment)!
		run(['git', '-C', directory, 'remote', 'add', 'origin', 'https://github.com/${repository}.git'], environment)!
	}
	if output(['git', '-C', directory, 'status', '--porcelain', '--untracked-files=no'])! != '' {
		return error('Dependency has local changes: ${directory}')
	}
	current := output(['git', '-C', directory, 'rev-parse', 'HEAD']) or { '' }
	if current != revision {
		run(['git', '-C', directory, 'fetch', '--depth', '1', 'origin', revision], environment)!
		run(['git', '-C', directory, 'checkout', '--quiet', '--detach', 'FETCH_HEAD'], environment)!
	}
}

fn prepare_compiler(root string, pins Pins, tools Tools, environment map[string]string) !string {
	toolchain := os.join_path(root, 'build', 'audio', 'toolchain', 'v')
	bootstrap := os.join_path(toolchain, 'vc')
	checkout('vlang/v', pins.v, toolchain, environment)!
	checkout('vlang/vc', pins.vc, bootstrap, environment)!
	windows := os.user_os() == 'windows'
	compiler := os.join_path(toolchain, if windows { 'v-audio.exe' } else { 'v-audio' })
	if !os.is_file(compiler) {
		// Use the pinned compatibility compiler for the desktop event loop and GC.
		mut command := [tools.cc, '-DCUSTOM_DEFINE_v1_fallback', '-w', '-o', compiler]
		if windows {
			command << ['-std=c99', '-municode', os.join_path(bootstrap, 'v_win.c'), '-ladvapi32',
				'-lws2_32', '-lbcrypt', '-Wl,--stack=33554432']
		} else {
			command << ['-std=gnu11', os.join_path(bootstrap, 'v.c'), '-lm', '-lpthread']
		}
		run(command, environment)!
	}
	return compiler
}

fn build_imgui(root string, modules string, imgui string, tools Tools, environment map[string]string) !string {
	config := os.join_path(root, 'build', 'audio', 'cmake', 'Vulkan')
	os.mkdir_all(config)!
	headers :=
		os.join_path(modules, 'antono2', 'vulkan', 'c', 'vendor', 'include').replace('\\', '/')
	// Supply the headers-only Vulkan target expected by the Volk-backed ImGui build.
	os.write_file(os.join_path(config, 'VulkanConfig.cmake'), 'set(Vulkan_FOUND TRUE)
set(Vulkan_INCLUDE_DIRS "${headers}")
if(NOT TARGET Vulkan::Headers)
  add_library(Vulkan::Headers INTERFACE IMPORTED)
  set_target_properties(Vulkan::Headers PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${headers}")
endif()
')!
	native := os.join_path(imgui, 'build', 'audio-playground')
	mut command := ['cmake', '-S', imgui, '-B', native, '-DCMAKE_BUILD_TYPE=Release',
		'-DCMAKE_C_COMPILER=${tools.cc}', '-DCMAKE_CXX_COMPILER=${tools.cxx}', '-DVIMGUI_OUTPUT_DIR=${os.join_path(imgui, 'lib')}',
		'-DCIMGUI_NO_EXPORT=OFF', '-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON', '-DVulkan_DIR=${config}']
	if os.user_os() == 'windows' {
		command << ['-G', 'Ninja', '-DVIMGUI_GLFW_PROVIDER=bundled', '-DVIMGUI_GLFW_VERSION=3.4']
	} else {
		command << '-DVIMGUI_GLFW_PROVIDER=system'
	}
	run(command, environment)!
	run(['cmake', '--build', native, '--config', 'Release', '--parallel', native_build_jobs],
		environment)!
	return native
}

fn configure_glfw(root string, native string, mut environment map[string]string) ! {
	if os.user_os() == 'windows' {
		deps := os.join_path(native, '_deps')
		headers :=
			os.walk_ext(deps, '.h').filter(it.replace('\\', '/').ends_with('/include/GLFW/glfw3.h'))
		imports := os.walk_ext(deps, '.a').filter(os.file_name(it) in [
			'libglfw3dll.a',
			'libglfw3.dll.a',
			'glfw3dll.a',
		])
		if headers.len == 0 || imports.len != 1 {
			return error('Expected a GLFW header and one import archive in ${deps}')
		}
		libraries := os.join_path(root, 'build', 'audio', 'windows-libs')
		os.mkdir_all(libraries)!
		// V links libglfw3.a. Give the generated import archive that name in the build directory.
		os.cp(imports[0], os.join_path(libraries, 'libglfw3.a'))!
		environment['GLFW_INCLUDE'] = os.dir(os.dir(headers[0]))
		environment['GLFW_LIB'] = libraries
	} else {
		environment['GLFW_INCLUDE'] = output(['pkg-config', '--variable=includedir', 'glfw3'])!
		environment['GLFW_LIB'] = output(['pkg-config', '--variable=libdir', 'glfw3'])!
	}
}

fn replace_binary(staging string, destination string) ! {
	$if windows {
		if C.MoveFileExW(staging.to_wide(), destination.to_wide(), u32(C.MOVEFILE_REPLACE_EXISTING)) == 0 {
			return error('Could not publish ${destination}')
		}
	} $else {
		os.rename(staging, destination)!
	}
}

fn copy_windows_runtime(imgui string, native string, cc string, destination string) ! {
	mut libraries := os.walk_ext(os.join_path(imgui, 'lib'), '.dll')
	libraries << os.walk_ext(native, 'glfw3.dll')
	compiler := os.find_abs_path_of_executable(cc) or { return error('Missing compiler ${cc}') }
	for name in windows_runtime_dlls {
		path := os.join_path(os.dir(compiler), name)
		if os.is_file(path) {
			libraries << path
		}
	}
	for library in libraries {
		os.cp(library, os.join_path(destination, os.file_name(library)))!
	}
}

fn build(root string, modules string, compiler_arg string, tools Tools, test_model bool, launch bool) ! {
	example := os.join_path(root, 'examples', 'audio_playground')
	pins := json2.decode[Pins](os.read_file(os.join_path(example, 'dependencies.json'))!)!
	mut environment := os.environ()
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['V_MACOS_V3_NO_FALLBACK'] = '1'
	environment.delete('VFLAGS')
	// A V script inherits its launcher's VEXE. Use the selected compiler's own vlib.
	environment.delete('VEXE')
	antono2 := os.join_path(modules, 'antono2')
	for name, revision in pins.modules {
		checkout('antono2/${name}', revision, os.join_path(antono2, name), environment)!
	}
	imgui := os.join_path(antono2, 'imgui')
	audio := os.join_path(antono2, 'audio')
	run(['git', '-C', imgui, 'submodule', 'update', '--init', '--recursive', '--depth', '1', 'cimgui',
		'cimplot'], environment)!
	compiler := if compiler_arg == '' {
		prepare_compiler(root, pins, tools, environment)!
	} else {
		os.abs_path(compiler_arg)
	}
	native := build_imgui(root, modules, imgui, tools, environment)!
	environment['VMODULES'] = modules
	environment['ANTONO2_AUDIO_V_CC'] = tools.cc
	environment['ANTONO2_AUDIO_CC'] = tools.cc
	environment['ANTONO2_AUDIO_AR'] = tools.ar
	configure_glfw(root, native, mut environment)!
	run([compiler, '-cc', tools.cc, '-gc', 'none', 'run',
		os.join_path(audio, 'scripts', 'build_native_audio.vsh')], environment)!
	directory := os.join_path(root, 'build')
	os.mkdir_all(directory)!
	suffix := if os.user_os() == 'windows' { '.exe' } else { '' }
	player := os.join_path(directory, 'audio_playground' + suffix)
	staging := os.join_path(directory, 'audio_playground.building' + suffix)
	mut args := [compiler, '-no-memory-limit', '-gc', 'boehm', '-d', 'use_bundled_libgc', '-cc',
		tools.cc]
	match os.user_os() {
		'linux' { args << ['-ldflags', '-lm'] }
		'macos' { args << ['-ldflags', '-Wl,-rpath,${os.join_path(imgui, 'lib')}'] }
		else {}
	}

	args << ['-path', '${antono2}|@vlib|@vmodules', '-o', staging, example]
	run(args, environment)!
	replace_binary(staging, player)!
	if os.user_os() == 'windows' {
		copy_windows_runtime(imgui, native, tools.cc, directory)!
	}
	if test_model {
		// The help command also checks that the executable can load its libraries.
		run([player, '--help'], environment)!
		run([compiler, '-gc', 'boehm', '-d', 'use_bundled_libgc', '-cc', tools.cc,
			os.join_path(example, 'model', 'model_test.v')], environment)!
	}
	println('Built ${player}')
	if launch {
		run([player], environment)!
	}
}

fn run_cli(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('build_audio_playground')
	parser.description('Build the audio example with isolated pinned dependencies.')
	root := os.dir(@DIR)
	modules := parser.string('modules', 0, os.join_path(root, 'build', 'audio', 'modules'),
		'module checkout root')
	compiler := parser.string('compiler', 0, '', 'explicit compatibility compiler')
	check := parser.bool('check', 0, false, 'check local prerequisites without downloads')
	launch := parser.bool('run', 0, false, 'launch the finished example')
	test_model := parser.bool('test-model', 0, false, 'load the executable and run its model tests')
	if parser.bool('help', `h`, false, 'show this help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 {
		return error('unexpected positional arguments')
	}
	tools := prerequisites()!
	if check {
		println('Build prerequisites found. Running also requires a Vulkan-capable display and driver.')
		return
	}
	build(root, os.abs_path(modules), compiler, tools, test_model, launch)!
}

run_cli(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
