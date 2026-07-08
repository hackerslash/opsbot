# Terraform — infrastructure as code operations

## Pre-flight checks (always run these first)

```bash
# 1. Which workspace are you in?
terraform workspace show

# 2. What will change? (read-only, safe)
terraform plan -out=tfplan

# 3. Review the plan carefully before apply
terraform show tfplan
```

**Never `terraform apply` without reviewing the plan first.** A plan showing `destroy` or `replace` on prod resources needs explicit confirmation.

## Apply workflow

```bash
# Standard apply (MUTATING — confirm first)
terraform apply tfplan

# For state-only changes (imports, moves)
terraform apply -refresh-only

# Target a specific resource (escape hatch, not routine)
terraform apply -target=aws_instance.web
```

## State operations (HIGH RISK)

**State mutations are one-way — back up first:**

```bash
# Backup current state
terraform state pull > terraform.tfstate.backup.$(date +%s)

# Import existing resource
terraform import aws_instance.web i-1234567890abcdef0

# Move a resource (rename in state without recreating)
terraform state mv aws_instance.old aws_instance.new

# Remove from state without destroying (orphan the resource)
terraform state rm aws_instance.web
```

**Never edit `.tfstate` files by hand.** Use `terraform state` commands only.

## Remote state

```bash
# Initialize backend (first time or after backend config change)
terraform init -migrate-state

# Lock inspection (if apply is stuck "Acquiring state lock")
terraform force-unlock <lock-id>
```

**`force-unlock` is a last resort** — only use it if you're certain no other terraform process is running. Check with the team first.

## Workspace management

```bash
# List workspaces
terraform workspace list

# Switch workspace (changes which state file you're operating on)
terraform workspace select prod

# Create new workspace
terraform workspace new staging
```

**Workspace = environment.** Always verify with `workspace show` before any mutating command. Prod workspace requires explicit confirmation.

## Troubleshooting

**`Error acquiring the state lock`** = someone else is running terraform, or a previous run crashed. Check with the team, then `force-unlock` if needed.

**`Provider produced inconsistent result after apply`** = a race condition or API instability. Re-run `terraform apply` — if it persists, the provider may have a bug.

**`Error: Reference to undeclared resource`** = you referenced a resource that doesn't exist in this module's scope. Check the module structure and outputs.

## Drift detection

```bash
# Detect changes made outside Terraform (read-only)
terraform plan -refresh-only

# Accept the drift into state
terraform apply -refresh-only
```
