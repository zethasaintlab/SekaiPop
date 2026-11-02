#!/usr/bin/env bash
# Deprecated compatibility entrypoint. All work is delegated to the canonical installer.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$SCRIPT_DIR/install.sh" "$@"
