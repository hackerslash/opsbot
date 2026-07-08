# Containers — Docker, Compose, ECS

For Kubernetes and Helm operations, see [kubernetes.md](kubernetes.md) and [gitops.md](gitops.md).

## Interactive TTY

`docker exec -it` and ECS `execute-command` **cannot run through the agent Bash tool** — it can't hold an interactive TTY. Print the command for the user to paste:

```bash
bash scripts/connect.sh ssh <target>   # get the SSH line, then user runs:
# docker exec -it <container> /bin/sh
```

For non-interactive inspection (safe through the agent):
```bash
bash scripts/connect.sh run <target> "docker exec <container> env | grep -v PASSWORD; docker exec <container> ps aux"
```

## Docker system prune

`docker system prune` removes **stopped containers AND dangling images AND unused networks** — not just images. Preview first:

```bash
bash scripts/connect.sh run <target> "docker system df"
```

Then confirm with the user before running `docker system prune -f`.

## Docker Compose

Run Compose commands from the project directory. `docker compose pull && docker compose up -d --remove-orphans` is the standard update — `--remove-orphans` removes containers for services removed from the compose file.

## ECS

**ECS Exec requires the task definition to have `enableExecuteCommand: true`** and the task role needs SSM permissions. Check before trying — it's not on by default.

`aws ecs update-service --force-new-deployment` triggers a rolling update (zero-downtime). Use `aws ecs wait services-stable` to block until the deployment completes instead of polling manually.

## Logs

Docker logs and ECS task logs never use `-f` through the agent. Use `--tail 200` or `--since 30m`. ECS tasks log to CloudWatch by default — find the log group in the task definition's `logConfiguration`.
