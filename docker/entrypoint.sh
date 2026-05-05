#!/bin/bash
# ============================================================================
# OntoSQL Docker 容器入口脚本
# ============================================================================
# 功能：
#   1. 首次启动时执行 initdb 初始化数据目录
#   2. 配置 postgresql.conf 和 pg_hba.conf
#   3. 创建 vector 和 age 扩展
#   4. 设置 postgres 用户密码
#   5. 以 postgres 进程作为主进程运行
# ============================================================================

set -e

# 检查是否为新实例（数据目录为空）
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "=== First run: initializing database ==="

    # 初始化数据库（UTF-8 编码，C.UTF-8 locale）
    initdb --username=postgres --encoding=UTF8 --locale=C.UTF-8

    # 写入 postgresql.conf 配置
    # 注意：max_wal_senders=0 表示不启用流复制，仅用于单机部署
    cat >> "$PGDATA/postgresql.conf" <<'CONF'
listen_addresses = '*'
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
effective_cache_size = 1GB
wal_level = replica
max_wal_senders = 0
CONF

    # 写入 pg_hba.conf 认证配置
    # local: trust（本地免密）；host: md5（远程需密码）
    cat > "$PGDATA/pg_hba.conf" <<'HBA'
local   all             all                                     trust
host    all             all             0.0.0.0/0               md5
host    all             all             ::/128                  md5
HBA

    # 临时启动 PG 以创建扩展和设置密码
    pg_ctl -D "$PGDATA" -w -l /var/lib/pgsql/logfile start

    # 设置 postgres 用户密码（通过环境变量或默认值）
    psql -U postgres -c "ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD:-ontosql}';"

    # 创建所需扩展
    psql -U postgres <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
SQL

    echo "=== Initialization complete, stopping temp instance ==="
    pg_ctl -D "$PGDATA" -w stop
else
    echo "=== Existing data directory found, skipping init ==="
fi

# 启动 PostgreSQL 主进程（exec 替换当前 shell，确保信号正确传递）
echo "=== Starting PostgreSQL ==="
exec postgres -D "$PGDATA"
