#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  . "${SCRIPT_DIR}/.env"
  set +a
fi

ZIG_VERSION="${AGDB_ZIG_VERSION:-0.14.1}"

if [ -x "${SCRIPT_DIR}/zig" ]; then
  ZIG="${SCRIPT_DIR}/zig"
elif command -v zig >/dev/null 2>&1; then
  ZIG="$(command -v zig)"
else
  echo "error: zig ${ZIG_VERSION} not found; install it or place an executable named zig in ${SCRIPT_DIR}" >&2
  exit 2
fi

ACTUAL_ZIG_VERSION="$("${ZIG}" version)"
if [ "${ACTUAL_ZIG_VERSION}" != "${ZIG_VERSION}" ]; then
  echo "error: zig version mismatch: found ${ACTUAL_ZIG_VERSION}, required ${ZIG_VERSION}" >&2
  exit 2
fi

MODE="${1:---run}"
OPTIMIZE="${AGDB_OPTIMIZE:-Debug}"
REGISTRY_PATH="${AGDB_REGISTRY_PATH:-/tmp/agdb/registry.agdb}"
DATA_ROOT="${AGDB_DATA_ROOT:-/tmp/agdb/tenants}"

mkdir -p "$(dirname "${REGISTRY_PATH}")" "${DATA_ROOT}"

build() {
  "${ZIG}" build -Doptimize="$1" \
    "-DAGDB_REGISTRY_PATH=${REGISTRY_PATH}" \
    "-DAGDB_DATA_ROOT=${DATA_ROOT}"
}

case "${MODE}" in
  --build-only)
    build "${AGDB_OPTIMIZE:-ReleaseSafe}"
    echo "==> build complete"
    ;;
  --test)
    "${ZIG}" build test
    ;;
  --run)
    if [ -z "${AGDB_TARGET_HOST:-}" ]; then
      echo "error: AGDB_TARGET_HOST is required to run the wake proxy (see .env.example)" >&2
      exit 2
    fi
    build "${OPTIMIZE}"
    echo "==> starting agdb-wake-proxy on ${AGDB_WAKE_LISTEN_ADDR:-0.0.0.0}:${AGDB_WAKE_LISTEN_PORT:-5000}"
    exec ./zig-out/bin/agdb-wake-proxy
    ;;
  --cloud)
    build "${OPTIMIZE}"
    echo "==> starting agdb-cloud"
    exec ./zig-out/bin/agdb-cloud
    ;;
  *)
    echo "usage: $0 [--run|--cloud|--build-only|--test]" >&2
    exit 2
    ;;
esac
