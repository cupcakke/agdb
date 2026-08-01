#!/usr/bin/env bash
set -euo pipefail

# Wrapper to use the correct Zig 0.14.0 for this project
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="/tmp/zig-linux-x86_64-0.14.0"
ZIG="${ZIG_DIR}/zig"

if [ -f "${SCRIPT_DIR}/zig" ]; then
  ZIG="${SCRIPT_DIR}/zig"
else
  if [ ! -f "$ZIG" ]; then
    echo "Error: Zig 0.14.0 not found at ${ZIG} or ./zig"
    echo "Run deploy.sh to download Zig 0.14.0, or download it manually."
    exit 1
  fi
fi

export PATH="$(dirname "$ZIG"):$PATH"
exec "$ZIG" "$@"
