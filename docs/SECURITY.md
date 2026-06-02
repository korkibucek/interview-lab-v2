# Security Notes

This lab is intended to run on a **disposable** public-cloud VPS (AlmaLinux 10)
and be destroyed after each use. It deliberately introduces faults, so treat any
lab host as untrusted infrastructure.

## Threat model / assumptions

- The droplet is short-lived and single-purpose.
- The candidate is semi-trusted and has **passwordless `sudo` — i.e. is
  root-equivalent** on the box (required to fix services, firewall, and system
  files). Treat the host accordingly: keep the assessment **supervised**,
  optionally restrict source IPs with a DigitalOcean cloud firewall, and
  **destroy the droplet promptly** afterwards. A candidate could use the box for
  anything during the session.
- The admin holds an independent SSH key and can always recover the box.

> **Answer material on the host.** The installer makes the on-box repo
> (answer key, `break-lab.sh`, `validate-fixed.sh`, `lab/` templates)
> root-readable only, so the candidate cannot trivially `cat` the answers.
> Because the candidate is root-equivalent they could still read them with
> `sudo`, but that is a deliberate, observable act rather than a casual `cat`.

## SSH and access model

- **Admin:** logs in as `root` using the SSH key added at droplet creation. The
  lab never modifies root's keys or the core SSH service in a breaking way.
- **Candidate:** a dedicated `candidate` user in the `wheel` group with
  passwordless `sudo` (`/etc/sudoers.d/90-candidate`). Provide access one of two
  ways:
  - **SSH key (recommended):** `LAB_CANDIDATE_PUBKEY=...` at install time. No
    password auth is enabled.
  - **Password (fallback):** the installer generates a random 16-char password,
    prints it once, stores it root-only at
    `/var/lib/interview-lab/candidate-credentials.txt`, and enables
    `PasswordAuthentication yes` via `/etc/ssh/sshd_config.d/60-lab-candidate.conf`.
    This is less secure and is removed by `uninstall.sh`.

> SSH is **never** an injected fault. Breaking it would risk locking out both
> candidate and admin.

## SELinux

The installer sets SELinux to **permissive** (`setenforce 0` plus
`/etc/selinux/config`). This is a deliberate scope decision so SELinux does not
become an accidental, hard-to-diagnose fault (e.g. blocking nginx on :8080 or
the lab docroot). It is documented here for transparency; a future "hard mode"
could turn an SELinux denial into an intended objective.

## Built-in safety guards

- **No firewall lockout.** `setup-lab.sh`/`break-lab.sh` always ensure firewalld
  permits SSH before removing the HTTP service. `validate-lab.sh` FAILs if
  firewalld is active without SSH permitted.
- **No full disk.** The disk-pressure file is sized from live free space and is
  capped so the root filesystem never exceeds `DISK_MAX_PCT` (92%) and always
  keeps `DISK_SAFETY_FREE_BYTES` (~1.5 GiB) free. If that can't be done safely,
  fault F is skipped. `LAB_MAX_BIGFILE_BYTES` can cap it further.
  `validate-lab.sh` FAILs if usage hits 100%.
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
