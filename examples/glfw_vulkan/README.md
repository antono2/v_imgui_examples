# GLFW/Vulkan host and default demo

From the repository root:

```sh
v run setup.vsh
```

On Linux/macOS, launch `build/glfw_vulkan`. Windows setup reports its executable.
The root `main.v` still launches this example.

`main.c.v` owns the GLFW window, Vulkan objects, frame submission, and shutdown.
`ui.v` owns the default demo's persistent state. Other desktop examples pass a
frame callback and borrowed state pointer to `glfw_vulkan.run`. Optional
initialize/shutdown callbacks run while the ImGui context is alive.

Close and reopen the demo and secondary windows. In the docking variant, toggle
main dockspace or platform viewports. In the standard variant those controls are
unavailable. Disable main dockspace to see the Vulkan clear color; otherwise the
dockspace covers it with the current ImGui style background.
