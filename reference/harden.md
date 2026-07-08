# Harden — SSH, fail2ban, firewall, blocking attackers

## Under active attack — escape hatches

SSH may be dead under a flood. Two ways in that bypass SSH entirely:
- **Cloud console**: Lightsail browser SSH, EC2 Instance Connect, or SSM session — no SSH needed.
- **Provider firewall**: block the IP at the Lightsail/EC2 security group — no server access needed at all.

## Order of operations

**Stop the bleeding first, then harden:** block the IP → nginx rate limiting → fail2ban → SSH limits.

Find the attacker IP first (read-only):
```bash
bash scripts/connect.sh run <target> "sudo awk '{print \$1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20"
```

## Block an IP (pick by OS — see [os-matrix.md](os-matrix.md))

```bash
# Ubuntu
sudo ufw insert 1 deny from <IP> to any
# Amazon Linux 2023
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='<IP>' reject" && sudo firewall-cmd --reload
```

## fail2ban gotchas

**Ubuntu `jail.conf` ships `maxretry = 150` for sshd** — this is useless. Always override it to 5 with a drop-in in `jail.d/`.

**AL2023:** fail2ban sshd reads journald (`backend = systemd`). Do **not** override `logpath` for sshd on AL2023 — the default handles journald correctly and overriding it with `/var/log/auth.log` breaks it.

**`nginx-limit-req` jail shows "does not exist"** after enabling: fail2ban didn't reload — use `restart`, not `reload` (`systemctl restart fail2ban`). Verify each jail: `sudo fail2ban-client status sshd`.

## SSH daemon limits (drop-in, doesn't touch sshd_config)

```bash
sudo tee /etc/ssh/sshd_config.d/99-harden.conf > /dev/null <<'EOF'
MaxStartups 5:50:15
LoginGraceTime 30
EOF
sudo sshd -t && sudo systemctl reload sshd   # Ubuntu: reload ssh
```

`sshd -t` validates before reload — skip this and a typo locks you out.

## Verify

```bash
bash scripts/connect.sh run <target> "sudo fail2ban-client status; sudo ufw status verbose 2>/dev/null || sudo firewall-cmd --list-all"
```

Tell the user what's left in a non-default state (any blocked IPs, changed limits).
