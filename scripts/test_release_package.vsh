// Launch a relocated desktop package with a clean user and runtime-only PATH.
import flag
import os
import rand
import scripts.releaseconsumer
import strconv
import strings
import time

const headless_ticks = '600'
const example_frames = '60'
const dashboard_frames = '660' // Allow the dashboard's full history and resize smoke sequence.
const process_poll = 10 * time.millisecond

struct TestRun {
	cwd     string
	logs    string
	timeout time.Duration
}

fn (test TestRun) launch(executable string, args []string, env map[string]string, name string, expected string, exit_code int) ! {
	if !os.is_file(executable) {
		return error('Missing package executable: ${executable}')
	}
	log_path := os.join_path(test.logs, name + '.log')
	mut log := os.create(log_path)!
	defer { log.close() }
	mut child := os.new_process(executable)
	child.set_args(args)
	child.set_work_folder(test.cwd)
	child.set_environment(env)
	child.set_redirect_stdio()
	child.create_no_window = true
	child.use_pgroup = true
	child.run()
	defer { child.close() }
	mut diagnostics := strings.new_builder(1024)
	timer := time.new_stopwatch()
	for {
		live := child.is_alive()
		out := child.stdout_read()
		err := child.stderr_read()
		diagnostics.write_string(out)
		diagnostics.write_string(err)
		// Flush output once per poll so an externally stopped check still leaves diagnostics.
		if out.len + err.len > 0 {
			log.write_string(out)!
			log.write_string(err)!
			log.flush()
		}
		if !live && out == '' && err == '' {
			child.wait()
			break
		}
		if timer.elapsed() >= test.timeout {
			if live {
				terminate(mut child, env)
				child.wait()
			}
			return error('${name} timed out; see ${log_path}')
		}
		if out == '' && err == '' {
			time.sleep(process_poll)
		}
	}
	captured := diagnostics.str()
	print(captured)
	lower := captured.to_lower_ascii()
	if child.code != exit_code || ['vuid-', 'validation error', 'segmentation', 'assert', 'fatal'].any(lower.contains(it)) {
		return error('${name} failed (exit ${child.code}); see ${log_path}')
	}
	if expected != '' && !captured.contains(expected) {
		return error('${name} did not report ${expected}; see ${log_path}')
	}
	println('Passed: ${name}')
}

fn windows_root(env map[string]string) string {
	return env['SystemRoot'] or { r'C:\Windows' }
}

fn terminate(mut child os.Process, env map[string]string) {
	$if windows {
		// The Windows process API only terminates the parent. Use the OS tree terminator.
		mut task := os.new_process(os.join_path(windows_root(env), 'System32', 'taskkill.exe'))
		task.set_args(['/PID', child.pid.str(), '/T', '/F'])
		task.set_redirect_stdio()
		task.create_no_window = true
		task.wait()
		task.close()
		if child.is_alive() {
			child.signal_pgkill()
		}
	} $else {
		child.signal_pgkill()
	}
}

fn runtime_environment(home string) map[string]string {
	mut env := os.environ()
	// Windows treats variable names case-insensitively, including Path.
	for key in env.keys() {
		if key.to_upper_ascii() in ['VULKAN_SDK', 'VMODULES', 'VEXE', 'V_BIN', 'VTMP', 'GLFW_INCLUDE',
			'GLFW_LIB', 'IMGUI_DIR', 'LIB', 'LIBPATH', 'INCLUDE', 'LD_LIBRARY_PATH', 'LD_PRELOAD',
			'PYTHONPATH', 'PATH', 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'APPDATA', 'LOCALAPPDATA',
			'USERPROFILE'] {
			env.delete(key)
		}
	}
	$if windows {
		windows := windows_root(env)
		env['PATH'] = os.join_path(windows, 'System32') + os.path_delimiter + windows
		for name in ['APPDATA', 'LOCALAPPDATA', 'USERPROFILE'] {
			env[name] = home
		}
	} $else {
		env['PATH'] = '/usr/bin:/bin'
		env['HOME'] = home
		env['XDG_CONFIG_HOME'] = os.join_path(home, 'config')
		env['XDG_DATA_HOME'] = os.join_path(home, 'data')
	}
	return env
}

fn run_torus(test TestRun, package string, env map[string]string) ! {
	windows := os.user_os() == 'windows'
	launcher := os.join_path(package, if windows { 'torus_trooper.exe' } else { 'play.sh' })
	$if !windows {
		os.chmod(launcher, 0o755)!
	}
	test.launch(launcher, ['--headless', '--ticks', headless_ticks, '--no-sound', '--volume', '0'],
		env, 'headless', if windows { '' } else { 'checksum=490efd84cf12692f' }, 0)!
	test.launch(launcher, ['--probe', '--no-sound', '--volume', '0'], env, 'vulkan-probe',
		if windows { '' } else { 'GLFW: Vulkan surface creation succeeded' }, 0)!
	// The error exit still verifies the GUI-subsystem executable on Windows, where it has no console.
	test.launch(launcher, ['--resolution', 'invalid'], env, 'invalid-resolution', '', 2)!
}

fn run_imgui(test TestRun, package string, mut env map[string]string) ! {
	windows := os.user_os() == 'windows'
	menu := os.join_path(package, if windows { 'examples.exe' } else { 'examples' })
	launcher := if windows { menu } else { os.join_path(package, 'run.sh') }
	examples := ['glfw_vulkan', 'widget_gallery', 'implot_dashboard']
	$if !windows {
		os.chmod(launcher, 0o755)!
		os.chmod(menu, 0o755)!
		for name in examples {
			os.chmod(os.join_path(package, name), 0o755)!
		}
	}
	// The Linux wrapper accepts example names. The compiled menu handles help on both platforms.
	test.launch(menu, ['--help'], env, 'launcher-help', 'Usage:', 0)!
	for example in examples {
		env['VIMGUI_SMOKE_FRAMES'] = if example == 'implot_dashboard' {
			dashboard_frames
		} else {
			example_frames
		}
		test.launch(launcher, [example], env, example, '', 0)!
	}
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('test_release_package')
	parser.description('Launch a relocated desktop package with runtime-only dependencies.')
	parser.arguments_description('ARCHIVE')
	project := parser.string('project', 0, '', 'torus or imgui')
	checksums := parser.string('checksums', 0, '', 'verify the archive against SHA256SUMS')
	loader := parser.string('vulkan-loader', 0, '', 'Windows CI Vulkan runtime DLL')
	logs := os.abs_path(parser.string('logs', 0, 'package-smoke-logs', 'log directory'))
	timeout := parser.string('timeout', 0, '120', 'timeout in seconds for each launch')
	if parser.bool('help', `h`, false, 'show this help') {
		println(parser.usage())
		return
	}
	positional := parser.finalize()!
	if positional.len != 1 || project !in ['torus', 'imgui'] {
		return error(parser.usage())
	}
	seconds := strconv.atoi(timeout)!
	if seconds <= 0 {
		return error('--timeout must be positive')
	}
	if loader != '' && os.user_os() != 'windows' {
		return error('--vulkan-loader is only supported on Windows')
	}
	archive := os.abs_path(positional[0])
	if checksums != '' {
		releaseconsumer.verify_checksum(archive, checksums)!
	}
	os.mkdir_all(logs)!
	work := os.join_path(os.temp_dir(), 'release consumer with spaces ' + rand.uuid_v4())
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	extracted := os.join_path(work, 'original extraction')
	os.mkdir(extracted)!
	releaseconsumer.extract(archive, extracted)!
	entries := os.ls(extracted)!
	if entries.len != 1 || !os.is_dir(os.join_path(extracted, entries[0])) {
		return error('Expected one top-level package directory')
	}
	package := os.join_path(work, 'relocated package with spaces')
	os.rename(os.join_path(extracted, entries[0]), package)!
	cwd := os.join_path(work, 'unrelated working directory')
	os.mkdir(cwd)!
	home := os.join_path(work, 'clean user')
	os.mkdir(home)!
	mut env := runtime_environment(home)
	if loader != '' {
		runtime := os.join_path(work, 'Vulkan runtime')
		os.mkdir(runtime)!
		os.cp(os.abs_path(loader), os.join_path(runtime, 'vulkan-1.dll'))!
		env['PATH'] += os.path_delimiter + runtime
	}
	test := TestRun{ cwd: cwd, logs: logs, timeout: seconds * time.second }
	if project == 'torus' {
		run_torus(test, package, env)!
	} else {
		run_imgui(test, package, mut env)!
	}
	println('Package passed after relocation, with a clean user and runtime-only PATH.')
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
