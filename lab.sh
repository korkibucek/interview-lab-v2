#!/usr/bin/env bash
# AlmaLinux 10 – Troubleshooting Lab Preparer (v5.2)
# - No SELinux in exam
# - firewalld fully disabled (stop+disable)
# - Nginx starts on 8080; exam requires 80
# - Postfix binds to 80 to block nginx initially
# - Faults: broken systemd unit, bad logrotate, cron CPU hog, 4GB spam log
# - Drops hints file and MOTD notice

set -euo pipefail
log(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."


# ---------- 0) Package baseline ----------
log "Refreshing dnf metadata & installing baseline packages..."
dnf -y makecache || true
dnf -y install nginx postfix cronie tar gzip curl which procps-ng || die "pkg install failed"

# ---------- 1) Service baselines ----------
log "Ensuring baseline services…"
systemctl enable --now crond

# Ensure firewalld is OFF for this lab
if systemctl list-unit-files | grep -q '^firewalld\.service'; then
  log "Disabling firewalld for this lab…"
  systemctl stop firewalld || true
  systemctl disable firewalld || true
fi

# ---------- 2) Token, web root, MOTD, hints ----------
mkdir -p /usr/share/nginx/html /etc/nginx/conf.d
[[ -f /root/.lab_token ]] || tr -dc 'A-F0-9' </dev/urandom | head -c 16 >/root/.lab_token
LAB_TOKEN="$(cat /root/.lab_token)"
echo "<h1>Lab Web</h1><p>Token: ${LAB_TOKEN}</p>" >/usr/share/nginx/html/index.html

# Hints (very mild) + MOTD
log "Writing hints and MOTD…"
cat >/root/hints.txt <<'HINTS'
Mild Hints (read only if stuck):
- Use: ss -tulpen   -> see which process holds port 80.
- Use: systemctl status <service> and journalctl -u <service> for errors.
- If a service cannot write a file, check ownership/permissions of its target directory.
- Continuous log writers often need copytruncate or a restart on rotation.
- Cron jobs can spawn unexpected load; check /etc/cron.* and /etc/cron.d.
- Large files under /var/log can be safely removed if not in use (confirm with lsof).
HINTS

printf "\n Please read instructions at /root/instructions.txt***\n\n" >/etc/motd
printf "\n*** NOTE: A hints file exists at /root/hints.txt (use ONLY if needed). ***\n\n" >>/etc/motd

# ---------- 3) Nginx initial config (8080 only) ----------
log "Configuring nginx to listen ONLY on :8080…"
cat >/etc/nginx/conf.d/lab.conf <<'NGINX'
server {
    listen 8080 default_server;
    server_name lab.local;
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

# Rewrite any stray :80 listeners (IPv4+IPv6) to :8080 across configs
shopt -s nullglob
for f in /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf; do
  [[ -f "$f" ]] || continue
  sed -ri 's/^\s*listen\s+\[::\]:80(\s+default_server)?\s*;/    listen [::]:8080\1;/' "$f" || true
  sed -ri 's/^\s*listen\s+80(\s+default_server)?\s*;/    listen 8080\1;/'            "$f" || true
done
shopt -u nullglob

nginx -t
systemctl enable nginx
systemctl restart nginx

# ---------- 4) Postfix binds to 80 to force conflict later ----------
log "Configuring postfix to BIND :80 (to block nginx when moved)…"
postconf -e 'inet_interfaces = all'
grep -qE '^80\s+inet' /etc/postfix/master.cf || printf "\n80      inet  n       -       n       -       -       smtpd\n" >> /etc/postfix/master.cf
systemctl enable postfix
systemctl restart postfix || {
  warn "postfix restart failed; checking listeners"
  ss -tulpen | egrep ':80|:8080' || true
  die "postfix could not bind :80; fix configs and rerun"
}

# ---------- 5) Broken systemd unit ----------
log "Creating intentionally broken app.service…"
id appuser >/dev/null 2>&1 || useradd --system --home /opt/app --shell /sbin/nologin appuser
mkdir -p /opt/app && chown root:root /opt/app && chmod 700 /opt/app

cat >/usr/local/bin/app.sh <<'APP'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /opt/app
echo "$(date -Is) app OK" >> /opt/app/run.log
exit 0
APP
chmod 0644 /usr/local/bin/app.sh  # NOT executable on purpose

cat >/etc/systemd/system/app.service <<'UNIT'
[Unit]
Description=Lab App Service (intentionally broken)
After=network.target
[Service]
Type=simple
User=appuser
Group=appuser
ExecStart=/usr/local/bin/app.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable app.service
systemctl start app.service || true  # expected to fail initially

# ---------- 6) Chatty logger + broken logrotate ----------
log "Creating chatty logger and broken logrotate rule…"
mkdir -p /var/log/app
: >/var/log/app/app.log

cat >/usr/local/bin/app-logger.sh <<'LOGGER'
#!/usr/bin/env bash
while true; do
  echo "$(date -Is) heartbeat" >> /var/log/app/app.log
  sleep 2
done
LOGGER
chmod +x /usr/local/bin/app-logger.sh

cat >/etc/systemd/system/app-logger.service <<'UNIT'
[Unit]
Description=Lab App Logger (chatty)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/app-logger.sh
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now app-logger.service

# Bad path -> rotation fails by default
cat >/etc/logrotate.d/app <<'ROT'
/var/log/appp/*.log {
    weekly
    rotate 4
    missingok
    compress
    copytruncate
}
ROT

# ---------- 7) Cron CPU hog ----------
log "Installing cron-based CPU hog…"
cat >/usr/local/bin/cpuhog.sh <<'HOG'
#!/usr/bin/env bash
yes >/dev/null &
HOG
chmod +x /usr/local/bin/cpuhog.sh

cat >/etc/cron.d/cpuhog <<'CRON'
* * * * * root /usr/local/bin/cpuhog.sh
CRON
systemctl reload crond

# ---------- 8) Disk pressure via big /var/log/spam.log (4GB) ----------
log "Creating 4GB /var/log/spam.log to simulate disk pressure…"
mkdir -p /var/log
if [[ ! -f /var/log/spam.log || $(stat -c%s /var/log/spam.log 2>/dev/null || echo 0) -lt $((4*1024*1024*1024)) ]]; then
  (fallocate -l 18G /var/log/spam.log 2>/dev/null || dd if=/dev/zero of=/var/log/spam.log bs=1M count=4096 status=none) || true
fi

# ---------- 9) Candidate brief ----------
log "Writing candidate brief to /root/LAB.md…"
cat >/root/LAB.md <<LAB
# Linux Troubleshooting Lab (30 minutes)

SSH only. Do **not** reboot or change runlevels. Fix what matters most for production.
Document what you changed and why.

## Goals
1. **Run the web service on port 80 and make it reachable.**
   - Nginx currently serves on **8080**. The requirement is **80**.
   - If switching to 80 fails, investigate which process holds the port and remediate.
2. **Fix a failing systemd service** (\`app.service\`).
3. **Make log rotation work** for \`/var/log/app/app.log\`.
4. **Stop unnecessary CPU load** introduced by a scheduled task.
5. **Relieve disk pressure** caused by a large file under \`/var/log\`.

## Constraints
- SSH must remain available.
- No reboots / single-user modes.
- Changes should be auditable and documented.

## Notes
- Firewall is disabled for this lab.
- Useful commands: \`systemctl status\`, \`journalctl -u\`, \`ss -tulpen\`, \`lsof -i :80\`, \`logrotate\`, \`crontab/cron.d\`.
- A very mild hints file exists at **/root/hints.txt**.

**Web token:** ${LAB_TOKEN}
LAB

# ---------- 10) Lightweight grader ----------
log "Dropping /root/grade.sh…"
cat >/root/grade.sh <<'GRADE'
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
GRADE
chmod +x /root/grade.sh

# ---------- 11) Summary ----------
log "Lab prepared (v5.2)."
echo "[i] Hints:           /root/hints.txt (also advertised in /etc/motd)"
echo "[i] Candidate brief: /root/LAB.md"
echo "[i] Grader:          bash /root/grade.sh"
echo "[i] Baseline: nginx :8080, postfix :80, firewalld disabled."
