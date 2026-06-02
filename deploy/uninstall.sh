#!/usr/bin/env bash
# deploy/uninstall.sh
# Remove all lab artifacts (AlmaLinux 10). Leaves base packages installed.
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
rm -rf "$APP_DIR" "$APP_LOG_DIR"
rm -f "$NGINX_CONF" "$WEB_ROOT/index.html"
# Restore the stock nginx.conf if we backed it up.
if [[ -f "$NGINX_BACKUP" ]]; then
  cp -a "$NGINX_BACKUP" "$NGINX_MAIN"
fi
systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true

log "Restoring DNS resolver and firewall..."
if [[ -f "$RESOLV_BACKUP" ]]; then
  cat "$RESOLV_BACKUP" > "$RESOLV_CONF"
fi
if firewalld_active; then
  firewall-cmd --permanent --remove-port="${WRONG_WEB_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

log "Removing candidate sudo/ssh drop-ins..."
rm -f /etc/sudoers.d/90-candidate /etc/ssh/sshd_config.d/60-lab-candidate.conf
systemctl reload "$SSH_SERVICE" 2>/dev/null || true

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
