#!/usr/bin/env bash
set -euo pipefail

SERVER="ubuntu@91.134.72.253"
SCRIPT_DIR_EARLY="$(cd "$(dirname "$0")" && pwd)"
# Prefer project-local key, then env var path, then default
if [ -f "${SCRIPT_DIR_EARLY}/.deploy_key" ]; then
  SSH_KEY="${SCRIPT_DIR_EARLY}/.deploy_key"
else
  SSH_KEY="${OVH_SSH_KEY:-$HOME/.ssh/id_ed25519}"
fi
DEPLOY_DIR="/opt/agdb"
REGISTRY_PATH="/var/lib/agdb/registry.agdb"
DATA_ROOT="/var/lib/agdb/tenants"
RUNNER_PATH="/usr/lib/agdb/sandbox_runner"
CLOUD_PORT="7070"
ZIG_VERSION="0.14.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIG_DIR="/tmp/zig-linux-x86_64-${ZIG_VERSION}"
ZIG="${ZIG_DIR}/zig"

# Prefer local project ./zig if available
if [ -f "${SCRIPT_DIR}/zig" ]; then
  ZIG="${SCRIPT_DIR}/zig"
  ZIG_DIR="$(dirname "$ZIG")"
  echo "==> Using project-local Zig: $ZIG"
else
  echo "==> Checking Zig ${ZIG_VERSION}..."
  if [ ! -f "$ZIG" ]; then
    echo "    Downloading Zig ${ZIG_VERSION}..."
    curl -sL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
      -o "/tmp/zig-${ZIG_VERSION}.tar.xz"
    tar -xf "/tmp/zig-${ZIG_VERSION}.tar.xz" -C /tmp/
    echo "    Zig ${ZIG_VERSION} ready."
  fi
  echo "==> Using Zig: $ZIG"
fi
export PATH="${ZIG_DIR}:$PATH"

echo "==> Syncing frontend..."
cp index.html src/cloud/index.html

echo "==> Building agdb-cloud for x86_64-linux-musl (static)..."
"$ZIG" build \
  -Dtarget=x86_64-linux-musl \
  -Doptimize=ReleaseSafe \
  "-DAGDB_REGISTRY_PATH=${REGISTRY_PATH}" \
  "-DAGDB_DATA_ROOT=${DATA_ROOT}" \
  "-Dsandbox_runner_path=${RUNNER_PATH}"

echo "==> Binaries built:"
ls -lh zig-out/bin/agdb-cloud zig-out/bin/agdb-autoshutdown zig-out/usr/lib/agdb/sandbox_runner

echo "==> Preparing server directories..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SERVER" "
  sudo mkdir -p ${DEPLOY_DIR}/bin
  sudo mkdir -p $(dirname ${REGISTRY_PATH})
  sudo mkdir -p ${DATA_ROOT}
  sudo mkdir -p $(dirname ${RUNNER_PATH})
  sudo chown -R ubuntu:ubuntu ${DEPLOY_DIR} $(dirname ${REGISTRY_PATH}) ${DATA_ROOT} $(dirname ${RUNNER_PATH}) || true
  sudo mkdir -p /sys/fs/cgroup/agdb
  sudo chown ubuntu:ubuntu /sys/fs/cgroup/agdb
  sudo sh -c 'echo \"+memory +cpu +pids\" > /sys/fs/cgroup/cgroup.subtree_control' 2>/dev/null || true
  sudo sh -c 'echo \"+memory +cpu +pids\" > /sys/fs/cgroup/agdb/cgroup.subtree_control' 2>/dev/null || true
"

echo "==> Copying binaries..."
ssh -i "$SSH_KEY" "$SERVER" "sudo systemctl stop agdb-cloud agdb-autoshutdown 2>/dev/null || true"

scp -i "$SSH_KEY" zig-out/bin/agdb-cloud "${SERVER}:${DEPLOY_DIR}/bin/agdb-cloud"
ssh -i "$SSH_KEY" "$SERVER" "sudo chmod +x ${DEPLOY_DIR}/bin/agdb-cloud"

scp -i "$SSH_KEY" zig-out/bin/agdb-autoshutdown "${SERVER}:${DEPLOY_DIR}/bin/agdb-autoshutdown"
ssh -i "$SSH_KEY" "$SERVER" "sudo chmod +x ${DEPLOY_DIR}/bin/agdb-autoshutdown"

scp -i "$SSH_KEY" zig-out/usr/lib/agdb/sandbox_runner "${SERVER}:/tmp/sandbox_runner"
ssh -i "$SSH_KEY" "$SERVER" "sudo mv /tmp/sandbox_runner ${RUNNER_PATH} && sudo chmod +x ${RUNNER_PATH}"

echo "==> Installing nginx..."
ssh -i "$SSH_KEY" "$SERVER" "
  if ! command -v nginx &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y nginx
  fi
"

echo "==> Deploying nginx config..."
scp -i "$SSH_KEY" nginx.conf "${SERVER}:/tmp/agdb-nginx.conf"
ssh -i "$SSH_KEY" "$SERVER" "
  sudo mv /tmp/agdb-nginx.conf /etc/nginx/sites-available/agdb
  sudo ln -sf /etc/nginx/sites-available/agdb /etc/nginx/sites-enabled/agdb
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
"

echo "==> Installing systemd service..."
cat > /tmp/agdb-cloud.service <<EOF
[Unit]
Description=agdb Cloud Server
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=${DEPLOY_DIR}/bin/agdb-cloud
Restart=on-failure
RestartSec=5
Environment=AGDB_CLOUD_PORT=${CLOUD_PORT}
Environment=AGDB_REGISTRY_PATH=${REGISTRY_PATH}
Environment=AGDB_DATA_ROOT=${DATA_ROOT}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agdb-cloud
AmbientCapabilities=CAP_SYS_ADMIN CAP_NET_ADMIN CAP_SETUID CAP_SETGID CAP_CHOWN CAP_SYS_CHROOT
CapabilityBoundingSet=CAP_SYS_ADMIN CAP_NET_ADMIN CAP_SETUID CAP_SETGID CAP_CHOWN CAP_SYS_CHROOT
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

scp -i "$SSH_KEY" /tmp/agdb-cloud.service "${SERVER}:/tmp/agdb-cloud.service"

cat > /tmp/agdb-autoshutdown.service <<EOF
[Unit]
Description=agdb Auto-Shutdown (idle monitor)
After=agdb-cloud.service

[Service]
Type=simple
User=root
ExecStart=${DEPLOY_DIR}/bin/agdb-autoshutdown
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agdb-autoshutdown

[Install]
WantedBy=multi-user.target
EOF

scp -i "$SSH_KEY" /tmp/agdb-autoshutdown.service "${SERVER}:/tmp/agdb-autoshutdown.service"
ssh -i "$SSH_KEY" "$SERVER" "
  sudo mv /tmp/agdb-cloud.service /etc/systemd/system/agdb-cloud.service
  sudo mv /tmp/agdb-autoshutdown.service /etc/systemd/system/agdb-autoshutdown.service
  sudo systemctl daemon-reload
  sudo systemctl enable agdb-cloud agdb-autoshutdown
  sudo systemctl restart agdb-cloud agdb-autoshutdown
  sleep 2
  sudo systemctl status agdb-cloud --no-pager | head -10
  sudo systemctl status agdb-autoshutdown --no-pager | head -10
"

echo ""
echo "==> Verifying health endpoint..."
sleep 2
ssh -i "$SSH_KEY" "$SERVER" "curl -sf http://localhost:${CLOUD_PORT}/v1/health || echo 'health check failed'"

echo ""
echo "==============================="
echo "  Deploy complete!"
echo "  Server: http://91.134.72.253"
echo "  API:    http://91.134.72.253/v1/health"
echo "==============================="
echo ""
echo "  To enable HTTPS (after DNS is configured):"
echo "  ssh -i ${SSH_KEY} ${SERVER} 'sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d your-domain.com'"
