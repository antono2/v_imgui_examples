#!/usr/bin/env bash
# Starts the packaged desktop example menu or a named example on Linux.
# Locates the requested executable relative to the extracted package directory.
set -euo pipefail
package_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -eq 0 ]]; then exec "$package_dir/examples"; fi
example=$1
case "$example" in glfw_vulkan|widget_gallery|implot_dashboard) ;; *) echo 'Usage: run.sh [glfw_vulkan|widget_gallery|implot_dashboard]' >&2; exit 2 ;; esac
if [[ $# -gt 0 ]]; then shift; fi
exec "$package_dir/$example" "$@"
