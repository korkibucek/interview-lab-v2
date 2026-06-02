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
- `deploy/digitalocean.sh`: zero-touch DigitalOcean provisioner (create/status/
  destroy) — self-installing droplet via cloud-init, generates admin + candidate
  SSH keys, reads the API token only from `DO_TOKEN`.
- `scripts/examiner.sh`: examiner playbook/runner that mirrors the full assessor
  sequence (provision → info → verify → shell → score → answer-key → reset →
  destroy) over the `./.do-lab` admin key; prints the whole playbook with no args.
- `scripts/smoke-test.sh` and GitHub Actions CI (shellcheck + syntax + answer
  leak guard).
- Safety guards: firewall never blocks SSH; disk fault sized to never fill the
  filesystem (`LAB_MAX_BIGFILE_BYTES` cap for testing/large disks).

### Verified
- Full lifecycle (install → validate-lab → canonical fixes → validate-fixed 6/6
  → reset → uninstall) exercised in an `almalinux:10` systemd container.
- End-to-end on a live DigitalOcean AlmaLinux 10 droplet (lon1) via
  `deploy/digitalocean.sh`: zero-touch provision → validate-lab 16/16 → candidate
  key login with working sudo → fixes → validate-fixed 6/6 → external HTTP 200 on
  port 80 → reset 16/16 → destroy. Droplet and admin key confirmed removed.

### Changed
- Targeted **AlmaLinux 10 exclusively** (dnf, firewalld, cronie/crond, sshd,
  wheel, `/etc/nginx/conf.d`, SELinux permissive). The original single-file
  AlmaLinux script is preserved on `archived-almalinux-attempt`.
