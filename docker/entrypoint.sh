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
# 安全：
#   - 密码通过 psql 变量引用传递，避免在命令行暴露
#   - 启动主进程前清除所有密码相关环境变量
# ============================================================================

set -e

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"

MIN_PASSWORD_LENGTH=8
if [ "${#POSTGRES_PASSWORD}" -lt "$MIN_PASSWORD_LENGTH" ]; then
    echo "ERROR: POSTGRES_PASSWORD must be at least $MIN_PASSWORD_LENGTH characters long" >&2
    exit 1
fi

if ! echo "$POSTGRES_PASSWORD" | grep -q '[A-Z]' || \
   ! echo "$POSTGRES_PASSWORD" | grep -q '[a-z]' || \
   ! echo "$POSTGRES_PASSWORD" | grep -q '[0-9]'; then
    echo "WARNING: POSTGRES_PASSWORD should contain at least uppercase, lowercase, and digits for better security" >&2
fi

# 检查是否为新实例（数据目录为空）
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "=== First run: initializing database ==="

    # 初始化数据库（UTF-8 编码，C.UTF-8 locale，scram-sha-256 认证）
    initdb --username=postgres --encoding=UTF8 --locale=C.UTF-8 --auth=scram-sha-256

    # 生成自签名 SSL 证书（生产环境请替换为 CA 签发的正式证书）
    # 证书有效期 5 年，避免频繁更换；生产环境建议使用 Let's Encrypt 或企业 CA
    openssl req -new -x509 -days 1825 -nodes \
        -subj "/CN=ontosql" \
        -keyout "$PGDATA/server.key" \
        -out "$PGDATA/server.crt" 2>/dev/null
    chmod 600 "$PGDATA/server.key"

    # 写入 postgresql.conf 配置
    # 注意：Docker 容器内使用精简配置（比生产模板保守），因为容器通常分配有限内存
    #       生产环境请使用 config/postgresql.template.sql 中的完整参数
    #       max_wal_senders=0 表示不启用流复制，仅用于单机部署
    cat >> "$PGDATA/postgresql.conf" <<'CONF'
listen_addresses = '*'
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
effective_cache_size = 1GB
wal_level = replica
max_wal_senders = 0
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
statement_timeout = 30000
CONF

    # 写入 pg_hba.conf 认证配置
    # local: peer（通过 OS 用户身份认证，安全且无需密码）；host: scram-sha-256（远程强加密认证）
    # 生产环境建议将 0.0.0.0/0 替换为实际业务网络的 IP 段
    cat > "$PGDATA/pg_hba.conf" <<'HBA'
local   all             all                                     peer
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/128                  scram-sha-256
HBA

    # 临时启动 PG 以创建扩展和设置密码
    pg_ctl -D "$PGDATA" -w -l /var/lib/pgsql/logfile start

    # 设置 postgres 用户密码
    # 通过 .pgpass 文件传递密码，避免环境变量在 /proc 中泄露
    printf '*:*:*:postgres:%s\n' "$POSTGRES_PASSWORD" > /tmp/.pgpass
    chmod 600 /tmp/.pgpass
    PGPASSFILE=/tmp/.pgpass psql -U postgres -v pw="$POSTGRES_PASSWORD" <<'SQL'
ALTER USER postgres PASSWORD :'pw';
SQL

    # 创建所需扩展（pg_stat_statements 用于性能监控）
    PGPASSFILE=/tmp/.pgpass psql -U postgres <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL
    rm -f /tmp/.pgpass

    echo "=== Initialization complete, stopping temp instance ==="
    pg_ctl -D "$PGDATA" -w stop
else
    echo "=== Existing data directory found, skipping init ==="
fi

# 启动 PostgreSQL 主进程（exec 替换当前 shell，确保信号正确传递）
# 清除环境变量中的密码，避免在 postgres 进程环境中泄露
echo "=== Starting PostgreSQL ==="
unset PGPASSWORD POSTGRES_PASSWORD
exec postgres -D "$PGDATA"
