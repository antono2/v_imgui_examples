#ifndef V_IMGUI_TOUCH_ACCESSIBILITY_STATE_H
#define V_IMGUI_TOUCH_ACCESSIBILITY_STATE_H
// The UI DSO stays loaded across context/window recreation. Only the render
// thread reads this retained preference; process restart restores the default.
static bool v_imgui_touch_high_contrast = false;
static bool *v_imgui_touch_contrast(void) { return &v_imgui_touch_high_contrast; }
#endif
