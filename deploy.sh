#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  . "${SCRIPT_DIR}/.env"
  set +a
fi

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: required environment variable ${name} is not set" >&2
    echo "define it in the environment or in ${SCRIPT_DIR}/.env (see .env.example)" >&2
    exit 2
  fi
}

require_env AGDB_DEPLOY_HOST
require_env AGDB_DEPLOY_USER

DEPLOY_HOST="${AGDB_DEPLOY_HOST}"
DEPLOY_USER="${AGDB_DEPLOY_USER}"
SERVER="${DEPLOY_USER}@${DEPLOY_HOST}"
SSH_KEY="${AGDB_DEPLOY_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_PORT="${AGDB_DEPLOY_SSH_PORT:-22}"
DEPLOY_DIR="${AGDB_DEPLOY_DIR:-/opt/agdb}"
REGISTRY_PATH="${AGDB_REGISTRY_PATH:-/var/lib/agdb/registry.agdb}"
DATA_ROOT="${AGDB_DATA_ROOT:-/var/lib/agdb/tenants}"
RUNNER_PATH="${AGDB_RUNNER_PATH:-/usr/lib/agdb/sandbox_runner}"
CLOUD_PORT="${AGDB_CLOUD_PORT:-7070}"
SERVICE_USER="${AGDB_SERVICE_USER:-agdb}"
SHUTDOWN_USER="${AGDB_SHUTDOWN_USER:-agdb-shutdown}"
ZIG_VERSION="${AGDB_ZIG_VERSION:-0.14.1}"
RELEASE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [ ! -f "${SSH_KEY}" ]; then
  echo "error: ssh key ${SSH_KEY} not found" >&2
  exit 2
fi

SSH=(ssh -i "${SSH_KEY}" -p "${SSH_PORT}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
SCP=(scp -i "${SSH_KEY}" -P "${SSH_PORT}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)

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

echo "==> running test suite"
"${ZIG}" build test

echo "==> building release artifacts"
"${ZIG}" build \
  -Dtarget=x86_64-linux-musl \
  -Doptimize=ReleaseSafe \
  "-DAGDB_REGISTRY_PATH=${REGISTRY_PATH}" \
  "-DAGDB_DATA_ROOT=${DATA_ROOT}" \
  "-Dsandbox_runner_path=${RUNNER_PATH}"

for artifact in \
  "zig-out/bin/agdb-cloud" \
  "zig-out/bin/agdb-autoshutdown" \
  "zig-out${RUNNER_PATH}"; do
  if [ ! -f "${artifact}" ]; then
    echo "error: expected build artifact ${artifact} is missing" >&2
    exit 1
  fi
done

echo "==> artifacts"
ls -lh zig-out/bin/agdb-cloud zig-out/bin/agdb-autoshutdown "zig-out${RUNNER_PATH}"

echo "==> preparing remote host ${DEPLOY_HOST}"
"${SSH[@]}" "${SERVER}" "sudo -n true" >/dev/null

"${SSH[@]}" "${SERVER}" bash -s <<REMOTE_PREPARE
set -euo pipefail
sudo install -d -m 0755 "${DEPLOY_DIR}/bin"
sudo install -d -m 0755 "${DEPLOY_DIR}/releases/${RELEASE_STAMP}"
sudo install -d -m 0750 "\$(dirname "${REGISTRY_PATH}")"
sudo install -d -m 0750 "${DATA_ROOT}"
sudo install -d -m 0755 "\$(dirname "${RUNNER_PATH}")"
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  sudo useradd --system --home-dir "${DEPLOY_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi
if ! id -u "${SHUTDOWN_USER}" >/dev/null 2>&1; then
  sudo useradd --system --home-dir "${DEPLOY_DIR}" --shell /usr/sbin/nologin "${SHUTDOWN_USER}"
fi
sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "${DEPLOY_DIR}" "\$(dirname "${REGISTRY_PATH}")" "${DATA_ROOT}"
sudo install -d -m 0755 /sys/fs/cgroup/agdb || true
sudo chown "${SERVICE_USER}:${SERVICE_USER}" /sys/fs/cgroup/agdb || true
REMOTE_PREPARE

echo "==> uploading binaries"
"${SCP[@]}" zig-out/bin/agdb-cloud "${SERVER}:/tmp/agdb-cloud.${RELEASE_STAMP}"
"${SCP[@]}" zig-out/bin/agdb-autoshutdown "${SERVER}:/tmp/agdb-autoshutdown.${RELEASE_STAMP}"
"${SCP[@]}" "zig-out${RUNNER_PATH}" "${SERVER}:/tmp/sandbox_runner.${RELEASE_STAMP}"
"${SCP[@]}" nginx.conf "${SERVER}:/tmp/agdb-nginx.conf.${RELEASE_STAMP}"

echo "==> installing release ${RELEASE_STAMP}"
"${SSH[@]}" "${SERVER}" bash -s <<REMOTE_INSTALL
set -euo pipefail
sudo install -m 0755 "/tmp/agdb-cloud.${RELEASE_STAMP}" "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/agdb-cloud"
sudo install -m 0755 "/tmp/agdb-autoshutdown.${RELEASE_STAMP}" "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/agdb-autoshutdown"
sudo install -m 0755 "/tmp/sandbox_runner.${RELEASE_STAMP}" "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/sandbox_runner"
rm -f "/tmp/agdb-cloud.${RELEASE_STAMP}" "/tmp/agdb-autoshutdown.${RELEASE_STAMP}" "/tmp/sandbox_runner.${RELEASE_STAMP}"

if [ -f "${DEPLOY_DIR}/bin/agdb-cloud" ]; then
  sudo cp -a "${DEPLOY_DIR}/bin/agdb-cloud" "${DEPLOY_DIR}/bin/agdb-cloud.previous"
fi
if [ -f "${DEPLOY_DIR}/bin/agdb-autoshutdown" ]; then
  sudo cp -a "${DEPLOY_DIR}/bin/agdb-autoshutdown" "${DEPLOY_DIR}/bin/agdb-autoshutdown.previous"
fi
if [ -f "${RUNNER_PATH}" ]; then
  sudo cp -a "${RUNNER_PATH}" "${RUNNER_PATH}.previous"
fi

sudo systemctl stop agdb-autoshutdown 2>/dev/null || true
sudo systemctl stop agdb-cloud 2>/dev/null || true

sudo install -m 0755 "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/agdb-cloud" "${DEPLOY_DIR}/bin/agdb-cloud"
sudo install -m 0755 "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/agdb-autoshutdown" "${DEPLOY_DIR}/bin/agdb-autoshutdown"
sudo install -m 0755 "${DEPLOY_DIR}/releases/${RELEASE_STAMP}/sandbox_runner" "${RUNNER_PATH}"

if ! command -v nginx >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y nginx
fi
sudo mv "/tmp/agdb-nginx.conf.${RELEASE_STAMP}" /etc/nginx/sites-available/agdb
sudo ln -sf /etc/nginx/sites-available/agdb /etc/nginx/sites-enabled/agdb
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
REMOTE_INSTALL

echo "==> writing systemd units"
CLOUD_UNIT="$(mktemp)"
SHUTDOWN_UNIT="$(mktemp)"
trap 'rm -f "${CLOUD_UNIT}" "${SHUTDOWN_UNIT}"' EXIT

cat > "${CLOUD_UNIT}" <<UNIT
[Unit]
Description=agdb cloud server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=${DEPLOY_DIR}/bin/agdb-cloud
Restart=on-failure
RestartSec=5
Environment=AGDB_CLOUD_PORT=${CLOUD_PORT}
Environment=AGDB_REGISTRY_PATH=${REGISTRY_PATH}
Environment=AGDB_DATA_ROOT=${DATA_ROOT}
EnvironmentFile=-${DEPLOY_DIR}/agdb-cloud.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agdb-cloud
AmbientCapabilities=CAP_SYS_ADMIN CAP_NET_ADMIN CAP_SETUID CAP_SETGID CAP_CHOWN CAP_SYS_CHROOT
CapabilityBoundingSet=CAP_SYS_ADMIN CAP_NET_ADMIN CAP_SETUID CAP_SETGID CAP_CHOWN CAP_SYS_CHROOT
ProtectHome=yes
PrivateTmp=yes
ProtectControlGroups=no
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
LimitNOFILE=65536
TasksMax=4096

[Install]
WantedBy=multi-user.target
UNIT

cat > "${SHUTDOWN_UNIT}" <<UNIT
[Unit]
Description=agdb idle shutdown supervisor
After=agdb-cloud.service
Requires=agdb-cloud.service

[Service]
Type=simple
User=${SHUTDOWN_USER}
Group=${SHUTDOWN_USER}
ExecStart=${DEPLOY_DIR}/bin/agdb-autoshutdown
Restart=on-failure
RestartSec=10
EnvironmentFile=-${DEPLOY_DIR}/agdb-autoshutdown.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agdb-autoshutdown
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryMax=128M
TasksMax=16

[Install]
WantedBy=multi-user.target
UNIT

"${SCP[@]}" "${CLOUD_UNIT}" "${SERVER}:/tmp/agdb-cloud.service.${RELEASE_STAMP}"
"${SCP[@]}" "${SHUTDOWN_UNIT}" "${SERVER}:/tmp/agdb-autoshutdown.service.${RELEASE_STAMP}"

"${SSH[@]}" "${SERVER}" bash -s <<REMOTE_ACTIVATE
set -euo pipefail
sudo install -m 0644 "/tmp/agdb-cloud.service.${RELEASE_STAMP}" /etc/systemd/system/agdb-cloud.service
sudo install -m 0644 "/tmp/agdb-autoshutdown.service.${RELEASE_STAMP}" /etc/systemd/system/agdb-autoshutdown.service
rm -f "/tmp/agdb-cloud.service.${RELEASE_STAMP}" "/tmp/agdb-autoshutdown.service.${RELEASE_STAMP}"
sudo systemctl daemon-reload
sudo systemctl enable agdb-cloud agdb-autoshutdown
sudo systemctl restart agdb-cloud
sudo systemctl restart agdb-autoshutdown
REMOTE_ACTIVATE

echo "==> verifying health endpoint"
HEALTH_OK=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if "${SSH[@]}" "${SERVER}" "curl -sf --max-time 5 http://127.0.0.1:${CLOUD_PORT}/v1/health >/dev/null"; then
    HEALTH_OK=1
    break
  fi
  sleep 3
done

if [ "${HEALTH_OK}" -ne 1 ]; then
  echo "error: health check failed, rolling back to previous release" >&2
  "${SSH[@]}" "${SERVER}" bash -s <<REMOTE_ROLLBACK
set -euo pipefail
if [ -f "${DEPLOY_DIR}/bin/agdb-cloud.previous" ]; then
  sudo install -m 0755 "${DEPLOY_DIR}/bin/agdb-cloud.previous" "${DEPLOY_DIR}/bin/agdb-cloud"
fi
if [ -f "${DEPLOY_DIR}/bin/agdb-autoshutdown.previous" ]; then
  sudo install -m 0755 "${DEPLOY_DIR}/bin/agdb-autoshutdown.previous" "${DEPLOY_DIR}/bin/agdb-autoshutdown"
fi
if [ -f "${RUNNER_PATH}.previous" ]; then
  sudo install -m 0755 "${RUNNER_PATH}.previous" "${RUNNER_PATH}"
fi
sudo systemctl restart agdb-cloud
sudo systemctl restart agdb-autoshutdown
REMOTE_ROLLBACK
  exit 1
fi

echo "==> deploy ${RELEASE_STAMP} complete on ${DEPLOY_HOST}"
echo "==> health endpoint: http://${DEPLOY_HOST}/v1/health"
