# Error Recovery — when things go wrong during operations

## Critical gotchas

- Always back up config before editing: `sudo cp <file> <file>.bak.$(date +%s)`
- Validate before reload: `nginx -t`, `sshd -t`, `systemd-analyze verify`
- Processes in D state (uninterruptible sleep) can't be killed — reboot required
- Firewall lockout: use AWS console SSM/browser SSH, never lock yourself out
- Database migrations: snapshot BEFORE attempting manual rollback

## Failed deploy recovery

```bash
# Triage
bash scripts/connect.sh run <target> "systemctl status <svc> --no-pager; journalctl -u <svc> -n 50 --no-pager"
bash scripts/connect.sh run <target> "cd ~/<app> && git status; git log --oneline -3"
curl -s -o /dev/null -w "%{http_code}\n" https://<domain>/healthz

# Rollback to last commit
bash scripts/connect.sh run <target> "cd ~/<app> && git reset --hard HEAD~1 && npm ci && npm run build && sudo systemctl restart <svc>"

# Clear stale build artifacts
bash scripts/connect.sh run <target> "cd ~/<app> && rm -rf dist/ node_modules/.cache && npm run build && sudo systemctl restart <svc>"
```

## Config file rollback

```bash
# Restore from backup
bash scripts/connect.sh run <target> "ls -lt /etc/nginx/sites-available/*.bak* | head -5"
bash scripts/connect.sh run <target> "sudo cp <file>.bak.<timestamp> <file> && sudo nginx -t && sudo systemctl reload nginx"

# Restore systemd from package default
bash scripts/connect.sh run <target> "sudo cp /usr/lib/systemd/system/<svc>.service /etc/systemd/system/ && sudo systemctl daemon-reload"

# Restore sshd from package (Ubuntu)
bash scripts/connect.sh run <target> "sudo cp /usr/share/openssh/sshd_config /etc/ssh/sshd_config && sudo sshd -t && sudo systemctl reload sshd"

# No backup exists: reinstall package to restore defaults
# Ubuntu: sudo apt install --reinstall <package>
# Amazon Linux: sudo dnf reinstall <package>
```

## Firewall lockout recovery

```bash
# From AWS console SSM or Lightsail browser SSH
sudo ufw disable && sudo ufw allow 22 && sudo ufw enable  # Ubuntu
sudo firewall-cmd --add-service=ssh --permanent && sudo firewall-cmd --reload  # Amazon Linux

# EC2: detach security group, attach permissive one, fix, reattach
```

## Disk full recovery

```bash
# Immediate space reclamation
bash scripts/connect.sh run <target> "sudo journalctl --vacuum-size=500M"
bash scripts/connect.sh run <target> "docker system prune -af --volumes"  # if Docker
bash scripts/connect.sh run <target> "rm -rf ~/.npm"
bash scripts/connect.sh run <target> "sudo find /var/log -name '*.gz' -mtime +30 -delete"

# Find culprit
bash scripts/connect.sh run <target> "sudo du -sh /* 2>/dev/null | sort -rh | head -10"

# Restart failed services after freeing space
bash scripts/connect.sh run <target> "systemctl --failed --no-pager"
bash scripts/connect.sh run <target> "sudo systemctl reset-failed && sudo systemctl restart <svc>"
```

## Database migration rollback

```bash
# Automated rollback
bash scripts/connect.sh run <target> "cd ~/<app> && npm run migrate:rollback && sudo systemctl restart <svc>"

# Manual: snapshot DB first, write reverse migration, test on dev, apply to prod
```

## Broken dependency recovery

```bash
# Node.js
bash scripts/connect.sh run <target> "cd ~/<app> && rm -rf node_modules package-lock.json && npm cache clean --force && npm install"

# Check version mismatch
bash scripts/connect.sh run <target> "node --version; cat ~/<app>/.nvmrc 2>/dev/null || cat ~/<app>/package.json | grep '\"node\":'"
```

## SSL certificate renewal failure

```bash
bash scripts/connect.sh run <target> "sudo certbot certificates; sudo certbot renew --dry-run"

# nginx blocking port 80
bash scripts/connect.sh run <target> "sudo systemctl stop nginx && sudo certbot renew && sudo systemctl start nginx"

# DNS wrong: check `dig <domain>` matches server IP, fix DNS, wait 5-30min
# Rate limit: wait 7 days (5 certs/week limit)
```

## Service stuck/won't restart

```bash
# Force kill
bash scripts/connect.sh run <target> "sudo systemctl kill --signal=SIGKILL <svc> && sudo systemctl reset-failed <svc> && sudo systemctl start <svc>"

# If still stuck
bash scripts/connect.sh run <target> "ps aux | grep <svc-name>"
bash scripts/connect.sh run <target> "sudo kill -9 <pid> && sudo systemctl reset-failed && sudo systemctl start <svc>"

# Check for D state (uninterruptible sleep) — reboot required
bash scripts/connect.sh run <target> "ps aux | awk '\$8 ~ /D/ {print}'"
```

## Git conflicts during deploy

```bash
# Stash local changes, pull, pop
bash scripts/connect.sh run <target> "cd ~/<app> && git stash && git pull origin <branch> && git stash pop"

# Preserve .env, reset code
bash scripts/connect.sh run <target> "cd ~/<app> && cp .env /tmp/env.bak && git reset --hard origin/<branch> && cp /tmp/env.bak .env"

# Save local changes as patch before hard reset
bash scripts/connect.sh run <target> "cd ~/<app> && git diff > /tmp/local-changes.patch && git reset --hard origin/<branch>"
```

## Recovery after interrupted operation

```bash
# Assess state
bash scripts/connect.sh run <target> "systemctl status <svc> --no-pager"
bash scripts/connect.sh run <target> "cd ~/<app> && git status; ls -lt | head -10"
bash scripts/connect.sh run <target> "ps aux | grep -E '(npm|node|yarn|build)'"

# Build process still running: wait 2-5min
# Build killed: clean and restart
bash scripts/connect.sh run <target> "pkill -f 'npm.*build'; cd ~/<app> && rm -rf dist/ && npm run build && sudo systemctl restart <svc>"

# Git in weird state
bash scripts/connect.sh run <target> "cd ~/<app> && git rebase --abort 2>/dev/null; git merge --abort 2>/dev/null; git status"
```
