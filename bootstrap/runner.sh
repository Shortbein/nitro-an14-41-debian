#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/nitro-bootstrap/common.sh
[[ -r "$REPO_PATH/bootstrap/versions.env" ]] && source "$REPO_PATH/bootstrap/versions.env"
require_root

: "${TARGET_USER:?TARGET_USER missing}"
: "${TARGET_HOME:?TARGET_HOME missing}"
: "${REPO_PATH:?REPO_PATH missing}"
AUTO_REBOOT="${AUTO_REBOOT:-1}"
TEST_MODE="${TEST_MODE:-0}"
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

setup_vendor_repositories() {
  log 'Configuring vendor repositories used by the captured workstation.'
  install -d -m 0755 /etc/apt/keyrings

  # Docker official Debian repository.
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.sources <<'SRC'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
SRC

  # Visual Studio Code official repository.
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /usr/share/keyrings/microsoft.gpg
  cat > /etc/apt/sources.list.d/vscode.sources <<'SRC'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
SRC

  # Google Chrome official repository.
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
  cat > /etc/apt/sources.list.d/google-chrome.sources <<'SRC'
X-Repolib-Name: Google Chrome
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
SRC

  # AnyDesk official Debian repository.
  curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
  chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
  cat > /etc/apt/sources.list.d/anydesk-stable.list <<'SRC'
deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main
SRC

  # NVIDIA CUDA repository keyring also creates the Debian 13 source.
  local tmp
  tmp="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$tmp" https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
  dpkg -i "$tmp"
  rm -f "$tmp"

  apt-get update
}

install_chatgpt_desktop() {
  # The official .deb bootstraps OpenAI's signed APT source for later upgrades.
  local tmp
  tmp="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$tmp" https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp"
  rm -f "$tmp"
}

install_apt_restore_manifest() {
  local manifest="$REPO_PATH/manifests/apt-manual-reference.txt"
  [[ -r "$manifest" ]] || die "APT restore manifest missing: $manifest"

  local -a available=()
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" && "$pkg" != \#* ]] || continue
    case "$pkg" in
      anydesk|chatgpt|heroic|linux-xanmod-x64v3|linux-image-amd64|linux-headers-amd64|linux-headers-6.12.107+deb13-amd64|cuda-keyring|nvidia-driver|nvidia-driver-cuda|nvidia-driver-libs:i386|nvidia-driver-pinning-595|nvidia-kernel-open-dkms|nvidia-settings|firmware-amd-graphics|firmware-mediatek|mesa-vulkan-drivers:i386|libgl1-mesa-dri:i386|gamescope|zram-tools)
        continue
        ;;
    esac
    if apt-cache show "$pkg" >/dev/null 2>&1; then
      available+=("$pkg")
    else
      warn "captured manual package is currently unavailable and will be skipped: $pkg"
    fi
  done < "$manifest"

  ((${#available[@]})) || die 'APT restore manifest contains no installable packages'
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
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

install_cachyos_proton() {
  local api json url sum_url tmp sum dir compat src
  api='https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest'
  json="$(curl -fsSL "$api")"
  url="$(jq -r '.assets[] | select(.name | test("-x86_64\\.tar\\.xz$")) | .browser_download_url' <<<"$json" | head -n1)"
  sum_url="$(jq -r '.assets[] | select(.name | test("-x86_64\\.sha512sum$")) | .browser_download_url' <<<"$json" | head -n1)"
  [[ -n "$url" && "$url" != null && -n "$sum_url" && "$sum_url" != null ]] || return 1

  tmp="$(mktemp --suffix=.tar.xz)"
  sum="$(mktemp --suffix=.sha512sum)"
  dir="$(mktemp -d)"
  curl -fsSL -o "$tmp" "$url"
  curl -fsSL -o "$sum" "$sum_url"
  # Check the published hash regardless of the local temporary filename.
  local expected actual
  expected="$(awk '{print $1}' "$sum" | head -n1)"
  actual="$(sha512sum "$tmp" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || die 'Proton-CachyOS SHA512 verification failed'

  tar -xJf "$tmp" -C "$dir"
  src="$(find "$dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$src" ]] || die 'Proton-CachyOS archive did not contain a top-level directory'
  compat="$TARGET_HOME/.local/share/Steam/compatibilitytools.d"
  mkdir -p "$compat"
  rm -rf "$compat/Proton-CachyOS Latest"
  cp -a "$src" "$compat/Proton-CachyOS Latest"
  chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$compat"
  rm -rf "$tmp" "$sum" "$dir"
}

install_flatpaks() {
  local manifest="$REPO_PATH/manifests/flatpak-apps.tsv"
  command -v flatpak >/dev/null 2>&1 || return 0
  flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  local app branch origin
  while IFS=$'\t' read -r app branch origin; do
    [[ -n "$app" ]] || continue
    [[ "$origin" == flathub ]] || { warn "skipping non-Flathub captured app: $app ($origin)"; continue; }
    flatpak install --system -y --noninteractive flathub "$app"
  done < "$manifest"
}

install_protontricks_cli() {
  apt_install pipx
  as_user "$TARGET_USER" pipx ensurepath || true
  if ! as_user_shell "$TARGET_USER" 'command -v protontricks >/dev/null 2>&1'; then
    as_user "$TARGET_USER" pipx install protontricks
  fi
}

asense_command() {
  local cmd="$1"
  runuser -u "$TARGET_USER" -- env CMD="$cmd" python3 - <<'PY'
import os, socket
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(5)
s.connect('/run/asense-control.sock'); f=s.makefile('rwb',buffering=0)
f.write(b'HELLO 2\n'); hello=f.readline(4097).decode().strip()
if not hello.startswith('OK'): raise SystemExit(1)
f.write((os.environ['CMD']+'\n').encode()); result=f.readline(4097).decode().strip()
print(result)
raise SystemExit(0 if result.startswith('OK') else 1)
PY


stage_10_base() {
  log 'STAGE 10: Debian base, vendor sources, captured APT manifest, ZRAM and power baseline'
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
  apt_install ca-certificates curl wget git jq unzip zip patch gnupg lsb-release \
    build-essential dkms libelf-dev python3 python3-pip pipx \
    linux-headers-amd64 amd64-microcode firmware-sof-signed \
    power-profiles-daemon lm-sensors pciutils usbutils mesa-utils vulkan-tools \
    mokutil desktop-file-utils flatpak plasma-discover-backend-flatpak

  setup_vendor_repositories
  install_chatgpt_desktop || warn 'ChatGPT desktop installation failed; continuing.'
  install_apt_restore_manifest
  apt_install anydesk

  apt_install_backports firmware-amd-graphics firmware-mediatek \
    mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 \
    libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386

  apt_install zram-tools
  install -m 0644 "$REPO_PATH/bootstrap/zramswap" /etc/default/zramswap
  systemctl enable zramswap.service
  systemctl restart zramswap.service

  ensure_grub_arg acpi_backlight=native
  update-grub
  systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
  powerprofilesctl set balanced 2>/dev/null || true
  set_stage 20
}

stage_20_graphics_gaming_and_apps() {
  log 'STAGE 20: NVIDIA 595 open modules, desktop/dev apps, gaming stack and Flatpaks'
  wait_for_apt

  apt_install "nvidia-driver-pinning-${NVIDIA_BRANCH:-595}" \
    nvidia-driver nvidia-driver-cuda nvidia-kernel-open-dkms \
    nvidia-driver-libs:i386 nvidia-settings

  apt_install steam-installer steam-devices wine wine32:i386 wine64 winetricks lutris \
    gamemode mangohud:amd64 mangohud:i386 vkmark glmark2-x11 sysbench stress-ng
  apt_install_backports gamescope

  install -m 0755 "$REPO_PATH/gamemode/gamemode-profile-start" /usr/local/bin/gamemode-profile-start
  install -m 0755 "$REPO_PATH/gamemode/gamemode-profile-end" /usr/local/bin/gamemode-profile-end
  install -m 0644 "$REPO_PATH/gamemode/gamemode.ini" /etc/gamemode.ini

  install_heroic || warn 'Heroic automatic installation failed; continuing.'
  install_protontricks_cli || warn 'protontricks CLI installation failed; Flatpak copy will still be restored.'
  install_ge_proton || warn 'GE-Proton automatic installation failed; continuing.'
  install_cachyos_proton || warn 'Proton-CachyOS automatic installation failed; continuing.'
  install_flatpaks || warn 'One or more Flatpak applications failed to restore.'

  getent group docker >/dev/null 2>&1 && usermod -aG docker "$TARGET_USER" || true
  systemctl enable --now docker.service 2>/dev/null || true
  systemctl enable --now ssh.service 2>/dev/null || true
  systemctl enable --now anydesk.service 2>/dev/null || true
  systemctl enable --now bluetooth.service 2>/dev/null || true
  systemctl enable fstrim.timer 2>/dev/null || true

  set_stage 30
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
  sum_url="$(curl -fsSL "$api" | jq -r '.assets[] | select(.name | test("ubuntu-26.04-x86_64-installer.*\\.zip\\.sha256$")) | .browser_download_url' | head -n1)"
  [[ -n "$zip_url" && "$zip_url" != null && -n "$sum_url" && "$sum_url" != null ]] || die 'ASense release assets not found'
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

  if [[ "$TEST_MODE" == 1 ]]; then
    log 'TEST MODE: ASense payload/checksum/AN14-41 patch validated; skipping Acer WMI/DKMS install and hardware writes.'
    rm -rf "$tmp"
    set_stage 40
    return 0
  fi

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

stage_40_kernels() {
  log 'STAGE 40: Debian Backports fallback kernel and XanMod x64v3'
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
  if [[ "$TEST_MODE" == 1 ]]; then
    log 'TEST MODE: skipping ASense DKMS gate (QEMU has no Acer WMI endpoint).'
  else
    dkms status | grep -F "asense-rgb/${ASENSE_VERSION:-0.3.0}, $xk" | grep -q 'installed' || die "ASense DKMS missing for $xk"
  fi
  dkms status | grep -F 'nvidia/' | grep -F ", $xk" | grep -q 'installed' || die "NVIDIA DKMS missing for $xk"

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

  if [[ "$TEST_MODE" == 1 ]]; then
    log 'TEST MODE: XanMod reboot/resume succeeded. Verifying NVIDIA DKMS build only; hardware load/ASense/RTD3 checks are skipped.'
    dkms status | grep -F 'nvidia/' | grep -F ", $kernel" | grep -q 'installed' || die "NVIDIA DKMS missing for running test kernel $kernel"
    powerprofilesctl set balanced 2>/dev/null || true
    set_stage 60
    return 0
  fi

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
  log 'STAGE 60: OpenClaw CLI and safe local policy (provider OAuth stays manual)'
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
  log 'STAGE 70: final validation report'
  local report="$STATE_DIR/final-report.txt"
  {
    echo "completed=$(date --iso-8601=seconds)"
    echo "kernel=$(uname -r)"
    echo "power_profile=$(powerprofilesctl get 2>/dev/null || true)"
    echo "user=$TARGET_USER"
    echo "test_mode=$TEST_MODE"
    echo '--- dkms ---'; dkms status || true
    echo '--- swap ---'; swapon --show || true
    echo '--- flatpaks ---'; flatpak list --app --columns=application,branch,origin 2>/dev/null || true
    echo '--- failed units ---'; systemctl --failed --no-pager || true
  } > "$report"

  if [[ -x "$REPO_PATH/scripts/verify-restore-coverage.sh" ]]; then
    if ! "$REPO_PATH/scripts/verify-restore-coverage.sh" > "$STATE_DIR/coverage-report.txt" 2>&1; then
      warn "Restore coverage has differences; see $STATE_DIR/coverage-report.txt"
    fi
  fi

  set_stage done
  systemctl disable nitro-bootstrap-resume.service || true
  log 'Bootstrap complete.'
  log 'Manual items intentionally remaining: account logins, OpenClaw model-provider OAuth/onboarding, and Secure Boot MOK enrollment if firmware requires it.'
  log "Final report: $report"
}

stage="$(cat "$STAGE_FILE" 2>/dev/null || echo 10)"
log "Starting/resuming Nitro bootstrap at stage $stage (kernel $(uname -r), test_mode=$TEST_MODE)"
case "$stage" in
  10) stage_10_base; stage_20_graphics_gaming_and_apps; stage_30_asense; stage_40_kernels ;;
  20) stage_20_graphics_gaming_and_apps; stage_30_asense; stage_40_kernels ;;
  30) stage_30_asense; stage_40_kernels ;;
  40) stage_40_kernels ;;
  50) stage_50_verify_after_reboot; stage_60_openclaw; stage_70_finalize ;;
  60) stage_60_openclaw; stage_70_finalize ;;
  70) stage_70_finalize ;;
  done) log 'Bootstrap already completed.' ;;
  *) die "unknown stage: $stage" ;;
esac
