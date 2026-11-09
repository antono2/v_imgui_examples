// Owns the native audio example lifecycle and keyboard shortcuts.
module main

import examples.glfw_vulkan as host
import examples.audio_playground.model
import antono2.glfw
import antono2.imgui
import os
import time
import json2

struct Demo {
mut:
	session       Session
	silent        bool
	report        string
	last_report   string
	smoke         bool
	frames        int
	scale         f32 = 1
	stacked       bool
	error_message string
	items         map[string]Item
	scroll_y      f32
	scroll_max    f32
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

fn run() ! {
	mut file, mut report, mut audio_report := '', '', ''
	mut silent, mut smoke := false, false
	mut i := 1
	for i < os.args.len {
		match os.args[i] {
			'--help' {
				println('Audio playground — antono2.audio + Dear ImGui / GLFW / Vulkan\n\nUsage: audio_playground [--file MONO.wav|MONO.ogg] [--silent]\n       audio_playground --input-check REPORT.json\n       audio_playground --smoke-test REPORT.json\n       audio_playground --audio-check REPORT.json\n\nP: play/stop; Space: activate focused control; 1/2/3: position presets; +/-: volume; M: mute; R: reset.\nTab: navigate controls; arrows: focused slider; Esc: stop.\nNo automatic playback. Initial volume is 10%.')
				return
			}
			'--silent' {
				silent = true
			}
			'--file', '--input-check', '--smoke-test', '--audio-check' {
				if i + 1 >= os.args.len || os.args[i + 1] == '' {
					return error('Missing value for ${os.args[i]}')
				}
				match os.args[i] {
					'--file' {
						file = os.args[i + 1]
					}
					'--audio-check' {
						audio_report = os.args[i + 1]
					}
					else {
						report = os.args[i + 1]
						smoke = os.args[i] == '--smoke-test'
					}
				}
				i++
			}
			else {
				return error('Unknown argument: ${os.args[i]}. Use --help.')
			}
		}
		i++
	}
	if audio_report != '' && (report != '' || silent || file != '') {
		return error('--audio-check uses native playback and the bundled chime; do not combine modes.')
	}
	mut temporary := ''
	defer { if temporary != '' { os.rmdir_all(temporary) or {} } }
	custom := file != ''
	if !custom {
		temporary = os.join_path(os.temp_dir(), 'antono2-audio-imgui-${os.getpid()}-${time.now().unix_milli()}')
		os.mkdir(temporary, mode: 0o700)!
		file = os.join_path(temporary, 'chime.wav')
		chime := $embed_file('assets/chime.wav')
		os.write_file_array(file, chime.to_bytes())!
	}
	if audio_report != '' {
		run_audio_check(file, audio_report)!
		return
	}
	if report != '' {
		silent = true
	}
	mut demo := &Demo{ session: new_session(file, silent, custom)!, silent: silent, report: report, smoke: smoke }
	defer { demo.session.audio.shutdown() }
	host.run(host.Options{
		title: 'Audio playground | antono2.audio'
		fit_work_area: true
		dockspace: false
		prepare: prepare
	}, frame, demo)
	if demo.error_message != '' {
		return error(demo.error_message)
	}
}

fn prepare(mut app host.App, data voidptr) {
	mut d := unsafe { &Demo(data) }
	window := unsafe { &glfw.Window(app.native_window) }
	d.scale = host.content_scale(window)
	apply_theme(d.scale)
	mut io := imgui.get_io_nil()
	io.IniFilename = unsafe { nil }
	io.LogFilename = unsafe { nil }
	if glfw.get_window_attrib(window, glfw.focused) == 0 && d.session.state.playing {
		d.apply(.stop)
	}
}

fn frame(mut app host.App, data voidptr) {
	mut d := unsafe { &Demo(data) }
	d.frames++
	// This example uses Escape to stop audio; closing uses the native window button.
	app.escape_handled = true
	d.shortcuts()
	d.draw()
	if d.report != '' { d.write_snapshot(app) }
	if (d.smoke && d.frames >= 8) || (d.report != '' && imgui.is_key_pressed_bool(int(imgui.Key.f12), false)) {
		glfw.set_window_should_close(unsafe { &glfw.Window(app.native_window) }, 1)
	}
}

fn (mut d Demo) apply(action model.Action) {
	if d.error_message != '' || action == .none {
		return
	}
	d.session.apply(action) or {
		d.session.audio.stop('chime') or {}
		d.session.state.playing = false
		d.error_message = err.msg()
	}
}

fn (mut d Demo) shortcuts() {
	if imgui.is_key_pressed_bool(int(imgui.Key.escape), false) { d.apply(.stop) }
	io := imgui.get_io_nil()
	if io.WantTextInput || imgui.is_any_item_active() {
		return
	}
	if imgui.is_key_pressed_bool(int(imgui.Key.p), false) {
		d.apply(if d.session.state.playing { model.Action.stop } else { model.Action.play })
	}
	if imgui.is_key_pressed_bool(int(imgui.Key._1), false) {
		d.apply(d.session.state.set_position(-4, -1))
	}
	if imgui.is_key_pressed_bool(int(imgui.Key._2), false) {
		d.apply(d.session.state.set_position(0, -1))
	}
	if imgui.is_key_pressed_bool(int(imgui.Key._3), false) {
		d.apply(d.session.state.set_position(4, -1))
	}
	if imgui.is_key_pressed_bool(int(imgui.Key.m), false) { d.apply(d.session.state.mute()) }
	if imgui.is_key_pressed_bool(int(imgui.Key.r), false) { d.apply(d.session.state.reset()) }
	if imgui.is_key_pressed_bool(int(imgui.Key.equal), true) {
		d.apply(d.session.state.set_gain(d.session.state.gain + 0.05))
	}
	if imgui.is_key_pressed_bool(int(imgui.Key.minus), true) {
		d.apply(d.session.state.set_gain(d.session.state.gain - 0.05))
	}
}

struct CheckEvent {
	label      string
	x          f32
	z          f32
	gain       f32
	started_at i64
}

fn run_audio_check(file string, report string) ! {
	mut s := new_session(file, false, false)!
	defer { s.audio.shutdown() }
	mut events := []CheckEvent{}
	for values in [[f32(-4), -1, 0.2], [f32(0), -2, 0.2], [f32(4), -1, 0.2], [f32(0), -2, 0.1],
		[f32(0), -6, 0.2]] {
		s.apply(s.state.set_position(values[0], values[1]))!
		s.apply(s.state.set_gain(values[2]))!
		s.apply(.play)!
		events << CheckEvent{ label: ['left', 'centre', 'right', 'quiet', 'far'][events.len], x: s.state.x, z: s.state.z, gain: s.state.gain, started_at: time.now().unix_milli() }
		time.sleep(2 * time.second)
		s.apply(.stop)!
	}
	time.sleep(600 * time.millisecond)
	os.write_file(report, json2.encode(events))!
}
