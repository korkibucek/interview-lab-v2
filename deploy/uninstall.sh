#!/usr/bin/env bash
# deploy/uninstall.sh
# Remove all lab artifacts. Leaves base packages (nginx, ufw, cron) installed.
# Use --purge-user to also delete the candidate account and its home directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root

PURGE_USER=0
[[ "${1:-}" == "--purge-user" ]] && PURGE_USER=1

log "Stopping and removing lab services..."
for unit in app.service app-logger.service; do
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
done
rm -f "$APP_UNIT" "$LOGGER_UNIT"
systemctl daemon-reload || true

log "Killing any runaway processes..."
pkill -x yes 2>/dev/null || true

log "Removing lab files, cron, logrotate and web config..."
rm -f "$APP_BIN" "$LOGGER_BIN" "$CPUHOG_BIN" "$CPUHOG_CRON" "$LOGROTATE_CONF" "$BIGFILE"
rm -rf "$APP_DIR" "$APP_LOG_DIR" "$WEB_ROOT"
rm -f "$NGINX_SITE_ENABLED" "$NGINX_SITE_AVAILABLE"
systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true

log "Restoring a working DNS resolver..."
if systemctl is-active --quiet systemd-resolved && [[ -f /run/systemd/resolve/stub-resolv.conf ]]; then
  ln -sf /run/systemd/resolve/stub-resolv.conf "$RESOLV_CONF"
else
  printf 'nameserver 1.1.1.1\n' > "$RESOLV_CONF"
fi

log "Removing candidate sudo/ssh drop-ins..."
rm -f /etc/sudoers.d/90-candidate /etc/ssh/sshd_config.d/60-lab-candidate.conf
systemctl reload ssh 2>/dev/null || true

if [[ $PURGE_USER -eq 1 ]] && id "$CANDIDATE_USER" >/dev/null 2>&1; then
  log "Removing candidate user..."
  pkill -u "$CANDIDATE_USER" 2>/dev/null || true
  userdel -r "$CANDIDATE_USER" 2>/dev/null || true
fi
if id "$APP_USER" >/dev/null 2>&1; then
  userdel "$APP_USER" 2>/dev/null || true
fi

rm -rf "$STATE_DIR"
log "Uninstall complete. (Base packages were left installed.)"
if [[ $PURGE_USER -eq 0 ]]; then
  info "Candidate user kept. Re-run with --purge-user to remove it."
fi
