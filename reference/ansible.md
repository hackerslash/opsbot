# Ansible — configuration management and orchestration

## Pre-flight

```bash
# Test connectivity (ping module, no changes)
ansible <group|host> -i inventory.ini -m ping

# List hosts matched by a pattern
ansible <pattern> -i inventory.ini --list-hosts
```

## Running playbooks

```bash
# Dry run (check mode — see what would change without changing it)
ansible-playbook -i inventory.ini playbook.yml --check --diff

# Real run (MUTATING — confirm first)
ansible-playbook -i inventory.ini playbook.yml

# Limit to specific hosts
ansible-playbook -i inventory.ini playbook.yml --limit prod-web-01

# Run specific tags only
ansible-playbook -i inventory.ini playbook.yml --tags nginx,ssl
```

**Always run `--check --diff` first** and show the user what will change. The diff shows file edits, package installs, service restarts.

## Ad-hoc commands

Useful for one-off tasks without writing a playbook:

```bash
# Run a shell command on all hosts
ansible <group> -i inventory.ini -m shell -a "df -h"

# Copy a file
ansible <group> -i inventory.ini -m copy -a "src=/local/file dest=/remote/path"

# Restart a service
ansible <group> -i inventory.ini -m systemd -a "name=nginx state=restarted" --become

# Install a package
ansible <group> -i inventory.ini -m apt -a "name=nginx state=present" --become
```

**`--become` = sudo.** Most system-level tasks need it.

## Inventory formats

INI: `[group]\nhost ansible_host=IP ansible_user=ubuntu ansible_ssh_private_key_file=path`
YAML: Standard Ansible inventory with `ansible_host`, `ansible_user`, `ansible_ssh_private_key_file`

## Vault (secrets)

```bash
# Encrypt a file
ansible-vault encrypt vars/secrets.yml

# Decrypt for editing
ansible-vault edit vars/secrets.yml

# Run playbook with vault password
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass

# Or use a password file
ansible-playbook -i inventory.ini playbook.yml --vault-password-file ~/.ansible_vault_pass
```

**Never commit unencrypted secrets** to git. Always use `ansible-vault encrypt` before committing.

## Common errors

**`Host key checking failed`** = SSH strict host key check. Set `ANSIBLE_HOST_KEY_CHECKING=False` env var or add `host_key_checking = False` to `ansible.cfg`. Only do this for internal/trusted networks.

**`Permission denied (publickey)`** = wrong SSH key or user. Verify `ansible_user` and `ansible_ssh_private_key_file` in inventory.

**`Module failed: apt requires python-apt`** = target host missing Python apt bindings. Run `ansible <host> -m raw -a "apt-get update && apt-get install -y python3-apt" --become` first.

**Playbook hangs on a task** = likely waiting for user input (like apt asking about config file changes). Add `-e "DEBIAN_FRONTEND=noninteractive"` or use `--timeout 30` to fail fast.
