# Fleet — multi-host operations

## Critical gotchas

- **Never restart all hosts simultaneously** — do sequentially with verification between each
- **Never mix prod/non-prod in same command** — `--confirm-prod` flag required for prod
- **Config drift detection** — compare checksums across fleet before assuming consistency
- **Canary pattern** — deploy to one host, verify 10-15min, then roll out to rest
- **Log aggregation requires single-arg quoting** — `"grep ERROR /var/log/app.log"` not unquoted

## Quick reference

```bash
# Health sweep
bash scripts/connect.sh run --env dev --all --timeout 5 "systemctl --failed --no-pager; df -h / | tail -1"

# Version check
bash scripts/connect.sh run --tags api --all "cd ~/app && git rev-parse --short HEAD"

# Service status
bash scripts/connect.sh run --env uat --all "systemctl is-active app-api || echo FAILED"
```

## Fleet health sweep

```bash
bash scripts/connect.sh run --env <env> --all --timeout 5 \
  "systemctl --failed --no-pager; uptime; df -h / | tail -1; free -m | awk 'NR==2{print \$3\"/\"\$2\" MB used\"}'"
```

Pattern recognition: all workers failing = upstream dependency, one host = host-specific issue.

## Version consistency

```bash
bash scripts/connect.sh run --env prod --tags api --all "cd ~/app && git rev-parse HEAD"
```

## Config drift detection

```bash
# .env checksum comparison
bash scripts/connect.sh run --env prod --tags api --all "test -f ~/app/.env && md5sum ~/app/.env || echo 'Missing'"

# Nginx config comparison
bash scripts/connect.sh run --tags nginx --all "sudo nginx -T 2>/dev/null | grep -E 'limit_req_zone|ssl_certificate'"

# Systemd unit comparison
bash scripts/connect.sh run --env dev --tags api --all "systemctl cat app-api | grep -E '^ExecStart=|^Environment='"
```

## Rolling restart

```bash
# 1. Restart first host, verify
bash scripts/connect.sh run api-01.prod "sudo systemctl restart app-api && sleep 5 && curl -sf http://localhost:8000/healthz"

# 2. Proceed to next if healthy
bash scripts/connect.sh run api-02.prod "sudo systemctl restart app-api && sleep 5 && curl -sf http://localhost:8000/healthz"
```

## Canary deploy

```bash
# 1. Deploy to canary
bash scripts/connect.sh run api-01.prod "cd ~/app && git pull && npm ci && npm run build && sudo systemctl restart app-api"

# 2. Verify (wait 10-15min, watch monitoring)
bash scripts/connect.sh run api-01.prod "systemctl is-active app-api && curl -sf http://localhost:8000/healthz"

# 3. If healthy, deploy to rest one at a time
bash scripts/connect.sh run api-02.prod "cd ~/app && git pull && npm ci && npm run build && sudo systemctl restart app-api"
```

## Troubleshooting patterns

**All hosts failing:**
- Upstream dependency down (DB, Redis, external API)
- Shared config issue (bad .env via SSM sync)
- Network-level (security group, NAT gateway, DNS)

**One host outlier:**
- Config drift (compare .env checksums)
- Deployment lag (check git HEAD across fleet)
- Resource pressure (memory/disk specific to that host)

**Gradual degradation:**
- Memory leak (track RSS growth over days)
- Disk growth (log rotation failing)
- Connection pool exhaustion (track active connections)
