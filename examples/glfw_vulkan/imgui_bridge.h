#ifndef V_IMGUI_EXAMPLE_BRIDGE_H
#define V_IMGUI_EXAMPLE_BRIDGE_H

#ifndef CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#endif
#include "cimgui.h"
#include <stdlib.h>

static inline int v_imgui_example_smoke_frame_limit(void) {
    const char *value = getenv("VIMGUI_SMOKE_FRAMES");
    return value ? atoi(value) : 0;
}

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

// Snapshot before NewFrame: Escape may clear an edit or popup during NewFrame.
static inline bool v_imgui_example_escape_reserved(void) {
    const ImGuiContext *g = igGetCurrentContext();
    return igIsAnyItemActive() || igGetDragDropPayload() != NULL ||
           igIsPopupOpen_Str(NULL, ImGuiPopupFlags_AnyPopupId | ImGuiPopupFlags_AnyPopupLevel) ||
           g->NavLayer != ImGuiNavLayer_Main || g->NavWindowingTarget != NULL ||
           (g->NavWindow && g->NavWindow != g->NavWindow->RootWindow &&
            !(g->NavWindow->RootWindowForNav->Flags & ImGuiWindowFlags_Popup) &&
            g->NavWindow->RootWindowForNav->ParentWindow);
}

static inline bool v_imgui_example_escape_pressed(void) {
    // ImGuiKeyOwner_NoOwner is -1; zero means any owner.
    return igIsKeyPressed_InputFlags(ImGuiKey_Escape, 0, (ImGuiID)-1);
}

static inline bool v_imgui_example_fullscreen_pressed(void) {
    return igIsKeyPressed_Bool(ImGuiKey_F11, false);
}

#endif
