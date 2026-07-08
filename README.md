# opsbot

A DevOps agent skill that turns Claude, Codex, and Antigravity into a careful senior
DevOps engineer for your fleet. It connects to remote hosts (SSH via PEM key + IP, or
AWS SSM), inspects and operates them, and follows battle-tested procedures for
diagnosis, deployment, nginx, security hardening, and provisioning.

## Setup

1. Install `jq` (required), and the `aws` CLI if any of your targets use SSM instead of SSH.
2. Copy the inventory template and fill in your real hosts:

   ```bash
   cp inventory.example.json inventory.json
   ```

   Set `pem_dir` to the folder holding your `.pem` keys, then add one entry per host under `targets` — see `inventory.example.json` for SSH and SSM examples.
3. Open this repo in Claude Code, Codex, or Antigravity. `CLAUDE.md` makes the skill trigger automatically on any server-operations request — no `/opsbot` needed.

## Usage

Describe what you want in plain language and opsbot resolves the target from `inventory.json`, inspects before it mutates anything, and asks for explicit confirmation before any change — especially on a `prod` host:

- "ssh into prod.api.1 and check disk usage"
- "dev.api is being hit hard, harden it"
- "deploy the latest branch to uat.api"
- "why is nginx returning 429s on dev.web"

You can also drive it directly from the shell:

```bash
bash scripts/connect.sh list                       # list configured targets
bash scripts/connect.sh run <target> "<command>"    # run a one-off remote command
bash scripts/connect.sh ssh <target>                # open an interactive session
```

## Layout

- `SKILL.md` - entry point and task-guide routing table
- `scripts/connect.sh` - SSH/SSM abstraction
- `reference/*.md` - task guides (loaded on demand)
- `inventory.json` - your hosts (gitignored, copy from inventory.example.json)

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
