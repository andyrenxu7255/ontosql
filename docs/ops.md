# OntoSQL 运维手册

## 1. 部署流程

### 1.1 环境要求

| 项目 | 开发环境 | 生产环境（最小） | 生产环境（推荐） |
|------|---------|----------------|----------------|
| CPU | 4 核 | 4 核 | 8 核+ |
| 内存 | 8 GB | 8 GB | 32 GB+ |
| 磁盘 | SSD 20 GB | SSD 50 GB | NVMe SSD 200 GB+ |
| 操作系统 | macOS 13+ / Ubuntu 22.04 | Ubuntu 22.04+ / Debian 12+ | Ubuntu 22.04 LTS |
| 网络 | — | 低延迟内网 | 独立网段 / VPC |

### 1.2 编译部署（手动）

```bash
# 克隆项目
git clone <repo-url> ontosql && cd ontosql

# 安装系统依赖（Ubuntu/Debian）
sudo apt-get update
sudo apt-get install -y build-essential bison flex \
    libreadline-dev zlib1g-dev libssl-dev libicu-dev \
    libxml2-dev libxslt1-dev liblz4-dev libzstd-dev \
    pkg-config python3-dev

# 安装系统依赖（macOS）
brew install readline openssl icu4c libxml2 libxslt lz4 zstd

# 编译全部组件
make build

# 初始化数据库
make init-db

# 启动数据库
make start

# 部署测试
make test
```

### 1.3 Docker 部署

```bash
# 构建镜像
docker build -t ontosql:latest -f docker/Dockerfile .

# 或使用 docker compose 一键启动
cd docker
PG_PORT=5432 POSTGRES_PASSWORD=your_strong_password docker compose up -d

# 等待健康检查通过
docker compose ps

# 进入容器执行 SQL
docker compose exec ontosql psql -U postgres
```

### 1.4 初始化 OntoSQL Schema

```bash
# 方法 1：通过 psql 直接加载
build/pgsql17/bin/psql -p 5432 -U <user> -d postgres -f sql/001_core_schema.sql

# 方法 2：运行测试（测试脚本会自动加载 Schema）
make test

# 方法 3：加载知识图谱示例
build/pgsql17/bin/psql -p 5432 -U <user> -d postgres -f sql/002_knowledge_graph.sql
```

---

## 2. 性能优化

### 2.1 内存配置建议

根据服务器内存大小调整 PG 核心参数：

| 服务器内存 | shared_buffers | effective_cache_size | work_mem | maintenance_work_mem |
|-----------|----------------|---------------------|----------|---------------------|
| 8 GB | 512 MB | 2 GB | 32 MB | 256 MB |
| 16 GB | 4 GB | 8 GB | 64 MB | 512 MB |
| 32 GB | 8 GB | 24 GB | 128 MB | 1 GB |
| 64 GB | 16 GB | 48 GB | 256 MB | 2 GB |

应用配置：
```sql
-- 生产环境完整参数配置，参见 config/postgresql.template.sql
psql -U postgres -d postgres -f config/postgresql.template.sql
```

### 2.2 向量索引优化

```sql
-- HNSW 参数调优
-- m：每层的最大邻居数，越大召回精度越高但构建越慢（默认 16）
-- ef_construction：构建时的搜索范围，越大索引质量越高但构建越慢（默认 200）
-- ef_search：查询时的搜索范围，越大精度越高但越慢（默认 40）

-- 场景：精度优先（NL 问数场景，10 万级数据量）
-- 索引创建时调整 m
CREATE INDEX CONCURRENTLY idx_ve_high_precision
    ON vertex_embeddings USING hnsw (embedding vector_cosine_ops)
    WITH (m = 32, ef_construction = 300);

-- 查询时调整 ef_search
SET hnsw.ef_search = 200;  -- 高精度查询，适合问数场景
SET hnsw.ef_search = 40;   -- 低延迟查询，适合实时搜索
```

### 2.3 连接管理

```sql
-- 连接池建议：通过 PgBouncer 或应用层连接池管理
-- 单 PG 实例最大连接数建议
ALTER SYSTEM SET max_connections = 200;

-- 为 DBA 操作预留连接
ALTER SYSTEM SET superuser_reserved_connections = 5;

-- 连接超时设置
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';
ALTER SYSTEM SET statement_timeout = '30s';  -- 单条查询最长 30 秒
```

### 2.4 定时维护任务

```sql
-- 定期 VACUUM（回收死元组，更新统计信息）
-- 建议在低峰期（凌晨）执行
VACUUM ANALYZE vertex_embeddings;
VACUUM ANALYZE attribute_embeddings;
VACUUM ANALYZE object_attribute_mapping;

-- 定期 REINDEX（索引碎片整理）
-- HNSW 索引写入会产生碎片，建议每月重建一次
REINDEX INDEX CONCURRENTLY idx_vertex_embeddings_hnsw;
REINDEX INDEX CONCURRENTLY idx_attribute_embeddings_hnsw;

-- 自动化：使用 cron + psql
-- 0 3 * * 0 psql -U postgres -d postgres -c "VACUUM ANALYZE ontosql.vertex_embeddings;"
```

---

## 3. 备份与恢复

### 3.1 逻辑备份（pg_dump）

适用于中小规模数据、迁移、或保留 SQL 可读版本：

```bash
# 全库备份
pg_dump -p 5432 -U postgres -d postgres -F c -f /backup/ontosql_full_$(date +%Y%m%d).dump

# 仅备份 ontosql schema 数据
pg_dump -p 5432 -U postgres -d postgres -n ontosql -F c -f /backup/ontosql_schema.dump

# 仅备份 Schema 结构（不含数据）
pg_dump -p 5432 -U postgres -d postgres -n ontosql --schema-only -f /backup/ontosql_structure.sql

# 恢复
pg_restore -p 5432 -U postgres -d postgres -j 4 /backup/ontosql_full_20250101.dump
```

### 3.2 物理备份（pg_basebackup）

适用于大数据量、快速故障恢复（PITR）：

```bash
# 需要在 postgresql.conf 中启用 WAL 归档
# ALTER SYSTEM SET wal_level = 'replica';
# ALTER SYSTEM SET archive_mode = 'on';
# ALTER SYSTEM SET archive_command = 'cp %p /backup/wal_archive/%f';
# SELECT pg_reload_conf();

# 全量物理备份
pg_basebackup -p 5432 -U postgres -D /backup/base_$(date +%Y%m%d) -F t -z -P

# 设置恢复点（在备份前创建标记）
psql -U postgres -c "SELECT pg_create_restore_point('pre_backup_$(date +%Y%m%d)');"

# 增量备份：需配合 WAL 归档 + pg_basebackup 的 -R 选项
# 恢复时：将备份解压到 PGDATA，修改 postgresql.conf 的 restore_command，启动 PG
```

### 3.3 自动化备份脚本

```bash
#!/bin/bash
# /etc/cron.daily/ontosql_backup.sh
BACKUP_DIR="/backup/ontosql"
RETENTION_DAYS=30
PG_PORT=5432
PG_USER=postgres
PG_DB=postgres

mkdir -p "$BACKUP_DIR"

# 全量备份
pg_dump -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -F c \
    -f "$BACKUP_DIR/ontosql_$(date +%Y%m%d_%H%M).dump"

# 清理超过保留期的备份
find "$BACKUP_DIR" -name "ontosql_*.dump" -mtime +$RETENTION_DAYS -delete

# 记录日志
echo "[$(date)] Backup completed" >> "$BACKUP_DIR/backup.log"
```

### 3.4 恢复验证流程

```bash
# 在测试环境验证备份可用性（建议每月执行一次）
psql -U postgres -c "CREATE DATABASE restore_test;"
pg_restore -p 5432 -U postgres -d restore_test /backup/ontosql_full_*.dump
psql -U postgres -d restore_test -f tests/test_cases.sql
psql -U postgres -c "DROP DATABASE restore_test;"
```

---

## 4. 灾备方案

### 4.1 方案对比

| 方案 | RPO | RTO | 复杂度 | 适用场景 |
|------|-----|-----|--------|---------|
| 定时备份 + 恢复 | 分钟~小时 | 分钟~小时 | 低 | 预算有限，可接受部分数据丢失 |
| 流复制（Hot Standby） | ~0 | 秒级 | 中 | 需要读负载分担或快速切换 |
| 同步复制 | 0 | 秒级 | 高 | 零数据丢失要求 |
| 跨区域异步复制 | 秒级 | 分钟级 | 高 | 灾难性故障恢复（地域级） |

### 4.2 搭建流复制备库

```bash
# 主库配置
psql -U postgres -c "ALTER SYSTEM SET wal_level = 'replica';"
psql -U postgres -c "ALTER SYSTEM SET max_wal_senders = 5;"
psql -U postgres -c "ALTER SYSTEM SET wal_keep_size = '1GB';"
psql -U postgres -c "SELECT pg_reload_conf();"

# 创建复制用户
psql -U postgres -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'strong_password';"

# 在 pg_hba.conf 添加
# host replication replicator <备库IP>/32 md5

# 备库：使用 pg_basebackup 克隆主库
pg_basebackup -h <主库IP> -p 5432 -U replicator -D $PGDATA -R -P

# 启动备库
pg_ctl -D $PGDATA start
```

### 4.3 故障切换

```bash
# 主库不可用时，在备库执行提升操作
pg_ctl -D $PGDATA promote

# 验证新主库状态
psql -U postgres -c "SELECT pg_is_in_recovery();"  # 应返回 false
```

---

## 5. 监控

### 5.1 核心监控指标

| 指标 | SQL 查询 | 告警阈值 |
|------|---------|---------|
| 数据库连接数 | `SELECT count(*) FROM pg_stat_activity;` | > 80% max_connections |
| 长事务 | `SELECT pid, now()-xact_start FROM pg_stat_activity WHERE state='active' AND now()-xact_start > interval '5 min';` | > 5 分钟 |
| 锁等待 | `SELECT count(*) FROM pg_locks WHERE NOT granted;` | > 0 持续 30 秒 |
| 表膨胀率 | `SELECT schemaname, tablename, n_dead_tup, n_live_tup FROM pg_stat_user_tables;` | n_dead_tup > n_live_tup * 0.5 |
| 索引命中率 | `SELECT sum(idx_scan) * 100.0 / nullif(sum(idx_scan + seq_scan), 0) FROM pg_stat_user_tables;` | < 90% |
| 慢查询 | 配置 `log_min_duration_statement = 1000` | 持续出现 |
| 磁盘使用率 | `SELECT pg_database_size('postgres');` | > 80% |
| HNSW 索引大小 | `SELECT pg_size_pretty(pg_relation_size('idx_vertex_embeddings_hnsw'));` | 异常增长 |

### 5.2 监控脚本示例

```sql
-- 当前活跃查询概览
SELECT pid, usename, application_name,
       state, wait_event_type, wait_event,
       now() - query_start AS duration,
       left(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY now() - query_start DESC
LIMIT 20;

-- 表统计信息（死元组比例检查）
SELECT schemaname, tablename,
       n_live_tup, n_dead_tup,
       round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_ratio,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE (n_live_tup + n_dead_tup) > 0
ORDER BY dead_ratio DESC;

-- 索引使用统计
SELECT indexrelname, idx_scan, idx_tup_read, idx_tup_fetch,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'ontosql'
ORDER BY idx_scan DESC;
```

### 5.3 慢查询分析

```sql
-- 启用 pg_stat_statements 扩展（需先 CREATE EXTENSION）
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Top-10 最慢查询
SELECT queryid, calls,
       round(mean_exec_time::numeric, 2) AS avg_ms,
       round(total_exec_time::numeric, 2) AS total_ms,
       left(query, 80) AS query_snippet
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 重置统计（性能测试前后使用）
SELECT pg_stat_statements_reset();
```

---

## 6. 安全加固

### 6.1 认证与授权

```sql
-- 为 postgres 用户设置强密码
ALTER USER postgres PASSWORD 'strong_random_password';

-- 创建应用专用用户（最小权限原则）
CREATE USER ontosql_app WITH PASSWORD 'app_password';
GRANT USAGE ON SCHEMA ontosql TO ontosql_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ontosql TO ontosql_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ontosql TO ontosql_app;

-- 创建只读用户（报表/分析场景）
CREATE USER ontosql_readonly WITH PASSWORD 'readonly_password';
GRANT USAGE ON SCHEMA ontosql TO ontosql_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA ontosql TO ontosql_readonly;

-- 默认拒绝 public schema 的创建权限
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

### 6.2 网络安全

```bash
# pg_hba.conf 最小化配置
# 本地连接
local   all             all                     md5
# 应用服务器（仅允许白名单 IP）
host    all             ontosql_app            10.0.1.0/24         md5
# DBA 管理网络
host    all             postgres               10.0.0.0/24         md5
# 禁止其他所有连接
host    all             all                    0.0.0.0/0           reject

# 重载配置
psql -U postgres -c "SELECT pg_reload_conf();"
```

### 6.3 数据加密

```sql
-- 启用 SSL 连接（编译时需 --with-openssl）
ALTER SYSTEM SET ssl = 'on';
ALTER SYSTEM SET ssl_cert_file = '/etc/ssl/certs/server.crt';
ALTER SYSTEM SET ssl_key_file = '/etc/ssl/private/server.key';
SELECT pg_reload_conf();
```

### 6.4 审计日志

```sql
-- 启用审计日志（记录所有 DDL 和连接事件）
ALTER SYSTEM SET log_statement = 'ddl';           -- 记录 CREATE/ALTER/DROP
ALTER SYSTEM SET log_connections = 'on';           -- 记录连接尝试
ALTER SYSTEM SET log_disconnections = 'on';        -- 记录断开事件
ALTER SYSTEM SET log_lock_waits = 'on';            -- 记录锁等待超过 deadlock_timeout 的情况
SELECT pg_reload_conf();
```

---

## 7. 常见问题排查

### Q1: AGE Cypher 查询报错 "label not found"

**原因**：未创建对应的 vertex label 或 edge label。

**解决**：
```sql
SET search_path TO ontosql, ag_catalog, public;
SELECT create_vlabel('ontosql_graph', 'YourLabel');
SELECT create_elabel('ontosql_graph', 'YOUR_EDGE');
```

### Q2: 向量搜索报 "type vector does not exist"

**原因**：pgvector 扩展未加载或 schema search_path 未包含 ontosql。

**解决**：
```sql
CREATE EXTENSION IF NOT EXISTS vector;
SET search_path TO ontosql, ag_catalog, public;
```

### Q3: HNSW 索引构建非常慢

**原因**：ef_construction 值过大，或向量维度高且数据量大。

**解决**：
- 降低 `ef_construction`（如 100）加快构建，牺牲少量精度
- 分批插入数据后再建索引（而非插入时即时更新索引）
- 对于百万级以上数据，考虑分表 + 分区索引

### Q4: 查询性能突然下降

**可能原因和排查步骤**：

```sql
-- 1. 检查是否有长时间运行的事务阻塞了 VACUUM
SELECT pid, now() - xact_start AS age, query
FROM pg_stat_activity WHERE state != 'idle' AND now() - xact_start > interval '5 min';

-- 2. 检查表膨胀情况
SELECT tablename, n_dead_tup, n_live_tup
FROM pg_stat_user_tables WHERE tablename IN ('vertex_embeddings','attribute_embeddings');

-- 3. 手动执行 VACUUM ANALYZE
VACUUM ANALYZE ontosql.vertex_embeddings;
VACUUM ANALYZE ontosql.attribute_embeddings;

-- 4. 检查索引是否已损坏
REINDEX INDEX CONCURRENTLY idx_vertex_embeddings_hnsw;
```

### Q5: 磁盘空间不足

**解决**：
```bash
# 检查 PG 数据目录大小
du -sh build/data/

# 检查 WAL 日志大小
du -sh build/data/pg_wal/

# 手动触发 checkpoint 回收 WAL
psql -U postgres -c "CHECKPOINT;"

# 清理归档日志（如果未启用 PITR）
# 检查日志目录
du -sh build/data/pg_log/

# 扩展磁盘或迁移数据目录
pg_ctl -D build/data stop
cp -r build/data /mnt/large_disk/
# 修改 PGDATA 环境变量后重启
```

---

## 8. 版本更新策略

### 8.1 组件升级路径

| 组件 | 升级方式 | 停机时间 | 回滚方案 |
|------|---------|---------|---------|
| PG 小版本 (17.x → 17.y) | `make build-pg && pg_ctl restart` | ~秒级 | 重新安装旧版本 |
| PG 大版本 (17 → 18) | `pg_upgrade --link` | ~分钟级 | 保留旧版本数据目录 |
| pgvector | `make build-pgvector && pg_ctl restart` | ~秒级 | 重新安装旧版本 |
| Apache AGE | `make build-age && pg_ctl restart` | ~秒级 | 重新安装旧版本 |
| ontosql SQL Schema | `psql -f sql/001_core_schema.sql` | 0 | 保持向下兼容，无需回滚 |

### 8.2 升级步骤示例（PG 小版本）

```bash
# 更新 PG 源码
cd upstream/postgresql
git pull origin REL_17_STABLE

# 重新编译
cd ../..
make build-pg

# 快速重启（连接会断开，事务会回滚）
make stop
make start

# 或使用 pg_ctl 的 fast 模式（等待当前事务完成）
build/pgsql17/bin/pg_ctl -D build/data -m fast restart
```

### 8.3 升级前检查清单

- [ ] 备份全库数据
- [ ] 在测试环境验证新版本兼容性
- [ ] 确认所有扩展在新版本可用
- [ ] 通知用户/应用计划维护窗口
- [ ] 准备回滚方案
- [ ] 升级后执行 `make test` 确认所有测试通过
