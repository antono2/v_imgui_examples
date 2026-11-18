#!/bin/sh
# Compatibility entry point for the V shortcut test.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${V_BIN:-v}" run "$script_dir/shortcuts.vsh" "$@"
