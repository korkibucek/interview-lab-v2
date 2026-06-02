# Assessor Guide

End-to-end runbook for deploying, validating, running, scoring, and tearing
down the lab. The internal root causes are in `docs/ANSWER_KEY.md` (keep that
away from candidates).

> **Quick path:** `scripts/examiner.sh` is a one-command playbook for the
> zero-touch DigitalOcean flow. Run it with no argument to print the whole
> sequence, or run a phase: `provision`, `info`, `verify`, `shell`, `score`,
> `answer-key`, `reset`, `destroy`. It reuses the admin key in `./.do-lab/` so
> you don't have to hand-type SSH commands. The sections below explain each step.

## 1. Create the droplet

- DigitalOcean → Create Droplet → **AlmaLinux 10 x64** (see the image note in
  `docs/DEPLOYMENT.md` if it isn't offered directly).
- Region **London (LON1)**.
- Cheapest practical size (Basic / Regular, 1 GB RAM is fine; the disk fault
  adapts to whatever disk size you pick).
- Add **your own** SSH key (this is the admin/recovery key).

## 2. Deploy

SSH in as root and run:

```bash
git clone https://github.com/korkibucek/interview-lab-v2.git
cd interview-lab-v2
sudo ./deploy/install.sh
```

Recommended: provision a candidate SSH key instead of a password:

```bash
sudo LAB_CANDIDATE_PUBKEY="ssh-ed25519 AAAA... candidate" ./deploy/install.sh
```

The installer prints the candidate access details (and, in password mode, saves
them to `/var/lib/interview-lab/candidate-credentials.txt`, root-only).

## 3. Validate before handover

```bash
sudo ./scripts/validate-lab.sh
```

Expect **all PASS** and exit code 0. The script also runs safety checks (SSH is
allowed through the firewall; the disk is not at 100%). If anything FAILs, fix
it before bringing in a candidate — see `docs/TROUBLESHOOTING.md`.

## 4. Hand over to the candidate

Give the candidate:

- The server IP and their `candidate` credentials/key.
- `docs/CANDIDATE_INSTRUCTIONS.md` (the only document they should see).

The admin retains independent root access via the key from step 1.

> The installer makes the on-box repo (which contains the answer key, the
> breakage script and the lab templates) **root-readable only**, so the candidate
> cannot simply `cat` the answers. Run all assessor scripts with `sudo`. Note
> that `candidate` has root-equivalent `sudo`, so a determined candidate could
> still read those files deliberately — keep the session supervised.

## 5. Score

```bash
sudo ./scripts/validate-fixed.sh      # prints Score: N/6
```

### Scoring rubric (suggested)

| Score | Reading |
|---|---|
| 6/6 | Strong. All services healthy. |
| 4–5/6 | Solid; missed one layer or one objective under time pressure. |
| 2–3/6 | Mixed; got the easy wins, struggled with layered faults. |
| 0–1/6 | Weak practical skills. |

Weight **diagnosis and communication** as heavily as the raw score. Ask the
candidate to talk through each fix and their production-prevention ideas.

### What separates strong candidates

- Finds the **second layer** of A and B (firewall after the port; permissions
  after the exec bit) instead of declaring victory early.
- Uses `systemctl status` / `journalctl` / `ss` / `df` / `du` /
  `firewall-cmd --list-all` methodically rather than guessing.
- Confirms a file is unused (`lsof`) before deleting it.
- Removes the cron **cause** of the CPU hog, not just the symptom.

### Red flags

- Rebooting, reinstalling, or wiping configs to "reset" the box.
- Disabling firewalld entirely instead of allowing the `http` service (works,
  but discuss why it's worse than a targeted rule).
- `chmod 777` / `chown` sprees, or running everything as root with no reasoning.
- Editing the SSH service and losing access.
- Deleting `/var/log/verbose-debug.log` without checking it is safe first.

### Bonus observations (credit if mentioned)

- Suggesting log-based alerting or `monitoring`/`node_exporter` for the CPU and
  disk issues.
- Noting the password-auth SSH drop-in and recommending key-only auth.
- Proposing config management (Ansible) so these regressions are caught.

## 6. Reset for the next candidate

```bash
sudo ./deploy/reset-lab.sh
sudo ./scripts/validate-lab.sh        # confirm 6 faults are back
```

## 7. Tear down

Cheapest and safest: **destroy the droplet** in the DigitalOcean console
(Droplet → Destroy). This guarantees no lab artifacts or temporary credentials
survive.

To clean a host you want to keep:

```bash
sudo ./deploy/uninstall.sh --purge-user
```
