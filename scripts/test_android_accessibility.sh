#!/bin/sh
# Compatibility entry point for the V Android instrumentation runner.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${V_BIN:-v}" run "$script_dir/test_android_accessibility.vsh" "$@"
