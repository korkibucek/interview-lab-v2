# Changelog

## [Unreleased]

### Added
- AlmaLinux 10 interview lab with six layered faults (web/firewalld,
  systemd/permissions, DNS, log rotation, cron CPU hog, disk).
- Idempotent `deploy/install.sh` (dnf packages, candidate user/access, SELinux
  permissive, setup, break).
- `deploy/reset-lab.sh`, `deploy/uninstall.sh`, `deploy/healthcheck.sh`.
- `scripts/setup-lab.sh`, `scripts/break-lab.sh`.
- `scripts/validate-lab.sh` (pre-candidate, with safety checks) and
  `scripts/validate-fixed.sh` (behavioural `N/6` scoring).
- Shared library `lab/lib/common.sh` with firewalld helpers, SIGPIPE-safe random
  helpers, and a validation harness.
- Full docs set: README, ARCHITECTURE, DEPLOYMENT, CANDIDATE_INSTRUCTIONS,
  ASSESSOR_GUIDE, ANSWER_KEY, SECURITY, TROUBLESHOOTING, ROADMAP.
- `scripts/smoke-test.sh` and GitHub Actions CI (shellcheck + syntax + answer
  leak guard).
- Safety guards: firewall never blocks SSH; disk fault sized to never fill the
  filesystem (`LAB_MAX_BIGFILE_BYTES` cap for testing/large disks).

### Verified
- Full lifecycle (install → validate-lab → canonical fixes → validate-fixed 6/6
  → reset → uninstall) exercised in an `almalinux:10` systemd container.

### Changed
- Targeted **AlmaLinux 10 exclusively** (dnf, firewalld, cronie/crond, sshd,
  wheel, `/etc/nginx/conf.d`, SELinux permissive). The original single-file
  AlmaLinux script is preserved on `archived-almalinux-attempt`.
