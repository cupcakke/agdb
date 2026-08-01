#!/usr/bin/env bash
set -euo pipefail

ZIG_VERSION="0.14.0"
ZIG_DIR="/tmp/zig-linux-x86_64-${ZIG_VERSION}"
ZIG="${ZIG_DIR}/zig"

if [ -f "./zig" ]; then
  ZIG="./zig"
  ZIG_DIR="$(dirname "$ZIG")"
elif [ ! -f "$ZIG" ]; then
  echo "==> Downloading Zig ${ZIG_VERSION}..."
  curl -sL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
    -o "/tmp/zig-${ZIG_VERSION}.tar.xz"
  tar -xf "/tmp/zig-${ZIG_VERSION}.tar.xz" -C /tmp/
  echo "==> Zig ${ZIG_VERSION} ready."
fi

export PATH="${ZIG_DIR}:$PATH"

BUILD_MODE="${1:-}"

if [ "$BUILD_MODE" = "--build-only" ]; then
  echo "==> Building agdb-wake-proxy (ReleaseSafe)..."
  "$ZIG" build -Doptimize=ReleaseSafe \
    "-DAGDB_REGISTRY_PATH=/tmp/agdb/registry.agdb" \
    "-DAGDB_DATA_ROOT=/tmp/agdb/tenants"
  echo "==> Build complete."
  exit 0
fi

echo "==> Building agdb-wake-proxy (Debug)..."
"$ZIG" build -Doptimize=Debug \
  "-DAGDB_REGISTRY_PATH=/tmp/agdb/registry.agdb" \
  "-DAGDB_DATA_ROOT=/tmp/agdb/tenants"

echo "==> Starting agdb-wake-proxy on port 5000..."
exec env \
  PORT=5000 \
  OVH_APP_KEY="${OVH_APP_KEY}" \
  OVH_APP_SECRET="${OVH_APP_SECRET}" \
  OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY}" \
  ./zig-out/bin/agdb-wake-proxy
