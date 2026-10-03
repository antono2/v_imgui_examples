# Installing release downloads

Download assets from [Releases](https://github.com/antono2/v_imgui_examples/releases).
The downloads include their application libraries. You do not need to install
V, CMake, GLFW, an Android SDK, or a separate Visual C++ runtime.
Your operating system, graphical desktop and graphics driver still provide the
platform services. The examples use Vulkan; a supported Vulkan graphics driver
is required.

## Desktop

Choose a ZIP for your OS and **x64** processor. **Docking** is the recommended download:

- **Windows:** Windows 10 or 11. Extract the entire ZIP to a writable folder.
  Open `examples.exe`, then choose an example from its menu. Press Enter for the
  Widget gallery. You can also open each example executable directly.
  Keep the DLLs beside the executables.
- **Linux:** Ubuntu 24.04 or a compatible newer distribution, with an X11 or
  XWayland desktop. Extract the entire ZIP. Run `./run.sh`, or
  choose an example from its menu (Enter opens Widget gallery), or run
  `./run.sh implot_dashboard` / `./run.sh glfw_vulkan` directly.
  Keep the `lib` directory beside the executables. If your archive tool drops
  executable permissions, run `chmod +x run.sh examples glfw_vulkan widget_gallery implot_dashboard`.

**Docking** includes ImGui docking and optional platform viewports.
**Standard** uses independent ImGui windows. Both contain all three examples.
You can move the extracted folder; binaries use package-relative library paths.
Press **F11** to toggle borderless fullscreen and restore the previous window
position and size. **Escape** quits, after any active edit or popup consumes it.
`licenses/` and `RUNTIME-LIBRARIES.txt` identify bundled components.

## Android: installation without a Play Store

The Android app needs Android 7.0 (API 24) or later and Vulkan 1.0 support.

1. Download `v-imgui-touch-universal.apk` on the device. It contains ARM 32-bit,
   ARM 64-bit, and x86_64 libraries, so you do not need to choose an ABI.
   Smaller APKs for each ABI are also available.
2. Open the download. If Android asks, allow **Install unknown apps** for the
   browser or file manager used to open this APK, then return to the installer.
   Menu names vary by device. You can disable that permission after installation.
3. Install and open **V ImGui Touch Examples**. Everything needed by the app,
   including native libraries and its font, is in the APK.

To update, install a later release APK over the existing app. Published releases
use the same signing identity. Builds from CI are developer test APKs signed
with debug keys; to replace one with a release, uninstall the test app first.
Uninstalling removes its application data. A signature conflict is not fixed by
installing extra libraries.

Optional installation from a computer with Android platform tools:

```sh
adb install -r v-imgui-touch-universal.apk
```

The app has no Internet permission. Clipboard copy uses the whole editable
field, and read displays a preview. Touch scrolling works on static text and
empty space. Navigation bars and the keyboard reserve space automatically.

## Accessibility in the examples

The desktop widget gallery opens in **Accessible controls** mode. It includes
labelled input, native button/checkbox/radio actions, keyboard focus, status and
progress, high contrast, 200% text, and a virtual file list with off-screen focus.
The **Raw ImGui widgets** view retains the original API gallery, tables and
popups. Raw ImGui widgets and ImPlot charts do not automatically publish native
screen-reader semantics; use Accessible controls to exercise that layer.

The Android touch app uses the same application/accessibility layer for its
normal controls. Try TalkBack or your device's accessibility service, keyboard
navigation, high contrast and larger text. The native adapter exposes Unicode
text and selection to assistive technology and forwards edits to the keyboard.
Font coverage depends on the bundled font; Unicode round-trips even when a
particular glyph is unavailable.

There is no separate accessibility app to install. On Linux the native bridge
uses AT-SPI, on Windows UI Automation, and on Android native accessibility nodes.
See [testing](testing.md) for the verified checks and manual release checklist.

## Other platforms and verification

Upstream includes iOS/Metal source integrations. Installable iOS artifacts are
not part of this release: device signing and hardware testing remain necessary.
macOS portable Vulkan packages are also not currently published.

Compare a downloaded file with `SHA256SUMS.txt` from the same release. On Linux
use `sha256sum <filename>`; on Windows use `Get-FileHash <filename> -Algorithm SHA256`.
