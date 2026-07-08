# Backup & disaster recovery

## Critical gotchas

- **Always stream directly to S3** - `pg_dump | aws s3 cp -` avoids disk space issues on small instances
- **PITR requires WAL/binlog archiving** - base backups alone can't restore to arbitrary timestamp
- **Automate verification** - systemd timer runs `pg_restore --list` daily, alerts on failure
- **EBS snapshots are per-region** - not per-AZ
- **S3 lifecycle policies save costs** - transition backups to Glacier after 90d

## PostgreSQL

```bash
# Stream to S3 (no disk usage)
bash scripts/connect.sh run <target> "pg_dump -Fc <db> | aws s3 cp - s3://<bucket>/backups/pg-$(date +%Y%m%d-%H%M%S).dump"

# Verify backup
aws s3 cp s3://<bucket>/backups/<file> - | pg_restore --list -

# PITR: enable WAL archiving (wal_level=replica, archive_mode=on, archive_command to S3)
bash scripts/connect.sh run <target> "sudo -u postgres pg_basebackup -D /tmp/base -Ft -z && aws s3 cp /tmp/base s3://<bucket>/base/ --recursive"

# Restore
bash scripts/connect.sh run <target> "aws s3 cp s3://<bucket>/backups/<file> /tmp/r.dump && sudo systemctl stop <app-service> && sudo -u postgres dropdb <db> && sudo -u postgres createdb <db> && pg_restore -d <db> /tmp/r.dump && sudo -u postgres psql <db> -c 'ANALYZE;' && rm /tmp/r.dump"
bash scripts/connect.sh run <target> "sudo systemctl start <app-service>"
```

## MySQL

```bash
# Backup
bash scripts/connect.sh run <target> "mysqldump --single-transaction --routines --triggers <db> | gzip | aws s3 cp - s3://<bucket>/backups/mysql-$(date +%Y%m%d-%H%M%S).sql.gz"

# PITR: enable binary logging (log_bin in my.cnf), then replay: mysqlbinlog --start-datetime="..." mysql-bin.000001 | mysql <db>

# Restore
bash scripts/connect.sh run <target> "aws s3 cp s3://<bucket>/backups/<file> /tmp/r.sql.gz && sudo systemctl stop <app-service> && mysql -e 'DROP DATABASE <db>; CREATE DATABASE <db>;' && zcat /tmp/r.sql.gz | mysql <db> && rm /tmp/r.sql.gz"
bash scripts/connect.sh run <target> "sudo systemctl start <app-service>"
```

## Redis

```bash
# RDB snapshot
bash scripts/connect.sh run <target> "redis-cli BGSAVE && sleep 2 && aws s3 cp /var/lib/redis/dump.rdb s3://<bucket>/backups/redis-$(date +%Y%m%d-%H%M%S).rdb"
bash scripts/connect.sh run <target> "redis-cli LASTSAVE"

# AOF for better durability (appendonly yes, appendfsync everysec in redis.conf) - use both: RDB daily, AOF for recovery between snapshots

# Restore
bash scripts/connect.sh run <target> "sudo systemctl stop redis && aws s3 cp s3://<bucket>/backups/<file> /var/lib/redis/dump.rdb && sudo chown redis:redis /var/lib/redis/dump.rdb && sudo systemctl start redis"
bash scripts/connect.sh run <target> "redis-cli DBSIZE"
```

## MongoDB

```bash
bash scripts/connect.sh run <target> "mongodump --db <db> --archive | gzip | aws s3 cp - s3://<bucket>/backups/mongo-$(date +%Y%m%d-%H%M%S).archive.gz"
bash scripts/connect.sh run <target> "aws s3 cp s3://<bucket>/backups/<file> /tmp/r.archive.gz && sudo systemctl stop <app-service> && mongorestore --db <db> --drop --gzip --archive=/tmp/r.archive.gz && rm /tmp/r.archive.gz"
```

## Application files

```bash
bash scripts/connect.sh run <target> "tar czf - /var/www/<app> --exclude=node_modules --exclude=.git | aws s3 cp - s3://<bucket>/backups/app-$(date +%Y%m%d-%H%M%S).tar.gz"
bash scripts/connect.sh run <target> "aws s3 sync /var/www/<app>/public s3://<bucket>/static/ --delete"
bash scripts/connect.sh run <target> "aws s3 cp s3://<bucket>/backups/<file> /tmp/r.tar.gz && sudo systemctl stop <app-service> && sudo tar xzf /tmp/r.tar.gz -C / && rm /tmp/r.tar.gz && sudo systemctl start <app-service>"
```

## EBS snapshots

```bash
aws ec2 create-snapshot --volume-id <vol-xxx> --description "backup $(date +%Y%m%d-%H%M%S)" --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=<env>-<service>}]"
aws ec2 wait snapshot-completed --snapshot-ids <snap-xxx>

# Restore
aws ec2 create-volume --snapshot-id <snap-xxx> --availability-zone <az>
aws ec2 attach-volume --volume-id <vol-yyy> --instance-id <i-xxx> --device /dev/sdf
bash scripts/connect.sh run <target> "sudo mkdir -p /mnt/restored && sudo mount /dev/xvdf /mnt/restored"

# Automate: tag volumes with Backup=true, DLM policy creates daily 3am snapshots, retains 7d
```

## Lightsail snapshots

```bash
aws lightsail create-instance-snapshot --instance-name <instance> --instance-snapshot-name <name>-$(date +%Y%m%d-%H%M%S)
aws lightsail enable-add-on --resource-name <instance> --add-on-request addOnType=AutoSnapshot,autoSnapshotAddOnRequest={snapshotTimeOfDay=03:00}
aws lightsail create-instances-from-snapshot --instance-snapshot-name <snapshot> --instance-names <new-name> --availability-zone <az> --bundle-id <bundle>
```

## S3 lifecycle

```bash
# Transition: 30d → IA, 90d → Glacier, expire 365d
# Cross-region replication: enable versioning, create replication config
aws s3api put-bucket-versioning --bucket <source> --versioning-configuration Status=Enabled

# Manual cleanup (backups > 30 days)
aws s3 ls s3://<bucket>/backups/ | awk '$1 < "'$(date -d '30 days ago' +%Y-%m-%d)'" {print $4}' | xargs -I {} aws s3 rm s3://<bucket>/backups/{}
```

## Troubleshooting

```bash
# Backup not running
bash scripts/connect.sh run <target> "systemctl list-timers | grep backup; journalctl -u backup.timer -n 20 --no-pager; df -h"

# Verification failing
aws s3 cp s3://<bucket>/backups/<latest> /tmp/test.dump && pg_restore --list /tmp/test.dump
aws s3 ls s3://<bucket>/backups/ --recursive --human-readable | tail -5

# Restore too slow
pg_restore -j 4 -d <db> <dump_file>
```
