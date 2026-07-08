# Deploy & rollback

For Kubernetes GitOps deployments (ArgoCD, Flux, Helm), see [gitops.md](gitops.md).

## Standard deploy

**Always use the project's own `deploy/deploy.sh` if it exists.** It encodes the correct build order and preserves `.env`. Only hand-run steps if there's no deploy script.

```bash
bash scripts/connect.sh run <target> "cd ~/<app> && ./deploy/deploy.sh [<branch>]"
```

## Verify after deploy

```bash
bash scripts/connect.sh run <target> "systemctl --no-pager --lines=20 status <svc>"
curl -s -o /dev/null -w "%{http_code}\n" https://<domain>/healthz
bash scripts/connect.sh run <target> "cd ~/<app> && git rev-parse --short HEAD"
```

## Rollback

```bash
bash scripts/connect.sh run <target> "cd ~/<app> && git reset --hard HEAD~1 && npm ci && npm run build && sudo systemctl restart <svc>"
```

Or to a specific known-good commit: `git reset --hard <sha>`. Re-verify after.

## OOM during build

`Killed` in the middle of `npm ci` or `npm run build` = out of memory, not a code error. Add swap then rebuild (one-shot — see [maintenance.md](maintenance.md) to make it permanent):

```bash
bash scripts/connect.sh run <target> "sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
```

## Zero-downtime patterns

**`systemctl restart` has a brief gap.** For services that must not drop connections:

- **Graceful reload:** add `ExecReload=/bin/kill -HUP $MAINPID` + `KillSignal=SIGTERM` + `TimeoutStopSec=30` to the unit. Then use `systemctl reload <svc>` — not restart. Run `daemon-reload` after editing the unit file.
- **PM2:** `pm2 reload --update-env` is zero-downtime (forks a new process, waits for ready, kills the old). `pm2 restart` drops connections — don't use it for prod.
- **Blue-green:** two instances on different ports (e.g. :8000 and :8001), nginx proxies to the active one. Before swapping: grep current `proxy_pass` to confirm which is live. Then `sed` the upstream and `nginx -t && systemctl reload nginx`.

## Database migrations

**Apply schema changes before restarting the service**, not after. The running code must be compatible with both old and new schema during the migration window.

```bash
# 1. Deploy code (no restart yet)
bash scripts/connect.sh run <target> "cd ~/<app> && git reset --hard origin/<branch> && npm ci && npm run build"
# 2. Run migrations
bash scripts/connect.sh run <target> "cd ~/<app> && npm run migrate"
# 3. Only then restart
bash scripts/connect.sh run <target> "sudo systemctl restart <svc>"
```

## Prod

Every prod deploy/rollback is a **separate, explicit confirmation** naming the host (`--confirm-prod`). Deploy and verify on dev/uat first.
