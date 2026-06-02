#!/usr/bin/env bash
# scripts/break-lab.sh
# Apply the six intentional faults on top of the healthy baseline (AlmaLinux 10).
# Safe to run after setup-lab.sh. Designed so no fault can lock out SSH or
# fill the root filesystem.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root
require_almalinux_10

log "Applying lab faults..."

# --- Fault A: web off :80, and firewall blocking :80 -------------------------
log "A) Moving nginx off :${RIGHT_WEB_PORT} to :${WRONG_WEB_PORT} and blocking :${RIGHT_WEB_PORT} at the firewall..."
sed -ri "s/listen 80 default_server;/listen ${WRONG_WEB_PORT} default_server;/" "$NGINX_CONF"
sed -ri "s/listen \[::\]:80 default_server;/listen [::]:${WRONG_WEB_PORT} default_server;/" "$NGINX_CONF"
nginx -t
systemctl restart nginx

# Firewall: ALWAYS keep SSH open (no lockout), remove HTTP, expose the wrong port.
systemctl enable --now firewalld >/dev/null 2>&1 || warn "firewalld not available?"
if firewalld_active; then
  firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-service=http >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port="${WRONG_WEB_PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# --- Fault B: app.service binary non-executable + dir not writable by appuser -
log "B) Breaking app.service (non-executable binary + unwritable working dir)..."
chmod 0644 "$APP_BIN"                 # layer 1: 203/EXEC
chown root:root "$APP_DIR"            # layer 2: appuser cannot write run.log
chmod 0700 "$APP_DIR"
systemctl restart app.service || true # expected to fail

# --- Fault C: DNS resolver pointed at an unroutable nameserver ---------------
log "C) Breaking DNS resolution..."
printf '# lab fault: resolver unreachable\nnameserver %s\n' "$BOGUS_DNS" > "$RESOLV_CONF"

# --- Fault D: log rotation pointed at the wrong directory, no copytruncate ----
log "D) Breaking log rotation (wrong path, no copytruncate)..."
cat > "$LOGROTATE_CONF" <<ROT
${LOGROTATE_WRONG_DIR}/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
}
ROT

# --- Fault E: cron-driven CPU hog --------------------------------------------
log "E) Installing cron CPU hog..."
install -m 0755 "$REPO_ROOT/lab/files/cpuhog.sh" "$CPUHOG_BIN"
cat > "$CPUHOG_CRON" <<CRON
# Lab fault: runaway scheduled job
* * * * * root ${CPUHOG_BIN}
CRON
chmod 0644 "$CPUHOG_CRON"
systemctl reload "$CRON_SERVICE" 2>/dev/null || systemctl restart "$CRON_SERVICE" 2>/dev/null || true
# Kick one off immediately so the load is present before the first cron tick.
"$CPUHOG_BIN" || true

# --- Fault F: disk pressure (size-aware, never fills the disk) ----------------
log "F) Creating disk pressure (size-aware with a safety margin)..."
total_bytes=$(df -P --block-size=1 / | awk 'NR==2 { print $3+$4 }')
used_bytes=$(df -P --block-size=1 / | awk 'NR==2 { print $3 }')
avail_bytes=$(root_fs_avail_bytes)

alloc_by_pct=$(( total_bytes * DISK_MAX_PCT / 100 - used_bytes ))
alloc_by_free=$(( avail_bytes - DISK_SAFETY_FREE_BYTES ))
alloc=$alloc_by_pct
[[ $alloc_by_free -lt $alloc ]] && alloc=$alloc_by_free
# Optional hard cap (e.g. to bound pressure on a large disk, or for testing).
if [[ -n "${LAB_MAX_BIGFILE_BYTES:-}" && "${LAB_MAX_BIGFILE_BYTES}" -lt "$alloc" ]]; then
  alloc="${LAB_MAX_BIGFILE_BYTES}"
fi

min_alloc=$(( 256 * 1024 * 1024 ))
if [[ $alloc -lt $min_alloc ]]; then
  warn "Root filesystem too small/full to safely create disk pressure; skipping fault F."
  warn "(avail=${avail_bytes}B, computed alloc=${alloc}B). Lab will run with 5 faults."
else
  rm -f "$BIGFILE"
  if fallocate -l "$alloc" "$BIGFILE" 2>/dev/null; then
    :
  else
    dd if=/dev/zero of="$BIGFILE" bs=1M count=$(( alloc / 1024 / 1024 )) status=none
  fi
  info "Created $BIGFILE (~$(( alloc / 1024 / 1024 )) MiB); root fs now at $(root_fs_use_pct)%."
fi

log "Faults applied. Run scripts/validate-lab.sh to confirm the lab is ready."
