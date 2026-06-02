#!/usr/bin/env bash
# scripts/validate-lab.sh
# Pre-candidate check: confirm the lab is correctly broken AND safe to hand over.
# Read-only. Exits non-zero if the lab is not ready (any FAIL).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root

printf '%s== Interview Lab :: pre-candidate validation ==%s\n\n' "$C_BOLD" "$C_RESET"

# --- Prerequisites -----------------------------------------------------------
if id "$CANDIDATE_USER" >/dev/null 2>&1; then
  v_pass "candidate user '$CANDIDATE_USER' exists"
else
  v_fail "candidate user '$CANDIDATE_USER' is missing"
fi

if id "$APP_USER" >/dev/null 2>&1; then
  v_pass "service user '$APP_USER' exists"
else
  v_fail "service user '$APP_USER' is missing"
fi

if command -v nginx >/dev/null 2>&1; then
  v_pass "nginx is installed"
else
  v_fail "nginx is not installed"
fi

# --- Fault A: web off :80 + firewall closed ----------------------------------
if curl -fsS --max-time 4 "http://127.0.0.1:${RIGHT_WEB_PORT}/" >/dev/null 2>&1; then
  v_fail "web service answers on :${RIGHT_WEB_PORT} (fault A already fixed)"
else
  v_pass "web service is intentionally NOT serving on :${RIGHT_WEB_PORT}"
fi
if curl -fsS --max-time 4 "http://127.0.0.1:${WRONG_WEB_PORT}/" >/dev/null 2>&1; then
  v_pass "nginx is (mis)configured on :${WRONG_WEB_PORT} as designed"
else
  v_warn "nginx is not answering on :${WRONG_WEB_PORT} either (check nginx state)"
fi
if ufw status 2>/dev/null | grep -q "Status: active"; then
  if ufw status 2>/dev/null | grep -qE "(^|[^0-9])${RIGHT_WEB_PORT}/tcp[[:space:]]+ALLOW"; then
    v_fail "firewall already allows :${RIGHT_WEB_PORT} (fault A partly fixed)"
  else
    v_pass "firewall is active and :${RIGHT_WEB_PORT} is closed"
  fi
else
  v_fail "ufw is not active (firewall layer of fault A is missing)"
fi

# --- Fault B: app.service broken ---------------------------------------------
if unit_is_active app.service; then
  v_fail "app.service is active (fault B already fixed)"
else
  v_pass "app.service is intentionally not running"
fi
if [[ -x "$APP_BIN" ]]; then
  v_warn "$APP_BIN is executable (one layer of fault B already addressed)"
else
  v_pass "$APP_BIN is intentionally non-executable"
fi

# --- Fault C: DNS broken -----------------------------------------------------
if timeout 6 getent hosts "$DNS_PROBE_HOST" >/dev/null 2>&1; then
  v_fail "DNS resolves '$DNS_PROBE_HOST' (fault C already fixed)"
else
  v_pass "DNS resolution is intentionally broken"
fi

# --- Fault D: log rotation broken --------------------------------------------
if grep -q "$LOGROTATE_WRONG_DIR" "$LOGROTATE_CONF" 2>/dev/null \
   || ! grep -q "copytruncate" "$LOGROTATE_CONF" 2>/dev/null; then
  v_pass "log rotation for the app log is intentionally broken"
else
  v_fail "logrotate config looks correct (fault D already fixed)"
fi

# --- Fault E: CPU hog --------------------------------------------------------
if [[ -f "$CPUHOG_CRON" ]]; then
  v_pass "CPU-hog cron job is present ($CPUHOG_CRON)"
else
  v_fail "CPU-hog cron job is missing (fault E already removed)"
fi
if pgrep -x yes >/dev/null 2>&1; then
  v_pass "a runaway 'yes' process is consuming CPU"
else
  v_warn "no 'yes' process right now (cron will respawn it within a minute)"
fi

# --- Fault F: disk pressure --------------------------------------------------
use_pct="$(root_fs_use_pct)"
if [[ -f "$BIGFILE" ]]; then
  if [[ "$use_pct" -ge "$DISK_PRESSURE_PCT" ]]; then
    v_pass "disk pressure present: root fs at ${use_pct}% (large file ${BIGFILE})"
  else
    v_warn "large file present but root fs only at ${use_pct}% (small disk?)"
  fi
else
  v_fail "disk pressure file ${BIGFILE} is missing (fault F already fixed/skipped)"
fi

# --- Safety / recoverability -------------------------------------------------
printf '\n%s-- safety checks --%s\n' "$C_BOLD" "$C_RESET"
if ufw status 2>/dev/null | grep -q "Status: active"; then
  if ufw status 2>/dev/null | grep -qE "(22/tcp|OpenSSH)[[:space:]]+ALLOW"; then
    v_pass "SSH (22) is allowed through the firewall (no lockout)"
  else
    v_fail "ufw is active but SSH (22) is NOT allowed -- lockout risk!"
  fi
fi
if [[ "$use_pct" -ge 100 ]]; then
  v_fail "root filesystem is at 100% -- disk safety margin failed!"
else
  v_pass "root filesystem has headroom (${use_pct}% used)"
fi
if systemctl is-active --quiet ssh; then
  v_pass "ssh service is running (admin can reconnect)"
else
  v_warn "ssh service not detected as active (verify access path)"
fi

v_summary
