# Example validation before release

Build and rendering results are recorded in the PR checks. See
[the 2026-10-03 interaction report](validation-2026-10-03.md) for completed checks,
the viewport fix, and the remaining device checks.

## Automated checks

- Compile all desktop examples on Linux and Windows with pinned dependencies.
- Compile and render the standard ImGui variant on Linux.
- Render with Lavapipe, Xvfb, and Vulkan validation; reject errors and require clean shutdown.
- Render 660 dashboard frames to cross the 600-sample ring boundary.
- Compile Android V UI and package signed debug APKs for armeabi-v7a, arm64-v8a, and x86_64.
- Check package identity and the native V UI export.
- Keep current dependency masters as an advisory compatibility check.

Local Linux smoke check, after building the three desktop executables:

```sh
scripts/smoke_desktop.sh "$PWD/build"
```

## Desktop interaction

- [x] Type a name; verify it appears in Details.
- [x] Change the gallery checkbox, slider, and combo; reopen the popup and secondary windows.
- [x] Resize table columns and the main window; collapse/reopen windows.
- [x] Close and reopen the upstream demo.
- [x] Try standard and docking variants; toggle dockspace and platform viewports where supported.
- [x] Change plot amplitude/frequency and series visibility, including legend clicks.
- [x] Pan/zoom waveforms; pause/resume/reset history and observe a full wrap.
- [x] Close each application normally.

## Android interaction

Record the APK revision, ABI, device/Android version, keyboard app, and languages.
Install the matching debug APK; its launcher label is **V ImGui Touch Examples**.

- [x] Tap the counter repeatedly and check the progress indicator.
- [ ] Enter ASCII and non-ASCII text; select and replace part of it with the native keyboard.
- [ ] Move the cursor with touch and hardware keys, where available.
- [ ] Hide the keyboard with Back, then tap the active field to reopen it.
- [ ] Copy/read clipboard text, including non-ASCII text; clear the preview.
- [ ] Rotate while editing; confirm text, count, and zoom survive window recreation.
- [ ] Background/resume the app and repeat an edit.
- [ ] Change zoom, use portrait/landscape, and reach the bottom controls by scrolling.
- [ ] Relaunch after process termination; confirm the sample starts with fresh state.
- [ ] Check logcat for crashes, Vulkan errors, or failed input initialization.

```sh
adb logcat -s vimgui-android-demo:I AndroidRuntime:E
```

Release only after reviewing CI results and recording the interactive results.
No physical-device or assistive-technology coverage is implied by compilation.
