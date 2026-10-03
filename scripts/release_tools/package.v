module release_tools

import os
import crypto.sha256

const examples = ['glfw_vulkan', 'widget_gallery', 'implot_dashboard']

struct Library {
	name string
	path string
}

fn os_library(name string) bool {
	for base in ['libc.so.', 'libm.so.', 'libpthread.so.', 'libdl.so.', 'librt.so.', 'libresolv.so.',
		'libutil.so.', 'libmvec.so.', 'ld-linux', 'linux-vdso'] {
		if name.starts_with(base) {
			return true
		}
	}
	return false
}

fn linux_dependencies(file string) ![]Library {
	output := checked_output('ldd', [file])!
	if output.contains('not found') {
		return error('Unresolved dependency: ${file}\n${output}')
	}
	mut result := []Library{}
	for line in output.split_into_lines() {
		if !line.contains('=>') {
			continue
		}
		parts := line.split('=>')
		name := parts[0].trim_space()
		destination := parts[1].all_before_last(' (').trim_space()
		if destination.starts_with('/') && !os_library(name) {
			result << Library{ name: name, path: destination }
		}
	}
	return result
}

fn debian_notice(path string, output string) ! {
	for candidate in [path, os.real_path(path), path.trim_string_left('/usr')] {
		code, owners := capture('dpkg-query', ['-S', candidate])!
		if code != 0 {
			continue
		}
		for line in owners.split_into_lines() {
			owner := line.all_before(': ').all_before(':')
			notice := os.join_path('/usr/share/doc', owner, 'copyright')
			if os.is_file(notice) { copy(notice, os.join_path(output, owner + '.txt'))! }
		}
	}
}

fn package_linux(root string, binaries string, imgui string, output string) ![]string {
	prior := os.getenv('LD_LIBRARY_PATH')
	os.setenv('LD_LIBRARY_PATH', '', true)
	defer { os.setenv('LD_LIBRARY_PATH', prior, true) }
	library_dir := os.join_path(output, 'lib')
	os.mkdir_all(library_dir)!
	mut queue := []Library{}
	for example in examples {
		source := os.join_path(binaries, example)
		copy(source, os.join_path(output, example))!
		os.chmod(os.join_path(output, example), 0o755)!
		queue << linux_dependencies(source)!
	}
	// GLFW loads extension libraries and Vulkan presentation with dlopen.
	for name in ['libvulkan.so.1', 'libXrandr.so.2', 'libXinerama.so.1', 'libXcursor.so.1',
		'libXi.so.6', 'libXxf86vm.so.1'] {
		queue << Library{ name: name, path: os.join_path('/usr/lib/x86_64-linux-gnu', name) }
	}
	mut digests := map[string]string{}
	mut index := 0
	for index < queue.len {
		library := queue[index]
		index++
		digest := sha256.sum(os.read_bytes(library.path)!).hex()
		if library.name in digests {
			if digests[library.name] != digest {
				return error('Conflicting library contents: ${library.name}')
			}
			continue
		}
		digests[library.name] = digest
		copy(library.path, os.join_path(library_dir, library.name))!
		queue << linux_dependencies(library.path)!
		debian_notice(library.path, os.join_path(output, 'licenses'))!
	}
	collect_licenses(root, imgui, os.join_path(output, 'licenses'), false)!
	copy(os.join_path(root, 'packaging', 'run.sh'), os.join_path(output, 'run.sh'))!
	os.chmod(os.join_path(output, 'run.sh'), 0o755)!
	copy(os.join_path(root, 'packaging', 'README-linux.txt'), os.join_path(output, 'README.txt'))!
	mut audit_files := []string{}
	for example in examples {
		file := os.join_path(output, example)
		command('patchelf', ['--set-rpath', r'$ORIGIN/lib', file])!
		audit_files << file
	}
	for name in digests.keys() {
		file := os.join_path(library_dir, name)
		command('patchelf', ['--set-rpath', r'$ORIGIN', file])!
		audit_files << file
	}
	for file in audit_files {
		for dependency in linux_dependencies(file)! {
			if !dependency.path.starts_with(library_dir + os.path_separator) {
				return error('Unbundled library: ${dependency.path}')
			}
		}
	}
	return digests.keys()
}

fn windows_os_library(name string) bool {
	return name.starts_with('api-ms-') || name.starts_with('ext-ms-') || name in [
		'kernel32.dll',
		'user32.dll',
		'gdi32.dll',
		'advapi32.dll',
		'shell32.dll',
		'ole32.dll',
		'oleaut32.dll',
		'comdlg32.dll',
		'shlwapi.dll',
		'setupapi.dll',
		'cfgmgr32.dll',
		'ntdll.dll',
		'ucrtbase.dll',
		'ws2_32.dll',
		'bcrypt.dll',
		'crypt32.dll',
		'secur32.dll',
		'rpcrt4.dll',
		'dwmapi.dll',
		'version.dll',
		'userenv.dll',
		'imm32.dll',
		'winmm.dll',
		'msvcrt.dll',
		'powrprof.dll',
		'uxtheme.dll',
		'hid.dll',
		'winspool.drv',
		'uiautomationcore.dll',
		'comctl32.dll',
		'propsys.dll',
		'netapi32.dll',
		'mswsock.dll',
		'normaliz.dll',
		'd3d11.dll',
		'dxgi.dll',
		'opengl32.dll',
	]
}

fn package_windows(root string, binaries string, imgui string, output string) ![]string {
	for example in examples {
		copy(os.join_path(binaries, example + '.exe'), os.join_path(output, example + '.exe'))!
	}
	for name in ['vimgui.dll', 'glfw3.dll'] {
		copy(os.join_path(binaries, name), os.join_path(output, name))!
	}
	redist := os.getenv('VCToolsRedistDir')
	if redist == '' {
		return error('Run in the Visual Studio developer shell')
	}
	mut crt := ''
	for directory in os.ls(os.join_path(redist, 'x64'))! {
		if directory.starts_with('Microsoft.VC') && directory.ends_with('.CRT') {
			crt = os.join_path(redist, 'x64', directory)
			break
		}
	}
	if crt == '' {
		return error('The redistributable x64 C runtime was not found')
	}
	for file in os.ls(crt)! {
		if file.to_lower().ends_with('.dll') { copy(os.join_path(crt, file), os.join_path(output, file))! }
	}
	copy(os.join_path(os.getenv('VULKAN_SDK'), 'Bin', 'vulkan-1.dll'), os.join_path(output, 'vulkan-1.dll'))!
	notices := os.join_path(output, 'licenses')
	collect_licenses(root, imgui, notices, false)!
	mut glfw_license := ''
	for file in os.walk_ext(os.join_path(imgui, 'build', 'shared-bundled-3.4'), 'LICENSE.md') {
		if file.contains('glfw-src') {
			glfw_license = file
			break
		}
	}
	if glfw_license == '' {
		return error('GLFW license not found')
	}
	copy(glfw_license, os.join_path(notices, 'glfw.txt'))!
	copy(os.join_path(root, 'packaging', 'README-windows.txt'), os.join_path(output, 'README.txt'))!
	for file in ['MICROSOFT-RUNTIME-NOTICE.txt', 'VULKAN-LOADER-LICENSE.txt'] {
		copy(os.join_path(root, 'packaging', file), os.join_path(notices, file))!
	}
	mut imports := map[string]bool{}
	files := os.ls(output)!
	bundled := files.map(it.to_lower())
	for file in files {
		if !file.to_lower().ends_with('.exe') && !file.to_lower().ends_with('.dll') {
			continue
		}
		listing := checked_output('dumpbin', ['/nologo', '/dependents', os.join_path(output, file)])!
		for line in listing.split_into_lines() {
			name := line.trim_space().to_lower()
			if !name.ends_with('.dll') || name.contains(' ') || name.contains('\t') {
				continue
			}
			imports[name] = true
			if name !in bundled && !windows_os_library(name) {
				return error('Unbundled runtime dependency: ${file} -> ${name}')
			}
		}
	}
	return imports.keys()
}

pub fn package_release(root string, binaries string, imgui string, destination string, variant string) ! {
	if variant !in ['docking', 'standard'] {
		return error('Variant must be docking or standard')
	}
	if os.exists(destination) || os.exists(destination + '.zip') {
		return error('Output already exists: ${destination}')
	}
	os.mkdir_all(os.join_path(destination, 'licenses'))!
	output := os.real_path(destination)
	mut runtime := []string{}
	$if windows {
		runtime = package_windows(root, binaries, imgui, output)!
	} $else $if linux {
		runtime = package_linux(root, binaries, imgui, output)!
	} $else {
		return error('Portable packages currently support Linux and Windows')
	}
	runtime.sort()
	os.write_file(os.join_path(output, 'RUNTIME-LIBRARIES.txt'), runtime.join('\n') + '\n')!
	os.write_file(os.join_path(output, 'VARIANT.txt'), variant + '\n')!
	zip_folder(output, output + '.zip')!
	println(output + '.zip')
}
