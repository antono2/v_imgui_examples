#!/usr/bin/env bash
set -euo pipefail
package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
example=${1:-widget_gallery}
case "$example" in glfw_vulkan|widget_gallery|implot_dashboard) ;; *) echo 'Usage: run.sh [glfw_vulkan|widget_gallery|implot_dashboard]' >&2; exit 2 ;; esac
if [[ $# -gt 0 ]]; then shift; fi
exec "$package_dir/$example" "$@"
