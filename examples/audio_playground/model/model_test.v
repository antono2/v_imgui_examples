// Checks invalid inputs, volume restoration and default state.
module model

import math

fn test_bounds_reject_invalid_audio_parameters() {
	mut s := State{}
	s.set_gain(f32(math.nan()))
	assert s.gain == 0
	s.set_gain(3)
	assert s.gain == 1
	s.set_gain(-1)
	assert s.gain == 0
	s.set_position(-100, 100)
	assert s.x == -6 && s.z == 6
	s.set_position(f32(math.inf(1)), f32(math.nan()))
	assert s.x == -6 && s.z == -6
}

fn test_mute_restores_last_audible_gain_and_reset_restores_defaults() {
	mut s := State{}
	s.set_gain(0.37)
	s.mute()
	assert s.gain == 0
	s.mute()
	assert math.abs(s.gain - 0.37) < 0.0001
	s.set_position(5, 4)
	assert s.reset() == .reset
	assert s.x == -3 && s.z == -2
	assert s.gain == default_gain && s.previous_gain == default_gain
}
