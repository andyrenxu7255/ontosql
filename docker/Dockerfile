# ============================================================================
# OntoSQL Docker 多阶段构建
# ============================================================================
# 构建：docker build -t ontosql:latest -f docker/Dockerfile .
# 说明：阶段 1 编译 PG + pgvector + AGE；阶段 2 仅保留运行时依赖

# ============================================================================
# 阶段 1: Builder — 编译环境
# ============================================================================
FROM debian:bookworm-slim AS builder

# 安装编译工具和依赖库
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        bison \
        flex \
        libreadline-dev \
        zlib1g-dev \
        libssl-dev \
        libicu-dev \
        libxml2-dev \
        libxslt1-dev \
        libperl-dev \
        python3-dev \
        tcl-dev \
        liblz4-dev \
        libzstd-dev \
        libsystemd-dev \
        pkg-config \
        ca-certificates \
        git \
        wget \
    ; \
    rm -rf /var/lib/apt/lists/*

# 复制上游源码到编译容器
COPY upstream/postgresql /tmp/postgresql
COPY upstream/pgvector /tmp/pgvector
COPY upstream/age /tmp/age

# 编译 PostgreSQL
WORKDIR /tmp/postgresql
RUN ./configure \
        --prefix=/usr/local/pgsql \
        --enable-debug \
        --enable-cassert \
        --with-icu \
        --with-lz4 \
        --with-zstd \
        --with-openssl \
        --with-libxml \
        --with-libxslt \
        --with-perl \
        --with-python \
        --with-tcl \
    && make -j$(nproc) \
    && make install

ENV PATH="/usr/local/pgsql/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/pgsql/lib:$LD_LIBRARY_PATH"

# 编译 pgvector
WORKDIR /tmp/pgvector
RUN make -j$(nproc) PG_CONFIG=/usr/local/pgsql/bin/pg_config \
    && make install PG_CONFIG=/usr/local/pgsql/bin/pg_config

# 编译 Apache AGE（含 PG 18 兼容补丁）
WORKDIR /tmp/age
RUN make -j$(nproc) PG_CONFIG=/usr/local/pgsql/bin/pg_config \
    && make install PG_CONFIG=/usr/local/pgsql/bin/pg_config

# ============================================================================
# 阶段 2: Runtime — 精简运行环境
# ============================================================================
FROM debian:bookworm-slim

# 安装运行时依赖（不含编译器头文件，大幅减小镜像体积）
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libreadline8 \
        zlib1g \
        libssl3 \
        libicu72 \
        libxml2 \
        libxslt1.1 \
        liblz4-1 \
        libzstd1 \
        libperl5.36 \
        python3 \
        libsystemd0 \
        libcurl4 \
    ; \
    rm -rf /var/lib/apt/lists/*

# 从构建阶段复制已编译的 PG 安装目录
COPY --from=builder /usr/local/pgsql /usr/local/pgsql

# 创建 postgres 用户和数据目录
RUN groupadd -r postgres && useradd -r -g postgres -d /var/lib/pgsql postgres \
    && mkdir -p /var/lib/pgsql/data /var/run/pgsql \
    && chown -R postgres:postgres /var/lib/pgsql /var/run/pgsql

# 环境变量
ENV PATH="/usr/local/pgsql/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/pgsql/lib:$LD_LIBRARY_PATH"
ENV PGDATA="/var/lib/pgsql/data"

# 入口脚本
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 暴露 PostgreSQL 默认端口
EXPOSE 5432

# 以 postgres 用户运行
USER postgres
ENTRYPOINT ["/entrypoint.sh"]
