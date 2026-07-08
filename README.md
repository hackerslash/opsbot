# opsbot

A DevOps agent skill that turns Claude, Codex, and Antigravity into a careful senior
DevOps engineer for your fleet. It connects to remote hosts (SSH via PEM key + IP, or
AWS SSM), inspects and operates them, and follows battle-tested procedures for
diagnosis, deployment, nginx, security hardening, and provisioning.

## Layout

- `SKILL.md` - entry point
- `scripts/connect.sh` - SSH/SSM abstraction
- `reference/*.md` - task guides (loaded on demand)
- `inventory.json` - your hosts (gitignored, copy from inventory.example.json)

## Requirements

- `jq` (required)
- `aws` CLI (SSM targets only)

## Bastion / jump-host support

Add a `"bastion"` field to any target pointing to another inventory entry. `connect.sh` will tunnel through that host automatically via `ProxyCommand` — no extra flags needed.

```json
"bastion": { "host": "203.0.113.10", "user": "ubuntu", "key": "bastion.pem", ... },
"prod.private.1": { "host": "10.0.1.50", "key": "prod.pem", "bastion": "bastion", ... }
```

```bash
bash scripts/connect.sh run prod.private.1 "uptime"   # tunnels through bastion silently
bash scripts/connect.sh ssh prod.private.1            # prints the full ProxyCommand line
```

## Changelog

See git history for full changelog.
