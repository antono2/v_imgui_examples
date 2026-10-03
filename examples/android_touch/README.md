# Android touch and text

The V UI reuses the pinned upstream NativeActivity/Vulkan host, Java input
bridge, and FreeType font. It has its own package ID,
`io.antono2.vimgui.examples.touch`, so it can coexist with upstream's demo.

Install a JDK, CMake/Ninja, V, Android SDK platform/build-tools 36, and NDK r27c.
Android API 24 and a Vulkan-capable device are required. From the repository root:

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
