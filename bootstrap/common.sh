#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date --iso-8601=seconds)" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date --iso-8601=seconds)" "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'root privileges required'
}

retry() {
  local tries="$1" delay="$2"
  shift 2
  local n=1
  until "$@"; do
    if (( n >= tries )); then
      return 1
    fi
    warn "command failed (attempt $n/$tries): $*"
    sleep "$delay"
    ((n++))
  done
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

apt_install_backports() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y -t trixie-backports "$@"
}

as_user() {
  local user="$1"
  shift
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" ]] || die "cannot resolve home for $user"
  runuser -u "$user" -- env HOME="$home" USER="$user" LOGNAME="$user" "$@"
}

as_user_shell() {
  local user="$1"
  shift
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" ]] || die "cannot resolve home for $user"
  runuser -u "$user" -- env HOME="$home" USER="$user" LOGNAME="$user" bash -lc "$*"
}

ensure_line() {
  local line="$1" file="$2"
  touch "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

ensure_grub_arg() {
  local arg="$1" file=/etc/default/grub
  [[ -f "$file" ]] || return 0
  python3 - "$arg" "$file" <<'PY'
import pathlib, re, sys
arg, fn = sys.argv[1], pathlib.Path(sys.argv[2])
s = fn.read_text()
m = re.search(r'^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"', s, re.M)
if not m:
    s += f'\nGRUB_CMDLINE_LINUX_DEFAULT="{arg}"\n'
else:
    args = m.group(1).split()
    if arg not in args:
        args.append(arg)
    s = s[:m.start(1)] + ' '.join(args) + s[m.end(1):]
fn.write_text(s)
PY
}

ensure_debian_components() {
  python3 <<'PY'
from pathlib import Path
wanted = ['main','contrib','non-free','non-free-firmware']
for p in [Path('/etc/apt/sources.list')] + sorted(Path('/etc/apt/sources.list.d').glob('*.list')):
    if not p.exists():
        continue
    out=[]
    changed=False
    for line in p.read_text().splitlines():
        raw=line
        s=line.strip()
        if s.startswith(('deb ', 'deb-src ')) and 'debian' in s and not s.startswith('#'):
            parts=line.split()
            if len(parts)>=4:
                for c in wanted:
                    if c not in parts:
                        parts.append(c); changed=True
                line=' '.join(parts)
        out.append(line)
    if changed:
        p.with_suffix(p.suffix+'.nitro-backup').write_text(p.read_text())
        p.write_text('\n'.join(out)+'\n')

for p in sorted(Path('/etc/apt/sources.list.d').glob('*.sources')):
    text=p.read_text()
    lines=[]; changed=False
    for line in text.splitlines():
        if line.startswith('Components:'):
            comps=line.split(':',1)[1].split()
            for c in wanted:
                if c not in comps:
                    comps.append(c); changed=True
            line='Components: ' + ' '.join(comps)
        lines.append(line)
    if changed:
        Path(str(p)+'.nitro-backup').write_text(text)
        p.write_text('\n'.join(lines)+'\n')
PY
}

wait_for_apt() {
  local i
  for i in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
       ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  die 'APT lock did not become available'
}
