module glfw_vulkan

import vulkan as vk

#flag linux -I$env('VULKAN_SDK')/include
#flag linux -I$env('VULKAN_SDK')/include/vulkan
#flag linux -I$env('VULKAN_SDK')/include/volk
#flag linux -L$env('VULKAN_SDK')/lib
#flag windows -I$env('VULKAN_SDK')/Include
#flag windows -I$env('VULKAN_SDK')/Include/vulkan
#flag windows -I$env('VULKAN_SDK')/Include/Volk
#flag windows -L$env('VULKAN_SDK')/Lib

//#include "vulkan.h"
#define VOLK_IMPLEMENTATION
#define VK_NO_PROTOTYPES
#include "volk.h"

fn C.volkInitialize() vk.Result
fn C.volkLoadInstance(vk.Instance)
fn C.volkLoadDevice(vk.Device)


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

// Please see https://www.glfw.org/docs/latest/build_guide.html#build_macros for more information
//#flag windows -DGLFW_INCLUDE_GLCOREARB=1 // makes the GLFW header include the modern GL/glcorearb.h header (OpenGL/gl3.h on macOS) instead of the regular OpenGL header.
#flag -D GLFW_INCLUDE_NONE
//#flag -D GLFW_INCLUDE_VULKAN

#include "GLFW/glfw3.h"
