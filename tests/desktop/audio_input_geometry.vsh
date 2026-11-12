// Observe real input on a private X11 display, including label-change geometry.
import json2
import math
import os
import time

struct Bounds {
	x      f64
	y      f64
	w      f64
	h      f64
	active bool
}

struct PlaybackState {
	playing bool
	gain    f64
}

struct InputReport {
	frame int
	scale f64
	state PlaybackState
	items map[string]Bounds
	error string
}

fn command(arguments []string) !string {
	result := os.execute(arguments.map(os.quoted_path(it)).join(' '))
	if result.exit_code != 0 { return error('${arguments}: ${result.output}') }
	return result.output.trim_space()
}

fn report_when(path string, predicate fn (InputReport) bool, label string) !InputReport {
	deadline := time.sys_mono_now() + 12 * time.second
	mut last := ''
	for time.sys_mono_now() < deadline {
		last = os.read_file(path) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		snapshot := json2.decode[InputReport](last) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		if snapshot.error != '' { return error(snapshot.error) }
		if predicate(snapshot) { return snapshot }
		time.sleep(10 * time.millisecond)
	}
	return error('Timed out waiting for ${label}. Last report: ${last}')
}

fn next_layout(path string, previous InputReport) !InputReport {
	frame := previous.frame + 2
	return report_when(path, fn [frame] (r InputReport) bool {
		return r.frame >= frame
	}, 'next layout')
}

fn click(window string, path string, name string, bounds Bounds, rx f64, ry f64) ! {
	x := int(math.round(bounds.x + bounds.w * rx))
	y := int(math.round(bounds.y + bounds.h * ry))
	command(['xdotool', 'mousemove', '--window', window, x.str(),
		y.str()])!
	command(['xdotool', 'mousedown', '1'])!
	// A frame acknowledgement keeps the test valid with slow software rendering.
	report_when(path, fn [name] (r InputReport) bool {
		return r.items[name].active
	}, '${name} press') or {
		command(['xdotool', 'mouseup', '1']) or {}
		return err
	}
	command(['xdotool', 'mouseup', '1'])!
	report_when(path, fn [name] (r InputReport) bool {
		return !r.items[name].active
	}, '${name} release')!
}

fn unchanged_buttons(before InputReport, after InputReport) ! {
	for name in ['play', 'stop', 'mute', 'reset'] {
		a := before.items[name]
		b := after.items[name]
		if math.abs(a.x - b.x) > .01 || math.abs(a.y - b.y) > .01 || math.abs(a.w - b.w) > .01
			|| math.abs(a.h - b.h) > .01 {
			return error('${name} bounds changed with playback label: before=${a}, after=${b}')
		}
	}
}

fn check_scale(root string, dpi int) ! {
	output := os.join_path(root, 'build/audio-validation/input-geometry', 'dpi-${dpi}')
	os.mkdir_all(output)!
	xrdb := os.join_path(output, 'xresources')
	os.write_file(xrdb, 'Xft.dpi: ${dpi}\n')!
	command(['xrdb', '-merge', xrdb])!
	report := os.join_path(output, 'state.json')
	if os.exists(report) { os.rm(report)! }
	mut app := os.new_process(os.join_path(root, 'build/audio_playground'))
	app.set_args(['--input-check', report])
	app.set_redirect_stdio()
	app.run()
	defer {
		if app.is_alive() { app.signal_kill() }
		app.wait()
		os.write_file(os.join_path(output, 'window.log'), app.stdout_slurp() + app.stderr_slurp()) or {}
		app.close()
	}
	first := report_when(report, fn (r InputReport) bool {
		return r.frame >= 3
	}, 'initial layout')!
	if math.abs(first.scale - f64(dpi) / 96) > .01 {
		return error('Unexpected scale: ${first.scale}')
	}
	ids := command(['xdotool', 'search', '--onlyvisible', '--name',
		r'^Audio playground \| antono2\.audio$'])!.split_into_lines()
	if ids.len != 1 { return error('Expected one audio window, got ${ids}') }
	window := ids[0]
	command(['xdotool', 'windowfocus', '--sync', window])!
	baseline := next_layout(report, first)!
	os.write_file(os.join_path(output, 'initial.json'), json2.encode(baseline))!
	for position in [[f64(.05), .05], [.95, .05], [.05, .95],
		[.95, .95], [.5, .5]] {
		// Reuse pre-transition bounds just as an external observer can during a frame.
		click(window, report, 'play', baseline.items['play'], position[0], position[1])!
		playing := report_when(report, fn (r InputReport) bool {
			return r.state.playing
		}, 'play')!
		settled_playing := next_layout(report, playing)!
		os.write_file(os.join_path(output, 'playing.json'), json2.encode(settled_playing))!
		unchanged_buttons(baseline, settled_playing)!
		click(window, report, 'stop', baseline.items['stop'], position[0], position[1])!
		stopped := report_when(report, fn (r InputReport) bool {
			return !r.state.playing
		}, 'stop')!
		unchanged_buttons(baseline, next_layout(report, stopped)!)!
		click(window, report, 'mute', baseline.items['mute'], position[0], position[1])!
		muted := report_when(report, fn (r InputReport) bool {
			return r.state.gain == 0
		}, 'mute')!
		unchanged_buttons(baseline, next_layout(report, muted)!)!
		click(window, report, 'mute', baseline.items['mute'], position[0], position[1])!
		restored := report_when(report, fn (r InputReport) bool {
			return r.state.gain > 0
		}, 'unmute')!
		unchanged_buttons(baseline, next_layout(report, restored)!)!
	}
	command(['xdotool', 'key', 'F12'])!
	deadline := time.sys_mono_now() + 5 * time.second
	for app.is_alive() && time.sys_mono_now() < deadline {
		time.sleep(10 * time.millisecond)
	}
	if app.is_alive() { return error('Audio window did not close') }
	app.wait()
	if app.code != 0 { return error('Audio window exited ${app.code}') }
	println('PASS: stable button geometry and native edge clicks at ${dpi}/96 scale')
}

fn run() ! {
	root := @VMODROOT
	mut scales := [96, 105, 120, 144, 192]
	index := os.args.index('--dpi')
	if index >= 0 {
		if index + 1 >= os.args.len {
			return error('Usage: audio_input_geometry.vsh [--dpi 72..240]')
		}
		dpi := os.args[index + 1].int()
		if dpi < 72 || dpi > 240 { return error('DPI must be between 72 and 240') }
		scales = [dpi]
	}
	if '--inside-xvfb' !in os.args {
		result := os.execute('xvfb-run -a -s ' +
			os.quoted_path('-screen 0 1920x1080x24 -noreset -nolisten tcp') + ' ' +
			os.quoted_path(os.executable()) + ' --inside-xvfb ' +
			os.args[1..].map(os.quoted_path(it)).join(' '))
		print(result.output)
		if result.exit_code != 0 { return error('Native input geometry check failed') }
		return
	}
	os.unsetenv('WAYLAND_DISPLAY')
	os.setenv('LIBGL_ALWAYS_SOFTWARE', '1', true)
	os.setenv('LP_NUM_THREADS', '1', true)
	for entry in os.ls('/usr/share/vulkan/icd.d')! {
		if entry.starts_with('lvp_icd') {
			os.setenv('VK_DRIVER_FILES', os.join_path('/usr/share/vulkan/icd.d', entry), true)
		}
	}
	if os.exists('/usr/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json') {
		os.setenv('VK_INSTANCE_LAYERS', 'VK_LAYER_KHRONOS_validation', true)
	}
	for dpi in scales {
		check_scale(root, dpi)!
	}
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
