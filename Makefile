# ============================================================================
# OntoSQL 顶层 Makefile
# ============================================================================
# 功能：管理 PostgreSQL + pgvector + Apache AGE 的编译、安装、启停和测试
# 用法：make <target>
# ============================================================================

.PHONY: all build build-pg build-pgvector build-age install init-db start stop clean test docs psql

# ----------------------------------------------------------------------------
# 路径配置
# ----------------------------------------------------------------------------
# PG 安装目录
PG_HOME     ?= $(CURDIR)/build/pgsql17
# pg_config 路径
PG_CONFIG   ?= $(PG_HOME)/bin/pg_config
# 数据目录
PG_DATA     ?= $(CURDIR)/build/data
# 运行日志
PG_LOG      ?= $(PG_DATA)/pg.log
# 监听端口
PG_PORT     ?= 5432
# 数据库用户（peer 认证时需与 OS 用户一致，可通过环境变量覆盖）
PG_USER     ?= $$(whoami)

# 上游源码路径
PG_SRC      := $(CURDIR)/upstream/postgresql
PGV_SRC     := $(CURDIR)/upstream/pgvector
AGE_SRC     := $(CURDIR)/upstream/age

# ----------------------------------------------------------------------------
# all — 默认目标：编译全部组件
# ----------------------------------------------------------------------------
all: build

build: build-pg build-pgvector build-age
	@echo "=== All components built ==="

# ----------------------------------------------------------------------------
# build-pg — 编译 PostgreSQL
# ----------------------------------------------------------------------------
# 使用 REL_17_STABLE 源码，启用调试和断言便于开发排查
# 配置选项：
#   --enable-cassert    启用断言检查（开发阶段推荐）
#   --with-icu          启用 ICU 排序
#   --with-lz4/zstd     启用高级压缩
#   --with-openssl      启用 SSL 连接加密
#   --with-libxml/xslt  启用 XML 支持
# ----------------------------------------------------------------------------
build-pg:
	@echo "=== Building PostgreSQL ==="
	cd $(PG_SRC) && \
		./configure --prefix=$(PG_HOME) \
			--enable-debug --enable-cassert \
			--with-icu --with-lz4 --with-zstd \
			--with-openssl --with-libxml --with-libxslt
	$(MAKE) -C $(PG_SRC) -j$$(sysctl -n hw.ncpu 2>/dev/null || nproc)
	$(MAKE) -C $(PG_SRC) install

# ----------------------------------------------------------------------------
# build-pgvector — 编译 pgvector 扩展
# ----------------------------------------------------------------------------
build-pgvector:
	@echo "=== Building pgvector ==="
	$(MAKE) -C $(PGV_SRC) PG_CONFIG=$(PG_CONFIG) -j4
	$(MAKE) -C $(PGV_SRC) PG_CONFIG=$(PG_CONFIG) install

# ----------------------------------------------------------------------------
# build-age — 编译 Apache AGE 扩展
# ----------------------------------------------------------------------------
# 注意：AGE master 分支针对 PG 18 开发，已通过版本守卫兼容 PG 17
build-age:
	@echo "=== Building Apache AGE ==="
	$(MAKE) -C $(AGE_SRC) PG_CONFIG=$(PG_CONFIG) -j4
	$(MAKE) -C $(AGE_SRC) PG_CONFIG=$(PG_CONFIG) install

# ----------------------------------------------------------------------------
# install — 安装 SQL Schema 文件到 PG 共享目录
# ----------------------------------------------------------------------------
install: build
	@echo "=== Installing SQL schema ==="
	cp $(CURDIR)/sql/*.sql $(PG_HOME)/share/

# ----------------------------------------------------------------------------
# init-db — 初始化新的数据库实例（会清空旧数据）
# ----------------------------------------------------------------------------
# 配置项写入 postgresql.conf 和 pg_hba.conf
# 注意：pg_hba.conf 使用覆盖写入（>）而非追加（>>），确保自定义规则不会被
#       initdb 默认生成的 trust 规则遮蔽（首条匹配优先原则）
#       scram-sha-256 替代 md5 提供更强的密码哈希保护
init-db:
	@echo "=== Initializing database ==="
	rm -rf $(PG_DATA)
	$(PG_HOME)/bin/initdb -D $(PG_DATA) --encoding=UTF8 --locale=C.UTF-8 --auth=scram-sha-256
	@echo "listen_addresses = '*'" >> $(PG_DATA)/postgresql.conf
	@echo "shared_buffers = 256MB" >> $(PG_DATA)/postgresql.conf
	@echo "work_mem = 16MB" >> $(PG_DATA)/postgresql.conf
	@echo "port = $(PG_PORT)" >> $(PG_DATA)/postgresql.conf
	@echo "statement_timeout = 30000" >> $(PG_DATA)/postgresql.conf
	@printf 'local   all             all                                     peer\nhost    all             all             0.0.0.0/0               scram-sha-256\nhost    all             all             ::/128                  scram-sha-256\n' > $(PG_DATA)/pg_hba.conf

# ----------------------------------------------------------------------------
# start — 启动数据库并加载 vector 和 age 扩展
# ----------------------------------------------------------------------------
start:
	$(PG_HOME)/bin/pg_ctl -D $(PG_DATA) -l $(PG_LOG) start
	@echo "=== PostgreSQL started on port $(PG_PORT) ==="
	@sleep 2
	$(PG_HOME)/bin/psql -p $(PG_PORT) -U $(PG_USER) -d postgres \
		-c "CREATE EXTENSION IF NOT EXISTS vector;"
	$(PG_HOME)/bin/psql -p $(PG_PORT) -U $(PG_USER) -d postgres \
		-c "CREATE EXTENSION IF NOT EXISTS age;"
	@echo "=== Extensions loaded ==="

# ----------------------------------------------------------------------------
# stop — 停止数据库
# ----------------------------------------------------------------------------
stop:
	$(PG_HOME)/bin/pg_ctl -D $(PG_DATA) stop || true

# ----------------------------------------------------------------------------
# clean — 清理所有编译产物和数据
# ----------------------------------------------------------------------------
# 先停止运行中的数据库，再清理源码编译产物，最后删除安装目录
clean:
	$(PG_HOME)/bin/pg_ctl -D $(PG_DATA) stop 2>/dev/null || true
	$(MAKE) -C $(PG_SRC) clean 2>/dev/null || true
	$(MAKE) -C $(PGV_SRC) clean 2>/dev/null || true
	$(MAKE) -C $(AGE_SRC) clean 2>/dev/null || true
	rm -rf $(PG_HOME) $(PG_DATA)

# ----------------------------------------------------------------------------
# test — 运行测试套件
# ----------------------------------------------------------------------------
# 流程：初始化测试环境 → 创建 ontosql Schema → 执行 23 组测试用例
test:
	$(PG_HOME)/bin/psql -p $(PG_PORT) -U $(PG_USER) -d postgres -f $(CURDIR)/tests/setup.sql
	$(PG_HOME)/bin/psql -p $(PG_PORT) -U $(PG_USER) -d postgres -f $(CURDIR)/tests/test_cases.sql

# ----------------------------------------------------------------------------
# docs — 文档索引
# ----------------------------------------------------------------------------
docs:
	@echo "=== Documentation available in docs/ ==="
	@echo "  docs/api.md              - API reference"
	@echo "  docs/ops.md              - Operations manual"
	@echo "  docs/architecture.md     - Architecture overview"
	@echo "  docs/overview.md         - Project overview"
	@echo "  docs/modules.md          - Module reference"
	@echo "  docs/data_dictionary.md  - Data dictionary"
	@echo "  docs/object_index.md     - Object graph index"
	@echo "  docs/code_review.md      - Code review report"
	@echo "  docs/consistency_audit.md - Consistency audit report"
	@echo "  docs/agent_guide.md      - Agent integration guide"
	@echo "  docs/knowledge_graph.md  - Ontology graph (agent-oriented)"
	@echo "  examples/usage.sql       - Usage examples"

# ----------------------------------------------------------------------------
# psql — 快速进入数据库交互终端
# ----------------------------------------------------------------------------
psql:
	$(PG_HOME)/bin/psql -p $(PG_PORT) -U $(PG_USER) -d postgres
