# Secrets

## Critical gotchas

- **Never print/echo secrets**: Value in stdout/logs requires immediate rotation
- **Restart after .env change**: Env vars read at startup, not continuously
- **SSM needs two permissions**: Both `ssm:GetParameter` AND `kms:Decrypt` for SecureString
- **Backup before sync**: `cp .env .env.bak.$(date +%s)` for rollback
- **Rotation requires restart**: Services must re-read after automatic rotation
- **.env permissions**: 600, owned by service user
- **IAM Deny wins**: Check SCPs, resource policies; use `simulate-principal-policy`

## Quick reference

```bash
# SSM
aws ssm get-parameter --name /myapp/prod/DB_PASSWORD --with-decryption --query 'Parameter.Value' --output text
aws ssm get-parameters-by-path --path /myapp/prod --recursive --with-decryption

# Secrets Manager
aws secretsmanager get-secret-value --secret-id myapp/prod/db --query 'SecretString' --output text
aws secretsmanager rotate-secret --secret-id myapp/prod/db

# Vault
vault kv get secret/myapp/prod/db
export VAULT_TOKEN=$(vault login -token-only -method=aws role=myapp-prod)

# .env inspection (no values)
grep -v '^\s*#' .env | cut -d= -f1; grep -q '^DB_PASSWORD=' .env && echo present || echo MISSING
```

## SSM sync to .env

```bash
# Full sync (pull by path prefix, write to file - value never touches stdout)
bash scripts/connect.sh run <target> "$(cat <<'REMOTE'
cp ~/<app>/.env ~/<app>/.env.bak.$(date +%s) 2>/dev/null || true
aws ssm get-parameters-by-path --path /myapp/<env> --recursive --with-decryption --query 'Parameters[*].{Name:Name,Value:Value}' --output json | jq -r '.[] | (.Name | split("/") | last) + "=" + .Value' > ~/<app>/.env
chmod 600 ~/<app>/.env
REMOTE
)"
bash scripts/connect.sh run <target> "sudo systemctl restart <svc>"

# Single parameter update
bash scripts/connect.sh run <target> "$(cat <<'REMOTE'
VALUE=$(aws ssm get-parameter --name /myapp/prod/DB_PASSWORD --with-decryption --query 'Parameter.Value' --output text)
cp ~/<app>/.env ~/<app>/.env.bak.$(date +%s)
grep -v "^DB_PASSWORD=" ~/<app>/.env > ~/<app>/.env.tmp && mv ~/<app>/.env.tmp ~/<app>/.env
echo "DB_PASSWORD=${VALUE}" >> ~/<app>/.env; chmod 600 ~/<app>/.env
REMOTE
)"

# Create/update parameter
aws ssm put-parameter --name /myapp/prod/KEY --value "secret" --type SecureString --overwrite

# History/rollback
aws ssm get-parameter-history --name /myapp/prod/DB_PASSWORD --with-decryption
```

## Secrets Manager sync to .env

```bash
bash scripts/connect.sh run <target> "$(cat <<'REMOTE'
cp ~/<app>/.env ~/<app>/.env.bak.$(date +%s) 2>/dev/null || true
aws secretsmanager get-secret-value --secret-id myapp/prod/db --query 'SecretString' --output text | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > ~/<app>/.env
chmod 600 ~/<app>/.env
REMOTE
)"

# Rotation
aws secretsmanager rotate-secret --secret-id myapp/prod/db --rotation-lambda-arn <arn> --rotation-rules AutomaticallyAfterDays=30
aws secretsmanager describe-secret --secret-id myapp/prod/db --query 'VersionIdsToStages'  # Check rotation status
```

## Vault sync to .env

```bash
# vault kv get -format=json secret/myapp/prod | jq to .env
vault token renew; vault token lookup
```

## git-crypt / SOPS

```bash
# git-crypt: git-crypt unlock /path/to/key
# SOPS: sops -d secrets.enc.yaml | yq to .env
```

## Rotation workflow

Zero-downtime database: 1) Create new creds in DB, 2) Update secret store, 3) Sync to servers, 4) Rolling restart with health checks, 5) Revoke old

API keys: 1) Generate new key (if service supports overlapping), 2) Deploy to all servers, 3) Verify no auth errors, 4) Revoke old

## Audit

```bash
# SSM/Secrets Manager access (CloudTrail)
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GetParameter --start-time 2026-06-01 --query 'Events[*].{Time:EventTime,User:Username}'

# Find secrets in git history
git log -S 'PASSWORD' --all --oneline
git log -G 'sk_live_[a-zA-Z0-9]+' --all --oneline
```

## Troubleshooting

**SSM not decrypting**: Check IAM role has both `ssm:GetParameter` AND `kms:Decrypt`; use `simulate-principal-policy`

**Service not using new .env**: Restart service (`systemctl restart`), verify .env permissions (600, correct owner), check `EnvironmentFile=` in systemd unit

**Vault token expired**: `vault token renew` or re-login `vault login -token-only -method=aws`

**Rotation broke service**: Check `describe-secret` for AWSCURRENT/AWSPREVIOUS versions; services must re-read after rotation; test in non-prod first
