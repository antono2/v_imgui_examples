# Audio playground: building and validation

The example connects native Dear ImGui widgets to the public `antono2.audio`
playback module. It reuses the existing GLFW/Vulkan host and generated bindings;
no handwritten additions to the ImGui generator are required.

## Build

Run `python3 scripts/build_audio_playground.py --check` to check build tools, then
`python3 scripts/build_audio_playground.py --run` to build and launch. Use `python`
on Windows. The script does not install system packages.

Prerequisites:

- Linux: Python 3, Git, CMake, pkg-config, a C/C++ compiler, GLFW development files,
  and a Vulkan driver. On Debian/Ubuntu: `build-essential cmake pkg-config
  libglfw3-dev mesa-vulkan-drivers` plus Python and Git.
- macOS: Xcode command-line tools, Python 3, Git, CMake, pkg-config and GLFW
  (`brew install cmake pkg-config glfw`). Running also requires a configured Vulkan
  loader and MoltenVK. Compilation alone does not verify presentation.
- Windows: Python, Git, CMake, Ninja and a MinGW-w64 GCC/G++ toolchain on PATH.
  The build prepares GLFW and copies runtime DLLs beside the executable. Running
  requires a Vulkan-capable graphics driver.

Pins are in [`dependencies.json`](../examples/audio_playground/dependencies.json).
CMake receives a headers-only Vulkan package; a Vulkan SDK is not needed to compile.
The builder bootstraps the explicit V1 compatibility compiler from pinned V/VC
sources, uses the garbage collector for the long-running UI and builds native
ImGui and miniaudio libraries. It uses Vulkan headers from the pinned binding.
The generated bindings are large: allow approximately 11 GiB RAM/swap for builds.

Output is `build/audio_playground` (`.exe` on Windows). `--modules PATH` chooses
an isolated dependency directory; `--compiler PATH` chooses an explicitly compatible
V compiler. Existing tracked dependency edits cause a refusal rather than a reset.

## Display scaling and interaction

On Windows/Linux the GLFW monitor content scale drives font size, spacing and
native widgets. The initial window is constrained to the monitor work area.
macOS already exposes window positions in logical points; framebuffer scaling
is handled by the ImGui backend, avoiding a second Retina multiplier.

The layout selects two columns only when at least 900 logical units are available.
Otherwise controls precede the diagram. Buttons wrap and a vertical scrollbar
keeps all controls reachable at small sizes. The optional position sliders and
V-call details start collapsed in the compact layout. Fonts are rasterized by
ImGui at the requested size rather than enlarging a low-resolution screenshot.
The embedded vector face uses pixel-aligned advances and a modest glyph-coverage
boost for sharper text, without changing character widths or control sizes.

Pointer hit testing, keyboard navigation, focus and widget activation belong to
ImGui. A custom invisible button handles the position diagram only. Pointer
coordinates are never multiplied by the font scale. OS scale changes are read
before each frame; fonts and spacing are assigned from unscaled base values.

Keyboard: Tab/Shift+Tab navigate, Space activates the focused widget, arrows adjust
a focused slider, P toggles playback, 1/2/3 select positions, M mutes, R resets,
+/- adjust volume and Escape stops playback. Shortcuts do not interfere with
active text/slider editing. Closing the window quits; F11 uses the shared host's
fullscreen toggle. There is no automatic playback and initial gain is 10%.

## Automated validation

```sh
python3 scripts/build_audio_playground.py --test-model
build/audio/toolchain/v/v-audio -cc cc -gc none run tests/desktop/audio_input_geometry.vsh
python3 tests/desktop/audio_input.py
python3 tests/desktop/audio_output.py
```

The build check also loads the executable with `--help`, checking runtime library
discovery without opening a window or an audio device.

The input test needs Xvfb, xrdb, xdotool, ImageMagick and a Vulkan driver (Lavapipe
is supported). It creates a separate **1920×1080** display and tests 100%, 109%,
125%, 150% and 200% scaling, plus a **960×700** window. It drives real X11 events
through GLFW and ImGui: preset/button edges, cancellation, sliders, mute/restore,
source dragging, keyboard, focus loss, resize and scrolling. It captures native
window images. The app's `--input-check` mode uses a null audio device and only
reports observed state and widget bounds; it does not simulate input internally.

Action buttons reserve their widest labels. The V geometry regression checks that
Play/Restart and Mute/Unmute transitions keep all action bounds stable. It reuses
pre-transition coordinates for real edge clicks, acknowledges press/release frames,
and runs Lavapipe with one worker to cover slow rendering. Add `--dpi 192` to run
only the 200% case. Frame numbers and active-item observations are diagnostic
output, never commands to the application.

The output test needs FFmpeg and PulseAudio or PipeWire. It records a dedicated
virtual stereo sink, never a microphone or another application's audio. Native
miniaudio output is checked for left/right panning, centre balance, volume ratio,
distance attenuation, clipping and silence after stopping (250 ms drain allowance).

Reports, logs and PNGs are under `build/audio-validation/`. The Linux input suite
enables Vulkan validation when installed. These tests do not substitute for
physical-device testing on Windows/macOS, mixed-DPI monitor moves or Wayland.
ImGui widgets here do not expose a native screen-reader accessibility tree.

## Code and assets

`main.v` owns lifecycle and shortcuts; `session.v` owns audio calls; `ui.v` builds
the interface; `model/` holds bounded state; `diagnostics.v` observes test runs.
The shared host adds optional work-area sizing and a pre-frame callback without
changing the other examples' defaults. The original mono chime is MIT-licensed
with the example and can be regenerated using `scripts/generate_audio_chime.py`.
Dependency source and licenses remain in their public repositories/checkouts.
