# Example validation before release

Build and rendering results are recorded in the PR checks. See
[the 2026-10-03 interaction report](validation-2026-10-03.md) for completed checks,
the viewport fix and the remaining device checks.

## Automated checks

- Compile all desktop examples on Linux and Windows with pinned dependencies.
- Compile and render the standard ImGui variant on Linux.
- Render with Lavapipe, Xvfb and Vulkan validation; reject errors and require clean shutdown.
- Render 660 dashboard frames to cross the 600-sample ring boundary.
- Compile Android V UI and package signed debug APKs for armeabi-v7a, arm64-v8a and x86_64.
- Check package identity and the native V UI export.
- Keep current dependency masters as an advisory compatibility check.

Local Linux smoke check, after building the three desktop executables:

```sh
scripts/smoke_desktop.sh "$PWD/build"
```

## Desktop interaction

- [x] Type a name; verify it appears in Details.
- [x] Change the gallery checkbox, slider and combo; reopen the popup and secondary windows.
- [x] Resize table columns and the main window; collapse/reopen windows.
- [x] Close and reopen the upstream demo.
- [x] Try standard and docking variants; toggle dockspace and platform viewports where supported.
- [x] Change plot amplitude/frequency and series visibility, including legend clicks.
- [x] Pan/zoom waveforms; pause/resume/reset history and observe a full wrap.
- [x] Close each application normally.
- [x] Escape quits each desktop example; active text editing and popups consume it first.
- [x] F11 toggles borderless fullscreen, preserves normal/maximized restore bounds and does not repeat while held.

Run `./tests/desktop/shortcuts.sh binary-dir --raw-gallery` for keyboard checks
of source builds, or omit `--raw-gallery` for accessible release builds. The
check uses its own Xvfb display with Openbox, xdotool, xprop and wmctrl.
It also checks that the display mode is unchanged and enables Vulkan validation
while toggling fullscreen. These keyboard checks were verified locally on Linux.

## Android interaction

Record the APK revision, ABI, device/Android version, keyboard app and languages.
Install the matching debug APK; its launcher label is **V ImGui Touch Examples**.

- [x] Tap the counter repeatedly and check the progress indicator.
- [x] Enter ASCII and non-ASCII text; select and replace part of it with the native keyboard.
- [x] Move the cursor with touch and hardware keys, where available.
- [x] Hide the keyboard with Back, then tap the active field to reopen it.
- [x] Copy/read clipboard text, including non-ASCII text; clear the preview.
- [x] Confirm Copy all text needs no selection; verify empty-field, copy, read and clear feedback.
- [x] Swipe static text and empty space in both directions; retain normal text selection and slider interaction.
- [x] Rotate while editing; confirm text, count and zoom survive window recreation.
- [x] Background/resume the app and repeat an edit.
- [x] Change zoom, use portrait/landscape and reach the bottom controls by scrolling.
- [x] Adapt to visible/hidden navigation bars and keyboard; keep the bottom controls inside the usable area.
- [x] Relaunch after process termination; confirm the sample starts with fresh state.
- [x] Check logcat for crashes, Vulkan errors or failed input initialization.

```sh
adb logcat -s vimgui-android-demo:I AndroidRuntime:E
```

Release only after reviewing CI results and recording the interactive results.
No physical-device or assistive-technology coverage is implied by compilation.

## Integrated accessibility release checks

The portable workflow renders each Linux bundle after copying its dependencies
and exercises the gallery through the real AT-SPI bus, including native roles,
button actions, status, high contrast, 200% text, off-screen list focus/selection
and view switching. Windows bundles are checked for missing imported runtime
DLLs. The Windows workflow also opens the packaged gallery in a runner's user
session and checks UI Automation actions, text/selection, list selection and
exact scroll percentages. Narrator speech still needs manual validation.
Unicode selected-text reads use the native `IUIAutomation` client API. The
legacy .NET selected-range wrapper also crashes against Windows' built-in
RichEdit on this runner; the comparison and reproduction instructions are in
[upstream's text checks](https://github.com/antono2/imgui/blob/master/tests/accessibility/README.md).

On the connected Android tablet, the integrated accessibility build passed native
roles/actions, checkbox state, progress ranges, Unicode text and UTF-16 selection,
full-field clipboard copy/read and feedback, zoom, scrolling from static text
and resume state. Repeat with the final release APK and test portrait/landscape,
visible system navigation bars and IME. Check TalkBack spoken navigation manually;
provider action tests do not establish the quality of spoken announcements.

To run instrumentation against a signed release APK, set
`VIMGUI_ANDROID_TEST_APK`, `VIMGUI_ANDROID_TEST_KEYSTORE` and
`VIMGUI_ANDROID_TEST_PASSWORD_FILE` before running
`scripts/test_android_accessibility.sh`. A debug installation with a different
certificate must be removed first; uninstalling it removes its saved demo data.
