#!/usr/bin/env bash
# One-time setup on a fresh Pi. Safe to re-run.
#
#   sudo bash bootstrap.sh <git-repo-url>
#
# Installs git + Docker, clones the repo to /opt/raspi, creates .env,
# installs the systemd timers and runs the first deploy.
set -euo pipefail

INSTALL_DIR="/opt/raspi"
REPO_URL="${1:-}"

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
OWNER="${SUDO_USER:-root}"

echo "==> Installing git and curl"
apt-get update -qq
apt-get install -y -qq git curl ca-certificates

if ! command -v docker >/dev/null; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
[[ "$OWNER" != root ]] && usermod -aG docker "$OWNER"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  [[ -n "$REPO_URL" ]] || { echo "usage: sudo bash bootstrap.sh <git-repo-url>"; exit 1; }
  echo "==> Cloning $REPO_URL to $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

if [[ ! -f "$INSTALL_DIR/.env" ]]; then
  echo "==> Creating $INSTALL_DIR/.env"
  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
  sed -i \
    -e "s|^PUID=.*|PUID=$(id -u "$OWNER")|" \
    -e "s|^PGID=.*|PGID=$(id -g "$OWNER")|" \
    -e "s|^TZ=.*|TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo Etc/UTC)|" \
    "$INSTALL_DIR/.env"
  chmod 600 "$INSTALL_DIR/.env"
fi

set -a; source "$INSTALL_DIR/.env"; set +a
mkdir -p "$DATA_ROOT" "$MEDIA_ROOT"
chown "$PUID:$PGID" "$DATA_ROOT"

echo "==> Installing systemd units"
cp "$INSTALL_DIR"/systemd/*.service "$INSTALL_DIR"/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now raspi-deploy.timer raspi-deploy-refresh.timer

# Convenience command: `sudo raspi-deploy [--force]`
cat > /usr/local/bin/raspi-deploy <<EOF
#!/bin/sh
exec /bin/bash $INSTALL_DIR/scripts/deploy.sh "\$@"
EOF
chmod +x /usr/local/bin/raspi-deploy

echo "==> First deploy"
/bin/bash "$INSTALL_DIR/scripts/deploy.sh" --force

echo
echo "Done. Review $INSTALL_DIR/.env (MEDIA_ROOT especially), then: sudo raspi-deploy --force"
