# Android touch and text

The V UI reuses the pinned upstream NativeActivity/Vulkan host, Java input
bridge, and FreeType font. It has its own package ID,
`io.antono2.vimgui.examples.touch`, so it can coexist with upstream's demo.

Install a JDK, CMake/Ninja, V, Android SDK platform/build-tools 36, and NDK r27c.
Android API 24 and a Vulkan-capable device are required. From the repository root:

Run `./setup.vsh` and choose **Android touch and text** for guided SDK/NDK
detection, device selection, building and installation. Enable USB debugging on
the device and accept its authorization prompt. The runner asks before building
and installing; it never uninstalls an existing app to resolve a signing conflict.
If multiple NDKs or devices are available, it asks which one to use.

For a build without prompts or device installation:

```sh
export ANDROID_SDK_ROOT=/path/to/android-sdk
export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/27.3.13750724"
export ANDROID_ABI=armeabi-v7a  # or arm64-v8a / x86_64
scripts/build_android.sh --build-only
```

The signed debug APK is
`build/android-touch-<abi>/vimgui-demo-<abi>.apk`. The default command only builds.
Set `V_BIN` to choose a compiler or `IMGUI_DIR` to reuse a checkout at exactly the
commit in `IMGUI_REVISION`. The build initializes that checkout's submodules.

To build, install, and launch on your selected device:

```sh
export ANDROID_SERIAL=your-device-serial
scripts/build_android.sh run
```

With no `ANDROID_ABI`, run mode selects the connected device's ABI. Build-only
mode requires an explicit ABI. CI also uploads APK artifacts for all three ABIs.

The UI demonstrates touch targets, a tap counter, editable text with synchronized
IME selection, clipboard preview, zoom, and scrolling. The host owns the text,
clipboard, tap, and zoom state. Window recreation preserves it; process death
restarts the sample. Clipboard preview is bounded and avoids cutting a UTF-8 code
point. Inline marked-text styling and candidate geometry remain upstream limits.

Follow [the release checklist](../../docs/testing.md). APK creation and symbol
checks do not establish correct behavior on a real keyboard or device.

## Accessible build and release installation

Release APKs use the application/accessibility layer in this same V UI. Set
`VIMGUI_ANDROID_APPLICATION_UI=1` before running the build script to enable
labelled native accessibility controls, high contrast and the touch-sized theme.
This build uses the Android SDK/NDK and Java toolchain; the upstream
script builds the native C++ accessibility bridge and Java node provider.
The host retains ownership of the input bridge, lifecycle and safe area.

End users only download and install an APK; follow
[installation without a Play Store](../../docs/installing-releases.md).
No development tools or additional application libraries are needed on the device.
Run `scripts/test_android_accessibility.sh` against the accessible debug build on
a connected device to exercise roles/actions, Unicode selection, full-field
clipboard, text sizing, content swipe and resume. It keeps configured accessibility
services enabled. Human screen-reader navigation remains part of release testing.
