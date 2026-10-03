#!/usr/bin/env bash
# Run against the accessible debug APK produced by build_android.sh.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
adb=("$sdk/platform-tools/adb")
if [[ -n ${ANDROID_SERIAL:-} ]]; then adb+=(-s "$ANDROID_SERIAL"); fi
abi=${ANDROID_ABI:-$("${adb[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')}
build=$repo/build/android-touch-$abi
build_tools=$(printf '%s\n' "$sdk"/build-tools/* | sort -V | tail -n 1)
android_jar=$(printf '%s\n' "$sdk"/platforms/*/android.jar | sort -V | tail -n 1)
package=$build/accessibility-test
mkdir -p "$package/classes" "$package/dex"
"${JAVAC:-javac}" -source 8 -target 8 -Xlint:-options -cp "$android_jar" -d "$package/classes" \
  "$repo/tests/android/accessibility/AccessibilitySmoke.java"
mapfile -d '' class_files < <(find "$package/classes" -name '*.class' -print0)
"$build_tools/d8" --min-api 24 --lib "$android_jar" --output "$package/dex" "${class_files[@]}"
"$build_tools/aapt" package -f -M "$repo/tests/android/accessibility/AndroidManifest.xml" \
  -I "$android_jar" -F "$package/unsigned.apk"
(cd "$package/dex"; "$build_tools/aapt" add "$package/unsigned.apk" classes.dex)
"$build_tools/zipalign" -f 4 "$package/unsigned.apk" "$package/aligned.apk"
"$build_tools/apksigner" sign --ks "$build/debug.keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$package/test.apk" "$package/aligned.apk"
"$build_tools/apksigner" verify "$package/test.apk"
"${adb[@]}" shell input keyevent 224
"${adb[@]}" shell wm dismiss-keyguard
"${adb[@]}" shell am force-stop io.antono2.vimgui.examples.touch
"${adb[@]}" install -r "$build/vimgui-demo-$abi.apk"
"${adb[@]}" install -r "$package/test.apk"
"${adb[@]}" shell am instrument -w \
  io.antono2.vimgui.examples.touch.test/io.antono2.vimgui.examples.touch.test.AccessibilitySmoke | tee "$package/instrumentation.log"
rg -q 'result=PASS:' "$package/instrumentation.log"
