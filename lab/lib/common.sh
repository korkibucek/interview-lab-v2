# shellcheck shell=bash
# shellcheck disable=SC2034  # constants below are consumed by scripts that source this file
# lab/lib/common.sh
# Shared constants and helpers for the Interview Lab tooling.
# Sourced by deploy/*.sh and scripts/*.sh. Not meant to be executed directly.
#
# Everything that the deploy, breakage, reset and validation scripts need to
# agree on lives here, so the "broken state" and the "checks for the broken
# state" can never drift apart.

# --- Identity / paths --------------------------------------------------------
LAB_NAME="interview-lab"
CANDIDATE_USER="candidate"
APP_USER="appuser"

# Web layer (objective A)
WEB_ROOT="/var/www/lab"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/lab"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/lab"
WRONG_WEB_PORT="8080"   # where break-lab leaves nginx listening
RIGHT_WEB_PORT="80"     # where the candidate must make it listen

# App service layer (objective B)
APP_DIR="/opt/app"
APP_BIN="/usr/local/bin/app.sh"
APP_UNIT="/etc/systemd/system/app.service"
APP_RUN_LOG="${APP_DIR}/run.log"

# Chatty logger (healthy source for the logrotate objective D)
LOGGER_BIN="/usr/local/bin/app-logger.sh"
LOGGER_UNIT="/etc/systemd/system/app-logger.service"
APP_LOG_DIR="/var/log/app"
APP_LOG="${APP_LOG_DIR}/app.log"

# Log rotation layer (objective D)
LOGROTATE_CONF="/etc/logrotate.d/app"
LOGROTATE_WRONG_DIR="/var/log/appp"   # the typo break-lab introduces

# CPU hog layer (objective E)
CPUHOG_BIN="/usr/local/bin/cpuhog.sh"
CPUHOG_CRON="/etc/cron.d/cpuhog"

# DNS layer (objective C)
RESOLV_CONF="/etc/resolv.conf"
BOGUS_DNS="192.0.2.53"               # RFC5737 TEST-NET-1: routable nowhere
DNS_PROBE_HOST="deb.debian.org"      # a name a healthy resolver will answer

# Disk pressure layer (objective F)
BIGFILE="/var/log/verbose-debug.log"
DISK_SAFETY_FREE_BYTES=$(( 1500 * 1024 * 1024 ))  # never consume below ~1.5 GiB free
DISK_MAX_PCT=92                                    # never push root fs above this
DISK_PRESSURE_PCT=85                               # "broken" means at/above this

# State / bookkeeping
STATE_DIR="/var/lib/${LAB_NAME}"
CANDIDATE_CRED_FILE="${STATE_DIR}/candidate-credentials.txt"

# --- Output helpers ----------------------------------------------------------
# Colour only when stdout is a TTY and NO_COLOR is unset.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BOLD=""
fi

log()  { printf '%s[+]%s %s\n' "$C_BLU" "$C_RESET" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- Guards ------------------------------------------------------------------
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "This script must be run as root (use: sudo $0)."
  fi
}

# Confirm we are on Ubuntu 24.04. Honour LAB_SKIP_OS_CHECK=1 for CI/dev only.
require_ubuntu_2404() {
  if [[ "${LAB_SKIP_OS_CHECK:-0}" == "1" ]]; then
    warn "LAB_SKIP_OS_CHECK=1 set; skipping OS version check."
    return 0
  fi
  local id ver
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"; ver="${VERSION_ID:-}"
  fi
  if [[ "$id" != "ubuntu" || "$ver" != "24.04" ]]; then
    err "Unsupported OS: ${id:-unknown} ${ver:-unknown}."
    err "This lab targets Ubuntu 24.04 LTS. Set LAB_SKIP_OS_CHECK=1 only for dev/CI."
    exit 1
  fi
}

# --- Validation harness (used by validate-lab.sh / validate-fixed.sh) --------
V_PASS=0; V_FAIL=0; V_WARN=0
v_pass() { printf '%s[PASS]%s %s\n' "$C_GRN" "$C_RESET" "$*"; V_PASS=$((V_PASS+1)); }
v_fail() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; V_FAIL=$((V_FAIL+1)); }
v_warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RESET" "$*"; V_WARN=$((V_WARN+1)); }

# Print a summary line and return non-zero if any check FAILed.
v_summary() {
  printf '\n%s---------------------------------------------%s\n' "$C_BOLD" "$C_RESET"
  printf '%sSummary:%s %s%d passed%s, %s%d failed%s, %s%d warnings%s\n' \
    "$C_BOLD" "$C_RESET" \
    "$C_GRN" "$V_PASS" "$C_RESET" \
    "$C_RED" "$V_FAIL" "$C_RESET" \
    "$C_YEL" "$V_WARN" "$C_RESET"
  [[ $V_FAIL -eq 0 ]]
}

# --- Misc helpers ------------------------------------------------------------
# SIGPIPE-safe random string generators. We read a fixed block from /dev/urandom
# (so the producer is never killed by an early `head` close, which would trip
# `set -o pipefail`) and slice with bash parameter expansion.
rand_alnum() {
  local n="${1:-16}" s
  s="$(head -c 1024 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  printf '%s' "${s:0:n}"
}
rand_hex() {
  local n="${1:-16}" s
  s="$(head -c 1024 /dev/urandom | LC_ALL=C tr -dc 'A-F0-9')"
  printf '%s' "${s:0:n}"
}

# Root filesystem usage as an integer percentage (0-100).
root_fs_use_pct() { df -P / | awk 'NR==2 { gsub("%","",$5); print $5 }'; }

# Bytes available on the root filesystem.
root_fs_avail_bytes() { df -P --block-size=1 / | awk 'NR==2 { print $4 }'; }

# True if a unit is in the "active" state.
unit_is_active() { systemctl is-active --quiet "$1"; }
