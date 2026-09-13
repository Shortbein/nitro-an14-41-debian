#!/usr/bin/env bash
set -u
ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
printf '=== APT manual package coverage ===\n'
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] || continue
  if [[ "$pkg" == linux-headers-6.12.107+deb13-amd64 ]]; then
    printf 'RETIRED   %s (reference kernel only)\n' "$pkg"
    continue
  fi
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
    :
  else
    printf 'MISSING   %s\n' "$pkg"
    fail=1
  fi
done < "$ROOT/manifests/apt-manual-reference.txt"

printf '\n=== Flatpak coverage ===\n'
if command -v flatpak >/dev/null 2>&1; then
  while IFS=$'\t' read -r app branch origin rest; do
    [[ -n "$app" ]] || continue
    if flatpak info "$app" >/dev/null 2>&1; then
      printf 'OK        %s\n' "$app"
    else
      printf 'MISSING   %s\n' "$app"
      fail=1
    fi
  done < "$ROOT/manifests/flatpak-apps.tsv"
else
  echo 'MISSING   flatpak command'
  fail=1
fi

printf '\n=== Critical configuration ===\n'
checks=(
  /etc/gamemode.ini
  /etc/default/zramswap
  /usr/local/bin/gamemode-profile-start
  /usr/local/bin/gamemode-profile-end
  /usr/local/sbin/asense-keyboard-warm
  /etc/systemd/system/asense-keyboard-warm.service
)
for f in "${checks[@]}"; do
  [[ -e "$f" ]] && printf 'OK        %s\n' "$f" || { printf 'MISSING   %s\n' "$f"; fail=1; }
done

printf '\n=== Kernel/DKMS ===\n'
uname -r
dkms status || true

exit "$fail"
