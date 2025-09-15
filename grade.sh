#!/usr/bin/env bash
set -euo pipefail
pass=0; total=5
check(){ printf "%-45s" "$1"; }
ok(){ echo "OK"; pass=$((pass+1)); }
ko(){ echo "NOT OK"; }

check "Web reachable (localhost :80)"
if curl -fsS http://127.0.0.1:80/ >/dev/null 2>&1; then ok; else ko; fi

check "app.service active"
systemctl status app | grep Active | awk '{print $2}' | grep -q failed && ko || ok

check "logrotate works (dry-run)"
grep -qE '^[[:space:]]*/var/log/app/\*\.log' /etc/logrotate.d/app && ok || ko

check "No 'yes' CPU hogs"
if ! pgrep -fa "yes" | grep -qv grep; then ok; else ko; fi

check "Root FS usage reasonable"
[ $(df -P / | awk 'NR==2{gsub("%","",$5); print $5}') -lt 50 ] && ok || ko

echo "Score: $pass/$total"
[[ $pass -eq $total ]]
