# Deployment

## Requirements

- A fresh **Ubuntu 24.04 LTS** host (DigitalOcean droplet, London region for the
  primary use case). The cheapest practical size is fine.
- Root (or sudo) access.
- Outbound internet (for `apt` and for the DNS objective).

The installer refuses to run on other OSes. For local development/CI on a
non-droplet Ubuntu host you can set `LAB_SKIP_OS_CHECK=1`, but never do that on
the real lab host.

## Install

```bash
git clone https://github.com/korkibucek/interview-lab-v2.git
cd interview-lab-v2
sudo ./deploy/install.sh
```

Provide a candidate SSH key (recommended over passwords):

```bash
sudo LAB_CANDIDATE_PUBKEY="ssh-ed25519 AAAA... candidate" ./deploy/install.sh
```

The installer is **idempotent** — re-running it rebuilds the baseline and
re-applies the faults.

What it does:

1. Installs packages: `nginx cron ufw curl logrotate ca-certificates`.
2. Creates the `candidate` user with passwordless `sudo` and sets up access.
3. Builds the healthy baseline (`scripts/setup-lab.sh`).
4. Injects the six faults (`scripts/break-lab.sh`).
5. Prints candidate access details and next steps.

## Validate

```bash
sudo ./scripts/validate-lab.sh      # all PASS, exit 0  → ready for a candidate
```

## Ports / firewall

| Port | Purpose |
|---|---|
| 22 | SSH (always allowed) |
| 8080 | misconfigured web port (fault A) |
| 80 | closed until the candidate fixes fault A |

You may add a DigitalOcean cloud firewall to restrict source IPs.

## Score after the candidate

```bash
sudo ./scripts/validate-fixed.sh    # Score: N/6
```

## Reset for the next candidate

```bash
sudo ./deploy/reset-lab.sh
sudo ./scripts/validate-lab.sh
```

## Upgrade

```bash
cd interview-lab-v2 && git pull
sudo ./deploy/reset-lab.sh          # re-applies from the updated scripts
```

## Uninstall

```bash
sudo ./deploy/uninstall.sh              # remove lab artifacts, keep candidate user
sudo ./deploy/uninstall.sh --purge-user # also remove the candidate user
```

## Destroy (recommended cleanup)

Destroy the droplet in the DigitalOcean console. See `docs/SECURITY.md`.

## Rollback

There is no in-place rollback; the model is destroy-and-redeploy. To return a
kept host to a clean lab state, run `reset-lab.sh`; to remove the lab entirely,
run `uninstall.sh`.
