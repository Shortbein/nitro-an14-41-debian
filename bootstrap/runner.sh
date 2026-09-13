#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/nitro-bootstrap/common.sh
[[ -r "$REPO_PATH/bootstrap/versions.env" ]] && source "$REPO_PATH/bootstrap/versions.env"
require_root

: "${TARGET_USER:?TARGET_USER missing}"
: "${TARGET_HOME:?TARGET_HOME missing}"
: "${REPO_PATH:?REPO_PATH missing}"
AUTO_REBOOT="${AUTO_REBOOT:-1}"
STATE_DIR=/var/lib/nitro-bootstrap
STAGE_FILE="$STATE_DIR/stage"
mkdir -p "$STATE_DIR"

touch /var/log/nitro-bootstrap.log
exec > >(tee -a /var/log/nitro-bootstrap.log) 2>&1

trap 'rc=$?; warn "bootstrap stopped with exit code $rc at stage $(cat "$STAGE_FILE" 2>/dev/null || echo unknown)"; exit $rc' ERR

set_stage() {
  printf '%s\n' "$1" > "$STAGE_FILE"
}

reboot_or_stop() {
  if [[ "$AUTO_REBOOT" == 1 ]]; then
    log 'Rebooting in 10 seconds; bootstrap will resume automatically.'
    sleep 10
    systemctl reboot
  else
    log 'Reboot required. Reboot manually; bootstrap will resume automatically.'
  fi
}

stage_10_base() {
  log 'STAGE 10: Debian base, firmware, Mesa/i386, power and ZRAM'
  wait_for_apt
  ensure_debian_components
  dpkg --add-architecture i386

  cat > /etc/apt/sources.list.d/nitro-backports.sources <<'SRC'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC

  apt-get update
  apt_install \
    ca-certificates curl wget git jq unzip zip patch gnupg lsb-release \
    build-essential dkms libelf-dev python3 python3-pip pipx \
    linux-headers-amd64 amd64-microcode firmware-sof-signed \
    power-profiles-daemon systemd-zram-generator \
    lm-sensors pciutils usbutils mesa-utils vulkan-tools \
    mokutil desktop-file-utils

  apt_install_backports firmware-amd-graphics firmware-mediatek \
    mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 \
    libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386

  cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
ZRAM

  ensure_grub_arg acpi_backlight=native
  update-grub
  systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
  powerprofilesctl set balanced 2>/dev/null || true
  set_stage 20
}

stage_20_graphics_gaming() {
  log 'STAGE 20: NVIDIA 595 open modules and gaming stack'
  wait_for_apt

  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/cuda-keyring.deb" \
    https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
  dpkg -i "$tmp/cuda-keyring.deb"
  apt-get update

  apt_install "nvidia-driver-pinning-${NVIDIA_BRANCH:-595}" nvidia-open nvidia-driver-libs:i386 \
    nvidia-settings nvidia-smi nvidia-powerd

  apt_install steam-installer steam-devices wine wine32:i386 winetricks lutris \
    gamemode mangohud:amd64 mangohud:i386 vkmark glmark2-x11 sysbench stress-ng
  apt_install_backports gamescope

  install -m 0755 "$REPO_PATH/gamemode/gamemode-profile-start" /usr/local/bin/gamemode-profile-start
  install -m 0755 "$REPO_PATH/gamemode/gamemode-profile-end" /usr/local/bin/gamemode-profile-end
  install -m 0644 "$REPO_PATH/gamemode/gamemode.ini" /etc/gamemode.ini

  if ! as_user_shell "$TARGET_USER" 'command -v protontricks >/dev/null 2>&1'; then
    as_user_shell "$TARGET_USER" 'python3 -m pipx install protontricks'
  fi

  install_heroic || warn 'Heroic automatic installation failed; it can be installed manually later.'
  install_ge_proton || warn 'GE-Proton automatic installation failed; it can be installed manually later.'

  set_stage 30
}

install_heroic() {
  local api url tmp
  api='https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest'
  url="$(curl -fsSL "$api" | jq -r '.assets[] | select(.name | test("linux-amd64.*\\.deb$|amd64.*\\.deb$"; "i")) | .browser_download_url' | head -n1)"
  [[ -n "$url" && "$url" != null ]] || return 1
  tmp="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$tmp" "$url"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp"
  rm -f "$tmp"
}

install_ge_proton() {
  local tag="${GE_PROTON_TAG:-GE-Proton11-6}" api url tmp dir compat
  api="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/tags/$tag"
  url="$(curl -fsSL "$api" | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' | head -n1)"
  [[ -n "$url" && "$url" != null ]] || return 1
  tmp="$(mktemp --suffix=.tar.gz)"
  dir="$(mktemp -d)"
  compat="$TARGET_HOME/.steam/root/compatibilitytools.d"
  curl -fsSL -o "$tmp" "$url"
  mkdir -p "$compat"
  tar -xzf "$tmp" -C "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 -type d -exec cp -a {} "$compat/" \;
  chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$compat"
  rm -rf "$tmp" "$dir"
}

stage_30_asense() {
  log 'STAGE 30: ASense 0.3.0, AN14-41 RGB quirk, battery cap and warm RGB service'
  wait_for_apt
  apt_install build-essential dkms "linux-headers-$(uname -r)" kmod udev util-linux \
    python3 unzip mokutil desktop-file-utils \
    libgtk-3-0t64 libwebkit2gtk-4.1-0 libxdo3 libssl3t64

  local tmp api zip_url sum_url zip sum dir
  tmp="$(mktemp -d)"
  api="https://api.github.com/repos/fladirm/asense/releases/tags/v${ASENSE_VERSION:-0.3.0}"
  zip_url="$(curl -fsSL "$api" | jq -r '.assets[] | select(.name | test("ubuntu-26.04-x86_64-installer.*\\.zip$")) | .browser_download_url' | head -n1)"
  sum_url="$(curl -fsSL "$api" | jq -r '.assets[] | select(.name | test("ubuntu-26.04-x86_64-installer.*\\.zip.sha256$")) | .browser_download_url' | head -n1)"
  [[ -n "$zip_url" && "$zip_url" != null && -n "$sum_url" && "$sum_url" != null ]] || die 'ASense v0.3.0 release assets not found'
  zip="$tmp/$(basename "$zip_url")"
  sum="$tmp/$(basename "$sum_url")"
  curl -fsSL -o "$zip" "$zip_url"
  curl -fsSL -o "$sum" "$sum_url"
  (cd "$tmp" && sha256sum --check "$(basename "$sum")")
  unzip -q "$zip" -d "$tmp/unpacked"
  dir="$(find "$tmp/unpacked" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$dir" ]] || die 'ASense installer directory not found'

  patch -d "$dir" -p1 --forward < "$REPO_PATH/bootstrap/asense-v0.3.0-an14-41.patch" || {
    grep -q 'Nitro AN14-41' "$dir/kernel/asense_rgb.c" || die 'ASense AN14-41 patch failed'
  }
  "$dir/install.sh" "$dir/bin/asense" "$TARGET_USER"
  rm -rf "$tmp"

  install -m 0755 "$REPO_PATH/asense/asense-keyboard-warm" /usr/local/sbin/asense-keyboard-warm
  sed "s/^User=.*/User=$TARGET_USER/" "$REPO_PATH/asense/asense-keyboard-warm.service" \
    > /etc/systemd/system/asense-keyboard-warm.service
  systemctl daemon-reload
  systemctl enable asense-keyboard-warm.service
  systemctl start asense-keyboard-warm.service || true

  asense_command 'PLATFORM BATTERY_LIMIT ON' || warn 'Could not set ASense battery limit automatically.'
  set_stage 40
}

asense_command() {
  local cmd="$1"
  runuser -u "$TARGET_USER" -- env CMD="$cmd" python3 - <<'PY'
import os, socket, sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(5)
s.connect('/run/asense-control.sock'); f=s.makefile('rwb',buffering=0)
f.write(b'HELLO 2\n'); hello=f.readline(4097).decode().strip()
if not hello.startswith('OK'): raise SystemExit(1)
f.write((os.environ['CMD']+'\n').encode()); result=f.readline(4097).decode().strip()
print(result)
raise SystemExit(0 if result.startswith('OK') else 1)
PY
}

stage_40_kernels() {
  log 'STAGE 40: Debian backports backup kernel and XanMod x64v3'
  wait_for_apt
  apt_install_backports linux-image-amd64 linux-headers-amd64

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
  cat > /etc/apt/sources.list.d/xanmod-release.list <<'XAN'
deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org trixie main
XAN
  apt-get update
  apt_install --no-install-recommends dkms libelf-dev clang lld llvm
  apt_install "${XANMOD_PACKAGE:-linux-xanmod-x64v3}"

  local xk
  xk="$(basename "$(ls -1 /boot/vmlinuz-*xanmod* 2>/dev/null | sort -V | tail -n1)" | sed 's/^vmlinuz-//')"
  [[ -n "$xk" ]] || die 'XanMod kernel was not installed'
  log "XanMod target kernel: $xk"
  dkms status | grep -F "asense-rgb/${ASENSE_VERSION:-0.3.0}, $xk" | grep -q 'installed' || die "ASense DKMS missing for $xk"
  dkms status | grep -F "nvidia/" | grep -F ", $xk" | grep -q 'installed' || die "NVIDIA DKMS missing for $xk"

  update-initramfs -u -k "$xk"
  update-grub
  set_stage 50
  reboot_or_stop
}

stage_50_verify_after_reboot() {
  log 'STAGE 50: post-reboot validation'
  local kernel
  kernel="$(uname -r)"
  [[ "$kernel" == *xanmod* ]] || die "expected XanMod after reboot, running $kernel. Boot XanMod manually and restart this service."

  modprobe nvidia || true
  modprobe asense_rgb || true
  [[ -r /proc/driver/nvidia/version ]] || die 'NVIDIA driver did not load'
  lsmod | grep -q '^asense_rgb' || die 'ASense module did not load'

  command -v glxinfo >/dev/null && glxinfo -B | grep -q 'AMD Radeon Graphics' || warn 'AMD OpenGL renderer could not be verified yet (graphical session may not be running).'
  command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -q 'NVIDIA GeForce RTX 4060' || warn 'NVIDIA Vulkan device could not be verified yet.'

  powerprofilesctl set balanced 2>/dev/null || true
  systemctl restart asense-keyboard-warm.service || true
  sleep 30
  if [[ -r /sys/bus/pci/devices/0000:01:00.0/power/runtime_status ]]; then
    log "NVIDIA runtime_status=$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status)"
  fi
  set_stage 60
}

stage_60_openclaw() {
  log 'STAGE 60: OpenClaw CLI and safe local policy (authentication remains manual)'
  if [[ "${INSTALL_OPENCLAW:-1}" == 1 ]]; then
    as_user_shell "$TARGET_USER" "curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install-cli.sh | bash -s -- --prefix \"\$HOME/.openclaw\" --version '${OPENCLAW_VERSION:-2026.9.4}'" || warn 'OpenClaw installation failed; continuing.'
    install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" -m 0755 "$TARGET_HOME/.openclaw/workspace"
    install -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" -m 0644 "$REPO_PATH/openclaw/AGENTS.md" "$TARGET_HOME/.openclaw/workspace/AGENTS.md"
    local oc="$TARGET_HOME/.openclaw/bin/openclaw"
    if [[ -x "$oc" ]]; then
      as_user "$TARGET_USER" "$oc" exec-policy preset cautious || true
      as_user "$TARGET_USER" "$oc" config set tools.fs.workspaceOnly true || true
      as_user "$TARGET_USER" "$oc" config set tools.elevated.enabled false || true
      as_user "$TARGET_USER" "$oc" config set tools.deny '["browser","portal","cron","automations","gateway"]' --strict-json || true
      as_user "$TARGET_USER" "$oc" config validate || true
    fi
  fi
  set_stage 70
}

stage_70_finalize() {
  log 'STAGE 70: final report and cleanup'
  local report="$STATE_DIR/final-report.txt"
  {
    echo "completed=$(date --iso-8601=seconds)"
    echo "kernel=$(uname -r)"
    echo "power_profile=$(powerprofilesctl get 2>/dev/null || true)"
    echo '--- dkms ---'; dkms status || true
    echo '--- swap ---'; swapon --show || true
    echo '--- failed units ---'; systemctl --failed --no-pager || true
  } > "$report"

  set_stage done
  systemctl disable nitro-bootstrap-resume.service || true
  log 'Bootstrap complete.'
  log 'Manual items intentionally not automated: Steam/other account logins, Proton Experimental download, and OpenClaw model OAuth/onboarding.'
  log "Final report: $report"
}

stage="$(cat "$STAGE_FILE" 2>/dev/null || echo 10)"
log "Starting/resuming Nitro bootstrap at stage $stage (kernel $(uname -r))"
case "$stage" in
  10) stage_10_base; stage_20_graphics_gaming; stage_30_asense; stage_40_kernels ;;
  20) stage_20_graphics_gaming; stage_30_asense; stage_40_kernels ;;
  30) stage_30_asense; stage_40_kernels ;;
  40) stage_40_kernels ;;
  50) stage_50_verify_after_reboot; stage_60_openclaw; stage_70_finalize ;;
  60) stage_60_openclaw; stage_70_finalize ;;
  70) stage_70_finalize ;;
  done) log 'Bootstrap already completed.' ;;
  *) die "unknown stage: $stage" ;;
esac
