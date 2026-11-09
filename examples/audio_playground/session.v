// Connects UI actions to the public native audio library.
module main

import antono2.audio.playback
import examples.audio_playground.model

// All native audio calls stay on the UI thread. Rendering never synthesizes audio.
struct Session {
mut:
	audio     &playback.Audio = unsafe { nil }
	state     model.State
	last_call string = "audio.set_sound_position(\n    'chime', -3.00, 0, -2.00)!"
}

fn new_session(path string, silent bool, stream bool) !Session {
	mut audio := playback.new_audio(playback.AudioConfig{ null_backend: silent, volume: model.default_gain })!
	mut success := false
	defer { if !success { audio.shutdown() } }
	audio.set_listener([f32(0), 0, 0]!, [f32(0), 0, -1]!, [f32(0), 1, 0]!)!
	audio.load('chime', path, playback.SoundConfig{ looping: true, min_distance: 2, stream: stream })!
	info := audio.info('chime')!
	if info.channels != 1 {
		return error('Use a mono WAV or Ogg file for the spatial demonstration.')
	}
	audio.set_sound_position('chime', -3, 0, -2)!
	success = true
	return Session{ audio: audio }
}

fn (mut s Session) apply(action model.Action) ! {
	match action {
		.none {
			return
		}
		.play {
			s.audio.play('chime')!
			s.last_call = "audio.play('chime')!"
		}
		.stop {
			s.audio.stop('chime')!
			s.last_call = "audio.stop('chime')!"
		}
		.position {
			s.audio.set_sound_position('chime', s.state.x, 0, s.state.z)!
			s.last_call = "audio.set_sound_position(\n    'chime', ${s.state.x:.2f}, 0, ${s.state.z:.2f})!"
		}
		.gain {
			s.audio.set_volume(s.state.gain)!
			s.last_call = 'audio.set_volume(${s.state.gain:.2f})!'
		}
		.reset {
			s.audio.stop('chime')!
			s.audio.set_volume(s.state.gain)!
			s.audio.set_sound_position('chime', s.state.x, 0, s.state.z)!
			s.last_call = 'Stopped; position and volume reset.'
		}
	}
	s.state.playing = s.audio.is_playing('chime')!
}
