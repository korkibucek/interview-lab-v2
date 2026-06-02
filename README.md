# Interview Lab

A realistic, self-contained **Linux troubleshooting interview lab**. It turns a
fresh Ubuntu 24.04 server into a deliberately (and safely) broken host that
looks like a small internal web service that has fallen over. A candidate SSHes
in and restores it; the assessor scores the result with a single command.

This is not a puzzle box — the faults are ordinary misconfigurations and
resource problems a real sysadmin meets, layered so the exercise rewards
diagnosis over memorised commands.

## What it tests

Six layered objectives across: web service config, firewall, systemd, file
permissions, DNS, log rotation, cron, process diagnosis, and disk usage. See the
fault matrix in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Quick start (DigitalOcean)

Create a **Ubuntu 24.04** droplet in **London**, add your SSH key, then:

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

**Ubuntu 24.04 LTS only.** The installer refuses other systems. (An earlier
AlmaLinux version is archived on the `archived-almalinux-attempt` branch.)

## ⚠️ Safety

This deploys broken services on a public VPS. It is built to be safe — SSH is
never an injected fault and is always allowed through the firewall, and the disk
fault is sized so it can never fill the disk — but you should still:

- Run it only on a **disposable** droplet you intend to destroy.
- Restrict access with a DigitalOcean cloud firewall if needed.
- **Destroy the droplet after each assessment.**

See [`docs/SECURITY.md`](docs/SECURITY.md).

## Development

```bash
bash scripts/smoke-test.sh         # bash -n + shellcheck + answer-leak guard
```

CI runs the same smoke test on every push/PR (`.github/workflows/ci.yml`).
