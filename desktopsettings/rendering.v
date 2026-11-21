// Share desktop rendering budgets between the dashboard and its smoke checks.
module desktopsettings

pub const dashboard_history_samples = 600
pub const standard_smoke_frames = 60

// Render a full dashboard history, then keep going to exercise wraparound.
pub const dashboard_smoke_frames = dashboard_history_samples + standard_smoke_frames
