#!/usr/bin/env bash
# deploy/healthcheck.sh
# Quick admin-facing snapshot of the lab host. Read-only; always exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

printf '%s== Lab host healthcheck ==%s\n\n' "$C_BOLD" "$C_RESET"

printf 'Root fs usage : %s%%\n' "$(root_fs_use_pct)"
printf 'nginx         : %s\n' "$(systemctl is-active nginx 2>/dev/null)"
printf 'app.service   : %s\n' "$(systemctl is-active app.service 2>/dev/null)"
printf 'app-logger    : %s\n' "$(systemctl is-active app-logger.service 2>/dev/null)"
printf 'cron          : %s\n' "$(systemctl is-active cron 2>/dev/null)"
printf 'ssh           : %s\n' "$(systemctl is-active ssh 2>/dev/null)"
printf 'ufw           : %s\n' "$(ufw status 2>/dev/null | awk 'NR==1{print $2}')"
printf 'runaway yes   : %s process(es)\n' "$(pgrep -xc yes 2>/dev/null || echo 0)"

printf '\nListening sockets (80/8080):\n'
ss -ltnp 2>/dev/null | grep -E ':80|:8080' || printf '  (none)\n'
