# Performance — profiling, tracing, bottlenecks

## CPU profiling

**Never run `perf` or `strace -p` on prod without approval** — both add measurable overhead.

```bash
# Top processes by CPU (safe, read-only)
bash scripts/connect.sh run <target> "top -b -n 1 | head -20"

# Which process is using CPU right now?
bash scripts/connect.sh run <target> "ps aux --sort=-%cpu | head -10"
```

## Memory profiling

```bash
# Process memory breakdown
bash scripts/connect.sh run <target> "ps aux --sort=-%mem | head -10"

# Detailed memory usage by process
bash scripts/connect.sh run <target> "sudo pmap -x \$(pgrep -f 'node.*server') | tail -1"
```

## Network profiling

```bash
# Active connections by state
bash scripts/connect.sh run <target> "ss -s"

# Top talkers by connection count
bash scripts/connect.sh run <target> "ss -tn | awk 'NR>1 {print \$5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10"

# Bandwidth by process (requires nethogs)
bash scripts/connect.sh run <target> "sudo nethogs -t -d 2 2>/dev/null || echo 'nethogs not installed'"
```

## Disk I/O

```bash
# I/O wait time (high %wa = disk bottleneck)
bash scripts/connect.sh run <target> "iostat -x 1 3"

# Which process is doing I/O?
bash scripts/connect.sh run <target> "sudo iotop -b -n 1 -o 2>/dev/null | head -15 || echo 'iotop not installed'"
```

## Application-level

Node.js: `--inspect` flag + Chrome DevTools or clinic.js for flame graphs.
Python: `py-spy top --pid <pid>` (no restart needed, low overhead).
Go: `pprof` HTTP endpoint (`/debug/pprof/profile?seconds=30`).

Always profile in a staging environment first. Production profiling requires approval and a clear hypothesis — don't profile "to see what's slow", profile to confirm a specific theory.

## Load testing

**Never load test prod.** Use a dedicated staging env with prod-like traffic patterns.

```bash
# Quick load test with Apache Bench
ab -n 10000 -c 100 https://<domain>/

# More realistic with vegeta (variable rate)
echo "GET https://<domain>/" | vegeta attack -duration=30s -rate=50/s | vegeta report
```

## After finding the bottleneck

State what you found (CPU-bound? I/O-bound? Network saturation? Database N+1?), then route to the appropriate guide — might be [database.md](database.md) for query optimization, [nginx.md](nginx.md) for rate limiting, or [maintenance.md](maintenance.md) for resource limits.
