// Exercise the real audio controls on a private X11 display and capture the layouts.
import math
import os
import strconv
import strings
import time
import x.json2

const dpi_default = 96
const dpi_high = 192
const screen_width = 1920
const screen_height = 1080
const compact_width = 960
const compact_height = 700
const narrow_width = 560
const default_gain = 0.1
const volume_tolerance = 0.001
const scroll_margin = 12
const check_timeout = 12 * time.second
const poll_time = 40 * time.millisecond
const click_hold = 60 * time.millisecond
const control_settling = 80 * time.millisecond
const display_marker = 'ANTONO2_AUDIO_INPUT_XVFB'

struct Bounds {
	x       f64
	y       f64
	w       f64
	h       f64
	visible bool
	focused bool
}

struct State {
	playing bool
	x       f64
	z       f64
	gain    f64
}

struct Snapshot {
	scale    f64
	width    int
	height   int
	scroll_y f64
	stacked  bool
	state    State
	items    map[string]Bounds
	error    string
}

struct Result {
	dpi     int
	scale   f64
	initial []int
	compact []int    = [compact_width, compact_height]
	passed  []string = ['work-area fit', 'presets', 'button edges', 'release cancellation', 'volume',
		'mute restore', 'drag', 'reset', 'keyboard', 'focus loss', 'reflow', 'scroll access',
		'Vulkan validation']
}

struct Alignment {
	x f64 = 0.5
	y f64 = 0.5
}

struct Preset {
	name string
	x    f64
}

struct TestWindow {
	folder string
	report string
mut:
	id  string
	app &os.Process
	log os.File
}

fn require(ok bool, detail string) ! {
	if !ok {
		return error(detail)
	}
}

fn command(args []string, timeout time.Duration) !string {
	program := if os.is_abs_path(args[0]) {
		args[0]
	} else {
		os.find_abs_path_of_executable(args[0])!
	}
	mut process := os.new_process(program)
	process.set_args(args[1..])
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	deadline := time.sys_mono_now() + timeout
	mut stdout := strings.new_builder(128)
	mut stderr := strings.new_builder(128)
	for {
		alive := process.is_alive()
		out := process.stdout_read()
		err := process.stderr_read()
		stdout.write_string(out)
		stderr.write_string(err)
		if !alive && out == '' && err == '' {
			process.wait()
			break
		}
		if time.sys_mono_now() >= deadline {
			if alive {
				process.signal_kill()
				// Mark the child running long enough for V 0.5.2 to reap it.
				process.status = .running
				process.wait()
			}
			return error('${args[0]} timed out: ${args}')
		}
		if out == '' && err == '' {
			time.sleep(5 * time.millisecond)
		}
	}
	output := stdout.str().trim_space()
	require(process.code == 0, '${args[0]} exited ${process.code}: ${output}${stderr.str()}')!
	return output
}

fn (window TestWindow) xdo(args ...string) !string {
	mut command_args := ['xdotool']
	command_args << args
	return command(command_args, 8 * time.second)
}

fn (mut window TestWindow) drain() {
	for channel in [os.ChildProcessPipeKind.stdout, .stderr] {
		for {
			chunk := window.app.pipe_read(channel) or { break }
			window.log.write_string(chunk) or { break }
		}
	}
}

fn (mut window TestWindow) wait_for(label string, predicate fn (Snapshot) bool) !Snapshot {
	deadline := time.sys_mono_now() + check_timeout
	for time.sys_mono_now() < deadline {
		window.drain()
		require(window.app.is_alive(),
			'The audio window exited during ${label}. See ${window.folder}/window.log')!
		if data := os.read_file(window.report) {
			if current := json2.decode[Snapshot](data) {
				require(current.error == '', current.error)!
				if predicate(current) {
					return current
				}
			}
		}
		time.sleep(poll_time)
	}
	return error('Timed out waiting for ${label}. See ${window.report}')
}

fn (mut window TestWindow) snapshot(label string) !Snapshot {
	return window.wait_for(label, fn (_ Snapshot) bool {
		return true
	})
}

fn (mut window TestWindow) playing(active bool, label string) ! {
	window.wait_for(label, fn [active] (snapshot Snapshot) bool {
		return snapshot.state.playing == active
	})!
}

fn (window TestWindow) capture(name string) ! {
	time.sleep(200 * time.millisecond)
	command(['import', '-display', os.getenv('DISPLAY'), '-window', window.id,
		os.join_path(window.folder, name + '.png')], 15 * time.second)!
}

fn (mut window TestWindow) move(name string, alignment Alignment) ! {
	current := window.wait_for(name + ' geometry', fn [name] (snapshot Snapshot) bool {
		return name in snapshot.items
	})!
	bounds := current.items[name]
	// GLFW reports physical X11 coordinates. Keep the content scale out of input positioning.
	x := bounds.x + bounds.w * alignment.x
	y := bounds.y + bounds.h * alignment.y
	require(x >= 0 && x < current.width && y >= 0 && y < current.height,
		'Widget ${name} is outside the X11 window: ${bounds}')!
	window.xdo('mousemove', '--window', window.id, int(math.round(x)).str(),
		int(math.round(y)).str())!
}

fn (mut window TestWindow) click(name string, alignment Alignment) ! {
	window.move(name, alignment)!
	window.xdo('mousedown', '1')!
	time.sleep(click_hold)
	window.xdo('mouseup', '1')!
	time.sleep(control_settling)
}

fn (mut window TestWindow) top() ! {
	padding := scroll_margin.str()
	window.xdo('mousemove', '--window', window.id, padding, padding, 'click', '--repeat', '30',
		'--delay', '12', '4')!
	window.wait_for('scroll to top', fn (snapshot Snapshot) bool {
		return snapshot.scroll_y == 0
	})!
}

fn (mut window TestWindow) reveal(name string) ! {
	// Scroll one wheel step at a time so a control cannot pass the visible area between probes.
	for _ in 0 .. 35 {
		current := window.snapshot('scroll geometry')!
		bounds := current.items[name]
		if bounds.visible && bounds.y >= scroll_margin
			&& bounds.y + bounds.h < current.height - scroll_margin {
			return
		}
		direction := if name in current.items && bounds.y < scroll_margin { '4' } else { '5' }
		window.xdo('mousemove', '--window', window.id, scroll_margin.str(),
			(current.height / 2).str(), 'click', direction)!
		time.sleep(control_settling)
	}
	return error('Cannot scroll to ${name}')
}

fn (mut window TestWindow) preset(preset Preset, after_resize bool) ! {
	if after_resize {
		window.reveal(preset.name)!
		window.click(preset.name, Alignment{ x: 0.95, y: 0.95 })!
	} else {
		window.click(preset.name, Alignment{})!
	}
	window.wait_for(preset.name + ' preset', fn [preset, after_resize] (r Snapshot) bool {
		return r.state.x == preset.x && (after_resize || r.state.z == -1)
	})!
}

fn (mut window TestWindow) verify_controls() ! {
	for preset in [Preset{'right', 4}, Preset{'centre', 0}, Preset{'left', -4}] {
		window.preset(preset, false)!
	}
	for alignment in [Alignment{0.05, 0.05}, Alignment{0.95, 0.05},
		Alignment{0.05, 0.95}, Alignment{0.95, 0.95}, Alignment{}] {
		window.click('play', alignment)!
		window.playing(true, 'Play button edge')!
		window.click('stop', alignment)!
		window.playing(false, 'Stop button edge')!
	}
	window.move('play', Alignment{})!
	window.xdo('mousedown', '1')!
	time.sleep(150 * time.millisecond)
	require(!window.snapshot('held Play')!.state.playing, 'Pressing Play activated before release')!
	window.move('stop', Alignment{})!
	window.xdo('mouseup', '1')!
	time.sleep(150 * time.millisecond)
	require(!window.snapshot('cancelled Play')!.state.playing, 'Release outside Play activated it')!
	window.click('volume', Alignment{ x: 0.75 })!
	window.wait_for('native volume slider', expected_volume)!
	window.click('mute', Alignment{})!
	window.wait_for('mute', fn (r Snapshot) bool {
		return r.state.gain == 0
	})!
	window.click('mute', Alignment{})!
	window.wait_for('restore volume', expected_volume)!
	window.reveal('field')!
	window.move('field', Alignment{0.25, 0.25})!
	window.xdo('mousedown', '1')!
	time.sleep(100 * time.millisecond)
	window.move('field', Alignment{0.75, 0.75})!
	time.sleep(100 * time.millisecond)
	window.xdo('mouseup', '1')!
	window.wait_for('field drag', fn (r Snapshot) bool {
		return math.abs(r.state.x - 3) < 0.08 && math.abs(r.state.z - 3) < 0.08
	})!
	window.top()!
	window.click('reset', Alignment{})!
	window.wait_for('reset', fn (r Snapshot) bool {
		return r.state.z == -2 && reset_values(r)
	})!
}

fn reset_values(r Snapshot) bool {
	return r.state.x == -3 && math.abs(r.state.gain - default_gain) < volume_tolerance
}

fn expected_volume(r Snapshot) bool {
	return r.state.gain > 0.72 && r.state.gain < 0.79
}

fn (mut window TestWindow) verify_keyboard() ! {
	for _ in 0 .. 30 {
		current := window.snapshot('keyboard focus')!
		if current.items['play'].focused {
			break
		}
		window.xdo('key', 'Tab')!
		time.sleep(control_settling)
	}
	require(window.snapshot('Tab focus')!.items['play'].focused, 'Play is unreachable with Tab')!
	window.xdo('key', 'space')!
	window.playing(true, 'Space activates focused Play')!
	time.sleep(100 * time.millisecond)
	require(window.snapshot('focus after label change')!.items['play'].focused,
		'Play lost Tab focus after changing its label')!
	window.xdo('key', 'space')!
	time.sleep(100 * time.millisecond)
	require(window.snapshot('keyboard restart')!.state.playing, 'Space failed to restart playback')!
	window.xdo('key', 'Escape')!
	window.playing(false, 'Escape stops after native keyboard activation')!
	window.xdo('key', 'p')!
	window.playing(true, 'keyboard Play')!
	window.xdo('key', 'Escape')!
	window.playing(false, 'keyboard Stop')!
	window.click('play', Alignment{})!
	window.playing(true, 'Play before focus loss')!
	window.xdo('windowfocus', '0')!
	window.playing(false, 'focus loss stops audio')!
	window.xdo('windowfocus', '--sync', window.id)!
}

fn (mut window TestWindow) verify_compact(dpi int) ! {
	window.xdo('windowsize', '--sync', window.id, compact_width.str(), compact_height.str())!
	window.wait_for('compact resize', fn (r Snapshot) bool {
		return r.width == compact_width && r.height == compact_height
	})!
	window.top()!
	if dpi > dpi_default {
		require(window.snapshot('resized layout')!.stacked,
			'Compact high-DPI layout did not reflow')!
	}
	window.capture('compact')!
	for preset in [Preset{'right', 4}, Preset{'left', -4}] {
		window.preset(preset, true)!
	}
	window.reveal('details')!
	if 'x' !in window.snapshot('details state')!.items {
		window.click('details', Alignment{})!
	}
	window.reveal('x')!
	window.click('x', Alignment{ x: 0.75 })!
	window.wait_for('advanced slider', fn (r Snapshot) bool {
		return r.state.x > 2.7 && r.state.x < 3.5
	})!
	window.reveal('field')!
	window.capture('compact-scrolled')!
	window.top()!
	window.reveal('play')!
	window.click('play', Alignment{})!
	window.playing(true, 'Play after resize')!
	window.reveal('stop')!
	window.click('stop', Alignment{})!
	window.playing(false, 'Stop after resize')!
	if dpi == dpi_high {
		window.xdo('windowsize', '--sync', window.id, narrow_width.str(), compact_height.str())!
		window.wait_for('narrow resize', fn (r Snapshot) bool {
			return r.width == narrow_width
		})!
		window.top()!
		current := window.snapshot('wrapped buttons')!
		require(current.items['reset'].y > current.items['play'].y, 'Narrow controls did not wrap')!
		window.capture('narrow-wrapped')!
		window.reveal('right')!
		window.click('right', Alignment{})!
		window.wait_for('wrapped preset', fn (r Snapshot) bool {
			return r.state.x == 4
		})!
		window.reveal('reset')!
		window.click('reset', Alignment{})!
		window.wait_for('wrapped reset', reset_values)!
	}
}

fn check_scale(binary string, output string, dpi int) !Result {
	folder := os.join_path(output, 'dpi-${dpi}')
	os.mkdir_all(folder)!
	report := os.join_path(folder, 'state.json')
	if os.exists(report) {
		os.rm(report)!
	}
	resources := os.join_path(folder, 'xresources')
	os.write_file(resources, 'Xft.dpi: ${dpi}\n')!
	command(['xrdb', '-merge', resources], 8 * time.second)!
	command(['xdotool', 'mousemove', (screen_width - 10).str(),
		(screen_height - 10).str()], 8 * time.second)!
	mut window := TestWindow{
		folder: folder
		report: report
		log:    os.create(os.join_path(folder, 'window.log'))!
		app:    os.new_process(binary)
	}
	window.app.set_args(['--input-check', report])
	window.app.set_redirect_stdio()
	window.app.run()
	defer {
		if window.app.is_alive() {
			window.app.signal_kill()
			window.app.status = .running
			window.app.wait()
		}
		window.drain()
		window.app.close()
		window.log.close()
	}
	first := window.snapshot('initial state')!
	require(math.abs(first.scale - f64(dpi) / dpi_default) < 0.01,
		'Unexpected OS scale ${first.scale}')!
	// Keep native top-level window decorations inside the 1080p work area.
	require(first.width <= screen_width - 80 && first.height <= screen_height - 80,
		'Initial window exceeds the work area: ${first.width}x${first.height}')!
	require(!first.state.playing && math.abs(first.state.gain - default_gain) < volume_tolerance,
		'Initial state must be silent at 10% volume')!
	require(dpi != dpi_high || first.stacked, 'Initial 200% layout did not reflow')!
	ids := window.xdo('search', '--sync', '--onlyvisible', '--name',
		r'^Audio playground \| antono2\.audio$')!.fields()
	require(ids.len == 1, 'Expected one audio window, got ${ids}')!
	window.id = ids[0]
	window.xdo('windowfocus', '--sync', window.id)!
	window.capture('initial')!
	window.verify_controls()!
	window.verify_keyboard()!
	window.verify_compact(dpi)!
	window.xdo('key', 'F12')!
	deadline := time.sys_mono_now() + 10 * time.second
	for window.app.is_alive() {
		window.drain()
		require(time.sys_mono_now() < deadline, 'Audio window did not close')!
		time.sleep(poll_time)
	}
	window.app.wait()
	window.drain()
	window.log.flush()
	log := os.read_file(os.join_path(folder, 'window.log'))!.to_lower_ascii()
	require(window.app.code == 0
		&& !['validation error', 'vuid-', 'segmentation', 'fatal'].any(log.contains(it)),
		'Audio window failed. See ${folder}/window.log')!
	return Result{
		dpi:     dpi
		scale:   first.scale
		initial: [first.width, first.height]
	}
}

fn requested_dpis(args []string) ![]int {
	if args.len == 0 {
		return [dpi_default, 105, 120, 144, dpi_high]
	}
	require(args.len > 1 && args[0] == '--dpi',
		'usage: v run tests/desktop/audio_input.vsh [--dpi DPI ...]')!
	mut dpis := []int{}
	for arg in args[1..] {
		dpi := strconv.atoi(arg)!
		require(dpi >= 72 && dpi <= 240, 'DPI must be between 72 and 240')!
		dpis << dpi
	}
	return dpis
}

fn run(args []string) ! {
	if args in [['-h'], ['--help']] {
		println('usage: v run tests/desktop/audio_input.vsh [--dpi DPI ...]')
		return
	}
	// With no isolated session marker, xvfb-run creates a fresh display and X authority.
	if args.len == 0 || args[0] != '--inside-xvfb' {
		requested_dpis(args)!
		program := os.find_abs_path_of_executable('xvfb-run')!
		mut display := os.new_process(program)
		mut flags := ['-a', '-s',
			'-screen 0 ${screen_width}x${screen_height}x24 -noreset -nolisten tcp', os.executable(),
			'--inside-xvfb']
		flags << args
		display.set_args(flags)
		mut environment := os.environ()
		environment[display_marker] = os.executable()
		display.set_environment(environment)
		display.wait()
		defer { display.close() }
		require(display.code == 0, 'Isolated X11 input test failed')!
		return
	}
	require(os.getenv(display_marker) == os.executable() && os.getenv('DISPLAY') != '',
		'The audio input test requires its isolated X11 session')!
	os.unsetenv(display_marker)
	os.unsetenv('WAYLAND_DISPLAY')
	os.setenv('LIBGL_ALWAYS_SOFTWARE', '1', true)
	for entry in os.ls('/usr/share/vulkan/icd.d') or { []string{} } {
		if entry.starts_with('lvp_icd') {
			os.setenv('VK_DRIVER_FILES', os.join_path('/usr/share/vulkan/icd.d', entry), true)
		}
	}
	if os.exists('/usr/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json') {
		os.setenv('VK_INSTANCE_LAYERS', 'VK_LAYER_KHRONOS_validation', true)
	}
	root := os.dir(os.dir(@DIR))
	binary := os.join_path(root, 'build', 'audio_playground')
	require(os.is_executable(binary), 'Build the audio playground before checking native input')!
	output := os.join_path(root, 'build', 'audio-validation', 'input')
	os.mkdir_all(output)!
	report := os.join_path(output, 'results.json')
	if os.exists(report) {
		os.rm(report)!
	}
	mut results := []Result{}
	for dpi in requested_dpis(args[1..])! {
		results << check_scale(binary, output, dpi)!
		println('PASS: real ImGui input at ${f64(dpi) / dpi_default:.3f}x on 1080p')
	}
	os.write_file(report, json2.encode(results, prettify: true, indent_string: '  ') + '\n')!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
