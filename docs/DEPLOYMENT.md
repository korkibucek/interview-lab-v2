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

## Option A — zero-touch provisioner (recommended)

`deploy/digitalocean.sh` runs on *your* machine and creates a self-provisioning
droplet via the DigitalOcean API + cloud-init. It generates an admin key (for
you) and a candidate key (to hand over), waits until the lab is broken-and-ready,
and prints the connection details.

```bash
export DO_TOKEN="dop_v1_..."     # read ONLY from the environment; never stored
./deploy/digitalocean.sh create  # provision
./deploy/digitalocean.sh status  # check progress/readiness
./deploy/digitalocean.sh destroy # tear down droplet + remove the admin key
```

Defaults (override via env): `LAB_REGION=lon1`, `LAB_SIZE=s-1vcpu-1gb`,
`LAB_IMAGE=almalinux-10-x64`, `LAB_REPO`, `LAB_BRANCH=main`. State and generated
keys live in `./.do-lab/` (git-ignored). Requires `bash curl jq ssh ssh-keygen`
locally.

> `s-1vcpu-512mb-10gb` ($4/mo) also works but the 10 GB disk only reaches ~80%
> for the disk fault (a WARN); `s-1vcpu-1gb` (25 GB) gives a clean PASS.

> The disk-pressure fault assumes `/var/log` is on the **root filesystem** (true
> for standard DigitalOcean droplets). A custom image with a separate `/var` or
> `/var/log` mount would weaken that fault.

> The DigitalOcean API token is never written to disk, never stored in the
> `.do-lab` state, and never embedded in the droplet (cloud-init does not receive
> it). Revoke the token when you are done if it was temporary.

## Option B — manual install on an existing droplet

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
