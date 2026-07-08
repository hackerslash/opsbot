# SSL certificates — audit, certbot, ACM

**Expired cert = instant production outage.** Audit before incidents, not during.

## Fleet expiry audit (run locally — not via connect.sh)

```bash
for domain in <domain1> <domain2>; do
  expiry=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" \
    </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  echo "$domain: $expiry"
done
```

Flag anything within 30 days. Run this monthly.

## certbot health

```bash
bash scripts/connect.sh run <target> "sudo certbot renew --dry-run 2>&1"
bash scripts/connect.sh run <target> "sudo systemctl status certbot-renew.timer --no-pager"
```

**If dry-run fails:** check port 80 is open and nginx is running — certbot uses the HTTP-01 challenge on `:80`.

**After renewal:** certbot edits the live file in place but **nginx must reload** to pick up the new cert. The `certbot-renew` systemd unit needs a `--deploy-hook "systemctl reload nginx"` or this will be forgotten.

**Force renew a specific cert:**
```bash
bash scripts/connect.sh run <target> \
  "sudo certbot renew --force-renewal -d <domain> && sudo nginx -t && sudo systemctl reload nginx"
```

## ACM certificates

`PENDING_VALIDATION` = the DNS CNAME record for domain validation is missing from your DNS provider. `aws acm describe-certificate --certificate-arn <arn>` shows the exact CNAME record to add. ACM picks it up within minutes of the record being live.

ACM auto-renews **only when associated with an ALB or CloudFront** — a cert sitting in ACM not attached to anything won't auto-renew.

## Verify from outside after any cert change

```bash
echo | openssl s_client -connect <domain>:443 -servername <domain> </dev/null 2>/dev/null | openssl x509 -noout -dates
curl -sk -o /dev/null -w "%{http_code}\n" https://<domain>/healthz
```
