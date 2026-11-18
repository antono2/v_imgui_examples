// Generate the original MIT-licensed mono chime as PCM WAV.
import encoding.binary
import math
import os

const sample_rate = 48000
const duration_seconds = 2
const channels = 1
const bytes_per_sample = 2
const pcm_format = 1
const max_sample = 32767
const main_tone_hz = 440.0
const overtone_hz = 660.0
const overtone_gain = 0.3
const peak_gain = 0.24
const attack_rate = 90.0
const release_rate = 6.0
const fade_end_seconds = 1.2
const fade_duration_seconds = 0.15
const sample_count = duration_seconds * sample_rate
const pcm_bytes = sample_count * bytes_per_sample

fn append_u16(mut wav []u8, word u16) {
	mut bytes := []u8{len: 2}
	binary.little_endian_put_u16(mut bytes, word)
	wav << bytes
}

fn append_u32(mut wav []u8, word u32) {
	mut bytes := []u8{len: 4}
	binary.little_endian_put_u32(mut bytes, word)
	wav << bytes
}

fn wave() []u8 {
	mut wav := []u8{cap: 44 + pcm_bytes}
	wav << 'RIFF'.bytes()
	// RIFF size excludes its own eight-byte chunk header.
	append_u32(mut wav, 36 + pcm_bytes)
	wav << 'WAVEfmt '.bytes()
	append_u32(mut wav, 16) // PCM format chunk size.
	append_u16(mut wav, pcm_format)
	append_u16(mut wav, channels)
	append_u32(mut wav, sample_rate)
	append_u32(mut wav, sample_rate * channels * bytes_per_sample)
	append_u16(mut wav, channels * bytes_per_sample)
	append_u16(mut wav, bytes_per_sample * 8)
	wav << 'data'.bytes()
	append_u32(mut wav, pcm_bytes)
	for index in 0 .. sample_count {
		seconds := f64(index) / sample_rate
		envelope := (1.0 - math.exp(-seconds * attack_rate)) * math.exp(-seconds * release_rate)
		fade := math.max(0.0, math.min(1.0, (fade_end_seconds - seconds) / fade_duration_seconds))
		tones := math.sin(math.tau * main_tone_hz * seconds) +
			overtone_gain * math.sin(math.tau * overtone_hz * seconds)
		value := peak_gain * envelope * fade * tones / (1.0 + overtone_gain)
		append_u16(mut wav, u16(i16(math.round(value * max_sample))))
	}
	return wav
}

fn run_cli() ! {
	args := os.args[1..]
	if args.len > 1 || (args.len == 1 && args[0] != '--check') {
		return error('Usage: v run scripts/generate_audio_chime.vsh [--check]')
	}
	path := os.join_path(os.dir(@DIR), 'examples', 'audio_playground', 'assets', 'chime.wav')
	generated := wave()
	if args.len == 1 {
		if os.read_bytes(path)! != generated {
			return error('Bundled chime differs from generated PCM: ${path}')
		}
	} else {
		os.write_file_array(path, generated)!
	}
	println(path)
}

run_cli() or {
	eprintln(err)
	exit(1)
}
