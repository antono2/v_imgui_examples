#!/usr/bin/env bash
# Builds the Android touch UI against the pinned ImGui native host.
# Supports build-only APK production or an explicit connected-device run.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
imgui_dir="${IMGUI_DIR:-$repo_dir/build/modules/antono2/imgui}"
mode="${1:---build-only}"
if [[ $# -gt 1 || ( "$mode" != --build-only && "$mode" != run ) ]]; then
  echo 'Usage: scripts/build_android.sh [--build-only|run]' >&2
  exit 2
fi
tag="$("${V_BIN:-v}" run "$repo_dir/scripts/imgui_release.vsh")"
if [[ ! -f "$imgui_dir/v.mod" ]]; then
  mkdir -p "$(dirname "$imgui_dir")"
  git clone https://github.com/antono2/imgui.git "$imgui_dir"
  git -C "$imgui_dir" fetch origin tag "$tag"
  git -C "$imgui_dir" checkout --detach "refs/tags/$tag"
fi
expected="$(git -C "$imgui_dir" rev-parse "refs/tags/$tag^{commit}")"
if [[ "$(git -C "$imgui_dir" rev-parse HEAD)" != "$expected" ]]; then
  echo "ImGui must match $tag from v.mod; use a fresh IMGUI_DIR or check out that tag." >&2
  exit 2
fi
git -C "$imgui_dir" submodule update --init --recursive
export VIMGUI_ANDROID_UI_SOURCE="$repo_dir/examples/android_touch"
export VIMGUI_ANDROID_MANIFEST="$repo_dir/examples/android_touch/AndroidManifest.xml"
export VIMGUI_ANDROID_BUILD_DIR="${VIMGUI_ANDROID_BUILD_DIR:-$repo_dir/build/android-touch-${ANDROID_ABI:-device}}"
exec bash "$imgui_dir/scripts/run_android_demo.sh" "$mode"
