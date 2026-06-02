# Interview Lab

A realistic, self-contained **Linux troubleshooting interview lab** for
**AlmaLinux 10**. It turns a fresh AlmaLinux 10 server into a deliberately (and
safely) broken host that looks like a small internal web service that has fallen
over. A candidate SSHes in and restores it; the assessor scores the result with
a single command.

This is not a puzzle box — the faults are ordinary misconfigurations and
resource problems a real sysadmin meets, layered so the exercise rewards
diagnosis over memorised commands.

## What it tests

Six layered objectives across: web service config, firewall (firewalld),
systemd, file permissions, DNS, log rotation, cron, process diagnosis, and disk
usage. See the fault matrix in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Zero-touch deploy (DigitalOcean, one command)

From your own workstation, with a DigitalOcean API token, provision a fully
self-installing lab droplet — it boots, pulls this repo, runs the installer,
generates the candidate's SSH key, and tells you how to connect:

```bash
export DO_TOKEN="dop_v1_..."        # token is read ONLY from the environment
./deploy/digitalocean.sh create     # creates an AlmaLinux 10 droplet in lon1
# ... when finished:
./deploy/digitalocean.sh destroy    # tears down the droplet + admin key
```

`create` prints the admin SSH command, the **candidate username (`candidate`)**,
and the path to the generated candidate private key to hand over. Requires
`bash curl jq ssh ssh-keygen` locally. The token is never written to disk or
embedded in the droplet. See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

## Manual quick start (on an existing droplet)

Create an **AlmaLinux 10** droplet in **London**, add your SSH key, then:

```bash
git clone https://github.com/korkibucek/interview-lab-v2.git
cd interview-lab-v2
sudo ./deploy/install.sh
sudo ./scripts/validate-lab.sh     # all PASS, exit 0 → lab is ready
```

Prefer giving the candidate a key instead of a password:

```bash
sudo LAB_CANDIDATE_PUBKEY="ssh-ed25519 AAAA... candidate" ./deploy/install.sh
```

## The workflow

```bash
sudo ./deploy/install.sh           # provision + break the lab
sudo ./scripts/validate-lab.sh     # confirm it is broken AND safe
# ... candidate troubleshoots over SSH ...
sudo ./scripts/validate-fixed.sh   # Score: N/6
sudo ./deploy/reset-lab.sh         # re-break for the next candidate
```

When finished, **destroy the droplet** (cheapest, safest cleanup).

## Documentation

| Audience | Document |
|---|---|
| Candidate (hand this over) | [`docs/CANDIDATE_INSTRUCTIONS.md`](docs/CANDIDATE_INSTRUCTIONS.md) |
| Assessor runbook + scoring | [`docs/ASSESSOR_GUIDE.md`](docs/ASSESSOR_GUIDE.md) |
| Internal answer key | [`docs/ANSWER_KEY.md`](docs/ANSWER_KEY.md) |
| Deploy / reset / uninstall | [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) |
| Design + fault matrix | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Security & safety | [`docs/SECURITY.md`](docs/SECURITY.md) |
| Operator troubleshooting | [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) |
| Future work | [`docs/ROADMAP.md`](docs/ROADMAP.md) |

> Give candidates **only** `docs/CANDIDATE_INSTRUCTIONS.md`. The answer key and
> assessor guide reveal the faults.

## Supported OS

**AlmaLinux 10 only.** The installer refuses other systems (override only for
dev/CI with `LAB_SKIP_OS_CHECK=1`). SELinux is set to permissive so the six
intended faults behave predictably — see `docs/SECURITY.md`.

## ⚠️ Safety

This deploys broken services on a public VPS. It is built to be safe — SSH is
never an injected fault and is always allowed through the firewall, and the disk
fault is sized so it can never fill the disk — but you should still:

- Run it only on a **disposable** droplet you intend to destroy.
- Restrict access with a DigitalOcean cloud firewall if needed.
- **Destroy the droplet after each assessment.**

See [`docs/SECURITY.md`](docs/SECURITY.md).

## Development / testing

```bash
bash scripts/smoke-test.sh         # bash -n + shellcheck + answer-leak guard
```

The full lifecycle can be exercised in a container:

```bash
podman run -d --name lab --privileged --systemd=always \
  -v "$PWD":/opt/interview-lab:ro almalinux:10 /sbin/init
podman exec lab bash -c 'cp -a /opt/interview-lab /root/lab && cd /root/lab \
  && LAB_MAX_BIGFILE_BYTES=$((300*1024*1024)) ./deploy/install.sh \
  && ./scripts/validate-lab.sh'
```

CI runs the smoke test on every push/PR (`.github/workflows/ci.yml`).
