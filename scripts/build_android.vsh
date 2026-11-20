// Select the pinned ImGui Android host and build or deploy the Android touch example.
import os
import rand
import scripts.androidci

const host_repository = 'https://github.com/antono2/imgui.git'
const usage = 'Usage: v run scripts/build_android.vsh [--build-only|run]'

fn run_process(program string, args []string, environment map[string]string) int {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_environment(environment)
	process.wait()
	code := process.code
	process.close()
	return code
}

fn checked(program string, args []string, environment map[string]string) ! {
	code := run_process(program, args, environment)
	if code != 0 {
		return error_with_code('${os.file_name(program)} exited with status ${code}', code)
	}
}

fn output(program string, args []string, environment map[string]string) !string {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_environment(environment)
	process.set_redirect_stdio()
	process.run()
	text := process.stdout_slurp()
	diagnostics := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 {
		return error_with_code('${os.file_name(program)} exited with status ${code}: ${diagnostics.trim_space()}',
			code)
	}
	return text.trim_space()
}

fn fetch_host(git string, imgui string, pin string, env map[string]string) ! {
	parent := os.dir(imgui)
	os.mkdir_all(parent)!
	staged := os.join_path(parent, '.imgui-android-' + rand.uuid_v4())
	os.mkdir(staged, mode: 0o700)!
	defer { os.rmdir_all(staged) or {} }
	checked(git, ['clone', '--depth', '1', '--no-checkout', '--filter=blob:none', host_repository,
		staged], env)!
	checked(git, ['-C', staged, 'fetch', '--depth', '1', 'origin', pin], env)!
	checked(git, ['-C', staged, 'checkout', '--detach', pin], env)!
	// An empty destination is valid. Never replace an existing checkout.
	if os.is_dir(imgui) && !os.is_link(imgui) && os.ls(imgui)!.len == 0 {
		os.rmdir(imgui)!
	}
	os.mv(staged, imgui, overwrite: false)!
}

fn build(mode string) ! {
	javac := androidci.setting('JAVAC', 'javac')
	if !os.is_executable(javac) {
		os.find_abs_path_of_executable(javac) or {
			return error('Install a JDK with javac on PATH, or set JAVAC to the compiler executable.')
		}
	}
	root := os.dir(@DIR)
	imgui := androidci.host_directory(root)
	selected := androidci.setting('V_BIN', @VEXE)
	compiler := if os.is_executable(selected) {
		os.abs_path(selected)
	} else {
		os.find_abs_path_of_executable(selected)!
	}
	mut env := os.environ()
	env['V_BIN'] = compiler
	env['VEXE'] = compiler
	pin := output(compiler, ['run', os.join_path(root, 'scripts', 'compatibility.vsh'),
		'--get', 'imgui_android'], env)!
	git := os.find_abs_path_of_executable('git')!
	if !os.is_file(os.join_path(imgui, 'v.mod')) {
		fetch_host(git, imgui, pin, env)!
	}
	actual := output(git, ['-C', imgui, 'rev-parse', 'HEAD'], env)!
	if pin != actual {
		return error_with_code('The Android host must match ${pin} from compatibility.json. Use a fresh IMGUI_DIR or check out that commit.',
			2)
	}
	checked(git, ['-C', imgui, 'submodule', 'update', '--init', '--recursive'], env)!
	ui := os.join_path(root, 'examples', 'android_touch')
	env['VIMGUI_ANDROID_UI_SOURCE'] = ui
	env['VIMGUI_ANDROID_MANIFEST'] = os.join_path(ui, 'AndroidManifest.xml')
	env['VIMGUI_ANDROID_BUILD_DIR'] = androidci.build_directory(root)
	checked(compiler, ['run', os.join_path(imgui, 'scripts', 'run_android_demo.vsh'), mode], env)!
}

fn main() {
	args := os.args[1..]
	if args in [['-h'], ['--help']] {
		println(usage)
		return
	}
	mode := if args.len == 0 { '--build-only' } else { args[0] }
	if args.len > 1 || mode !in ['--build-only', 'run'] {
		eprintln(usage)
		exit(2)
	}
	build(mode) or {
		eprintln(err)
		exit(if err.code() > 0 { err.code() } else { 1 })
	}
}
