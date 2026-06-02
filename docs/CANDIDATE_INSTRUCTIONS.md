# Linux Troubleshooting Lab — Candidate Brief

You have been given SSH access to a Linux server (AlmaLinux 10) that is **not
healthy**. It hosts a small internal web service that should be reachable over
HTTP, but it is currently down — and while investigating you will find the host
is unwell in a few other ways too.

Your job is to **diagnose and restore the system to a healthy, production-ready
state**, the way an on-call engineer would.

## How to connect

Your assessor will give you a username, a server IP, and either a password or
an SSH key:

```bash
ssh candidate@<server-ip>
```

You have `sudo`. You may install tools and use any documentation, search
engines, or AI assistants you like — we care about how you think, not what you
have memorised.

## What "healthy" looks like

Work towards these outcomes. You are not given the causes — finding them is the
exercise.

1. **The web service responds over HTTP on port 80**, both locally on the host
   and from the outside world.
2. **The application service starts cleanly and stays running** under systemd.
3. **Name resolution works** — the host can resolve external hostnames.
4. **Log rotation works** so the application's log cannot fill the disk.
5. **CPU load is back to normal**, and whatever was causing the spikes will not
   come back on its own.
6. **The root filesystem has healthy free space.**

## Rules of engagement

- **Do not reboot** the server and do not drop to single-user/rescue mode.
- **Do not change the SSH service** in a way that could cut off your own access.
- **Do not reinstall the OS, wipe configuration wholesale, or `rm -rf` your way
  out of a problem.** Fix the actual faults.
- Prefer the smallest correct change. Destructive actions should be justified.
- Keep notes: for each issue, record what you observed, what the root cause was,
  and what you changed.

## Deliverables

When you finish (or run out of time), be ready to walk through:

- Each problem you found and how you diagnosed it.
- The change you made to fix it.
- **What you would do to prevent each issue in production** (monitoring,
  alerting, configuration management, etc.).

A typical attempt takes **45–90 minutes**. Good luck.
