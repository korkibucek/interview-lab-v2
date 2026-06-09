# Assessor Cheat Sheet — faults & fixes

> ⚠️ **ASSESSOR ONLY — CONTAINS ANSWERS.** Do not share with candidates. On a
> deployed lab host this repo is root-readable only (see `docs/SECURITY.md`).
> For full diagnosis paths and rationale see [`ANSWER_KEY.md`](ANSWER_KEY.md).

A one-screen brief of what is broken and the canonical fix for each fault.

```
INTERVIEW LAB — WHAT'S BROKEN & HOW TO FIX (assessor brief)

1. Web service not reachable on :80 (two layers)
   - nginx is listening on 8080, not 80
   - firewalld is blocking HTTP
   Fix:
   - sudo sed -ri 's/listen (\[::\]:)?8080 /listen \180 /' /etc/nginx/conf.d/lab.conf
   - sudo nginx -t && sudo systemctl restart nginx
   - sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --reload
   - verify: curl -I http://127.0.0.1   ->   200 OK

2. app.service won't start (two layers)
   - /usr/local/bin/app.sh is not executable (203/EXEC)
   - /opt/app is owned root:root 700, so appuser can't write run.log
   Fix:
   - sudo chmod +x /usr/local/bin/app.sh
   - sudo chown appuser:appuser /opt/app
   - sudo systemctl restart app.service   ->   systemctl is-active app.service = active

3. DNS resolution broken
   - /etc/resolv.conf points at a dead nameserver (192.0.2.53)
   Fix:
   - echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
   - verify: getent hosts mirrors.almalinux.org

4. Log rotation not working
   - /etc/logrotate.d/app has a typo path (/var/log/appp) and no copytruncate
   Fix:
   - sudo sed -i 's#/var/log/appp/#/var/log/app/#' /etc/logrotate.d/app
   - add 'copytruncate' inside the block
   - verify: sudo logrotate -f /etc/logrotate.d/app ; ls /var/log/app/app.log.1*

5. Runaway CPU (recurring)
   - /etc/cron.d/cpuhog respawns a 'yes' process every minute
   Fix:
   - sudo rm -f /etc/cron.d/cpuhog
   - sudo pkill -x yes

6. Disk almost full
   - large junk file /var/log/verbose-debug.log filling the root fs
   Fix:
   - sudo rm -f /var/log/verbose-debug.log
   - verify: df -h /

Score the result:  sudo /opt/interview-lab-v2/scripts/validate-fixed.sh   ->  6/6
```
