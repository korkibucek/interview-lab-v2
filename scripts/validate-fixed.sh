#!/usr/bin/env bash
# scripts/validate-fixed.sh
# Post-candidate check: score whether each objective was actually fixed.
# Behavioural where possible (tests behaviour, not config text).
# Prints Score: N/6 and exits non-zero unless all objectives pass.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root

printf '%s== Interview Lab :: post-candidate validation ==%s\n\n' "$C_BOLD" "$C_RESET"

PASS=0; TOTAL=6
objective() { printf '\n%s* %s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
good() { printf '  %s[OK]%s   %s\n' "$C_GRN" "$C_RESET" "$*"; }
bad()  { printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; }

# --- A: web reachable on :80 (and not firewalled) ----------------------------
objective "A. Web service reachable on :${RIGHT_WEB_PORT}"
a_ok=1
if curl -fsS --max-time 4 "http://127.0.0.1:${RIGHT_WEB_PORT}/" >/dev/null 2>&1; then
  good "HTTP 200 on http://127.0.0.1:${RIGHT_WEB_PORT}/"
else
  bad "no HTTP response on :${RIGHT_WEB_PORT}"; a_ok=0
fi
if firewalld_active; then
  if firewalld_has_service http; then
    good "firewall allows HTTP (:${RIGHT_WEB_PORT})"
  else
    bad "firewalld is active but HTTP (:${RIGHT_WEB_PORT}) is still blocked"; a_ok=0
  fi
else
  good "firewalld inactive (port reachable externally)"
fi
[[ $a_ok -eq 1 ]] && PASS=$((PASS+1))

# --- B: app.service running --------------------------------------------------
objective "B. app.service running cleanly"
if unit_is_active app.service; then
  good "app.service is active"; PASS=$((PASS+1))
else
  bad "app.service is not active ($(systemctl is-active app.service 2>/dev/null))"
fi

# --- C: DNS resolution -------------------------------------------------------
objective "C. DNS resolution working"
if timeout 6 getent hosts "$DNS_PROBE_HOST" >/dev/null 2>&1; then
  good "resolved $DNS_PROBE_HOST"; PASS=$((PASS+1))
else
  bad "could not resolve $DNS_PROBE_HOST"
fi

# --- D: log rotation works (forced rotation produces an artifact) ------------
objective "D. Log rotation functioning"
d_ok=0
if [[ -s "$APP_LOG" ]] && logrotate -f "$LOGROTATE_CONF" >/dev/null 2>&1; then
  if compgen -G "${APP_LOG}.1*" >/dev/null; then
    good "forced rotation produced $(compgen -G "${APP_LOG}.1*" | head -1)"
    d_ok=1
  fi
fi
if [[ $d_ok -eq 1 ]]; then
  PASS=$((PASS+1))
else
  bad "logrotate did not rotate $APP_LOG (check path/copytruncate)"
fi

# --- E: CPU hog stopped and prevented ----------------------------------------
objective "E. CPU hog stopped and prevented"
e_ok=1
if pgrep -x yes >/dev/null 2>&1; then bad "a 'yes' process is still running"; e_ok=0; else good "no runaway 'yes' process"; fi
if [[ -f "$CPUHOG_CRON" ]]; then bad "cron job $CPUHOG_CRON still present (will recur)"; e_ok=0; else good "cron job removed"; fi
[[ $e_ok -eq 1 ]] && PASS=$((PASS+1))

# --- F: disk pressure relieved -----------------------------------------------
objective "F. Disk pressure relieved"
use_pct="$(root_fs_use_pct)"
f_ok=1
if [[ -f "$BIGFILE" ]]; then bad "$BIGFILE still present"; f_ok=0; else good "$BIGFILE removed"; fi
if [[ "$use_pct" -lt 75 ]]; then good "root fs at ${use_pct}% (healthy)"; else bad "root fs still at ${use_pct}%"; f_ok=0; fi
[[ $f_ok -eq 1 ]] && PASS=$((PASS+1))

# --- Score -------------------------------------------------------------------
printf '\n%s---------------------------------------------%s\n' "$C_BOLD" "$C_RESET"
printf '%sScore: %d/%d objectives fixed%s\n' "$C_BOLD" "$PASS" "$TOTAL" "$C_RESET"
[[ $PASS -eq $TOTAL ]]
