# Database Operations

## Critical Gotchas

- **PostgreSQL pg_cancel vs pg_terminate**: cancel stops query but keeps connection; terminate closes connection
- **PostgreSQL replication lag**: `pg_last_xact_replay_timestamp()` returns NULL on primary (not replica)
- **PostgreSQL VACUUM FULL**: locks table exclusively; never run on prod under load
- **MySQL KILL vs KILL QUERY**: KILL terminates connection, KILL QUERY cancels query only
- **Redis KEYS command**: blocks server on large keyspaces; use SCAN instead
- **Redis FLUSHALL**: wipes entire keyspace; no undo
- **MongoDB write concern majority**: waits for replication; slower but safer

## Quick Triage

```bash
# PostgreSQL
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT pid, usename, state, wait_event_type, left(query,80) FROM pg_stat_activity WHERE state != 'idle' ORDER BY state;\""

# MySQL
bash scripts/connect.sh run <target> "mysql -e 'SHOW FULL PROCESSLIST;'"

# Redis
bash scripts/connect.sh run <target> "redis-cli INFO | grep -E 'used_memory_human|connected_clients|evicted_keys'"

# MongoDB
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.currentOp()'"
```

## PostgreSQL

```bash
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SHOW max_connections;\""
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT pg_cancel_backend(<pid>);\""
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT pg_terminate_backend(<pid>);\""

# Replication (NULL = primary)
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;\""

# Vacuum/bloat
bash scripts/connect.sh run <target> "sudo -u postgres psql -d <db> -c \"SELECT relname, last_autovacuum FROM pg_stat_user_tables ORDER BY last_autovacuum DESC NULLS LAST LIMIT 20;\""

# Query performance (requires pg_stat_statements)
bash scripts/connect.sh run <target> "sudo -u postgres psql -d <db> -c \"SELECT calls, total_exec_time/1000 as total_sec, mean_exec_time, left(query,100) FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;\""

# Locks
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT pid, usename, pg_blocking_pids(pid) as blocked_by, query FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;\""

# Index usage
bash scripts/connect.sh run <target> "sudo -u postgres psql -d <db> -c \"SELECT schemaname, tablename, indexname, idx_scan FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_relation_size(indexrelid) DESC LIMIT 20;\""

# Cache hit ratio
bash scripts/connect.sh run <target> "sudo -u postgres psql -c \"SELECT sum(heap_blks_hit)/(sum(heap_blks_hit)+sum(heap_blks_read)) AS cache_hit_ratio FROM pg_statio_user_tables;\""
```

## MySQL

```bash
bash scripts/connect.sh run <target> "mysql -e 'SHOW STATUS LIKE \"Threads_connected\";'"
bash scripts/connect.sh run <target> "mysql -e 'SHOW VARIABLES LIKE \"max_connections\";'"
bash scripts/connect.sh run <target> "mysql -e 'KILL QUERY <id>;'"
bash scripts/connect.sh run <target> "mysql -e 'KILL <id>;'"

# Replication
bash scripts/connect.sh run <target> "mysql -e 'SHOW REPLICA STATUS\\G' | grep Seconds_Behind_Master"

# Slow queries
bash scripts/connect.sh run <target> "tail -100 /var/log/mysql/slow.log"

# InnoDB buffer pool
bash scripts/connect.sh run <target> "mysql -e 'SHOW STATUS LIKE \"Innodb_buffer_pool%\";'"

# Locks
bash scripts/connect.sh run <target> "mysql -e 'SELECT * FROM sys.innodb_lock_waits\\G'"
```

## Redis

```bash
bash scripts/connect.sh run <target> "redis-cli INFO | grep -E 'used_memory_human|connected_clients|evicted_keys|keyspace_hits|keyspace_misses'"
bash scripts/connect.sh run <target> "redis-cli CONFIG GET maxmemory"

# Keys (NEVER KEYS in production - blocks server)
bash scripts/connect.sh run <target> "redis-cli DBSIZE"
bash scripts/connect.sh run <target> "redis-cli --scan --pattern 'user:*' | head -20"

# Clients
bash scripts/connect.sh run <target> "redis-cli CLIENT LIST"
bash scripts/connect.sh run <target> "redis-cli CLIENT KILL <addr>"

# Persistence
bash scripts/connect.sh run <target> "redis-cli LASTSAVE"
bash scripts/connect.sh run <target> "redis-cli BGSAVE"

# Eviction policy
bash scripts/connect.sh run <target> "redis-cli CONFIG SET maxmemory-policy allkeys-lru"
```

## MongoDB

```bash
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.currentOp()'"
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.killOp(<opid>)'"

# Replica set
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'rs.status()'"
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'rs.printSecondaryReplicationInfo()'"

# Profiling (0=off, 1=slow only, 2=all)
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.setProfilingLevel(1, {slowms: 100})'"
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.system.profile.find().limit(10).sort({ts:-1}).pretty()'"

# Indexes
bash scripts/connect.sh run <target> "mongosh --quiet --eval 'db.mycollection.aggregate([{\$indexStats:{}}])'"
```

## Troubleshooting

```bash
# Connection pool exhausted - check max_connections, kill idle, set pool max < DB max
# Slow query causing locks - check pg_stat_activity, pg_blocking_pids(), SHOW PROCESSLIST, kill blocking query
# Replication lag growing - check disk I/O on replica, inactive replication slots, network latency
# Database disk full - check WAL buildup, bloat, binlog retention, dump.rdb size, vacuum, purge old binlogs
```
