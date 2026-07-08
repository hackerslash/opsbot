# Observability & APM

## Critical gotchas

- **Agent must report to backend** — `datadog-agent status` shows connectivity, not just systemctl
- **Trace sampling rate** — default 10% can miss rare errors; increase in config for low-traffic services
- **Jaeger spans need clock sync** — NTP drift >1s breaks distributed trace assembly
- **Loki label cardinality** — high cardinality labels (request_id) cause query performance collapse
- **OTel collector buffer** — default 10MB queue fills fast under load, tune `sending_queue.queue_size`

## Quick triage

```bash
systemctl status datadog-agent newrelic-infra
sudo datadog-agent status  # connectivity check
sudo journalctl -u datadog-agent -n 50
tail -50 /var/log/app/error.log | grep -E "(ERROR|FATAL)"
```

## Datadog

```bash
# Agent status & troubleshooting
sudo datadog-agent status  # connectivity, integrations
sudo datadog-agent check nginx
sudo datadog-agent configcheck

# Query metrics (dogshell CLI)
dog metric query --from $(date -d '1 hour ago' +%s) --to $(date +%s) 'avg:system.cpu.user{host:prod.api}'
```

## New Relic

```bash
# Query NRQL
newrelic nrql query --profile prod --query "SELECT count(*) FROM Transaction WHERE appName='prod-api' SINCE 1 hour ago"
```

## Grafana Loki

```bash
export LOKI_ADDR=https://loki.example.com
logcli query '{job="app"} |= "ERROR"' --since=1h --limit=50
logcli query '{job="app"}' --follow  # live tail
```

## OpenTelemetry

```bash
# Collector
curl -L https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.91.0/otelcol_0.91.0_linux_amd64.tar.gz | tar xz
sudo mv otelcol /usr/local/bin/
otelcol --config=/etc/otel-collector-config.yaml
curl http://localhost:13133/  # health
```

## Jaeger

```bash
# Query traces
curl "http://jaeger.example.com:16686/api/traces?service=api-service&limit=20"
curl "http://jaeger.example.com:16686/api/traces?service=api-service&minDuration=1000ms"  # slow traces
```

## Sentry

```bash
curl -sL https://sentry.io/get-cli/ | bash
sentry-cli --auth-token <token> issues list -p <project> --status unresolved
```

## Troubleshooting

**Agent not reporting:**
- `sudo datadog-agent status | grep "API Keys"`
- `sudo datadog-agent configcheck`
- Check firewall: `curl -v https://api.datadoghq.com`

**High agent overhead:**
- `ps aux | grep datadog` — check CPU/MEM%
- Increase `min_collection_interval` in /etc/datadog-agent/datadog.yaml

**Missing custom metrics:**
- `sudo netstat -ulnp | grep 8125` — DogStatsD listener
- Test: `echo -n "custom.metric:1|c" | nc -u -w1 localhost 8125`
