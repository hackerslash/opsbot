# Troubleshooting — common failure patterns and fixes

## Critical gotchas

- Inode exhaustion: `df -h` shows space but writes fail — check `df -i`
- Connection tracking full causes random drops despite correct firewall rules — check `nf_conntrack_count`
- D state processes can't be killed — waiting on I/O, reboot required
- ALB 502: check target health, security group must allow ALB SG not 0.0.0.0/0
- Empty service endpoints = selector mismatch (K8s)

## Service starts but immediately crashes

```bash
bash scripts/connect.sh run <target> "journalctl -u <svc> -n 100 --no-pager"
# EADDRINUSE → ss -tlnp | grep :<port>
# Cannot find module → npm ci && npm run build
# Check WorkingDirectory, port <1024 needs CAP_NET_BIND_SERVICE, missing .env
```

## Intermittent 502/504 from nginx

```bash
bash scripts/connect.sh run <target> "sudo tail -50 /var/log/nginx/error.log | grep -E '(502|504|upstream)'"
bash scripts/connect.sh run <target> "systemctl status <app-svc> --no-pager"
# App restarting under load, upstream timeout too low, connection queue full
```

## SSH works but HTTP/HTTPS times out

```bash
bash scripts/connect.sh run <target> "sudo nginx -t && systemctl status nginx --no-pager"
bash scripts/connect.sh run <target> "ss -tlnp | grep -E ':(80|443)'"
curl -v --max-time 5 https://<domain>/
# Security group blocks 80/443, firewall, nginx listening on 127.0.0.1 not 0.0.0.0, DNS wrong
```

## Disk space but writes fail

```bash
bash scripts/connect.sh run <target> "df -h; df -i"
# Out of inodes (100% IUsed) - find dirs with most files
bash scripts/connect.sh run <target> "sudo find / -xdev -type d -exec sh -c 'echo \$(ls -1 {} | wc -l) {}' \; 2>/dev/null | sort -rn | head -20"
```

## High load but low CPU

```bash
bash scripts/connect.sh run <target> "uptime; iostat -x 1 3"
# I/O wait - look for high %util, disk full/slow, swap thrashing, NFS stalled
```

## SSL cert installed but shows old/expired

```bash
bash scripts/connect.sh run <target> "sudo systemctl reload nginx && sleep 2 && echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates"
curl -vI https://<domain>/ 2>&1 | grep -E '(expire|issuer)'
# nginx not reloaded, wrong cert path, CDN caching
```

## Random disconnects under load

```bash
bash scripts/connect.sh run <target> "sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max"
bash scripts/connect.sh run <target> "dmesg | grep -i 'nf_conntrack: table full'"
bash scripts/connect.sh run <target> "sudo sysctl -w net.netfilter.nf_conntrack_max=262144"
```

## Deploy succeeds but site shows old code

```bash
bash scripts/connect.sh run <target> "cd <app-dir> && git rev-parse --short HEAD"
bash scripts/connect.sh run <target> "ls -lh <app-dir>/dist/ | head -10"
bash scripts/connect.sh run <target> "systemctl show <svc> -p ActiveEnterTimestamp"
# Build failed, service not restarted, PM2 multiple instances, browser cache
```

## Database connection pool exhausted

```bash
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT count(*) FROM pg_stat_activity; SHOW max_connections;\""
bash scripts/connect.sh run <target> "mysql -u<user> -p<pass> -e 'SHOW STATUS LIKE \"Threads_connected\"; SHOW VARIABLES LIKE \"max_connections\";'"
# Connection leak, pool config mismatch, multiple instances × pool > DB max
```

## "Permission denied" even with sudo

```bash
bash scripts/connect.sh run <target> "sudo -l"
bash scripts/connect.sh run <target> "ls -l /etc/sudoers.d/"
# Typo in sudoers (fix from console), /etc/sudoers.d/ must be 440, SELinux blocking
```
