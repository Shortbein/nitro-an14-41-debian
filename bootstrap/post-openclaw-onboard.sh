#!/usr/bin/env bash
set -Eeuo pipefail
OC="$HOME/.openclaw/bin/openclaw"
[[ -x "$OC" ]] || { echo 'OpenClaw CLI not found.' >&2; exit 1; }

echo 'Run the interactive provider/model onboarding first:'
echo "  $OC onboard"
echo
echo 'After onboarding completes, run this script again with --finish.'

if [[ "${1:-}" != --finish ]]; then
  exit 0
fi

"$OC" exec-policy preset cautious
"$OC" config set tools.fs.workspaceOnly true
"$OC" config set tools.elevated.enabled false
"$OC" config set tools.deny '["browser","portal","cron","automations","gateway"]' --strict-json
"$OC" config validate
"$OC" plugins install '@openclaw/codex@2026.9.4' --pin || true
"$OC" gateway install
"$OC" gateway status
