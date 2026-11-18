// Exercise desktop keyboard shortcuts using a dedicated X11 server.
import os
import strconv
import time

const screen_width = 1600
const screen_height = 1000
const screen_depth = 24
const startup_timeout = 30 * time.second
const command_timeout = '10s'
const manager_timeout = 10 * time.second
const state_timeout = 5 * time.second
const poll_interval = 50 * time.millisecond
const key_hold_time = 600 * time.millisecond
const focus_settle_time = 300 * time.millisecond
const transition_settle_time = 200 * time.millisecond
const examples = ['glfw_vulkan', 'widget_gallery', 'implot_dashboard']
const usage = 'Usage: v run tests/desktop/shortcuts.vsh BINARY_DIRECTORY [--raw-gallery]'

struct Geometry {
	x      int
	y      int
	width  int
	height int
}

struct TestApp {
	name string
	path string
mut:
	process  &os.Process
	log_file os.File
	window   string
}

fn call(args []string) os.Result {
	mut invocation := ['timeout', '--kill-after=2s', command_timeout]
	invocation << args
	return os.exec(invocation)
}

fn command(args ...string) !string {
	result := call(args)
	if result.exit_code != 0 {
		return error('${args.join(' ')} exited with status ${result.exit_code}: ${result.output.trim_space()}')
	}
	return result.output.trim_space()
}

fn start_process(binary string, args []string) !&os.Process {
	mut child := os.new_process(os.find_abs_path_of_executable(binary) or {
		if !os.is_executable(binary) {
			return err
		}
		binary
	})
	child.set_args(args)
	child.use_pgroup = true
	child.set_redirect_stdio()
	child.run()
	return child
}

fn stop(mut child os.Process) {
	if child.is_alive() {
		child.signal_term()
		timer := time.new_stopwatch()
		for child.is_alive() && timer.elapsed() < time.second {
			time.sleep(poll_interval)
		}
		if child.is_alive() {
			child.signal_pgkill()
			child.wait()
		}
	}
	child.close()
}

fn (mut app TestApp) record() ! {
	text := app.process.stdout_read() + app.process.stderr_read()
	if text != '' {
		app.log_file.write_string(text)!
		app.log_file.flush()
	}
}

fn (mut app TestApp) close() {
	if app.process.is_alive() {
		app.process.signal_pgkill()
		app.process.wait()
	}
	app.record() or {}
	app.process.close()
	app.log_file.close()
}

fn start_display() !&os.Process {
	bounds := '${screen_width}x${screen_height}x${screen_depth}'
	mut server := start_process('Xvfb', ['-displayfd', '1', '-screen', '0', bounds, '-nolisten',
		'tcp', '-noreset'])!
	mut ready := false
	defer {
		if !ready {
			stop(mut server)
		}
	}
	timer := time.new_stopwatch()
	mut output := ''
	for server.is_alive() && timer.elapsed() < state_timeout {
		output += server.stdout_read()
		if output.contains('\n') {
			number := output.trim_space()
			if number.len == 0 || !number.bytes().all(it.is_digit()) {
				return error('Unexpected private Xvfb display: ${output}')
			}
			os.setenv('DISPLAY', ':${number}', true)
			os.unsetenv('XAUTHORITY')
			ready = true
			return server
		}
		time.sleep(poll_interval)
	}
	return error('Private Xvfb failed to start: ${server.stderr_read()}')
}

fn properties(window string, name string) !string {
	return command('xprop', '-id', window, name)
}

fn geometry(window string) !Geometry {
	output := command('xdotool', 'getwindowgeometry', '--shell', window)!
	mut values := map[string]int{}
	for line in output.split_into_lines() {
		key, value := line.split_once('=') or { continue }
		if key in ['X', 'Y', 'WIDTH', 'HEIGHT'] {
			values[key] = strconv.atoi(value)!
		}
	}
	if values.len != 4 {
		return error('Incomplete window geometry: ${output}')
	}
	return Geometry{values['X'], values['Y'], values['WIDTH'], values['HEIGHT']}
}

fn (mut app TestApp) wait_geometry(expected Geometry) ! {
	timer := time.new_stopwatch()
	for timer.elapsed() < state_timeout {
		app.record()!
		if geometry(app.window)! == expected {
			return
		}
		time.sleep(poll_interval)
	}
	return error('${app.name}: expected geometry ${expected}, got ${geometry(app.window)!}')
}

fn diagnose_startup(name string, pid int, wm_pid int, logs string) {
	eprintln(call(['xwininfo', '-root', '-tree']).output)
	eprintln(call(['ps', '-o', 'pid,stat,wchan:24,comm', '-p', pid.str()]).output)
	if _ := os.find_abs_path_of_executable('gdb') {
		for label, target in {
			'${name}-startup': pid
			'window-manager':  wm_pid
		} {
			trace := call(['gdb', '-batch', '-ex', 'set pagination off', '-ex', 'thread apply all bt',
				'-p', target.str()]).output
			os.write_file(os.join_path(logs, label + '-stack.log'), trace) or {}
			eprintln(trace)
		}
	}
}

fn start_example(name string, root string, logs string, wm_pid int) !TestApp {
	path := os.join_path(logs, name + '.log')
	mut file := os.create(path)!
	mut child := start_process(os.join_path(root, name), []) or {
		file.close()
		return err
	}
	mut app := TestApp{ name: name, path: path, process: child, log_file: file }
	mut started := false
	defer {
		if !started {
			app.close()
		}
	}
	timer := time.new_stopwatch()
	for timer.elapsed() < startup_timeout {
		app.record()!
		if !app.process.is_alive() {
			app.record()!
			eprintln(os.read_file(path) or { '' })
			eprintln(call(['xwininfo', '-root', '-tree']).output)
			return error('Failed to open ${name}. See ${path}')
		}
		window := call(['xdotool', 'search', '--onlyvisible', '--pid', child.pid.str(), '--name',
			'^V ImGui:']).output.trim_space().split_into_lines()
		if window.len > 0 && window[0].bytes().all(it.is_digit()) {
			app.window = window[0]
			command('xdotool', 'windowactivate', '--sync', app.window) or {
				eprintln(call(['xprop', '-id', app.window, '_NET_WM_STATE']).output)
				eprintln(os.read_file(os.join_path(logs, 'window-manager.log')) or { '' })
				return err
			}
			time.sleep(focus_settle_time)
			started = true
			return app
		}
		time.sleep(poll_interval)
	}
	diagnose_startup(name, child.pid, wm_pid, logs)
	return error('No visible ${name} window within ${startup_timeout}. See ${path}')
}

fn (mut app TestApp) quit() ! {
	command('xdotool', 'windowactivate', '--sync', app.window)!
	time.sleep(focus_settle_time)
	command('xdotool', 'key', 'Escape')!
	timer := time.new_stopwatch()
	for timer.elapsed() < state_timeout {
		app.record()!
		if !app.process.is_alive() {
			app.record()!
			log_text := os.read_file(app.path)!
			lower := log_text.to_lower_ascii()
			if app.process.code != 0
				|| ['vuid-', 'validation error', 'segmentation', 'assert', 'fatal'].any(lower.contains(it)) {
				return error('${app.name} exited ${app.process.code}. See ${app.path}\n${log_text}')
			}
			return
		}
		time.sleep(poll_interval)
	}
	return error('Escape did not quit ${app.name}')
}

fn fullscreen_test(root string, logs string, wm_pid int, desktop_mode string) ! {
	fullscreen := Geometry{0, 0, screen_width, screen_height}
	for name in examples {
		mut app := start_example(name, root, logs, wm_pid)!
		defer { app.close() }
		normal := geometry(app.window)!
		frame := properties(app.window, '_NET_FRAME_EXTENTS')!
		command('xdotool', 'keydown', 'F11')!
		app.wait_geometry(fullscreen)!
		time.sleep(key_hold_time)
		held := geometry(app.window)!
		command('xdotool', 'keyup', 'F11')!
		if held != fullscreen || !properties(app.window, '_NET_FRAME_EXTENTS')!.contains('= 0, 0, 0, 0')
			|| command('xrandr', '--current')! != desktop_mode {
			return error('${name}: holding F11 changed fullscreen geometry, decorations or display mode')
		}
		time.sleep(100 * time.millisecond)
		command('xdotool', 'key', 'F11')!
		app.wait_geometry(normal)!
		if properties(app.window, '_NET_FRAME_EXTENTS')! != frame {
			return error('${name}: F11 did not restore frame decorations')
		}
		app.quit()!
		println('PASS: ${name} — F11, held key, restore geometry and Escape')
	}
}

fn maximized_test(root string, logs string, wm_pid int) ! {
	mut app := start_example('widget_gallery', root, logs, wm_pid)!
	defer { app.close() }
	normal := geometry(app.window)!
	command('wmctrl', '-i', '-r', app.window, '-b', 'add,maximized_vert,maximized_horz')!
	timer := time.new_stopwatch()
	for timer.elapsed() < state_timeout {
		app.record()!
		if properties(app.window, '_NET_WM_STATE')!.contains('_NET_WM_STATE_MAXIMIZED_VERT') {
			break
		}
		time.sleep(poll_interval)
	}
	time.sleep(transition_settle_time)
	maximized := geometry(app.window)!
	if normal == maximized {
		return error('Window manager did not maximize the gallery')
	}
	command('xdotool', 'key', 'F11')!
	app.wait_geometry(Geometry{0, 0, screen_width, screen_height})!
	command('xdotool', 'key', 'F11')!
	app.wait_geometry(maximized)!
	command('wmctrl', '-i', '-r', app.window, '-b', 'remove,maximized_vert,maximized_horz')!
	app.wait_geometry(normal)!
	app.quit()!
	println('PASS: Fullscreen preserves maximized state and normal restore bounds')
}

fn raw_gallery_test(root string, logs string, wm_pid int) ! {
	// The raw gallery uses a fixed initial layout. Positions identify the text field and popup.
	cases := {
		'editing': ['200', '113']
		'a popup': ['100', '252']
	}
	for target, point in cases {
		mut app := start_example('widget_gallery', root, logs, wm_pid)!
		defer { app.close() }
		command('xdotool', 'mousemove', '--window', app.window, point[0], point[1], 'click', '1')!
		if target == 'editing' {
			command('xdotool', 'type', '--clearmodifiers', 'Escape cancels this edit')!
		} else {
			time.sleep(transition_settle_time)
		}
		command('xdotool', 'key', 'Escape')!
		time.sleep(transition_settle_time)
		if !app.process.is_alive() {
			return error('Escape quit the gallery while ${target} was active')
		}
		app.quit()!
		println('PASS: Escape dismisses ${target} before quitting')
	}
}

fn run(args []string) ! {
	if args in [['-h'], ['--help']] {
		println(usage)
		return
	}
	if args.len !in [1, 2] || (args.len == 2 && args[1] !in ['', '--raw-gallery']) {
		return error(usage)
	}
	root := os.abs_path(args[0])
	if !os.is_dir(root) {
		return error('Missing example directory: ${root}')
	}
	logs := os.join_path(root, 'shortcut-logs')
	os.mkdir_all(logs)!
	mut manifests := os.glob('/usr/share/vulkan/icd.d/lvp_icd*.json')!
	manifests.sort()
	if manifests.len == 0 {
		return error('Lavapipe is required for the private X11 session')
	}
	os.setenv('VK_DRIVER_FILES', manifests[0], true)
	os.setenv('VK_ICD_FILENAMES', manifests[0], true)
	os.setenv('VK_INSTANCE_LAYERS', 'VK_LAYER_KHRONOS_validation', true)
	os.unsetenv('WAYLAND_DISPLAY')
	os.unsetenv('VIMGUI_SMOKE_FRAMES')
	os.setenv('XDG_SESSION_TYPE', 'x11', true)
	mut server := start_display()!
	defer { stop(mut server) }
	wm_log := os.join_path(logs, 'window-manager.log')
	mut wm := TestApp{
		name:     'window manager'
		path:     wm_log
		log_file: os.create(wm_log)!
		process:  start_process('openbox', ['--sm-disable'])!
	}
	defer { wm.close() }
	timer := time.new_stopwatch()
	for {
		wm.record()!
		if call(['xprop', '-root', '_NET_SUPPORTING_WM_CHECK']).output.contains('window id') {
			break
		}
		if !wm.process.is_alive() || timer.elapsed() >= manager_timeout {
			return error('Openbox did not register with private Xvfb. See ${wm_log}')
		}
		time.sleep(poll_interval)
	}
	desktop := command('xrandr', '--current')!
	fullscreen_test(root, logs, wm.process.pid, desktop)!
	maximized_test(root, logs, wm.process.pid)!
	if args.len == 2 && args[1] == '--raw-gallery' {
		raw_gallery_test(root, logs, wm.process.pid)!
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
