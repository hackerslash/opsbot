# Maintenance — disk, logs, swap, cache

## Disk triage

Start broad, drill down:

```bash
bash scripts/connect.sh run <target> "df -h; echo '---'; sudo du -sh /* 2>/dev/null | sort -rh | head -15"
```

Then drill into the offending directory. The two biggest surprise consumers on app servers: **npm cache** (`~/.npm`) and **Docker layers** (`docker system df`).

## journald

```bash
# How much space is journald using?
bash scripts/connect.sh run <target> "sudo journalctl --disk-usage"

# Free space immediately (MUTATING — confirm first)
bash scripts/connect.sh run <target> "sudo journalctl --vacuum-size=500M"
```

**Make the limit permanent** (otherwise it fills back up):
```bash
bash scripts/connect.sh run <target> \
  "echo 'SystemMaxUse=1G' | sudo tee -a /etc/systemd/journald.conf && sudo systemctl restart systemd-journald"
```

## Swap

The one-shot swap in [deploy.md](deploy.md) doesn't survive reboot. To make it permanent, add to `/etc/fstab`:

```bash
bash scripts/connect.sh run <target> \
  "grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
```

## logrotate

Test without rotating: `sudo logrotate --debug /etc/logrotate.conf`. Force immediate rotation: `sudo logrotate -f /etc/logrotate.conf`.

## After cleanup

Re-run `df -h` to confirm space was recovered. If the cause was missing log rotation or journald limits, ensure the permanent config is set so it doesn't happen again.
