V ImGui examples — Ubuntu 24.04 or newer, x86_64

Extract the whole archive. From its directory, run:
  ./run.sh

Choose an example from the menu. Press Enter for Widget gallery.
To launch directly:
  ./run.sh widget_gallery
  ./run.sh implot_dashboard
  ./run.sh glfw_vulkan

In an example, Escape quits after active controls consume it to cancel an edit
or popup. F11 toggles borderless fullscreen and restores the previous window.

The examples, ImGui/ImPlot library, GLFW, Vulkan loader, C++ runtime, and
non-system runtime dependencies are included. No V compiler, Vulkan SDK,
or additional application libraries need to be installed.

A graphical X11/XWayland desktop and a Vulkan-capable graphics driver are
required. The graphics driver and base OS (including glibc) remain supplied
by your operating system. This is not a package for a headless server.

Keep the lib/ directory beside the executables. Paths inside the archive
are relative, so the extracted directory can be moved. VARIANT.txt names
the ImGui variant; RUNTIME-LIBRARIES.txt lists the bundled libraries.
Third-party license notices are in licenses/.
