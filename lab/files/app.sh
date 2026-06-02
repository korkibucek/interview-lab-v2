#!/usr/bin/env bash
# Lab demo "application". Long-running so the service has a stable active state.
# Writes a heartbeat into /opt/app/run.log. If the binary is not executable, or
# /opt/app is not writable by its user, systemd will fail to keep it running.
set -euo pipefail

RUN_LOG="/opt/app/run.log"

while true; do
  printf '%s app heartbeat\n' "$(date -Is)" >> "$RUN_LOG"
  sleep 5
done
