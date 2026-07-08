# Security — vulnerability scanning, compliance, incident response

## Vulnerability scanning

```bash
# Check for outdated packages with known CVEs (Ubuntu)
bash scripts/connect.sh run <target> "apt list --upgradable 2>/dev/null | grep -i security"

# Amazon Linux 2023 security updates
bash scripts/connect.sh run <target> "sudo dnf updateinfo list --security"

# Installed package versions (for manual CVE lookup)
bash scripts/connect.sh run <target> "dpkg -l | grep -E '(nginx|openssl|openssh)'"
```

## Port scanning (from outside)

```bash
# Quick external port check
nmap -Pn -p 22,80,443,8000-8080 <host-ip>

# Full TCP scan (slower, more thorough)
nmap -sS -p- <host-ip>
```

**Only scan hosts you own.** Scanning external/third-party infrastructure without permission is illegal in most jurisdictions.

## Intrusion detection

```bash
# Check for suspicious processes
bash scripts/connect.sh run <target> "ps aux | grep -vE '(grep|systemd|sshd|nginx|node)' | grep -E '(bash|sh|python|perl|nc|ncat)' | head -20"

# Recent sudo commands (audit trail)
bash scripts/connect.sh run <target> "sudo grep -E 'COMMAND=' /var/log/auth.log | tail -30 2>/dev/null || sudo journalctl -t sudo | tail -30"

# Recently modified files in /etc (config changes)
bash scripts/connect.sh run <target> "sudo find /etc -type f -mtime -7 -ls | head -20"

# Active SSH sessions (who else is logged in?)
bash scripts/connect.sh run <target> "who; w"

# Check for rogue cron jobs
bash scripts/connect.sh run <target> "sudo crontab -l; for u in \$(cut -d: -f1 /etc/passwd); do echo \"=== \$u ===\"&& sudo crontab -u \$u -l 2>/dev/null; done | grep -vE '^(#|$)'"
```

## File integrity

```bash
# Check if system binaries have been modified (Ubuntu/Debian)
bash scripts/connect.sh run <target> "sudo debsums -c 2>/dev/null | head -20 || echo 'debsums not installed'"

# AIDE (Advanced Intrusion Detection Environment) check
bash scripts/connect.sh run <target> "sudo aide --check 2>/dev/null | head -50 || echo 'AIDE not configured'"
```

## Compliance checks

**CIS Benchmarks** — automated scanner:
```bash
# Install lynis
bash scripts/connect.sh run <target> "command -v lynis || sudo apt install -y lynis 2>/dev/null || sudo dnf install -y lynis"

# Run audit (read-only, no changes)
bash scripts/connect.sh run <target> "sudo lynis audit system --quick"
```

Lynis reports hardening suggestions. Common findings: weak SSH config, missing SELinux/AppArmor, old kernel, unpatched packages.

## SSL/TLS audit

```bash
# Check certificate expiry
bash scripts/connect.sh run <target> "echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates"

# Test SSL configuration (requires ssllabs-scan or testssl.sh on control machine)
testssl.sh --fast https://<domain>
```

**Never run testssl.sh against domains you don't own** — it generates significant traffic and may trigger rate limits or alerts.

## Incident response checklist

When compromise is suspected:

1. **Isolate** — block the host at the firewall/security group level (don't just shut down, you'll lose volatile evidence)
2. **Snapshot** — take EBS/volume snapshots before any investigation
3. **Preserve logs** — copy `/var/log/`, `journalctl --all`, and `.bash_history` for all users to S3
4. **Identify** — what was accessed? Check `/var/log/auth.log` for SSH sessions, nginx access logs for HTTP requests
5. **Contain** — rotate credentials, revoke IAM keys, block attacker IPs at the network edge
6. **Eradicate** — rebuild from a known-good snapshot or provision a fresh instance
7. **Recover** — restore data, deploy clean code, verify integrity
8. **Review** — how did they get in? Patch the entry point before bringing the host back online

**Never just reboot and hope** — if you suspect compromise, treat the host as untrusted and rebuild.

## Rotating secrets post-incident

```bash
# Generate new SSH key
ssh-keygen -t ed25519 -f ~/.ssh/new_key -N ""

# Update authorized_keys on all hosts
ansible all -i inventory.ini -m authorized_key -a "user=ubuntu state=present key='{{ lookup('file', '~/.ssh/new_key.pub') }}'" --become

# Remove old key
ansible all -i inventory.ini -m authorized_key -a "user=ubuntu state=absent key='<old-key-fingerprint>'" --become
```

AWS IAM key rotation:
```bash
# Create new access key
aws iam create-access-key --user-name <user>

# Update apps/services to use new key, then deactivate old key
aws iam update-access-key --user-name <user> --access-key-id <old-key> --status Inactive

# Verify old key is no longer in use, then delete
aws iam delete-access-key --user-name <user> --access-key-id <old-key>
```
