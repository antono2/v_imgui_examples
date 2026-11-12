// GLFW 3.3's synchronous X11 show can wait inside an unrelated event queue.
// Request mapping directly so our event loop, retries and deadline stay active.
module glfw_vulkan

import antono2.glfw

#flag -ldl
#include <dlfcn.h>

fn C.dlsym(voidptr, &char) voidptr

type NativeDisplayFn = fn () voidptr

type NativeWindowFn = fn (&glfw.Window) usize

type NativeMapFn = fn (voidptr, usize) int

type NativeFlushFn = fn (voidptr) int

type NativePlatformFn = fn () int

fn request_x11_mapping(window &glfw.Window) bool {
	// Native X11 entry points are optional in Wayland GLFW builds. Looking
	// them up avoids adding an X11 link requirement to those builds.
	platform_symbol := C.dlsym(unsafe { nil }, c'glfwGetPlatform')
	if !isnil(platform_symbol) {
		platform := unsafe { NativePlatformFn(platform_symbol) }
		if platform() != glfw.platform_x11 { return false }
	}
	display_symbol := C.dlsym(unsafe { nil }, c'glfwGetX11Display')
	window_symbol := C.dlsym(unsafe { nil }, c'glfwGetX11Window')
	map_symbol := C.dlsym(unsafe { nil }, c'XMapWindow')
	flush_symbol := C.dlsym(unsafe { nil }, c'XFlush')
	if isnil(display_symbol) || isnil(window_symbol) || isnil(map_symbol) || isnil(flush_symbol) {
		return false
	}
	get_display := unsafe { NativeDisplayFn(display_symbol) }
	get_window := unsafe { NativeWindowFn(window_symbol) }
	map_window := unsafe { NativeMapFn(map_symbol) }
	flush := unsafe { NativeFlushFn(flush_symbol) }
	display := get_display()
	handle := get_window(window)
	if isnil(display) || handle == 0 { return false }
	map_window(display, handle)
	flush(display)
	return true
}
