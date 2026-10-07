// Configures native includes and linking for the shared GLFW/Vulkan example host.
// Build with the matching ImGui backend library and configured Vulkan/GLFW paths.
module glfw_vulkan

#flag linux -I$env('VULKAN_SDK')/include
#flag linux -I$env('VULKAN_SDK')/include/vulkan
#flag linux -I$env('VULKAN_SDK')/include/volk
#flag linux -L$env('VULKAN_SDK')/lib
#flag windows -I$env('VULKAN_SDK')/Include
#flag windows -I$env('VULKAN_SDK')/Include/vulkan
#flag windows -I$env('VULKAN_SDK')/Include/Volk
#flag windows -L$env('VULKAN_SDK')/Lib
// GLFW
// https://www.glfw.org/docs/latest/vulkan_guide.html

// C:\glfw-3.4.bin.WIN64\include
// /usr/include
#flag -I $env('GLFW_INCLUDE')
// Windows C:\glfw-3.4.bin.WIN64\lib-mingw-w64
// GNU/Linux /usr/lib/x86_64-linux-gnu
#flag -L $env('GLFW_LIB')

#flag linux   -lglfw
#flag darwin  -lglfw
#flag windows -lglfw3
#flag windows -lgdi32

// Vulkan headers are provided by the Vulkan binding; GLFW must not include OpenGL.
#flag -D GLFW_INCLUDE_NONE

#flag -I @VMODROOT/examples/glfw_vulkan
#include "GLFW/glfw3.h"
#include "imgui_bridge.h"
