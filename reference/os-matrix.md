# OS matrix — Amazon Linux 2023 vs Ubuntu 24.04 vs Debian 12

Detect with: `bash scripts/connect.sh run <target> "cat /etc/os-release | head -2; whoami"`

`ID=amzn` / `ID=ubuntu` / `ID=debian` is the authoritative signal.

| Concern | Amazon Linux 2023 | Ubuntu 24.04 | Debian 12 |
|---|---|---|---|
| Default login user | `ec2-user` | `ubuntu` | `admin` (varies by provider) |
| Package manager | `dnf` | `apt-get` | `apt-get` |
| Firewall tool | `firewall-cmd` | `ufw` | `ufw` or `nftables` |
| SSH daemon service | `sshd` | `ssh` (alias `sshd`) | `ssh` (alias `sshd`) |
| Reload SSH | `systemctl reload sshd` | `systemctl reload ssh` | `systemctl reload ssh` |
| fail2ban sshd log | journald (`backend = systemd`) | `/var/log/auth.log` | `/var/log/auth.log` |
| App user home | `/home/ec2-user/<app>` | `/home/ubuntu/<app>` | `/home/admin/<app>` |

## Key differences that cause failures

**fail2ban sshd:** AL2023 reads journald. Ubuntu/Debian read `/var/log/auth.log`. Never override the `logpath` for sshd on AL2023 — the default is correct and overriding it breaks it.

**SSH service name:** on Ubuntu/Debian, `systemctl reload ssh` (not `sshd`). Both have an alias but `sshd -t` validates the config for both.

**Debian default user** varies by provider (Hetzner: `debian` or `admin`, OVH: `debian`, DigitalOcean: `root`). Always run `whoami` on first connect.

**Firewall:** Debian 12 ships `nftables` as the backend. `ufw` is available but not enabled by default — install and enable it for consistency with Ubuntu. On AL2023, Lightsail/EC2 console firewall usually governs ingress; `firewalld` is the local tool.

## Block an attacking IP

```bash
# Ubuntu / Debian (ufw)
sudo ufw insert 1 deny from <IP> to any

# Amazon Linux 2023
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='<IP>' reject" && sudo firewall-cmd --reload
```

**Never leave an app port (8000/8080) open to the world** — nginx must front it.
