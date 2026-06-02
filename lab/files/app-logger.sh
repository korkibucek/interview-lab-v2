#!/usr/bin/env bash
# Chatty logger. This service is healthy on purpose: it is the source of the
# growing /var/log/app/app.log that the candidate must keep under control via
# working log rotation (objective D). Because it appends to an open file handle,
# rotation must use copytruncate to take effect without a restart.
set -euo pipefail

LOG="/var/log/app/app.log"

while true; do
  printf '%s heartbeat from app-logger\n' "$(date -Is)" >> "$LOG"
  sleep 2
done
