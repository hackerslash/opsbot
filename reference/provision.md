# Provision a new instance

## Critical gotchas

- **Runtime path must be /usr/bin not /usr/local/bin** — systemd ExecStart fails silently if runtime in wrong location. Verify with `which node` before creating service.
- **Deploy keys: generate on server, add public to git host as read-only** — never write keys on servers. Use `ssh-keygen -t ed25519 -N ""` (no passphrase).
- **EBS fstab needs nofail option** — boot hangs if volume detaches. Format: `/dev/xvdf /data ext4 defaults,nofail 0 2`
- **Security groups: SSH restricted to your IP, not 0.0.0.0/0** — HTTP/HTTPS can be 0.0.0.0/0
- **certbot --nginx rewrites server blocks in place** — commit changes to git after first run
- **CloudWatch agent needs CloudWatchAgentServerPolicy IAM** — logs/metrics fail silently without it
- **Never expose app port directly** — bind app to 127.0.0.1, nginx reverse proxies to it
- **Firewall before certbot** — allow 80/443 or Let's Encrypt challenge fails

## Provision sequence

1. Detect OS, install packages (git, nginx, node, certbot, jq)
2. Verify runtime path: `which node` MUST be /usr/bin/node
3. Deploy key: `ssh-keygen -t ed25519`, add public to repo
4. Clone, copy .env, build
5. Create systemd service, enable
6. Configure nginx, enable site, reload
7. Run certbot --nginx
8. Configure firewall (ufw allow 22/80/443 or firewall-cmd)
9. Verify: curl https://<domain>/healthz

See [services.md](services.md) for systemd, [nginx.md](nginx.md) for config, [os-matrix.md](os-matrix.md) for command variants.

## Troubleshooting

**Runtime wrong path:** `which node` → /usr/local/bin - uninstall, reinstall via package manager. systemd ExecStart fails silently (exit 203).

**Build OOM:** Add swap: `sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`

**certbot fails:** Firewall must allow 80/443 first. DNS A record must point to instance IP.

**ASG provisioning:** Launch Template user data: fetch SSM secrets, install, clone/build, systemd, signal completion.
