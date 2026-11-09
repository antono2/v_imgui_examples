// Keeps volume and position within valid audio API bounds.
module model

import math

pub const default_gain = f32(0.10)

pub enum Action {
	none
	play
	stop
	position
	gain
	reset
}

pub struct State {
pub mut:
	x             f32 = -3
	z             f32 = -2
	gain          f32 = default_gain
	previous_gain f32 = default_gain
	playing       bool
}

fn bounded(value f32, low f32, high f32) f32 {
	if math.is_nan(value) || math.is_inf(value, 0) {
		return low
	}
	return f32(math.max(low, math.min(value, high)))
}

pub fn (mut s State) set_position(x f32, z f32) Action {
	s.x = bounded(x, -6, 6)
	s.z = bounded(z, -6, 6)
	return .position
}

pub fn (mut s State) set_gain(value f32) Action {
	s.gain = bounded(value, 0, 1)
	if s.gain > 0 {
		s.previous_gain = s.gain
	}
	return .gain
}

pub fn (mut s State) mute() Action {
	return s.set_gain(if s.gain > 0 { f32(0) } else { s.previous_gain })
}

pub fn (mut s State) reset() Action {
	s.x = -3
	s.z = -2
	s.gain = default_gain
	s.previous_gain = default_gain
	return .reset
}
