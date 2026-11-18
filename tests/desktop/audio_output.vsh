// Measure miniaudio playback through a private stereo sink and its monitor.
import encoding.binary
import math
import os
import rand
import time
import x.json2

const sample_rate = 48_000
const channels = 2
const sample_bytes = 2 // Signed little-endian PCM16.
const frame_bytes = channels * sample_bytes
const capture_seconds = 18
const ready_bytes = sample_rate * frame_bytes / 2
const ready_timeout = 8 * time.second
const poll_interval = 50 * time.millisecond
const pcm16_full_scale = 32_768
const peak_limit = 32_700
const stop_drain_ms = 250
const positions = ['left', 'centre', 'right', 'quiet', 'far']

struct NodeProperties {
	name string @[json: 'node.name']
}

struct NodeInfo {
	props NodeProperties
}

struct SinkNode {
	id   int
	info NodeInfo
}

struct Report {
	backend                 string = 'native miniaudio via an isolated loopback'
	microphone              bool
	virtual_server          string
	rms                     [][]f64
	positions               []string
	quiet_ratio             f64
	far_ratio               f64
	clipping                bool
	stop_is_silent          bool = true
	stop_drain_allowance_ms int  = stop_drain_ms
}

fn require(condition bool, message string) ! {
	if !condition {
		return error(message)
	}
}

fn command(args []string) !string {
	result := os.exec(args)
	require(result.exit_code == 0,
		'${args[0]} exited with status ${result.exit_code}: ${result.output}')!
	return result.output
}

fn launch(program string, args []string, environment map[string]string) !&os.Process {
	path := if os.is_abs_path(program) { program } else { os.find_abs_path_of_executable(program)! }
	mut process := os.new_process(path)
	process.set_args(args)
	process.set_environment(environment)
	process.set_redirect_stdio()
	process.run()
	return process
}

fn stop(mut process os.Process) {
	if process.is_alive() {
		process.signal_kill()
		// V 0.5.2 marks the child aborted before wait() has reaped it.
		process.status = .running
	}
	process.wait()
	process.close()
}

fn drain(mut process os.Process, mut log os.File) {
	for channel in [os.ChildProcessPipeKind.stdout, .stderr] {
		for {
			chunk := process.pipe_read(channel) or { break }
			log.write_string(chunk) or { break }
		}
	}
}

fn finish(mut process os.Process, mut log os.File, timeout time.Duration, label string) ! {
	deadline := time.sys_mono_now() + timeout
	for process.is_alive() {
		drain(mut process, mut log)
		require(time.sys_mono_now() < deadline, '${label} timed out')!
		time.sleep(poll_interval)
	}
	process.wait()
	drain(mut process, mut log)
	require(process.code == 0, '${label} exited with status ${process.code}')!
}

fn observe(root string, directory string, sink string, environment map[string]string) ! {
	recording := os.join_path(directory, 'native-loopback.wav')
	if os.exists(recording) {
		os.rm(recording)!
	}
	mut recorder_log := os.create(os.join_path(directory, 'recording.log'))!
	defer { recorder_log.close() }
	mut player_log := os.create(os.join_path(directory, 'playback.log'))!
	defer { player_log.close() }
	mut recorder := launch('ffmpeg', ['-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-f',
		'pulse', '-i', '${sink}.monitor', '-t', capture_seconds.str(), '-ar', sample_rate.str(),
		'-ac', channels.str(), '-c:a', 'pcm_s16le', recording], environment)!
	defer { stop(mut recorder) }
	// Require captured silence before playback. An open device alone can still lose the start.
	deadline := time.sys_mono_now() + ready_timeout
	for !os.is_file(recording) || os.file_size(recording) < ready_bytes {
		drain(mut recorder, mut recorder_log)
		require(recorder.is_alive() && time.sys_mono_now() < deadline,
			'Loopback recorder did not become ready. See recording.log.')!
		time.sleep(poll_interval)
	}
	mut player := launch(os.join_path(root, 'build', 'audio_playground'), [
		'--audio-check',
		os.join_path(directory, 'audio-events.json'),
	], environment)!
	defer { stop(mut player) }
	finish(mut player, mut player_log, 20 * time.second, 'Native playback. See playback.log')!
	finish(mut recorder, mut recorder_log, capture_seconds * time.second,
		'Loopback capture. See recording.log')!
}

fn observe_pulse(root string, directory string, sink string, mut environment map[string]string) ! {
	temporary := os.join_path(os.temp_dir(), 'audio-loopback-' + rand.uuid_v4())
	os.mkdir(temporary, mode: 0o700)!
	defer { os.rmdir_all(temporary) or {} }
	socket := os.join_path(temporary, 'native')
	environment['PULSE_RUNTIME_PATH'] = temporary
	environment['PULSE_SERVER'] = 'unix:' + socket
	mut log := os.create(os.join_path(directory, 'pulse.log'))!
	defer { log.close() }
	mut server := launch('pulseaudio', ['-n', '--daemonize=no', '--exit-idle-time=-1',
		'--use-pid-file=no',
		'--load=module-null-sink sink_name=${sink} rate=${sample_rate} channels=${channels}',
		'--load=module-native-protocol-unix socket=${socket} auth-anonymous=1'], environment)!
	defer {
		if server.is_alive() {
			server.signal_term()
			finish(mut server, mut log, 5 * time.second, 'PulseAudio shutdown') or {}
		}
		drain(mut server, mut log)
		stop(mut server)
	}
	deadline := time.sys_mono_now() + ready_timeout
	for !os.exists(socket) {
		drain(mut server, mut log)
		require(server.is_alive() && time.sys_mono_now() < deadline,
			'Private PulseAudio socket did not appear. See pulse.log.')!
		time.sleep(poll_interval)
	}
	observe(root, directory, sink, environment)!
}

fn pipewire_nodes(sink string) ![]SinkNode {
	nodes := json2.decode[[]SinkNode](command(['pw-dump'])!)!
	return nodes.filter(it.info.props.name == sink)
}

fn remove_pipewire_sink(sink string) ! {
	for node in pipewire_nodes(sink)! {
		command(['pw-cli', 'destroy', node.id.str()])!
	}
}

fn observe_pipewire(root string, directory string, sink string, environment map[string]string) ! {
	require(pipewire_nodes(sink)!.len == 0, 'Loopback sink already exists')!
	command(['pw-cli', 'create-node', 'adapter',
		'{ factory.name = support.null-audio-sink node.name = ${sink} media.class = Audio/Sink object.linger = true audio.position = [ FL FR ] }'])!
	deadline := time.sys_mono_now() + ready_timeout
	observe_ready_pipewire(root, directory, sink, environment, deadline) or {
		remove_pipewire_sink(sink) or { eprintln(err) }
		return err
	}
	remove_pipewire_sink(sink)!
}

fn observe_ready_pipewire(root string, directory string, sink string, environment map[string]string, deadline i64) ! {
	for pipewire_nodes(sink)!.len == 0 {
		require(time.sys_mono_now() < deadline, 'Private PipeWire sink did not appear')!
		time.sleep(poll_interval)
	}
	observe(root, directory, sink, environment)!
}

fn pcm(path string) ![]i16 {
	data := os.read_bytes(path)!
	require(data.len >= 12 && data[..4].bytestr() == 'RIFF' && data[8..12].bytestr() == 'WAVE',
		'Expected a RIFF/WAVE capture')!
	mut format_ok := false
	mut position := 12 // Skip the RIFF signature, size and WAVE form type.
	for position + 8 <= data.len {
		tag := data[position..position + 4].bytestr()
		length := u64(binary.little_endian_u32_at(data, position + 4))
		position += 8
		require(length <= u64(data.len - position), 'Truncated WAVE chunk ${tag}')!
		end := position + int(length)
		match tag {
			'fmt ' {
				// Format tag 1 is PCM. Offsets refer to the standard WAVE format chunk.
				format_ok = length >= 16 && binary.little_endian_u16_at(data, position) == 1
					&& binary.little_endian_u16_at(data, position + 2) == channels
					&& binary.little_endian_u32_at(data, position + 4) == sample_rate
					&& binary.little_endian_u16_at(data, position + 14) == sample_bytes * 8
			}
			'data' {
				require(format_ok && length % frame_bytes == 0,
					'Expected stereo PCM16 at ${sample_rate} Hz')!
				return []i16{len: int(length) / sample_bytes, init: i16(binary.little_endian_u16_at(data,

					position + index * sample_bytes))}
			}
			else {}
		}

		position = end + int(length % 2) // WAVE pads odd-length chunks to an even byte boundary.
	}
	return error('Capture is missing its PCM data')
}

fn peak(samples []i16) int {
	mut maximum := 0
	for sample in samples {
		maximum = math.max(maximum, math.abs(int(sample)))
	}
	return maximum
}

fn analyze(samples []i16, backend string) !Report {
	mut onset := -1
	for index, sample in samples {
		// Ignore the monitor's low-level noise before the first playback sample.
		if math.abs(int(sample)) > 32 {
			onset = index / channels
			break
		}
	}
	require(onset >= 0, 'Loopback capture is silent')!
	start := math.max(0, onset - sample_rate / 100) // Start 10 ms before the observed onset.
	stride := 2 * sample_rate // The application plays each position for two seconds.
	window := stride * 9 / 10 // Exclude the last 200 ms at each position boundary.
	mut levels := [][]f64{}
	for index in 0 .. positions.len {
		offset := start + index * stride
		require((offset + window) * channels <= samples.len,
			'Insufficient capture for ${positions[index]}')!
		mut sums := [channels]i64{}
		for frame in offset .. offset + window {
			for channel in 0 .. channels {
				sample := i64(samples[frame * channels + channel])
				sums[channel] += sample * sample
			}
		}
		levels << []f64{len: channels, init: math.sqrt(f64(sums[index]) / window) / pcm16_full_scale}
	}
	require(levels[0][0] > levels[0][1] * 2.5, 'Left position did not pan left: ${levels}')!
	centre_ratio := levels[1][0] / levels[1][1]
	require(centre_ratio > 0.94 && centre_ratio < 1.06,
		'Centre channels did not balance: ${levels}')!
	require(levels[2][1] > levels[2][0] * 2.5, 'Right position did not pan right: ${levels}')!
	centre := levels[1][0] + levels[1][1]
	quiet_ratio := (levels[3][0] + levels[3][1]) / centre
	far_ratio := (levels[4][0] + levels[4][1]) / centre
	require(quiet_ratio > 0.43 && quiet_ratio < 0.57, 'Unexpected volume response: ${quiet_ratio}')!
	require(far_ratio > 0.27 && far_ratio < 0.40, 'Unexpected distance attenuation: ${far_ratio}')!
	require(peak(samples) < peak_limit, 'Capture clips')!
	tail := (start + positions.len * stride + stop_drain_ms * sample_rate / 1000) * channels
	require(samples.len - tail >= sample_rate, 'Insufficient post-stop capture')!
	require(peak(samples[tail..]) <= 2, 'Audio continues after Stop')!
	return Report{
		virtual_server: backend
		rms:            levels
		positions:      positions
		quiet_ratio:    quiet_ratio
		far_ratio:      far_ratio
	}
}

fn run() ! {
	root := os.dir(os.dir(@DIR))
	directory := os.join_path(root, 'build', 'audio-validation', 'output')
	os.mkdir_all(directory)!
	report_path := os.join_path(directory, 'audio-output.json')
	if os.exists(report_path) {
		os.rm(report_path)!
	}
	require(os.is_executable(os.join_path(root, 'build', 'audio_playground')),
		'Build the audio playground before running loopback')!
	os.find_abs_path_of_executable('ffmpeg') or {
		return error('Install ffmpeg with PulseAudio support')
	}
	sink := 'audio-visual-test-${os.getpid()}'
	mut environment := os.environ()
	environment['PULSE_SINK'] = sink
	backend := if os.exists_in_system_path('pulseaudio') {
		observe_pulse(root, directory, sink, mut environment)!
		'PulseAudio'
	} else {
		observe_pipewire(root, directory, sink, environment)!
		'PipeWire'
	}
	report := analyze(pcm(os.join_path(directory, 'native-loopback.wav'))!, backend)!
	encoded := json2.encode(report, prettify: true, indent_string: '  ')
	os.write_file(report_path, encoded + '\n')!
	println(encoded)
}

run() or {
	eprintln(err)
	exit(1)
}
