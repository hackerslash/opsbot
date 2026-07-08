# Logging — structured logging, aggregation, retention

## Critical gotchas

- JSON logs are queryable, text logs aren't — use structured logging
- Never log at INFO in hot paths (1000 req/s = 86M logs/day) — sample 1% or use DEBUG
- journalctl `-f` can't run through agent — print ssh command for user to run interactively
- CloudWatch needs IAM: `logs:CreateLogStream`, `logs:PutLogEvents`
- journald vacuum is immediate and safe: `journalctl --vacuum-size=1G`

## journalctl patterns

```bash
# Service logs, last 200 lines
bash scripts/connect.sh run <target> "journalctl -u <svc> -n 200 --no-pager"

# Since timestamp
bash scripts/connect.sh run <target> "journalctl -u <svc> --since '2024-06-26 14:00:00' --no-pager"

# Errors only (priority 0-3)
bash scripts/connect.sh run <target> "journalctl -u <svc> -p err --no-pager"

# Follow (print ssh command for user)
bash scripts/connect.sh ssh <target>   # user runs: journalctl -u <svc> -f

# All logs since last boot
bash scripts/connect.sh run <target> "journalctl -b --no-pager | head -500"
```

## Application log files

```bash
# Tail (bounded, not -f)
bash scripts/connect.sh run <target> "tail -200 /var/log/app/production.log"

# Search for errors
bash scripts/connect.sh run <target> "grep -i error /var/log/app/production.log | tail -50"

# Count by log level (structured JSON)
bash scripts/connect.sh run <target> "jq -r .level /var/log/app/production.log 2>/dev/null | sort | uniq -c"
```

## CloudWatch Logs

```bash
# List log groups
aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output table

# List log streams (most recent first)
aws logs describe-log-streams --log-group-name <group> --order-by LastEventTime --descending --max-items 10

# Tail log stream (last 100 events)
aws logs get-log-events --log-group-name <group> --log-stream-name <stream> --limit 100 --output text

# Insights query
aws logs start-query \
  --log-group-name <group> \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50'

# Get query results (wait 5-10s after start-query)
aws logs get-query-results --query-id <queryId>
```

## journald disk usage

```bash
# Current size
bash scripts/connect.sh run <target> "sudo journalctl --disk-usage"

# Limit to 1GB (immediate)
bash scripts/connect.sh run <target> "sudo journalctl --vacuum-size=1G"

# Limit to 7 days (immediate)
bash scripts/connect.sh run <target> "sudo journalctl --vacuum-time=7d"

# Make limit permanent
bash scripts/connect.sh run <target> "echo 'SystemMaxUse=1G' | sudo tee -a /etc/systemd/journald.conf && sudo systemctl restart systemd-journald"
```

## Log rotation

```bash
# Check logrotate config
bash scripts/connect.sh run <target> "cat /etc/logrotate.d/<app> 2>/dev/null || echo 'No logrotate config'"

# Force rotation (test)
bash scripts/connect.sh run <target> "sudo logrotate -vf /etc/logrotate.d/<app>"
```

## Centralized logging

- **Fluent Bit**: reads files/journald/containers → CloudWatch/Elasticsearch/S3 (config: `/etc/fluent-bit/fluent-bit.conf`)
- **ECS/Docker**: use `awslogs` log driver (built-in, no Fluent Bit needed)

## Debugging missing logs

**App logs not in journalctl?**
- Check service unit: `StandardOutput=journal`, `StandardError=journal`
- Verify service running: `systemctl status <svc>`
- Check if app writes to file instead of stdout/stderr

**CloudWatch logs missing?**
- IAM needs `logs:CreateLogStream`, `logs:PutLogEvents`
- Check log driver: `docker inspect <container> | jq '.[0].HostConfig.LogConfig'`
- CloudWatch agent running: `systemctl status amazon-cloudwatch-agent`
