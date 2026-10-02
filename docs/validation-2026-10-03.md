# Interaction validation — 2026-10-03

Examples source: `f3b6eda`, followed by the viewport-disable synchronization fix
included with this report. ImGui dependency: `1b6059e` (docking) and `60a0d5d`
(standard). Build and packaging CI at `f3b6eda` passed for Linux, Windows, standard
ImGui, and Android armeabi-v7a/arm64-v8a/x86_64.

## Desktop

Linux, Xvfb 1280×900, Openbox, Mesa Lavapipe, pinned V compiler, and Vulkan
validation enabled. Input was sent through X11 and results inspected in captures.

- Gallery: name appeared in Details; checkbox, slider/progress, combo (High), and
  counter (3) updated. Popup closed/reopened. Table divider and window resized.
  Window collapsed/reopened. Upstream demo closed/reopened; dockspace toggled.
- Dashboard: amplitude/frequency changed to 1.62/2.41; series checkboxes and legend
  visibility worked; waveform panning and wheel zoom changed axes. History crossed
  its 600-sample boundary. Pausing kept the history plot pixel-identical across
  captures; reset cleared it and resume restarted samples.
- Default example: secondary window closed/reopened; platform viewports produced
  a separate OS window, which could be moved and disabled again.
- Each application exited with status 0 using the window manager close button.
  The gallery's first Alt+F4 attempt exited 143; a repeat with the title-bar close
  button exited 0. Alt+F4 behavior should be checked on a user's desktop.
- Viewport disable initially reported `VUID-vkDestroyBuffer-buffer-00922`.
  Waiting for the Vulkan device to become idle before disabling viewports fixed
  it. The repeat run and normal shutdown had an empty validation log.

## Connected Android device

M821-EEA tablet, Android 13, armeabi-v7a, 800×1280 physical display, tested in
1280×800 landscape. Keyboard: Gboard (`com.google.android.inputmethod.latin`),
visible DE/EN layout. Installed the signed debug APK built from `f3b6eda`.

- Installation, startup, Vulkan rendering, and native keyboard display passed.
- Three taps produced `Taps: 3` and a matching progress increment.
- Injected ASCII `Hello` appeared in the editable field; cursor offset was 5.
- Back hid the keyboard. Re-tapping requested it again (confirmed in process
  log), but another application took the foreground before a settled capture.
- The sample process remained alive, and its captured process log had no crash
  or Vulkan error. Vendor Mali property-access warnings were present.

Further Android interaction is pending exclusive device access. Unicode editing,
selection replacement, clipboard, rotation, zoom/scroll, resume, and fresh-state
relaunch have **not** been established by this run. Other Android ABIs have build
coverage only. No iOS, screen-reader, or physical Windows interaction is claimed.

Captures and logs are local under the ignored `build/interaction-checks/` directory.
The release checklist remains the source of the remaining checks.
