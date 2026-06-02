#!/usr/bin/env bash
# scripts/examiner.sh
# Examiner command playbook / runner for the zero-touch DigitalOcean flow.
# It mirrors the exact sequence used to deploy, verify, grade, reset and tear
# down a lab, reusing deploy/digitalocean.sh and the generated admin key in
# ./.do-lab so you don't have to hand-assemble the SSH commands.
#
#   export DO_TOKEN=dop_v1_...         # needed for provision / destroy only
#   scripts/examiner.sh                # print the whole playbook (no changes)
#   scripts/examiner.sh provision      # 1. create the self-installing droplet
#   scripts/examiner.sh info           # 2. show admin + candidate connection info
#   scripts/examiner.sh verify         # 3. validate-lab on the droplet (pre-candidate)
#   scripts/examiner.sh shell          #    open an admin root shell on the droplet
#   scripts/examiner.sh score          # 4. validate-fixed on the droplet (post-candidate)
#   scripts/examiner.sh answer-key     #    show expected fixes (root-only on the box)
#   scripts/examiner.sh reset          # 5. re-break for the next candidate
#   scripts/examiner.sh destroy        # 6. tear down droplet + admin key
#
# The candidate's fixes are deliberately NOT automated — that is the exercise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DO_SCRIPT="$REPO_ROOT/deploy/digitalocean.sh"
STATE_DIR="${LAB_STATE_DIR:-.do-lab}"
REMOTE_REPO="/opt/interview-lab-v2"        # where cloud-init clones the repo

if [[ -t 1 ]]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
else C_G=""; C_Y=""; C_0=""; fi
log()  { printf '%s[examiner]%s %s\n' "$C_G" "$C_0" "$*"; }
die()  { printf '%s[examiner]%s %s\n' "$C_Y" "$C_0" "$*" >&2; exit 1; }

need_state() {
  [[ -f "$STATE_DIR/droplet_ip" && -f "$STATE_DIR/admin_key" ]] \
    || die "no provisioned droplet found in $STATE_DIR (run: $0 provision)"
}
droplet_ip() { cat "$STATE_DIR/droplet_ip"; }

# Run a command on the droplet as root over the admin key.
dssh() {
  need_state
  ssh -i "$STATE_DIR/admin_key" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      "root@$(droplet_ip)" "$@"
}

phase_provision() { exec bash "$DO_SCRIPT" create; }
phase_destroy()   { exec bash "$DO_SCRIPT" destroy; }

phase_info() {
  need_state
  local ip; ip="$(droplet_ip)"
  cat <<INFO
  Admin (you):
    ssh -i ${STATE_DIR}/admin_key root@${ip}

  Candidate (hand over the key + username, and docs/CANDIDATE_INSTRUCTIONS.md):
    username    : candidate
    private key : ${STATE_DIR}/candidate_key
    command     : ssh -i <candidate_key> candidate@${ip}
INFO
}

phase_verify()    { log "Running validate-lab on the droplet (pre-candidate)...";  dssh "sudo $REMOTE_REPO/scripts/validate-lab.sh"; }
phase_score()     { log "Running validate-fixed on the droplet (post-candidate)..."; dssh "sudo $REMOTE_REPO/scripts/validate-fixed.sh"; }
phase_reset()     { log "Re-breaking the lab for the next candidate...";           dssh "sudo $REMOTE_REPO/deploy/reset-lab.sh"; }
phase_answerkey() { log "Expected fixes (assessor reference):";                    dssh "sudo cat $REMOTE_REPO/docs/ANSWER_KEY.md"; }

phase_shell() {
  need_state
  ssh -t -i "$STATE_DIR/admin_key" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "root@$(droplet_ip)"
}

phase_playbook() {
  cat <<'PLAYBOOK'
Examiner playbook (zero-touch DigitalOcean flow)
================================================
Run each phase with:  scripts/examiner.sh <phase>
(or copy the underlying commands below)

0. One-time, on your workstation:
     export DO_TOKEN=dop_v1_...              # a scoped, temporary token
     #   needs: bash curl jq ssh ssh-keygen

1. provision   -> deploy/digitalocean.sh create
     Creates the cheapest AlmaLinux 10 droplet in lon1, which self-installs the
     lab via cloud-init and generates admin + candidate SSH keys in ./.do-lab/.

2. info        -> prints admin + candidate connection details from ./.do-lab/

3. verify      -> ssh root@<droplet> 'sudo /opt/interview-lab-v2/scripts/validate-lab.sh'
     Confirm the lab is correctly broken AND safe. Expect all PASS, exit 0.

   Hand over to the candidate:
     - their candidate key + username 'candidate'
     - docs/CANDIDATE_INSTRUCTIONS.md  (the ONLY doc they should see)

4. score       -> ssh root@<droplet> 'sudo /opt/interview-lab-v2/scripts/validate-fixed.sh'
     After the candidate finishes. Prints Score: N/6.
     answer-key -> sudo cat /opt/interview-lab-v2/docs/ANSWER_KEY.md  (expected fixes)

5. reset       -> ssh root@<droplet> 'sudo /opt/interview-lab-v2/deploy/reset-lab.sh'
     Re-break for the next candidate, then re-run 'verify'.

6. destroy     -> deploy/digitalocean.sh destroy
     Tears down the droplet and removes the admin key it registered.
     (Delete your API token afterwards if it was temporary.)

Notes
-----
* The candidate's fixes are the exercise; this script never applies them.
* The on-box repo is root-readable only, so run validators with sudo.
* See docs/ASSESSOR_GUIDE.md for scoring guidance and red flags.
PLAYBOOK
}

case "${1:-playbook}" in
  provision)   phase_provision ;;
  info)        phase_info ;;
  verify)      phase_verify ;;
  shell)       phase_shell ;;
  score)       phase_score ;;
  answer-key)  phase_answerkey ;;
  reset)       phase_reset ;;
  destroy)     phase_destroy ;;
  playbook|help|-h|--help) phase_playbook ;;
  *) die "unknown phase '${1}'. Run '$0' with no argument to see the playbook." ;;
esac
