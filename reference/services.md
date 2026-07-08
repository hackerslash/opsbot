# Services — systemd units

## Inspect

```bash
bash scripts/connect.sh run <target> "systemctl --no-pager status <svc>"
bash scripts/connect.sh run <target> "systemctl cat <svc>"
```

## Restart / stop / start (MUTATING — confirm first; prod needs --confirm-prod)

After any restart, always re-check status:
```bash
bash scripts/connect.sh run <target> "systemctl --no-pager --lines=20 status <svc>"
```

## Create unit

Match `User=` to OS (ec2-user/ubuntu/admin - see [os-matrix.md](os-matrix.md)). Then `daemon-reload && enable --now <svc>`.

## Gotchas

- **Editing a unit file requires `daemon-reload` before restart** — systemd won't pick up the change otherwise.
- **`Restart=always` masks startup failures** — if the app keeps crashing and restarting, `status` may show "active" while journalctl shows errors. Always read the logs, not just the status.
- **`Cannot find module` in logs** = build artifact missing. Build before starting (see [deploy.md](deploy.md)).

## Passwordless restart for CI (sudoers)

```bash
echo '<user> ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart <svc>, /usr/bin/systemctl status <svc>' | sudo tee /etc/sudoers.d/<app>-deploy
sudo chmod 440 /etc/sudoers.d/<app>-deploy && sudo visudo -c
```

**`visudo -c` must pass** — a broken sudoers file locks out all sudo on the box.
