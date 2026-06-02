#!/usr/bin/env bash
# scripts/smoke-test.sh
# Static checks runnable anywhere (no root, no mutation). Used locally and in CI.
#   - bash -n syntax check on every script
#   - shellcheck (if available)
#   - guard: candidate instructions must not leak answer-key internals
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

fail=0
note() { printf '%s\n' "$*"; }

mapfile -t SCRIPTS < <(find deploy scripts lab -type f -name '*.sh' | sort)

note "== bash -n syntax checks =="
for f in "${SCRIPTS[@]}"; do
  if bash -n "$f"; then note "  ok   $f"; else note "  FAIL $f"; fail=1; fi
done

note ""
note "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  # lab/lib/common.sh is sourced, not executed; -x lets shellcheck follow sources.
  if shellcheck -x "${SCRIPTS[@]}"; then
    note "  shellcheck clean"
  else
    note "  shellcheck reported issues"; fail=1
  fi
else
  note "  shellcheck not installed; skipping (install: dnf install ShellCheck)"
fi

note ""
note "== answer-key leak guard =="
CAND="docs/CANDIDATE_INSTRUCTIONS.md"
if [[ -f "$CAND" ]]; then
  leaks=0
  for token in "appp" "192.0.2.53" "copytruncate" "chmod 0644" "chmod +x" "cpuhog"; do
    if grep -qiF "$token" "$CAND"; then note "  LEAK: '$token' found in $CAND"; leaks=1; fi
  done
  if [[ $leaks -eq 0 ]]; then note "  candidate instructions reveal no fault internals"; else fail=1; fi
else
  note "  (skipped: $CAND not present yet)"
fi

note ""
if [[ $fail -eq 0 ]]; then note "SMOKE TEST: PASS"; else note "SMOKE TEST: FAIL"; fi
exit $fail
