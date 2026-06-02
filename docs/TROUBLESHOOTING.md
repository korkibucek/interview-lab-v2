# Troubleshooting (assessor / admin)

Problems you might hit operating the lab — not the candidate's faults.

## `install.sh` refuses to run

- **"must be run as root"** — use `sudo ./deploy/install.sh`.
- **"Unsupported OS"** — the host is not AlmaLinux 10. Use the right image. For
  dev/CI only, `LAB_SKIP_OS_CHECK=1` bypasses the check.

## `dnf` fails during install

Usually transient mirror/network issues. Re-run the installer (it is
idempotent). If DNS is the problem, confirm `/etc/resolv.conf` is sane *before*
install — the DNS fault is only applied later, by `break-lab.sh`.

## `validate-lab.sh` reports a FAIL

| FAIL | Likely cause | Action |
|---|---|---|
| `firewalld is not active` | firewalld didn't start (no netfilter backend) | run on a real droplet; check `systemctl status firewalld` |
| `disk pressure file ... missing` | disk too small/full, or `LAB_MAX_BIGFILE_BYTES` too low, fault F skipped | use a larger droplet; check installer warnings |
| `web service answers on :80` | a previous candidate already fixed it | `sudo ./deploy/reset-lab.sh` |
| `DNS resolves ...` | resolver still healthy | `sudo ./deploy/reset-lab.sh`; check `/etc/resolv.conf` |

Generally: if checks indicate the lab is already (partly) fixed, run
`sudo ./deploy/reset-lab.sh` then validate again.

## firewalld won't start

firewalld needs a working netfilter/nftables backend. This is present on a
normal droplet but may be absent in a minimal container. The lab is designed for
a real VM/droplet.

## Disk fault didn't appear

If the root filesystem is too small to create pressure while keeping ~1.5 GiB
free (or `LAB_MAX_BIGFILE_BYTES` is set too low), `break-lab.sh` logs a warning
and skips fault F; the lab then has five faults. Use a larger droplet (or accept
five faults).

## Candidate can't log in

- Key mode: confirm you passed `LAB_CANDIDATE_PUBKEY` and the candidate uses the
  matching private key: `ssh candidate@<ip>`.
- Password mode: read `/var/lib/interview-lab/candidate-credentials.txt` (root),
  and confirm `/etc/ssh/sshd_config.d/60-lab-candidate.conf` exists and `sshd`
  was reloaded.

## I'm locked out / something is badly wrong

Use your admin root key (added at droplet creation). If unrecoverable, destroy
and redeploy — the whole point of the destroy-and-redeploy model.

## Quick host snapshot

```bash
sudo ./deploy/healthcheck.sh
```
