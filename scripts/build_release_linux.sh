#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
imgui=${IMGUI_DIR:-$root/build/modules/antono2/imgui}
variant=${1:?Usage: build_release_linux.sh docking|standard}
export VMODULES=${VMODULES:-$root/build/modules}
export VULKAN_SDK=/usr GLFW_INCLUDE=/usr/include GLFW_LIB=/usr/lib/x86_64-linux-gnu
v=${V_BIN:-v}
"$v" run "$imgui/build_vimgui.vsh" --linkage shared --glfw system
cmake -S "$imgui" -B "$imgui/build/shared-system-3.3" \
  -DVIMGUI_APPLICATION_UI=ON "-DVIMGUI_OUTPUT_DIR=$imgui/lib"
cmake --build "$imgui/build/shared-system-3.3" --parallel 4
binaries="$root/build/release-binaries-$variant"
mkdir -p "$binaries"
for example in glfw_vulkan widget_gallery implot_dashboard; do
  source=$root
  if [[ $example != glfw_vulkan ]]; then source="$root/examples/$example"; fi
  "$v" -d release_accessibility -d appui_embedded -no-memory-limit -cc gcc -o "$binaries/$example" "$source"
done
bash "$root/scripts/package_linux.sh" "$binaries" "$imgui" "$root/build/v-imgui-examples-linux-x64-$variant" "$variant"
# Check the extracted bundle from outside its original build directory.
bash "$root/scripts/smoke_desktop.sh" "$root/build/v-imgui-examples-linux-x64-$variant"
