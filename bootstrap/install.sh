#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bootstrap/common.sh"

AUTO_REBOOT=1
TARGET_USER="${SUDO_USER:-${USER:-}}"
FORCE=0

usage() {
  cat <<'USAGE'
Usage: ./bootstrap/install.sh [--no-auto-reboot] [--user USER] [--force]

Installs a resumable Acer Nitro AN14-41 Debian configuration job.
The job survives reboots and continues automatically through systemd.
USAGE
}

while (($#)); do
  case "$1" in
    --no-auto-reboot) AUTO_REBOOT=0 ;;
    --user) shift; TARGET_USER="${1:-}" ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die 'run this as your normal desktop user, not as root'
getent passwd "$TARGET_USER" >/dev/null || die "unknown user: $TARGET_USER"

source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_CODENAME:-}" == trixie ]] || {
  (( FORCE )) || die 'this bootstrap targets Debian 13 (trixie); use --force only if you know what you are doing'
}

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
if [[ "$VENDOR" != Acer || "$PRODUCT" != 'Nitro AN14-41' ]]; then
  (( FORCE )) || die "expected Acer Nitro AN14-41, detected: $VENDOR $PRODUCT"
fi

command -v sudo >/dev/null 2>&1 || die 'sudo is required'
sudo -v

REPO_PATH="$ROOT"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

log "Installing resumable bootstrap service for $TARGET_USER"
sudo install -d -m 0755 /usr/local/lib/nitro-bootstrap /var/lib/nitro-bootstrap /var/log
sudo install -m 0755 "$ROOT/bootstrap/common.sh" /usr/local/lib/nitro-bootstrap/common.sh
sudo install -m 0755 "$ROOT/bootstrap/runner.sh" /usr/local/lib/nitro-bootstrap/runner.sh
sudo install -m 0644 "$ROOT/bootstrap/nitro-bootstrap-resume.service" /etc/systemd/system/nitro-bootstrap-resume.service

sudo tee /etc/nitro-bootstrap.env >/dev/null <<ENV
TARGET_USER=$TARGET_USER
TARGET_HOME=$TARGET_HOME
REPO_PATH=$REPO_PATH
AUTO_REBOOT=$AUTO_REBOOT
ENV
sudo chmod 0600 /etc/nitro-bootstrap.env

if [[ ! -f /var/lib/nitro-bootstrap/stage ]]; then
  echo 10 | sudo tee /var/lib/nitro-bootstrap/stage >/dev/null
fi

sudo systemctl daemon-reload
sudo systemctl enable nitro-bootstrap-resume.service

cat <<MSG
Bootstrap installed.

The machine will now execute the configuration in stages.
Progress: sudo journalctl -fu nitro-bootstrap-resume.service
State:    sudo cat /var/lib/nitro-bootstrap/stage
Abort:    sudo systemctl disable --now nitro-bootstrap-resume.service

Automatic reboot: $AUTO_REBOOT
MSG

sudo systemctl start nitro-bootstrap-resume.service
