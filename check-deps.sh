#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/installer/core/main.sh"
sekaipop_main --check "$@"
