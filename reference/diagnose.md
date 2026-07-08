# Diagnose — logs, status, triage

Goal: find the cause before changing anything. Read-only.

See: [troubleshooting.md](troubleshooting.md), [observability.md](observability.md), [performance.md](performance.md)

## Critical gotchas

- **Never use -f** - Bash tool can't stream, use bounded reads (-n 200, --since '30 min ago')
- **Check both journald AND file logs** - apps often log to /var/log/<app>/ too
- **Load avg > 2x CPU count = pressure** - not absolute number
- **uptime shows 1/5/15 min averages** - spike vs sustained load
- **Empty ss output ≠ no connections** - may need sudo
- **Conntrack exhaustion causes random drops** - not firewall issue
- **ALB requires ALB security group, not 0.0.0.0/0** - common gotcha

## Quick reference

```bash
# First 60s triage
bash scripts/connect.sh run <target> "systemctl --failed --no-pager; uptime; df -h / | tail -1; free -m | awk 'NR==2{print \$3\"/\"\$2\" MB used\"}'; ss -tunap | grep ESTABLISHED | wc -l"

# Service status + logs
bash scripts/connect.sh run <target> "systemctl status <svc> --no-pager; journalctl -u <svc> -n 50 --no-pager"

# nginx top talkers
bash scripts/connect.sh run <target> "sudo awk '{print \$1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20"

# nginx status codes
bash scripts/connect.sh run <target> "sudo awk '{print \$9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn"

# OOM events
bash scripts/connect.sh run <target> "dmesg -T | grep -i 'killed process' | tail -10"

# Conntrack exhaustion
bash scripts/connect.sh run <target> "cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max"
```

## Logs

```bash
# Bounded reads (never -f)
journalctl -u <svc> -n 200 --no-pager
journalctl -u <svc> --since '30 min ago' --no-pager
journalctl -u <svc> -p err -n 100 --no-pager

# Application file logs
bash scripts/connect.sh run <target> "tail -100 /var/log/<app>/error.log"

# Docker
bash scripts/connect.sh run <target> "docker logs <container> --tail 200"
```

## Triage patterns

### Service dead

Status: inactive (dead) or failed.

```bash
bash scripts/connect.sh run <target> "journalctl -u <svc> -n 200 --no-pager"
```

MODULE_NOT_FOUND (missing deps), EADDRINUSE (`ss -tlnp | grep :<port>`), OOM kill (`dmesg -T | grep 'killed process'`), bad .env (check `systemctl cat <svc>` EnvironmentFile, verify 600 perms), ExecStart path wrong (/usr/bin/node not /usr/local/bin/node)

### Service up but unresponsive

Status: running, requests timeout/502/504.

```bash
bash scripts/connect.sh run <target> "ps aux | grep <app>; ss -tlnp | grep :<port>; top -bn1 | grep <app>"
bash scripts/connect.sh run <target> "sudo tail -50 /var/log/nginx/error.log"
```

CPU/memory pressure, upstream timeout, nginx 502 (upstream dead), nginx 504 (too slow), request flood, DB pool exhausted

### Unreachable from outside

`curl localhost:8000` works, `curl https://domain.com` fails.

```bash
bash scripts/connect.sh run <target> "ss -tlnp | grep :80; ss -tlnp | grep :443; sudo nginx -t"
aws ec2 describe-instances --instance-ids <i-xxx> --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId'
```

AWS SG blocks 80/443, firewall blocks (ufw/firewalld), nginx binding 127.0.0.1 not public, DNS wrong, TLS cert expired

### Intermittent failures

```bash
bash scripts/connect.sh run <target> "cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max"
bash scripts/connect.sh run <target> "cat /proc/sys/fs/file-nr; vmstat 1 5"
```

conntrack exhaustion (count > 80% of max), ephemeral port exhaustion, file descriptor limit, swap thrashing, DB pool exhausted

## Resource pressure

```bash
# CPU
bash scripts/connect.sh run <target> "top -bn1 | head -20; vmstat 1 5"

# Memory
bash scripts/connect.sh run <target> "free -m; ps aux --sort=-%mem | head -10"

# Disk space
bash scripts/connect.sh run <target> "df -h; sudo du -hx / --max-depth=2 | sort -h | tail -10"

# Disk I/O
bash scripts/connect.sh run <target> "iostat -x 1 5; iotop -bn1 | head -20"
```

## Port conflict (EADDRINUSE)

```bash
bash scripts/connect.sh run <target> "ss -tlnp | grep :<port>"
# Kill process or change app port
```

## Conntrack exhaustion

Random drops despite firewall allowing traffic. Not a firewall issue.

```bash
bash scripts/connect.sh run <target> "cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max"
# If count > 80% of max:
bash scripts/connect.sh run <target> "sudo sysctl -w net.netfilter.nf_conntrack_max=262144"
# Permanent: echo 'net.netfilter.nf_conntrack_max = 262144' | sudo tee -a /etc/sysctl.conf; sudo sysctl -p
```

## AWS security group gotcha

SSH works, HTTP/HTTPS blocked.

**ALB setup**: Instance SG must allow ALB's security group, not 0.0.0.0/0.

```bash
aws ec2 describe-instances --instance-ids <i-xxx> --query 'Reservations[0].Instances[0].SecurityGroups[*].[GroupId,GroupName]' --output table
aws ec2 describe-security-groups --group-ids <sg-xxx> --query 'SecurityGroups[0].IpPermissions' --output table
```

See [networking.md](networking.md) for full VPC debugging.
