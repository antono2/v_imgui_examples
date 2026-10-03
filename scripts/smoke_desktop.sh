#!/usr/bin/env bash
set -euo pipefail
binary_dir="${1:?Usage: scripts/smoke_desktop.sh path/to/binaries}"
log_dir="$binary_dir/smoke-logs"
mkdir -p "$log_dir"
lavapipe=(/usr/share/vulkan/icd.d/lvp_icd*.json)
test -f "${lavapipe[0]}"
export VK_DRIVER_FILES="${lavapipe[0]}"
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
export VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation
for example in glfw_vulkan widget_gallery implot_dashboard; do
  frames=60
  # Exercise the ring buffer after wrapping past its 600-sample capacity.
  if [[ "$example" == implot_dashboard ]]; then frames=660; fi
  command=("$binary_dir/$example")
  if [[ -x "$binary_dir/examples" ]]; then command=("$binary_dir/examples" "$example"); fi
  VIMGUI_SMOKE_FRAMES="$frames" timeout 60s xvfb-run -a "${command[@]}" > "$log_dir/$example.log" 2>&1
  cat "$log_dir/$example.log"
  if rg -iq 'VUID-|validation error|segmentation|assert|fatal' "$log_dir/$example.log"; then
    echo "Rendering failed: $example" >&2
    exit 1
  fi
  echo "Rendered and shut down: $example ($frames frames)"
done
