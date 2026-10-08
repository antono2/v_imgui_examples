# Widget gallery

From the repository root:

```sh
./setup.vsh --example widget_gallery
```

On Linux/macOS, launch `build/widget_gallery`. Windows setup reports its executable.

The example keeps widget values in one V struct that outlives every frame. It
shows a fixed text buffer, checkbox, slider, progress indicator, combo, button,
popup, resizable table and optional secondary window. `Begin`/`End` pairs remain
balanced when windows are collapsed. The name buffer holds at most 127 UTF-8
bytes plus its terminator.

Type a name and open Details; change controls; open/close the popup and Details;
resize table columns; toggle the upstream demo. Docking is optional and the same
source runs against the standard ImGui variant.

![widget gallery](screenshot.png)

## Accessible release view

The portable release builds this same example with `-d release_accessibility
-d appui_embedded` and a native library configured with `VIMGUI_APPLICATION_UI`.
It starts with labelled native accessibility controls, high contrast, 200% text,
status/progress and a virtual file list. Focus last file reveals the list and
moves keyboard/native focus to its last row. Switch to Raw ImGui widgets for
the original tables, popups and secondary windows. See
[release installation](../../docs/installing-releases.md) for supported downloads.
Use `./scripts/build_release.v docking` to build the accessible
package from prepared dependencies (Windows uses a Visual Studio developer shell).
The normal setup command remains the direct raw API build.
