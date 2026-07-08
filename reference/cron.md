# Cron jobs & systemd timers

**Prefer systemd timers** over cron on modern distros — they log to journald automatically, handle missed runs with `Persistent=true`, and integrate with systemctl.

## List all scheduled work

```bash
bash scripts/connect.sh run <target> "systemctl list-timers --all --no-pager"
bash scripts/connect.sh run <target> "crontab -l 2>/dev/null; sudo crontab -l 2>/dev/null; ls /etc/cron.d/ 2>/dev/null"
```

## Debug a timer

```bash
# Last run output and next scheduled time
bash scripts/connect.sh run <target> "systemctl list-timers <name>.timer --no-pager"
bash scripts/connect.sh run <target> "sudo journalctl -u <name>.service -n 50 --no-pager"
```

## Run a timer right now for testing

Start the `.service`, **not** the `.timer`:
```bash
bash scripts/connect.sh run <target> "sudo systemctl start <name>.service"
bash scripts/connect.sh run <target> "sudo journalctl -u <name>.service -n 30 --no-pager"
```

## Create a systemd timer (MUTATING — confirm first)

Two files: `.service` (what runs) and `.timer` (when). Use [services.md](services.md) for the service unit template with `Type=oneshot`. Timer file:

```ini
[Timer]
OnCalendar=*-*-* 03:00:00   # daily at 3am
Persistent=true              # catch up on missed runs after reboot

[Install]
WantedBy=timers.target
```

Then `daemon-reload && systemctl enable --now <name>.timer`.

## Cron pitfalls (if you must use cron)

- **No PATH** — cron runs with a minimal PATH. Use absolute paths: `/usr/bin/node`, `/usr/bin/aws`, not `node`.
- **No HOME** — environment isn't set. Source the app's `.env` or export variables explicitly.
- **Silent failures** — redirect output: `command >> /var/log/job.log 2>&1`. Systemd timers log to journald automatically.
- **Time zone** — cron uses system time. Confirm: `bash scripts/connect.sh run <target> "timedatectl"`.
