// Prepare the pinned Android SDK, check the APK and collect release notices.
import os
import scripts.androidci
import scripts.releaseconsumer

const package_name = 'io.antono2.vimgui.examples.touch'
const draw_symbol = 'vimgui_android_demo_draw_ui'

fn install_sdk() ! {
	sdk := androidci.sdk_directory()!
	ndk := os.join_path(sdk, 'ndk', androidci.ndk_release)
	releaseconsumer.run_tool('sdkmanager', ['--install', 'ndk;${androidci.ndk_release}',
		'platforms;${androidci.android_platform}', 'build-tools;${androidci.build_tools_release}'])!
	if !os.is_file(os.join_path(ndk, 'build', 'cmake', 'android.toolchain.cmake')) {
		return error('The pinned Android NDK is missing: ${ndk}')
	}
	env := os.getenv('GITHUB_ENV')
	if env == '' {
		println('ANDROID_NDK_HOME=${ndk}')
		return
	}
	if ndk.contains_any('\r\n') {
		return error('The NDK path must fit on one GitHub Actions environment line')
	}
	mut output := os.open_append(env)!
	defer { output.close() }
	output.writeln('ANDROID_NDK_HOME=${ndk}')!
}

fn tool_output(program string, args []string) !string {
	mut invocation := [program]
	invocation << args
	result := os.exec(invocation)
	if result.exit_code != 0 {
		return error('${program} exited with status ${result.exit_code}\n${result.output}')
	}
	return result.output
}

fn check_package(root string) ! {
	abi := os.getenv('ANDROID_ABI')
	if abi !in ['armeabi-v7a', 'arm64-v8a', 'x86_64'] {
		return error('Set ANDROID_ABI to armeabi-v7a, arm64-v8a or x86_64.')
	}
	sdk := androidci.sdk_directory()!
	ndk := androidci.setting('ANDROID_NDK_HOME', os.join_path(sdk, 'ndk', androidci.ndk_release))
	aapt := os.join_path(sdk, 'build-tools', androidci.build_tools_release, 'aapt')
	nm := os.join_path(ndk, 'toolchains', 'llvm', 'prebuilt', 'linux-x86_64', 'bin', 'llvm-nm')
	build := androidci.build_directory(root)
	badging :=
		tool_output(aapt, ['dump', 'badging', os.join_path(build, 'vimgui-demo-${abi}.apk')])!
	os.write_file(os.join_path(build, 'apk-badging.txt'), badging)!
	print(badging)
	if !badging.split_into_lines().any(it.starts_with("package: name='${package_name}'")) {
		return error('Expected Android package ${package_name}')
	}
	symbols := tool_output(nm, ['-D', '--defined-only', os.join_path(build,
		'libvimgui_android_ui.so')])!
	if !symbols.split_into_lines().any(draw_symbol in it.fields()) {
		return error('The APK UI library does not export ${draw_symbol}')
	}
	println('Verified ${package_name} and ${draw_symbol} for ${abi}.')
}

fn run(args []string) ! {
	root := os.dir(@DIR)
	match args {
		['install'] {
			install_sdk()!
		}
		['verify'] {
			check_package(root)!
		}
		['notices'] {
			releaseconsumer.run_tool(@VEXE, ['run', os.join_path(@DIR, 'collect_licenses.v'),
				androidci.host_directory(root),
				os.join_path(androidci.build_directory(root),
					'licenses'), 'android'])!
		}
		else {
			return error('Usage: v run scripts/android_ci.vsh install|verify|notices')
		}
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
