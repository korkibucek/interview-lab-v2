#!/usr/bin/env bash
# Simulates a runaway scheduled job: spawns a detached `yes` that pins a CPU.
# Installed by break-lab.sh and triggered every minute from /etc/cron.d/cpuhog.
# It keeps exactly one runaway alive, so killing the process is not enough --
# the candidate must also remove the cron entry to stop it coming back.
pgrep -x yes >/dev/null 2>&1 || yes > /dev/null &
