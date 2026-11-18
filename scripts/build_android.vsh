// Select the pinned ImGui host and build or deploy the Android touch example.
import os

const host_repository = 'https://github.com/antono2/imgui.git'
const usage = 'Usage: v run scripts/build_android.vsh [--build-only|run]'

fn setting(name string, default_value string) string {
	value := os.getenv(name)
	return if value == '' { default_value } else { value }
}

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
		return error_with_code('${os.file_name(program)} exited with status ${code}: ${diagnostics.trim_space()}', code)
	}
	return text.trim_space()
}

fn build(mode string) ! {
	root := os.dir(@DIR)
	imgui := os.abs_path(setting('IMGUI_DIR', os.join_path(root, 'build', 'modules', 'antono2', 'imgui')))
	selected := setting('V_BIN', @VEXE)
	compiler := if os.is_executable(selected) {
		os.abs_path(selected)
	} else {
		os.find_abs_path_of_executable(selected)!
	}
	mut env := os.environ()
	env['V_BIN'] = compiler
	env['VEXE'] = compiler
	tag := output(compiler, ['run', os.join_path(root, 'scripts', 'imgui_release.vsh')], env)!
	git := os.find_abs_path_of_executable('git')!
	host := ['-C', imgui]
	tag_ref := 'refs/tags/${tag}'
	if !os.is_file(os.join_path(imgui, 'v.mod')) {
		os.mkdir_all(os.dir(imgui))!
		checked(git, ['clone', host_repository, imgui], env)!
		mut fetch := host.clone()
		fetch << ['fetch', 'origin', 'tag', tag]
		checked(git, fetch, env)!
		mut checkout := host.clone()
		checkout << ['checkout', '--detach', tag_ref]
		checked(git, checkout, env)!
	}
	expected := output(git, ['-C', imgui, 'rev-parse', tag_ref + '^{commit}'], env)!
	actual := output(git, ['-C', imgui, 'rev-parse', 'HEAD'], env)!
	if expected != actual {
		return error_with_code('ImGui must match ${tag} from v.mod. Use a fresh IMGUI_DIR or check out that tag.',
			2)
	}
	checked(git, ['-C', imgui, 'submodule', 'update', '--init', '--recursive'], env)!
	ui := os.join_path(root, 'examples', 'android_touch')
	env['VIMGUI_ANDROID_UI_SOURCE'] = ui
	env['VIMGUI_ANDROID_MANIFEST'] = os.join_path(ui, 'AndroidManifest.xml')
	env['VIMGUI_ANDROID_BUILD_DIR'] = setting('VIMGUI_ANDROID_BUILD_DIR',
		os.join_path(root, 'build', 'android-touch-' + setting('ANDROID_ABI', 'device')))
	bash := os.find_abs_path_of_executable('bash')!
	checked(bash, [os.join_path(imgui, 'scripts', 'run_android_demo.sh'), mode], env)!
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
