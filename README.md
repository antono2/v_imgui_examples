
# Dear ImGui and ImPlot examples in V

[Project portfolio](https://oreskin.de/projects_en.php)

Small runnable examples for the [`antono2/imgui`](https://github.com/antono2/imgui)
V bindings. Desktop examples share a GLFW/Vulkan host; the Android example
reuses upstream's native Vulkan/Activity host and constructs its UI in V.

| Example | Demonstrates | Target |
| --- | --- | --- |
| [GLFW/Vulkan](examples/glfw_vulkan/README.md) | Backend initialization, floating windows, docking | Desktop |
| [Widget gallery](examples/widget_gallery/README.md) | Text buffers, controls, combos, tables, popups | Desktop |
| [ImPlot dashboard](examples/implot_dashboard/README.md) | Lines, scatter plots, series selection, rolling history | Desktop |
| [Touch and text](examples/android_touch/README.md) | Touch controls, IME selection, clipboard, scaling | Android |

CI pins ImGui, GLFW, Vulkan, and V revisions. Linux renders all desktop examples
with Vulkan validation in both standard and docking variants; Windows compiles
all desktop examples. Android CI builds debug APKs for three ABIs. Device testing
is required before release; see [the testing checklist](docs/testing.md).

## Run a release download

[Download a release](https://github.com/antono2/v_imgui_examples/releases) and follow
[installation instructions](docs/installing-releases.md). Desktop ZIPs bundle
their application runtime libraries; Android APKs include their native libraries
and font. The gallery and Android app include labelled native accessibility
controls, high contrast and text sizing.

## Build from source

From this checkout, the cross-platform setup installs/builds ImGui and compiles
the example without opening a window:

```sh
v run setup.vsh
v run setup.vsh --example widget_gallery
v run setup.vsh --example implot_dashboard
```

Setup uses an isolated `build/modules` dependency directory and checks out the
ImGui commit recorded in `IMGUI_REVISION`. It does not discard changes in an
existing dependency checkout. Set `VMODULES` to use a different module directory.
The setup may install system prerequisites through the upstream setup script.

On Linux/macOS, launch `build/glfw_vulkan`, `build/widget_gallery`, or
`build/implot_dashboard` after setup. Windows setup reports its executable path.
Use `--build-only` to compile using dependencies already prepared, or `--check`
for read-only prerequisite diagnostics. Both accept `--example`.

For Android, set the SDK/NDK paths and ABI, then run
`scripts/build_android.sh --build-only`. It builds a signed debug APK without
installing it. See [Android instructions](examples/android_touch/README.md).

The pinned ImGui commit includes the external-example host options. Use this
revision rather than an older installed module.

The ImGui repository owns native-library setup and pins a tested revision of
this example. On Ubuntu or Debian, the shortest supported path is:

```bash
git clone --recursive https://github.com/antono2/imgui
cd imgui
./scripts/setup_linux.sh --install
./scripts/run_demo.sh
```

Use `./scripts/setup_linux.sh --check` instead when system-changing package
installation is not wanted. See the ImGui
[`QUICKSTART.md`](https://github.com/antono2/imgui/blob/master/QUICKSTART.md)
for Fedora, Windows, static linkage, and bundled-GLFW choices.

## Direct source build

Install the V modules, build the native ImGui library, and configure the
Vulkan/GLFW locations before compiling this repository:

```bash
v install antono2.imgui
cd ~/.vmodules/antono2/imgui
./build_vimgui.sh --linkage shared --glfw system

git clone https://github.com/antono2/v_imgui_examples
cd v_imgui_examples
export VULKAN_SDK=/usr
export GLFW_INCLUDE=/usr/include
export GLFW_LIB=/usr/lib/x86_64-linux-gnu
export VMODULES="${VMODULES:-$HOME/.vmodules}"
v -no-memory-limit -path "$VMODULES/antono2|@vlib|@vmodules" run .
```

The generated ImGui and ImPlot bindings make this an unusually large V
compilation and it may require about 11 GiB of memory. The
`-no-memory-limit` option prevents V's default compiler memory guard from
stopping a machine that has sufficient RAM or swap.

The demo requires a graphical session and a Vulkan-capable GPU/driver. Building
successfully does not guarantee that Vulkan presentation is available on the
selected machine. CI compiles this standalone demo with MSVC and verifies its
native Windows DLL artifacts; graphical presentation still requires a real GPU
session.

The window displays the selected ImGui upstream variant. With the default
`imgui` docking branch it creates a main-viewport dockspace and offers an
optional platform-viewports checkbox for moving ImGui windows outside the GLFW
window. With the `imgui` standard branch, the same source keeps independent
floating windows and reports that docking is unavailable.

## Layout

The root `main.v` retains the GLFW/Vulkan demo as the default. Each new desktop
example has its own `main.v`; the Android UI exports the callback consumed by
the upstream native host. `examples/glfw_vulkan/` contains the shared desktop
loop, native flags, and the default demo UI. ImPlot context/spec objects are
created and destroyed through host lifecycle callbacks.

The release gallery and touch app integrate the application/accessibility layer.
Raw API views retain ordinary ImGui widgets; they do not automatically expose
screen-reader semantics. iOS/Metal remains an upstream source integration.

![V + Vulkan + GLFW + Dear ImGui](Snapshot_glfw_vulkan.png)
