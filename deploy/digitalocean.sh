#!/usr/bin/env bash
# deploy/digitalocean.sh
# Zero-touch DigitalOcean provisioner for the AlmaLinux 10 interview lab.
#
# It creates a droplet that provisions itself via cloud-init (installs git,
# clones this repo, runs deploy/install.sh), generates an admin SSH key (for you)
# and a candidate SSH key (to hand to the candidate), waits until the lab is
# broken-and-ready, then prints exactly how to connect.
#
#   export DO_TOKEN="dop_v1_..."         # your DigitalOcean API token
#   ./deploy/digitalocean.sh create      # provision a lab droplet
#   ./deploy/digitalocean.sh status      # check progress / readiness
#   ./deploy/digitalocean.sh destroy     # tear down the last droplet + admin key
#
# The token is read ONLY from the DO_TOKEN environment variable. It is never
# written to disk, never stored in state, and never embedded in the droplet.
#
# Requirements on the machine you run this from: bash, curl, jq, ssh, ssh-keygen.
set -euo pipefail

# ---- Config (override via environment) --------------------------------------
LAB_REGION="${LAB_REGION:-lon1}"
LAB_SIZE="${LAB_SIZE:-s-1vcpu-1gb}"          # 1GB/25GB; cheapest clean disk fault
LAB_IMAGE="${LAB_IMAGE:-almalinux-10-x64}"
LAB_REPO="${LAB_REPO:-https://github.com/korkibucek/interview-lab-v2.git}"
LAB_BRANCH="${LAB_BRANCH:-main}"
LAB_TAG="interview-lab"

STATE_DIR="${LAB_STATE_DIR:-.do-lab}"
API="https://api.digitalocean.com/v2"

# ---- Output helpers ---------------------------------------------------------
if [[ -t 1 ]]; then C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""; fi
log()  { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

# ---- Preflight --------------------------------------------------------------
preflight() {
  [[ -n "${DO_TOKEN:-}" ]] || die "DO_TOKEN is not set. Run: export DO_TOKEN=dop_v1_..."
  for t in curl jq ssh ssh-keygen; do
    command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
  done
}

# ---- DigitalOcean API helper ------------------------------------------------
# api METHOD PATH [JSON-body]
api() {
  local method=$1 path=$2 body=${3:-}
  if [[ -n $body ]]; then
    curl -fsS -X "$method" "$API$path" \
      -H "Authorization: Bearer $DO_TOKEN" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -fsS -X "$method" "$API$path" -H "Authorization: Bearer $DO_TOKEN"
  fi
}

ssh_lab() {  # ssh_lab <ip> <command...>
  local ip=$1; shift
  ssh -i "$STATE_DIR/admin_key" -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
      -o LogLevel=ERROR "root@$ip" "$@"
}

# ---- create -----------------------------------------------------------------
cmd_create() {
  preflight
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  [[ -f "$STATE_DIR/droplet_id" ]] && die "A lab already exists in $STATE_DIR (droplet $(cat "$STATE_DIR/droplet_id")). Destroy it first."

  local suffix; suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  local name="interview-lab-${suffix}"

  log "Generating admin + candidate SSH keys..."
  ssh-keygen -t ed25519 -N '' -C "lab-admin-${suffix}"     -f "$STATE_DIR/admin_key"     >/dev/null
  ssh-keygen -t ed25519 -N '' -C "candidate-${suffix}"     -f "$STATE_DIR/candidate_key" >/dev/null
  chmod 600 "$STATE_DIR/admin_key" "$STATE_DIR/candidate_key"
  local admin_pub cand_pub
  admin_pub="$(cat "$STATE_DIR/admin_key.pub")"
  cand_pub="$(cat "$STATE_DIR/candidate_key.pub")"

  log "Registering admin key with DigitalOcean..."
  local admin_key_id
  admin_key_id="$(api POST /account/keys \
    "$(jq -n --arg n "lab-admin-${suffix}" --arg k "$admin_pub" '{name:$n,public_key:$k}')" \
    | jq -r '.ssh_key.id')"
  [[ -n "$admin_key_id" && "$admin_key_id" != null ]] || die "failed to register admin key"
  echo "$admin_key_id" > "$STATE_DIR/admin_key_id"

  # cloud-init: install git, clone the repo, run the lab installer with the
  # candidate public key injected. The DO_TOKEN is NOT present here.
  local user_data
  user_data="$(cat <<CLOUDINIT
#!/bin/bash
set -eux
exec > /var/log/lab-cloud-init.log 2>&1
dnf -y install git
rm -rf /opt/interview-lab-v2
git clone --branch "${LAB_BRANCH}" "${LAB_REPO}" /opt/interview-lab-v2
cd /opt/interview-lab-v2
LAB_CANDIDATE_PUBKEY="${cand_pub}" ./deploy/install.sh
touch /var/lib/interview-lab/.cloud-init-done
CLOUDINIT
)"

  log "Creating droplet ${name} (${LAB_SIZE}, ${LAB_IMAGE}, ${LAB_REGION})..."
  local droplet_id
  droplet_id="$(api POST /droplets "$(jq -n \
      --arg name "$name" --arg region "$LAB_REGION" --arg size "$LAB_SIZE" \
      --arg image "$LAB_IMAGE" --arg ud "$user_data" \
      --argjson keys "[$admin_key_id]" --arg tag "$LAB_TAG" \
      '{name:$name,region:$region,size:$size,image:$image,ssh_keys:$keys,user_data:$ud,tags:[$tag]}')" \
    | jq -r '.droplet.id')"
  [[ -n "$droplet_id" && "$droplet_id" != null ]] || die "failed to create droplet"
  echo "$droplet_id" > "$STATE_DIR/droplet_id"
  echo "$name" > "$STATE_DIR/droplet_name"
  log "Droplet id ${droplet_id} created. Waiting for it to become active..."

  # Wait for active + public IPv4
  local ip=""
  for _ in $(seq 1 60); do
    local j; j="$(api GET "/droplets/${droplet_id}")"
    if [[ "$(jq -r '.droplet.status' <<<"$j")" == "active" ]]; then
      ip="$(jq -r '.droplet.networks.v4[] | select(.type=="public") | .ip_address' <<<"$j" | head -1)"
      [[ -n "$ip" ]] && break
    fi
    sleep 5
  done
  [[ -n "$ip" ]] || die "droplet did not become active in time"
  echo "$ip" > "$STATE_DIR/droplet_ip"
  log "Droplet active at ${ip}. Waiting for cloud-init to provision the lab (a few minutes)..."

  # Wait for SSH, then for the lab readiness sentinel.
  for _ in $(seq 1 60); do
    ssh_lab "$ip" true 2>/dev/null && break
    sleep 5
  done
  local ready=0
  for _ in $(seq 1 90); do
    if ssh_lab "$ip" "test -f /var/lib/interview-lab/.cloud-init-done" 2>/dev/null; then ready=1; break; fi
    sleep 10
  done

  printf '\n%s================= LAB READY =================%s\n' "$C_B" "$C_0"
  if [[ $ready -eq 1 ]]; then
    log "Lab provisioned and broken. Verifying..."
    ssh_lab "$ip" "cd /opt/interview-lab-v2 && sudo ./scripts/validate-lab.sh" || \
      warn "validate-lab reported issues; inspect /var/log/lab-cloud-init.log on the droplet."
  else
    warn "Timed out waiting for cloud-init. Check status with: $0 status"
  fi

  cat <<INFO

  Droplet : ${name} (id ${droplet_id}) @ ${ip}

  ADMIN access (you):
    ssh -i ${STATE_DIR}/admin_key root@${ip}

  CANDIDATE access (give these to the candidate):
    username     : candidate
    private key  : ${STATE_DIR}/candidate_key
    command      : ssh -i <their-copy-of-candidate_key> candidate@${ip}

  Assessor commands (run over the admin SSH session):
    sudo /opt/interview-lab-v2/scripts/validate-lab.sh     # confirm broken
    sudo /opt/interview-lab-v2/scripts/validate-fixed.sh   # score N/6
    sudo /opt/interview-lab-v2/deploy/reset-lab.sh         # re-break

  When finished, tear everything down:
    $0 destroy

INFO
  printf '%s============================================%s\n' "$C_B" "$C_0"
}

# ---- status -----------------------------------------------------------------
cmd_status() {
  preflight
  [[ -f "$STATE_DIR/droplet_id" ]] || die "no lab state in $STATE_DIR"
  local id ip; id="$(cat "$STATE_DIR/droplet_id")"; ip="$(cat "$STATE_DIR/droplet_ip" 2>/dev/null || echo '')"
  local status; status="$(api GET "/droplets/${id}" | jq -r '.droplet.status')"
  log "Droplet ${id} status: ${status} (ip ${ip:-unknown})"
  if [[ -n "$ip" ]]; then
    if ssh_lab "$ip" "test -f /var/lib/interview-lab/.cloud-init-done" 2>/dev/null; then
      log "Lab provisioning: complete"
    else
      warn "Lab provisioning: not finished (see /var/log/lab-cloud-init.log on the droplet)"
    fi
  fi
}

# ---- destroy ----------------------------------------------------------------
cmd_destroy() {
  preflight
  [[ -f "$STATE_DIR/droplet_id" ]] || die "no lab state in $STATE_DIR to destroy"
  local id key_id; id="$(cat "$STATE_DIR/droplet_id")"
  log "Destroying droplet ${id}..."
  api DELETE "/droplets/${id}" >/dev/null || warn "droplet delete failed (already gone?)"
  if [[ -f "$STATE_DIR/admin_key_id" ]]; then
    key_id="$(cat "$STATE_DIR/admin_key_id")"
    log "Removing admin SSH key ${key_id} from the account..."
    api DELETE "/account/keys/${key_id}" >/dev/null || warn "key delete failed (already gone?)"
  fi
  rm -rf "$STATE_DIR"
  log "Teardown complete. (Remember to revoke the API token if it was temporary.)"
}

# ---- dispatch ---------------------------------------------------------------
case "${1:-create}" in
  create)  cmd_create ;;
  status)  cmd_status ;;
  destroy) cmd_destroy ;;
  *) die "usage: $0 {create|status|destroy}" ;;
esac
