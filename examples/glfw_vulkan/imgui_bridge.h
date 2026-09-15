#ifndef V_IMGUI_EXAMPLE_BRIDGE_H
#define V_IMGUI_EXAMPLE_BRIDGE_H

#include "cimgui.h"

static inline void v_imgui_example_enable_default_navigation(void) {
    ImGuiIO *io = igGetIO_Nil();
    io->ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io->ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;
}

static inline float v_imgui_example_framerate(void) {
    return igGetIO_Nil()->Framerate;
}

static inline bool v_imgui_example_draw_data_is_minimized(const ImDrawData *draw_data) {
    return draw_data->DisplaySize.x <= 0.0f || draw_data->DisplaySize.y <= 0.0f;
}

#endif
