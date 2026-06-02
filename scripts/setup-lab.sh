#!/usr/bin/env bash
# scripts/setup-lab.sh
# Build the HEALTHY baseline of the lab from the templates in lab/.
# This is the state the candidate is ultimately trying to restore. It is
# idempotent and is also used as the first half of a reset (setup -> break).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root
require_ubuntu_2404

log "Setting up healthy lab baseline..."
mkdir -p "$STATE_DIR"

# --- Token -------------------------------------------------------------------
if [[ ! -f "$STATE_DIR/token" ]]; then
  rand_hex 16 > "$STATE_DIR/token"
fi
LAB_TOKEN="$(cat "$STATE_DIR/token")"

# --- appuser -----------------------------------------------------------------
if ! id "$APP_USER" >/dev/null 2>&1; then
  log "Creating system user '$APP_USER'..."
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

# --- Web service (nginx, healthy on :80) -------------------------------------
log "Installing web content and nginx site (healthy on :${RIGHT_WEB_PORT})..."
mkdir -p "$WEB_ROOT"
sed "s/__LAB_TOKEN__/${LAB_TOKEN}/g" "$REPO_ROOT/lab/files/index.html" > "$WEB_ROOT/index.html"

install -m 0644 "$REPO_ROOT/lab/configs/nginx-lab.conf" "$NGINX_SITE_AVAILABLE"
ln -sf "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
# Remove the distro default site so nothing else owns :80.
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx >/dev/null 2>&1 || systemctl enable nginx
systemctl restart nginx

# --- app.service (healthy: executable + writable dir) ------------------------
log "Installing app.service (healthy)..."
install -m 0755 "$REPO_ROOT/lab/files/app.sh" "$APP_BIN"
mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"
chmod 0755 "$APP_DIR"
install -m 0644 "$REPO_ROOT/lab/services/app.service" "$APP_UNIT"

# --- app-logger.service (healthy chatty logger) ------------------------------
log "Installing app-logger.service (healthy)..."
install -m 0755 "$REPO_ROOT/lab/files/app-logger.sh" "$LOGGER_BIN"
mkdir -p "$APP_LOG_DIR"
: > "$APP_LOG"
install -m 0644 "$REPO_ROOT/lab/services/app-logger.service" "$LOGGER_UNIT"

systemctl daemon-reload
systemctl enable --now app.service
systemctl enable --now app-logger.service

# --- Log rotation (healthy) --------------------------------------------------
log "Installing healthy logrotate config..."
install -m 0644 "$REPO_ROOT/lab/configs/logrotate-app.conf" "$LOGROTATE_CONF"

# --- DNS (healthy resolver) --------------------------------------------------
log "Ensuring a working DNS resolver..."
if systemctl is-active --quiet systemd-resolved && [[ -f /run/systemd/resolve/stub-resolv.conf ]]; then
  ln -sf /run/systemd/resolve/stub-resolv.conf "$RESOLV_CONF"
else
  rm -f "$RESOLV_CONF"
  printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > "$RESOLV_CONF"
fi

# --- Clean any leftover faults so setup is a true healthy baseline -----------
rm -f "$CPUHOG_CRON" "$CPUHOG_BIN" "$BIGFILE"
pkill -f '^/usr/bin/yes$' 2>/dev/null || pkill -x yes 2>/dev/null || true

log "Healthy baseline ready (token: ${LAB_TOKEN})."
