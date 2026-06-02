# Changelog

## [Unreleased]

### Added
- Ubuntu 24.04 rewrite of the interview lab with six layered faults
  (web/firewall, systemd/permissions, DNS, log rotation, cron CPU hog, disk).
- Idempotent `deploy/install.sh` (packages, candidate user/access, setup, break).
- `deploy/reset-lab.sh`, `deploy/uninstall.sh`, `deploy/healthcheck.sh`.
- `scripts/setup-lab.sh`, `scripts/break-lab.sh`.
- `scripts/validate-lab.sh` (pre-candidate, with safety checks) and
  `scripts/validate-fixed.sh` (behavioural `N/6` scoring).
- Shared library `lab/lib/common.sh` with SIGPIPE-safe random helpers and a
  validation harness.
- Full docs set: README, ARCHITECTURE, DEPLOYMENT, CANDIDATE_INSTRUCTIONS,
  ASSESSOR_GUIDE, ANSWER_KEY, SECURITY, TROUBLESHOOTING, ROADMAP.
- `scripts/smoke-test.sh` and GitHub Actions CI (shellcheck + syntax + answer
  leak guard).
- Safety guards: firewall never blocks SSH; disk fault sized to never fill the
  filesystem.

### Changed
- Migrated from the AlmaLinux 10 monolithic `lab.sh` (archived on
  `archived-almalinux-attempt`) to a modular Ubuntu 24.04 design.
