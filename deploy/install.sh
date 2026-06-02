#!/usr/bin/env bash
# deploy/install.sh
# One-shot, idempotent installer for the Interview Lab on a fresh
# DigitalOcean Ubuntu 24.04 droplet.
#
#   sudo ./deploy/install.sh
#
# Optional: provide an SSH public key for the candidate (recommended, avoids
# password auth entirely):
#
#   sudo LAB_CANDIDATE_PUBKEY="ssh-ed25519 AAAA... candidate" ./deploy/install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root
require_ubuntu_2404

log "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  nginx cron ufw curl logrotate ca-certificates

systemctl enable --now cron >/dev/null 2>&1 || true

# --- Candidate user & access model -------------------------------------------
log "Creating candidate user '$CANDIDATE_USER'..."
mkdir -p "$STATE_DIR"; chmod 0700 "$STATE_DIR"

if ! id "$CANDIDATE_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$CANDIDATE_USER"
fi
usermod -aG sudo "$CANDIDATE_USER"

# Passwordless sudo so the candidate can work in either key or password mode.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$CANDIDATE_USER" > /etc/sudoers.d/90-candidate
chmod 0440 /etc/sudoers.d/90-candidate
visudo -c >/dev/null || die "sudoers validation failed; aborting."

ACCESS_SUMMARY=""
if [[ -n "${LAB_CANDIDATE_PUBKEY:-}" ]]; then
  log "Installing candidate SSH public key..."
  install -d -m 0700 -o "$CANDIDATE_USER" -g "$CANDIDATE_USER" "/home/$CANDIDATE_USER/.ssh"
  printf '%s\n' "$LAB_CANDIDATE_PUBKEY" > "/home/$CANDIDATE_USER/.ssh/authorized_keys"
  chmod 0600 "/home/$CANDIDATE_USER/.ssh/authorized_keys"
  chown "$CANDIDATE_USER:$CANDIDATE_USER" "/home/$CANDIDATE_USER/.ssh/authorized_keys"
  # Remove any previous lab password-auth drop-in.
  rm -f /etc/ssh/sshd_config.d/60-lab-candidate.conf
  systemctl reload ssh 2>/dev/null || true
  ACCESS_SUMMARY="ssh ${CANDIDATE_USER}@<droplet-ip>   (using the provided key)"
else
  log "No candidate key provided; generating a one-time password and enabling password auth..."
  CAND_PW="$(rand_alnum 16)"
  printf '%s:%s\n' "$CANDIDATE_USER" "$CAND_PW" | chpasswd
  # Enable password auth for SSH (lab convenience; documented in docs/SECURITY.md).
  cat > /etc/ssh/sshd_config.d/60-lab-candidate.conf <<SSHD
# Lab: allow the candidate to log in with a password. Remove after the lab.
PasswordAuthentication yes
SSHD
  systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  {
    printf 'Interview Lab candidate credentials\n'
    printf 'user: %s\n' "$CANDIDATE_USER"
    printf 'password: %s\n' "$CAND_PW"
  } > "$CANDIDATE_CRED_FILE"
  chmod 0600 "$CANDIDATE_CRED_FILE"
  ACCESS_SUMMARY="ssh ${CANDIDATE_USER}@<droplet-ip>   (password: ${CAND_PW})"
fi

# --- Build healthy baseline, then apply faults -------------------------------
log "Building healthy baseline..."
bash "$REPO_ROOT/scripts/setup-lab.sh"

log "Applying intentional faults..."
bash "$REPO_ROOT/scripts/break-lab.sh"

# --- MOTD pointer ------------------------------------------------------------
cat > /etc/motd <<'MOTD'

  Welcome to the troubleshooting lab.
  Several services on this host are not behaving correctly.
  Your brief has been provided separately by the assessor.
  Investigate, fix, and document your changes. Do not reboot or reinstall.

MOTD

LAB_TOKEN="$(cat "$STATE_DIR/token" 2>/dev/null || echo unknown)"

# --- Next steps --------------------------------------------------------------
printf '\n%s================ LAB INSTALLED ================%s\n' "$C_BOLD" "$C_RESET"
cat <<SUMMARY

  Candidate access:
    ${ACCESS_SUMMARY}
    (sudo is enabled for '${CANDIDATE_USER}')

  Web service token (for your reference): ${LAB_TOKEN}

  Next steps for the assessor:
    1. Verify the lab is correctly broken:
         sudo ./scripts/validate-lab.sh
    2. Hand the droplet to the candidate.
    3. After they finish, score the result:
         sudo ./scripts/validate-fixed.sh
    4. To re-run the lab for another candidate:
         sudo ./deploy/reset-lab.sh
    5. To remove all lab artifacts:
         sudo ./deploy/uninstall.sh

SUMMARY
[[ -f "$CANDIDATE_CRED_FILE" ]] && info "Credentials also saved to ${CANDIDATE_CRED_FILE} (root-only)."
printf '%s==============================================%s\n' "$C_BOLD" "$C_RESET"
