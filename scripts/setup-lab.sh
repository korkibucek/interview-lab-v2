#!/usr/bin/env bash
# scripts/setup-lab.sh
# Build the HEALTHY baseline of the lab from the templates in lab/ (AlmaLinux 10).
# This is the state the candidate is ultimately trying to restore. It is
# idempotent and is also used as the first half of a reset (setup -> break).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root
require_almalinux_10

log "Setting up healthy lab baseline..."
mkdir -p "$STATE_DIR"; chmod 0700 "$STATE_DIR"

# --- SELinux: permissive for this lab (documented in docs/SECURITY.md) --------
# Keeps SELinux out of scope so the six intended faults behave predictably
# (e.g. nginx binding :8080, serving the lab docroot).
if command -v setenforce >/dev/null 2>&1; then
  setenforce 0 2>/dev/null || true
fi
if [[ -f /etc/selinux/config ]]; then
  sed -ri 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true
fi

# --- Token -------------------------------------------------------------------
if [[ ! -f "$STATE_DIR/token" ]]; then
  rand_hex 16 > "$STATE_DIR/token"
fi
LAB_TOKEN="$(cat "$STATE_DIR/token")"

# --- appuser -----------------------------------------------------------------
if ! id "$APP_USER" >/dev/null 2>&1; then
  log "Creating system user '$APP_USER'..."
  useradd --system --home-dir "$APP_DIR" --shell "$NOLOGIN_SHELL" "$APP_USER"
fi

# --- Web service (nginx, healthy on :80) -------------------------------------
log "Installing web content and nginx config (healthy on :${RIGHT_WEB_PORT})..."
mkdir -p "$WEB_ROOT"
sed "s/__LAB_TOKEN__/${LAB_TOKEN}/g" "$REPO_ROOT/lab/files/index.html" > "$WEB_ROOT/index.html"

# Replace the stock nginx.conf with our minimal one (back up the original once)
# so conf.d/lab.conf is the single server and there is no duplicate default.
if [[ ! -f "$NGINX_BACKUP" && -f "$NGINX_MAIN" ]]; then
  cp -a "$NGINX_MAIN" "$NGINX_BACKUP"
fi
install -m 0644 "$REPO_ROOT/lab/configs/nginx.conf" "$NGINX_MAIN"
install -m 0644 "$REPO_ROOT/lab/configs/lab.conf" "$NGINX_CONF"

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
# Back up the original resolver once; restore from it (or fall back to 1.1.1.1).
if [[ ! -f "$RESOLV_BACKUP" ]]; then
  if [[ -e "$RESOLV_CONF" ]] && grep -q '^nameserver' "$RESOLV_CONF" 2>/dev/null \
     && ! grep -q "$BOGUS_DNS" "$RESOLV_CONF" 2>/dev/null; then
    cp -aL "$RESOLV_CONF" "$RESOLV_BACKUP"
  else
    printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > "$RESOLV_BACKUP"
  fi
fi
# Write in place (don't unlink) so this also works when /etc/resolv.conf is a
# bind-mounted or NetworkManager-managed file.
cat "$RESOLV_BACKUP" > "$RESOLV_CONF"

# --- Firewall (healthy: active, SSH + HTTP allowed) --------------------------
log "Configuring firewalld (healthy: SSH + HTTP allowed)..."
systemctl enable --now firewalld >/dev/null 2>&1 || true
if firewalld_active; then
  firewall-cmd --permanent --add-service=ssh  >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-port="${WRONG_WEB_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# --- Clean any leftover faults so setup is a true healthy baseline -----------
rm -f "$CPUHOG_CRON" "$CPUHOG_BIN" "$BIGFILE"
pkill -x yes 2>/dev/null || true

log "Healthy baseline ready (token: ${LAB_TOKEN})."
