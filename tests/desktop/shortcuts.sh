#!/usr/bin/env bash
set -euo pipefail
binary_dir=$(cd -- "${1:?Usage: shortcuts.sh binary-dir [--raw-gallery]}" && pwd)
# Always use a private display; never send keys to the user's desktop.
if [[ ${VIMGUI_SHORTCUT_TEST_SESSION:-0} != 1 ]]; then
  exec env VIMGUI_SHORTCUT_TEST_SESSION=1 xvfb-run -a -s '-screen 0 1600x1000x24' bash "$0" "$binary_dir" "${2:-}"
fi
lavapipe=(/usr/share/vulkan/icd.d/lvp_icd*.json)
test -f "${lavapipe[0]}"
export VK_DRIVER_FILES="${lavapipe[0]}"
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
export VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation
log_dir="$binary_dir/shortcut-logs"
mkdir -p "$log_dir"
app_pid=''
wm_pid=''
cleanup() {
  if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; fi
  if [[ -n "$wm_pid" ]]; then kill "$wm_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
openbox --sm-disable > "$log_dir/window-manager.log" 2>&1 &
wm_pid=$!
for i in {1..100}; do
  if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id'; then break; fi
  sleep 0.1
done
window=''
start_app() {
  current_example=$1
  "$binary_dir/$1" > "$log_dir/$1.log" 2>&1 &
  app_pid=$!
  window=''
  for i in {1..100}; do
    window=$(xdotool search --onlyvisible --name '^V ImGui:' 2>/dev/null | head -1 || true)
    if [[ -n "$window" ]]; then break; fi
    if ! kill -0 "$app_pid" 2>/dev/null; then cat "$log_dir/$1.log"; echo "Failed to open $1" >&2; exit 1; fi
    sleep 0.1
  done
  test -n "$window"
  if ! timeout 10s xdotool windowactivate --sync "$window"; then
    echo "Window manager did not activate $current_example" >&2
    xprop -id "$window" _NET_WM_STATE >&2 || true
    cat "$log_dir/window-manager.log" >&2
    exit 1
  fi
  sleep 0.3
}
geometry() {
  xdotool getwindowgeometry --shell "$window" | sed -n '/^X=/p; /^Y=/p; /^WIDTH=/p; /^HEIGHT=/p'
}
wait_geometry() {
  for i in {1..100}; do
    if [[ $(geometry) == "$1" ]]; then return; fi
    sleep 0.05
  done
  echo 'Window geometry did not reach expected state' >&2
  geometry >&2
  exit 1
}
quit_app() {
  xdotool key Escape
  for i in {1..100}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      wait "$app_pid"
      app_pid=''
      if grep -Eiq 'VUID-|validation error|segmentation|assert|fatal' "$log_dir/$current_example.log"; then
        cat "$log_dir/$current_example.log" >&2
        return 1
      fi
      return
    fi
    sleep 0.05
  done
  echo 'Escape did not quit the example' >&2
  exit 1
}
fullscreen=$'X=0\nY=0\nWIDTH=1600\nHEIGHT=1000'
desktop_mode=$(xrandr --current)
for example in glfw_vulkan widget_gallery implot_dashboard; do
  start_app "$example"
  normal=$(geometry)
  normal_frame=$(xprop -id "$window" _NET_FRAME_EXTENTS)
  xdotool keydown F11
  wait_geometry "$fullscreen"
  # Holding F11 must not toggle repeatedly.
  sleep 0.6
  test "$(geometry)" == "$fullscreen"
  xdotool keyup F11
  xprop -id "$window" _NET_FRAME_EXTENTS | grep -q '= 0, 0, 0, 0'
  test "$(xrandr --current)" == "$desktop_mode"
  sleep 0.1
  xdotool key F11
  wait_geometry "$normal"
  test "$(xprop -id "$window" _NET_FRAME_EXTENTS)" == "$normal_frame"
  quit_app
  echo "PASS: $example — F11, held key, restore geometry and Escape"
done
start_app widget_gallery
normal=$(geometry)
wmctrl -i -r "$window" -b add,maximized_vert,maximized_horz
for i in {1..100}; do
  if xprop -id "$window" _NET_WM_STATE | grep -q '_NET_WM_STATE_MAXIMIZED_VERT'; then break; fi
  sleep 0.05
done
sleep 0.2
maximized=$(geometry)
test "$normal" != "$maximized"
xdotool key F11
wait_geometry "$fullscreen"
xdotool key F11
wait_geometry "$maximized"
wmctrl -i -r "$window" -b remove,maximized_vert,maximized_horz
wait_geometry "$normal"
quit_app
echo 'PASS: Fullscreen preserves maximized state and normal restore bounds'
if [[ ${2:-} == --raw-gallery ]]; then
  start_app widget_gallery
  # Raw gallery's fixed initial layout: edit the Name field.
  xdotool mousemove --window "$window" 200 113 click 1
  xdotool type --clearmodifiers 'Escape cancels this edit'
  xdotool key Escape
  sleep 0.2
  kill -0 "$app_pid"
  quit_app
  echo 'PASS: Escape cancels editing before quitting'
  start_app widget_gallery
  xdotool mousemove --window "$window" 100 252 click 1
  sleep 0.2
  xdotool key Escape
  sleep 0.2
  kill -0 "$app_pid"
  quit_app
  echo 'PASS: Escape closes a popup before quitting'
fi
