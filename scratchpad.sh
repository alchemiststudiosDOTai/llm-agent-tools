#!/bin/bash

# Backward-compat wrapper. The tool moved to bash-tools/scratchpad.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/bash-tools/scratchpad.sh"

if [[ ! -x "${TARGET}" ]]; then
  echo "Error: ${TARGET} not found or not executable" >&2
  exit 1
fi

echo "[note] scratchpad.sh moved to bash-tools/scratchpad.sh" >&2
exec "${TARGET}" "$@"

