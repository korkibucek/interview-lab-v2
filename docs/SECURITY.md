# Security Notes

This lab is intended to run on a **disposable** public-cloud VPS and be
destroyed after each use. It deliberately introduces faults, so treat any lab
host as untrusted infrastructure.

## Threat model / assumptions

- The droplet is short-lived and single-purpose.
- The candidate is semi-trusted and has `sudo` (required to fix services,
  firewall, and system files).
- The admin holds an independent SSH key and can always recover the box.

## SSH and access model

- **Admin:** logs in as `root` using the SSH key added at droplet creation. The
  lab never modifies root's keys or the core SSH service in a breaking way.
- **Candidate:** a dedicated `candidate` user with passwordless `sudo`
  (`/etc/sudoers.d/90-candidate`). Provide access one of two ways:
  - **SSH key (recommended):** `LAB_CANDIDATE_PUBKEY=...` at install time. No
    password auth is enabled.
  - **Password (fallback):** the installer generates a random 16-char password,
    prints it once, stores it root-only at
    `/var/lib/interview-lab/candidate-credentials.txt`, and enables
    `PasswordAuthentication yes` via `/etc/ssh/sshd_config.d/60-lab-candidate.conf`.
    This is less secure and is removed by `uninstall.sh`.

> SSH is **never** an injected fault. Breaking it would risk locking out both
> candidate and admin.

## Built-in safety guards

- **No firewall lockout.** `break-lab.sh` always runs `ufw allow 22/tcp` /
  `ufw allow OpenSSH` *before* enabling ufw. `validate-lab.sh` FAILs if ufw is
  active without SSH permitted.
- **No full disk.** The disk-pressure file is sized from live free space and is
  capped so the root filesystem never exceeds `DISK_MAX_PCT` (92%) and always
  keeps `DISK_SAFETY_FREE_BYTES` (~1.5 GiB) free. If that can't be done safely,
  fault F is skipped. `validate-lab.sh` FAILs if usage hits 100%.
- **No malicious behaviour.** The faults are misconfigurations and resource
  pressure only — no persistence tricks, credential harvesting, outbound C2, or
  data exfiltration. The "CPU hog" is a plain `yes` process bounded to one
  instance.

## Secrets

- **Nothing secret is committed.** The web token and candidate password are
  generated at install time on the host and stored only under
  `/var/lib/interview-lab/` (mode 0700, files 0600).
- `.gitignore` excludes local credential/log artifacts.

## Network exposure

During a lab the host exposes:

| Port | State | Why |
|---|---|---|
| 22 | open | SSH (admin + candidate) |
| 8080 | open | the misconfigured web port (part of fault A) |
| 80 | closed until fixed | the firewall layer of fault A |

Restrict source IPs at the DigitalOcean cloud-firewall level if you want to
limit who can reach the droplet during the assessment.

## After the assessment

**Destroy the droplet** (DigitalOcean → Droplet → Destroy). This is the only
way to be certain temporary credentials and lab state are gone. If you must
keep the host, run `sudo ./deploy/uninstall.sh --purge-user`.
