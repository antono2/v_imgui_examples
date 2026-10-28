# Dear ImGui 1.93 standard compatibility — 2026-10-28

The standard desktop profile selects `v0.4.0-standard` (Dear ImGui 1.93.0).
The default docking/Android profile retains its existing dependency pin.
Variants can advance independently: the installed-dependency checker now
accepts an explicit `--tag-override module=tag`, while still checking the exact
Git tag commit and all transitive pins. The old suffix option remains supported.

Local Linux builds used the tested stable compiler `1f128c9`, TinyCC and a
matching rebuilt 1.93 standard native library. Screenshots in a private
Xvfb/Openbox display were inspected for:

- GLFW/Vulkan: standard-variant notice, Dear ImGui 1.93 demo, counter input;
- Widget gallery: edited text, incremented counter, popup and table rendering;
- ImPlot dashboard: both waveform series, rolling history and control input;
- Native accessible gallery: retained application widgets, text entry, count
  and high-contrast controls.

The raw desktop rendering smoke tests passed with Lavapipe and Vulkan
validation: 60 frames each for GLFW/Vulkan and the widget gallery, and 660 for
the dashboard, including history wraparound. The retained accessibility-tree
test passed 100,000 rows, off-screen actions, invalid-tree rollback and stale
action filtering. Five real-Git dependency-checker regression tests and six
distribution tests passed.

The desktop shortcut suite passed F11/held-key handling, geometry restoration,
maximized-state restoration and Escape behavior for editing, popups and exit.
An initial fresh-session launch hit the existing five-second window-visibility
deadline; a clean rerun passed the complete suite. This is not a claim of
exhaustive window-manager startup reliability.

These are local Linux visual checks, not Windows/macOS visual tests, physical
Android/iOS device tests or a full screen-reader certification. Existing
published ZIPs/APKs are not rebuilt or relabelled by this source update.
