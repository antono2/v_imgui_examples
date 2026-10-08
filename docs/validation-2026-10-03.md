# Interaction validation — 2026-10-03

Examples source: `f3b6eda`, followed by the viewport-disable synchronization fix
included with this report. Initial ImGui dependency: `1b6059e` (docking) and `60a0d5d`
(standard); Android lifecycle repeats use the corrected hosts noted below. Build and packaging CI at `f3b6eda` passed for Linux, Windows, standard
ImGui and Android armeabi-v7a/arm64-v8a/x86_64.

## Desktop

Linux, Xvfb 1280×900, Openbox, Mesa Lavapipe, pinned V compiler and Vulkan
validation enabled. Input was sent through X11 and results inspected in captures.

- Gallery: name appeared in Details; checkbox, slider/progress, combo (High) and
  counter (3) updated. Popup closed/reopened. Table divider and window resized.
  Window collapsed/reopened. Upstream demo closed/reopened; dockspace toggled.
- Dashboard: amplitude/frequency changed to 1.62/2.41; series checkboxes and legend
  visibility worked; waveform panning and wheel zoom changed axes. History crossed
  its 600-sample boundary. Pausing kept the history plot pixel-identical across
  captures; reset cleared it and resume restarted samples.
- Default example: secondary window closed/reopened; platform viewports produced
  a separate OS window, which could be moved and disabled again.
- Standard variant: the default example rendered, demo visibility toggled and
  the secondary window opened/moved. Docking/viewport controls were absent as
  expected. Normal close exited 0 with an empty Vulkan validation log. The
  standard gallery/dashboard retain CI compile/render coverage.
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

- Installation, startup, Vulkan rendering and native keyboard display passed.
- Three taps produced `Taps: 3` and a matching progress increment.
- Injected ASCII `Hello` appeared in the editable field; cursor offset was 5.
- An on-device instrumentation helper exercised Android `InputConnection` with
  `Aä📷éZ`, replaced the selection spanning `ä📷` with `café` and composed `ü`.
  Native text snapshots matched every expected result. This checks the text
  bridge, including UTF-16/UTF-8 boundaries; it does not establish every Gboard
  language's composition behavior or emoji glyph coverage.
- Touch moved the cursor, and an injected left-arrow key changed its byte offset.
  Back hid Gboard; tapping the active field reopened it. Settled screenshots
  confirmed both states. The helper uses touchscreen-source events and shell
  key events; no physical keyboard is claimed.
- Copy returned the exact Unicode text `AüéZ` through Android ClipboardManager.
  Read displayed it in the preview, and Clear removed the preview.
- Rotation preserved `Lifecycle42`, two taps and 1.68× zoom; the bottom zoom and
  checklist controls were reachable by dragging the scrollbar in portrait and
  landscape. Editing remained possible after background/resume (`Resumed` was
  inserted into the retained text).
- Background/resume exposed a host bug: a recreated ImGui context retained the
  zoom value but initialized the rendered scale without that zoom. Both upstream
  variants now initialize with `density_scale * zoom`. The rebuilt APK using
  host `050bcbc` passed the repeat: `ZoomRetained`, two taps, the 1.68× slider
  value and enlarged rendered fonts survived window/context recreation. A
  further portrait/landscape cycle and text edit also passed. Standard host
  counterpart: `f5818aa`; mobile-file parity passed.
- Force-stop/relaunch produced empty text/preview, zero taps and 1.00× zoom.
- Process-filtered logcat covered initialization, editing, orientation and
  native window teardown/recreation: no application crash, Vulkan error or
  failed input initialization was found. Vendor Mali property-access warnings
  and platform Binder/debugger diagnostics were present. No Vulkan validation
  layers were enabled on the tablet.
- The original rotation settings were restored and the temporary instrumentation
  helper uninstalled. The corrected sample APK remains installed for user testing.

Other Android ABIs have build coverage only. No iOS, screen-reader or physical
Windows interaction is claimed. The original fullscreen layout rendered beneath the native keyboard/navigation
overlay. The content-area follow-up below corrects this behavior.

Captures and logs are local under the ignored `build/interaction-checks/` directory.
The release checklist remains the source of the remaining checks.

## Swipe scrolling and clipboard feedback follow-up

The user's subsequent tablet test identified two usability gaps in the first
version: scrolling required the scrollbar, and clipboard actions had no visible
confirmation. The earlier scrolling check above covered the scrollbar only.

The V example now tracks touchscreen drags beginning on static text or empty
window space. It starts after the window's widgets are submitted, excludes active
controls, clamps to the scroll limits and uses window-owned gesture state.
Bottom padding keeps the last controls above the Android navigation overlay when
scrolled to the end. This is direct dragging; there is no kinetic scrolling.

Clipboard buttons now explain that Copy all text copies the whole editable field.
An empty field prompts the user to enter text. Copy reads back the system
clipboard, confirms equality and displays the result; Read and Clear preview
have explicit feedback. Editing clears stale action feedback. A field hint
identifies where text can be entered.

The corrected armeabi-v7a APK was rebuilt and installed on the same tablet:

- Swiping explanatory text scrolled without touching the scrollbar. Swiping
  empty space moved the page in both directions and clamped at the bottom.
- Portrait tests at 1.19× and 1.62× reached the zoom and checklist controls.
  Reverse swipes moved the page back; the slider changed zoom normally.
- A horizontal drag inside the input selected a substring (offsets 14..2).
  Copy all text still copied the full `SwipeClipboard42`, which appeared in
  the clipboard preview with confirmation.
- In the final build, empty Copy displayed its message; typing
  `ClipboardFinal` cleared that message. Copy/Read displayed the full text
  and read feedback. Clear removed the preview and explained that the system
  clipboard was unchanged.
- The process-filtered log contained no application crash, Vulkan error or
  failed input initialization. Original rotation settings were restored.

The corrected APK remains installed. These are tablet checks, including its
800-pixel portrait layout; physical phone and assistive-technology interaction
remain outside this coverage.

## Automatic Android content area follow-up

Replaced the fixed navigation spacer with NativeActivity's current content
rectangle. Both upstream host variants publish its clamped position and size as
the main viewport's work area and pass its dimensions to the V callback. The V
window uses that position and size every frame. Rendering and input coordinates
stay relative to the full native surface. The host reads the rectangle under
the native-app-glue mutex; an uninitialized/empty rectangle falls back to the
full display. The built-in upstream V sample also uses the work area.

On the same Android 13 tablet, the rebuilt APK passed:

- Landscape: 1280×800 surface, GUI bottom at y=736, navigation bar below it.
  Swiping to the end left the complete checklist above the bar without a dummy
  bottom spacer.
- Portrait: GUI bottom at y=1216 on the 800×1280 surface; navigation bar remained
  outside the GUI. The typed `InsetsCheck` survived rotation.
- Gboard: the GUI shortened above the keyboard (y=373 in the landscape capture)
  and expanded when Back hid it; text entry remained functional.
- Temporarily hiding navigation with Android's immersive policy expanded the GUI
  to the full portrait height. Restoring visibility restored the reserved area.
  The original absent policy and original rotation settings were restored.

This tests dynamic visible/hidden software navigation on one tablet. Hardware
buttons, side navigation bars and display cutouts were not physically tested;
the layout uses all four reported content edges instead of assuming a bar size.
