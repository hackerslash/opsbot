# CI/CD — Multi-Platform Pipeline Operations

For GitOps (ArgoCD, Flux), see [gitops.md](gitops.md).

## Critical gotchas

- **Deploy failures are server failures, not pipeline failures** - check server logs via connect.sh, not just pipeline output
- **Self-hosted runners need disk cleanup** - `/opt/actions-runner/_work` fills up, causing cryptic failures
- **Secret trailing whitespace breaks apps** - `DATABASE_URL=postgres://...\n` causes connection failures
- **GitLab Docker executor needs registry auth** - shell executor doesn't, creates environment-specific failures
- **Jenkins agents offline = silent queue** - jobs wait forever without clear error
- **Secrets masked/protected mismatch** - GitLab protected variable won't expose to unprotected branch

## Quick reference

```bash
# GitHub Actions
gh run view <run-id> --log-failed
gh run rerun <id> --failed-only
gh workflow run deploy.yml --ref main -f env=uat
gh secret list; gh secret set DB_URL < /dev/stdin

# GitLab CI/CD
glab ci view <job-id>; glab ci retry <pipeline-id>
glab api /projects/<id>/variables
gitlab-runner verify; sudo journalctl -u gitlab-runner -n 50 --no-pager

# CircleCI
circleci run list --limit 5
circleci workflow rerun <workflow-id> --from-failed
circleci ssh <build-num>  # requires enable_ssh: true in job

# Jenkins
java -jar jenkins-cli.jar -s https://jenkins.example.com/ -auth user:token console <job> <build>
curl -X POST https://jenkins.example.com/job/<name>/<build>/stop --user user:token
```

## GitHub Actions

```bash
# Runner offline
sudo systemctl status actions.runner.<org>-<repo>.<name>.service
sudo journalctl -u actions.runner.<org>-<repo>.<name>.service -n 50 --no-pager
sudo systemctl restart actions.runner.<org>-<repo>.<name>.service

# Runner stuck
gh api repos/{owner}/{repo}/actions/runs/{run_id}/cancel -X POST

# Runner disk full
du -sh /opt/actions-runner/_work/*
rm -rf /opt/actions-runner/_work/_tool  # safe to delete, rebuilds automatically

# "Resource not accessible by integration" = missing permissions: write in workflow
# "Process completed with exit code 1" = read actual error, not wrapper
# Runner out of disk = /opt/actions-runner/_work cleanup needed
```

## GitLab CI/CD

```bash
# Runner status
gitlab-runner verify
sudo journalctl -u gitlab-runner -n 100 --no-pager
sudo systemctl restart gitlab-runner

# Docker executor check
sudo systemctl status docker
docker ps --all --filter label=com.gitlab.gitlab-runner.type=build

# Shell executor check
sudo -u gitlab-runner -H sh -c 'whoami; pwd; ls -la'

# Variables
glab api /projects/<id>/variables
glab api --method POST /projects/<id>/variables -f key=DB_URL -f value=postgres://... -f protected=true

# "This job is stuck" = no runners registered or shared runners disabled
# "pull access denied" = Docker executor needs registry auth (Settings → CI/CD → Variables → add credentials)
# yaml invalid = glab ci lint < .gitlab-ci.yml
```

## CircleCI

```bash
# Rerun
circleci workflow rerun <workflow-id> --from-failed

# SSH debug (requires enable_ssh: true in job config)
circleci ssh <build-num>

# "No config found" = .circleci/config.yml missing or invalid YAML
# Out of credits = check plan usage in Settings
```

## Jenkins

```bash
# Console output
java -jar jenkins-cli.jar -s https://jenkins.example.com/ -auth user:token console <job> <build>

# Trigger with params
curl -X POST https://jenkins.example.com/job/<name>/build --user user:token --data-urlencode json='{"parameter": [{"name":"ENV", "value":"uat"}]}'

# Node offline
ssh jenkins@agent.example.com
sudo systemctl restart jenkins-agent

# "error=2, No such file or directory" = binary not in PATH on agent
# "Agent went offline" = network/agent service issue
```

## Cross-platform patterns

### Secrets injection debugging

```bash
# 1. Verify secret exists
gh secret list  # GitHub
glab api /projects/<id>/variables  # GitLab

# 2. Check exposure (protected/masked mismatch)
# 3. Print env var names only (never values)
env | grep -E '^[A-Z_]+=' | cut -d= -f1 | sort

# 4. Check trailing whitespace (common cause)
# If DB connection fails despite correct URL, secret likely has \n
```

### Deploy step failures

**Pipeline is automation. Failures are server-side.**

```bash
# 1. Check server logs (not pipeline logs)
bash scripts/connect.sh run <target> "sudo journalctl -u <svc> -n 50 --no-pager"

# 2. Verify code landed
bash scripts/connect.sh run <target> "cd /path/to/app && git rev-parse HEAD"

# 3. Check service status
bash scripts/connect.sh run <target> "systemctl status <svc>"

# 4. Check .env sync
bash scripts/connect.sh run <target> "ls -la /path/to/app/.env; md5sum /path/to/app/.env"
```

### Performance optimization

- Cache dependencies (npm, pip, Maven .m2), not build outputs
- Parallel jobs for test suites
- Docker layer caching for base images
- `--failed-only` rerun saves credits
