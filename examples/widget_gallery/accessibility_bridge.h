// Connects the gallery's GLFW window to the native accessibility adapter.
// Updates focus and window geometry and detaches the adapter during teardown.
#ifndef V_IMGUI_GALLERY_ACCESSIBILITY_H
#define V_IMGUI_GALLERY_ACCESSIBILITY_H
#include "vimgui_app.h"
#ifndef GLFW_INCLUDE_NONE
#define GLFW_INCLUDE_NONE
#endif
#include <GLFW/glfw3.h>
#ifdef _WIN32
#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>
#endif
static bool v_imgui_gallery_attach(void *handle) {
    GLFWwindow *window = (GLFWwindow *)handle;
    void *native = NULL;
#ifdef _WIN32
    native = glfwGetWin32Window(window);
#endif
    return vimgui_accessibility_attach(vimgui_app_accessibility(), native, NULL);
}
static void v_imgui_gallery_update(void *handle) {
    GLFWwindow *window = (GLFWwindow *)handle;
    int x, y, width, height;
    glfwGetWindowPos(window, &x, &y);
    glfwGetWindowSize(window, &width, &height);
    vimgui_accessibility_window_state(vimgui_app_accessibility(),
        glfwGetWindowAttrib(window, GLFW_FOCUSED) != 0, x, y, width, height);
    vimgui_accessibility_update(vimgui_app_accessibility());
}
static void v_imgui_gallery_detach(void) {
    vimgui_accessibility_detach(vimgui_app_accessibility());
}
#endif
