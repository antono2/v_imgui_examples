#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binaries=${1:?Usage: package_linux.sh binary-dir imgui-dir output-dir docking|standard}
imgui=${2:?Missing ImGui directory}
output=${3:?Missing output directory}
variant=${4:?Missing variant}
[[ $variant == docking || $variant == standard ]]
[[ ! -e $output ]]
mkdir -p "$output/lib" "$output/licenses"
output=$(cd "$output" && pwd)
queue=()
declare -A digests
base_library() { [[ $1 =~ ^(lib(c|m|pthread|dl|rt|resolv|util|mvec)\.so\.|ld-linux|linux-vdso) ]]; }
dependencies() {
  local file=$1 line name destination
  local listing
  listing=$(LD_LIBRARY_PATH= ldd "$file")
  if [[ $listing == *'not found'* ]]; then printf '%s\n' "$listing" >&2; return 1; fi
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+\=\>[[:space:]]+(/[^[:space:]]+)[[:space:]] ]]; then
      name=${BASH_REMATCH[1]}; destination=${BASH_REMATCH[2]}
      if ! base_library "$name"; then queue+=("$name" "$destination"); fi
    fi
  done <<< "$listing"
}
for example in glfw_vulkan widget_gallery implot_dashboard; do
  cp "$binaries/$example" "$output/$example"
  dependencies "$binaries/$example"
done
# GLFW uses dlopen for extension libraries and Vulkan presentation.
for name in libvulkan.so.1 libXrandr.so.2 libXinerama.so.1 libXcursor.so.1 libXi.so.6 libXxf86vm.so.1; do
  queue+=("$name" "/usr/lib/x86_64-linux-gnu/$name")
done
index=0
while (( index < ${#queue[@]} )); do
  name=${queue[index]}; file=${queue[index+1]}; index=$((index+2))
  digest=$(sha256sum "$file"); digest=${digest%% *}
  if [[ -v digests[$name] ]]; then [[ ${digests[$name]} == "$digest" ]]; continue; fi
  digests[$name]=$digest
  cp -L "$file" "$output/lib/$name"
  dependencies "$file"
  for candidate in "$file" "$(readlink -f "$file")" "${file#/usr}"; do
    while IFS= read -r owner; do
      owner=${owner%%: *}; owner=${owner%%:*}
      if [[ -f /usr/share/doc/$owner/copyright ]]; then
        cp "/usr/share/doc/$owner/copyright" "$output/licenses/$owner.txt"
      fi
    done < <(dpkg-query -S "$candidate" 2>/dev/null || true)
  done
done
bash "$root/scripts/collect_licenses.sh" "$imgui" "$output/licenses"
cp "$root/packaging/run.sh" "$output/run.sh"
chmod +x "$output/run.sh"
cp "$root/packaging/README-linux.txt" "$output/README.txt"
printf '%s\n' "$variant" > "$output/VARIANT.txt"
printf '%s\n' "${!digests[@]}" | sort > "$output/RUNTIME-LIBRARIES.txt"
for example in glfw_vulkan widget_gallery implot_dashboard; do
  patchelf --set-rpath '$ORIGIN/lib' "$output/$example"
done
for file in "$output"/lib/*; do patchelf --set-rpath '$ORIGIN' "$file"; done
queue=()
for file in "$output"/glfw_vulkan "$output"/widget_gallery "$output"/implot_dashboard "$output"/lib/*; do dependencies "$file"; done
for ((index=0;index<${#queue[@]};index+=2)); do
  [[ ${queue[index+1]} == "$output/lib/"* ]] || { printf 'Unbundled library: %s\n' "${queue[index+1]}" >&2; exit 1; }
done
# Store timestamps in the range supported by ZIP, including archive license files.
find "$output" -type f ! -newermt 1980-01-01 -exec touch -t 198001010000 {} +
(cd "$(dirname "$output")"; zip -q -r -9 "$(basename "$output").zip" "$(basename "$output")")
printf '%s.zip\n' "$output"
