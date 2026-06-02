# Answer Key (assessor only)

> **Do not give this to candidates.** It contains every root cause and fix.

Each objective lists the injected root cause, the diagnostic path a strong
candidate follows, and a canonical fix (AlmaLinux 10). Other valid fixes exist;
grade on a healthy end state (`validate-fixed.sh`), not on exact commands.

---

## A. Web service reachable on :80  (two layers)

**Root causes**
1. nginx is configured to `listen 8080` instead of `80`
   (`/etc/nginx/conf.d/lab.conf`).
2. firewalld is active and the `http` service is **not** allowed (only `ssh`
   and port `8080/tcp` are).

**Diagnosis**
- `curl -I http://127.0.0.1` → connection refused; `curl http://127.0.0.1:8080`
  works → nginx is on the wrong port.
- `ss -ltnp | grep nginx` confirms it listens on 8080.
- `sudo firewall-cmd --list-all` shows `http` is not permitted → external access
  is still blocked even after moving nginx to 80.

**Canonical fix**
```bash
sudo sed -ri 's/listen (\[::\]:)?8080 /listen \180 /' /etc/nginx/conf.d/lab.conf
sudo nginx -t && sudo systemctl restart nginx
sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --reload
curl -I http://127.0.0.1            # 200 OK
```

---

## B. app.service fails to start  (two layers)

**Root causes**
1. `/usr/local/bin/app.sh` is not executable (mode 0644) → `203/EXEC`.
2. `/opt/app` is owned `root:root` mode 0700, so `appuser` cannot write
   `run.log` → the script exits and the unit keeps failing.

**Diagnosis**
- `systemctl status app.service` / `journalctl -u app.service` → first shows an
  exec/permission-denied error; after the exec bit is fixed, a write/permission
  error on `/opt/app/run.log`.

**Canonical fix**
```bash
sudo chmod +x /usr/local/bin/app.sh
sudo chown appuser:appuser /opt/app
sudo systemctl restart app.service
systemctl is-active app.service     # active
```

---

## C. DNS resolution broken

**Root cause:** `/etc/resolv.conf` was overwritten with a static entry pointing
at `192.0.2.53` (RFC 5737 TEST-NET, routable nowhere).

**Diagnosis**
- `getent hosts mirrors.almalinux.org` hangs/fails; `cat /etc/resolv.conf` shows
  the bogus nameserver.

**Canonical fix** (set a working resolver)
```bash
echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
getent hosts mirrors.almalinux.org  # resolves
```
(Equally valid: restore the droplet's original resolver via NetworkManager.)

---

## D. Log rotation not working

**Root causes:** `/etc/logrotate.d/app` globs `/var/log/appp/*.log` (typo, the
real dir is `/var/log/app`) and omits `copytruncate`, which the always-open
logger needs.

**Diagnosis**
- `ls -lh /var/log/app/app.log` is large/growing; `sudo logrotate -d
  /etc/logrotate.d/app` shows it considering the wrong directory and rotating
  nothing.

**Canonical fix**
```bash
sudo sed -i 's#/var/log/appp/#/var/log/app/#' /etc/logrotate.d/app
# add `copytruncate` inside the block, then:
sudo logrotate -f /etc/logrotate.d/app
ls /var/log/app/app.log.1*          # rotated artifact appears
```

---

## E. Runaway CPU usage

**Root cause:** `/etc/cron.d/cpuhog` runs `/usr/local/bin/cpuhog.sh` every
minute, which keeps a `yes` process alive. Killing the process is not enough —
cron respawns it.

**Diagnosis**
- `top`/`pgrep -a yes` shows the runaway; `cat /etc/cron.d/cpuhog` reveals the
  scheduled cause.

**Canonical fix**
```bash
sudo rm -f /etc/cron.d/cpuhog
sudo pkill -x yes
```

---

## F. Disk pressure

**Root cause:** a large zero-filled file at `/var/log/verbose-debug.log`.

**Diagnosis**
- `df -h /` near full; `du -xhd1 /var/log | sort -h` points at the file;
  `lsof /var/log/verbose-debug.log` confirms nothing holds it open.

**Canonical fix**
```bash
sudo rm -f /var/log/verbose-debug.log
df -h /                              # back to healthy
```

---

## Re-scoring

```bash
sudo ./scripts/validate-fixed.sh    # expect: Score: 6/6
```
