# Monitoring — alerts, SLOs, dashboards, on-call

## Critical gotchas

- **datapoints-to-alarm vs evaluation-periods** — eval 3 with datapoints 2 means "2 of last 3" (less flappy)
- **composite alarms** — AND/OR logic across alarms; use for "CPU high AND disk full" conditions
- **SLO burn rate** — fast burn (10x) alerts in 5min, slow burn (5x) alerts in 1h
- **Alert fatigue audit** — monthly review: which fired but weren't incidents? Which incidents had no alert?
- **Prometheus recording rules** — pre-compute expensive queries or alerts will lag

## Quick triage

```bash
aws cloudwatch describe-alarms --state-value ALARM
aws cloudwatch describe-alarm-history --start-date $(date -u -d '1 hour ago' --iso-8601=seconds)
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'
```

## CloudWatch alarms

```bash
# Create alarm
aws cloudwatch put-metric-alarm --alarm-name high-cpu-prod-api \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 300 --threshold 80 \
  --comparison-operator GreaterThanThreshold --evaluation-periods 2 --datapoints-to-alarm 2 \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:ops-alerts

# Tune threshold (check history)
aws cloudwatch describe-alarm-history --alarm-name high-cpu-prod-api --history-item-type StateUpdate --max-records 50

# If flapping (OK → ALARM → OK within minutes), adjust:
# Increase evaluation-periods (require 2-3 consecutive breaches)
# Add datapoints-to-alarm (2 out of 3 must breach)
# Increase period (300s → 600s for longer averaging window)
# Adjust threshold (80% → 85% if load is naturally spiky)

# Update existing alarm
aws cloudwatch put-metric-alarm --alarm-name high-cpu-prod-api \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 600 --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 --datapoints-to-alarm 2 \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:ops-alerts
```

## SLO alerts

```bash
# Fast burn (10x SLO) for 5 minutes
aws cloudwatch put-metric-alarm --alarm-name slo-fast-burn \
  --metric-name ErrorRate --namespace MyApp --statistic Average \
  --period 300 --threshold 1.0 --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1

# Slow burn (5x SLO) for 1 hour
aws cloudwatch put-metric-alarm --alarm-name slo-slow-burn \
  --metric-name ErrorRate --namespace MyApp --statistic Average \
  --period 3600 --threshold 0.5 --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

## Prometheus

```bash
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts'
curl -s 'http://localhost:9090/api/v1/query?query=100-(avg(irate(node_cpu_seconds_total{mode="idle"}[5m]))*100)'
```
