#!/bin/sh
# Compatibility entry point for the V desktop render check.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${V_BIN:-v}" run "$script_dir/smoke_desktop.vsh" "$@"
