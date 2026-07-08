# nginx — reverse proxy, rate limiting, TLS

## The golden rule

**Never `restart` when `reload` works** — reload is zero-downtime. **Never reload without `nginx -t`.**

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Inspect current config

```bash
bash scripts/connect.sh run <target> "nginx -T 2>/dev/null | head -120"
bash scripts/connect.sh run <target> "cat /etc/nginx/sites-enabled/* 2>/dev/null"
```

Two layouts: Ubuntu uses `sites-available`+`sites-enabled`; AL2023 uses `conf.d/*.conf`.

## Rate limiting — the parts that bite

`limit_req_zone` **must live in the `http` context**, defined **before** the `server` blocks that reference it. Use `conf.d/00-rate-limit.conf` — the `00-` prefix guarantees it loads before `sites-enabled`:

```nginx
# /etc/nginx/conf.d/00-rate-limit.conf
limit_req_zone $binary_remote_addr zone=one:10m rate=800r/m;
limit_req_status 429;
```

Then inside the `server` or `location` block: `limit_req zone=one burst=200 nodelay;`

**NAT trap:** `$binary_remote_addr` is the client IP. An entire office behind one public IP shares a single bucket — everyone hits the same limit. Set the rate for the busiest shared origin, not a single user.

**Test with parallel curl, not sequential** — sequential requests are too slow to exhaust the burst (tokens refill between requests):
```bash
for i in $(seq 1 250); do curl -s -o /dev/null -w "%{http_code}\n" https://<domain>/ & done | sort | uniq -c; wait
```

## certbot gotcha

certbot rewrites the server block in place and adds a new `:443 ssl` block. After running certbot, `location /` moves into the HTTPS block. Re-read the config before injecting any directives:
```bash
bash scripts/connect.sh run <target> "cat /etc/nginx/sites-enabled/<site>"
```

Always back up before editing: `sudo cp <file> <file>.bak.$(date +%s)`.

## TLS renewal

```bash
bash scripts/connect.sh run <target> "sudo certbot renew --dry-run"
bash scripts/connect.sh run <target> "sudo systemctl status certbot-renew.timer --no-pager"
```

After any renewal, nginx must reload to pick up the new cert.
