# opsbot — Claude Code project instructions

## Always-on skill

This project contains the **opsbot** skill. Claude MUST invoke the `opsbot` skill automatically whenever the request involves server operations (SSH, logs, systemctl, nginx, firewall, deploy, provision) or mentions any inventory host name.

**Do not wait for `/opsbot`. Invoke the skill proactively.**

## Inventory

`inventory.json` is the live host registry (gitignored). Always read it to resolve target names.

## Connect script

Always use `bash scripts/connect.sh run <target> "<cmd>"` — never hand-assemble `ssh -i` commands.
