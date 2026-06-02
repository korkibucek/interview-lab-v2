# Deployment

## Requirements

- A fresh **AlmaLinux 10** host (DigitalOcean droplet, London region for the
  primary use case). The cheapest practical size is fine.
- Root (or sudo) access.
- Outbound internet (for `dnf` and for the DNS objective).

The installer refuses to run on other OSes. For local development/CI on a
non-droplet host you can set `LAB_SKIP_OS_CHECK=1`, but never do that on the
real lab host.

> **DigitalOcean image note:** if AlmaLinux 10 is not yet offered as a base
> image in your region, create the droplet from a custom AlmaLinux 10 image, or
> from AlmaLinux 9 and `dnf` upgrade to 10. The scripts require AlmaLinux 10.

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

1. Installs packages via `dnf`: `nginx cronie firewalld logrotate curl
   procps-ng policycoreutils util-linux sudo openssh-server`.
2. Creates the `candidate` user (in `wheel`) with passwordless `sudo`.
3. Sets SELinux to permissive (so it is not an unintended fault).
4. Builds the healthy baseline (`scripts/setup-lab.sh`).
5. Injects the six faults (`scripts/break-lab.sh`).
6. Prints candidate access details and next steps.

## Validate

```bash
sudo ./scripts/validate-lab.sh      # all PASS, exit 0  → ready for a candidate
```

## Ports / firewall (firewalld)

| Port | Purpose |
|---|---|
| 22 (ssh) | always allowed |
| 8080 | misconfigured web port (fault A) |
| 80 (http) | closed until the candidate fixes fault A |

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
