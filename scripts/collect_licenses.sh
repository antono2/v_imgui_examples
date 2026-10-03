#!/usr/bin/env bash
# Copy redistribution notices for the components actually used by the builds.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
imgui=${1:?Usage: collect_licenses.sh imgui-dir output-dir [android]}
output=${2:?Missing output directory}
mkdir -p "$output"
cp "$root/LICENSE" "$output/examples.txt"
cp "$imgui/LICENSE" "$output/imgui-v.txt"
cp "$imgui/cimgui/imgui/LICENSE.txt" "$output/imgui.txt"
cp "$imgui/cimgui/LICENSE" "$output/cimgui.txt"
cp "$imgui/cimplot/implot/LICENSE" "$output/implot.txt"
cp "$imgui/cimplot/LICENSE" "$output/cimplot.txt"
cp "$root/packaging/PROGGY-LICENSE.txt" "$root/packaging/PROGGYFOREVER-LICENSE.txt" "$output/"
if [[ ${3:-} == android ]]; then
  cp "$root/packaging/ROBOTO-LICENSE.txt" "$output/"
  freetype="$imgui/third_party/freetype"
  cp "$freetype/LICENSE.TXT" "$output/freetype-license.txt"
  cp "$freetype/docs/FTL.TXT" "$output/freetype-FTL.txt"
  cp "$freetype/subprojects/dlg/LICENSE" "$output/freetype-dlg.txt"
  sed -n '1,/\*\//p' "$freetype/src/gzip/zlib.h" > "$output/freetype-zlib.txt"
  cat > "$output/freetype-attribution.txt" <<'NOTICE'
This app includes FreeType 2.13.3. Portions of this software are copyright
© 2024 The FreeType Project (www.freetype.org). All rights reserved.
FreeType is redistributed under the FreeType License (FTL).
NOTICE
fi
v_binary=${V_BIN:-$(command -v v)}
v_root=$(cd -- "$(dirname -- "$v_binary")" && pwd)
cp "$v_root/LICENSE" "$output/v.txt"
if [[ ${3:-} != android ]]; then
  # The default desktop collector is statically linked. Retain every source
  # comment, including component copyright and permission notices.
  awk 'index($0,"/*") {block=1} block {print} index($0,"*/") {block=0}' \
    "$v_root/thirdparty/libgc/gc.c" > "$output/boehm-gc-notices.txt"
  cp "$v_root/thirdparty/libatomic_ops/LICENSE" "$output/libatomic-ops.txt"
fi
