#!/usr/bin/env bash
# deploy/reset-lab.sh
# Return the lab to a pristine broken state for the next candidate, without a
# full reinstall. Restores the healthy baseline (undoing candidate fixes) and
# re-applies the faults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lab/lib/common.sh
source "$REPO_ROOT/lab/lib/common.sh"

require_root
require_ubuntu_2404

log "Resetting lab to pristine broken state..."
bash "$REPO_ROOT/scripts/setup-lab.sh"
bash "$REPO_ROOT/scripts/break-lab.sh"
log "Reset complete. Run scripts/validate-lab.sh to confirm readiness."
