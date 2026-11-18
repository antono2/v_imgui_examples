#!/bin/sh
# Compatibility entry point for the V Android build driver.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${V_BIN:-v}" run "$script_dir/build_android.vsh" "$@"
