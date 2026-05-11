# OntoSQL 代码审查报告

> 审查日期：2026-05-06 | 审查范围：全项目 19 个文件

---

## 一、总体评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 代码规范性 | ★★★★☆ | SQL 命名清晰、注释详尽，Makefile 结构合理 |
| 架构设计 | ★★★★★ | 三层分离设计（向量侧表 + 图结构 + 物化关联表）职责分明 |
| 安全性 | ★★★☆☆ | 存在若干开发便利性妥协，生产部署需额外加固 |
| 性能 | ★★★★☆ | 索引设计合理，HNSW + B-tree + GIN 多索引策略得当 |
| 测试覆盖 | ★★★★★ | 23 组测试覆盖核心功能、安全校验和边界条件 |
| 可维护性 | ★★★★☆ | 函数封装良好，upsert 幂等设计，文档齐全 |

---

## 二、语法与逻辑检查

### 2.1 SQL 语法正确性

所有 SQL 文件语法正确，无语法错误。关键验证点：

| 文件 | 检查项 | 结果 |
|------|--------|------|
| `001_core_schema.sql` | CREATE TABLE / INDEX / FUNCTION 语法 | ✅ 通过 |
| `001_core_schema.sql` | PL/pgSQL 变量声明、异常处理 | ✅ 通过 |
| `002_knowledge_graph.sql` | AGE Cypher CREATE / MATCH 语法 | ✅ 通过 |
| `tests/test_cases.sql` | DO 块匿名函数、游标遍历 | ✅ 通过 |

### 2.2 逻辑正确性

**已确认正确的逻辑：**

1. **多路召回合并算法** — `search_objects()` 和 `search_attributes()` 中 UNION ALL + GROUP BY + MAX 去重合并逻辑正确，加权分数计算合理。

2. **Upsert 语义** — `upsert_vertex_embedding()` 和 `upsert_attribute_embedding()` 使用 `ON CONFLICT ... DO UPDATE` 配合 `COALESCE(EXCLUDED.field, original.field)` 保留旧值的策略正确。

3. **外键引用** — `object_attribute_mapping.attr_id` 正确引用了 `attribute_embeddings(id)`。

4. **关联验证** — `link_object_attribute()` 中的双重校验（检查 vertex_id 和 attr_id 存在性）防止了孤立的关联记录。

**潜在逻辑缺陷：**

| 编号 | 严重程度 | 位置 | 描述 |
|------|---------|------|------|
| L-01 | ⚠️ 中 | `001_core_schema.sql` L176 | `search_objects()` 当 `p_query_embedding IS NOT NULL` 时走向量召回路径，但 `p_query_embedding IS NULL` 时向量 CTS 中的 `ORDER BY ve.embedding <=> p_query_embedding` 会对 NULL 排序，结果不确定。虽然有 `AND p_query_embedding IS NOT NULL` 守卫条件，但 PostgreSQL 在 CTE 中仍会解析整个表达式。**建议**：确认实际执行计划中该分支是否被优化器跳过。 |
| L-02 | ⚠️ 中 | `001_core_schema.sql` L190-L191 | `trigram_scores` CTE 使用 `ve.vertex_name % query_text` 运算符，其阈值取决于 `pg_trgm.similarity_threshold` 参数（默认 0.3）。如果调整过该参数，trigram 召回结果会显著变化，可能导致召回率波动。**建议**：在函数文档中注明依赖该参数。 | ✅ 已修复：已在 `search_objects` 函数注释中添加 trigram 阈值依赖说明 |
| L-03 | ⚠️ 低 | `001_core_schema.sql` L352-L353 | `search_object_attribute()` 的 CROSS JOIN 在 `p_top_k=10` 时最多产生 `20×20=400` 行，可接受。但如果上游调用方传入较大 `p_top_k`（如 100），会产生 `200×200=40000` 行的笛卡尔积。**建议**：对 `p_top_k` 添加上限校验或文档警告。 | ✅ 已修复：函数内部添加 `LEAST(p_top_k * 2, 50)` 截断扩容因子，文档注释中标注 p_top_k 建议不超过 50 |
| L-04 | ⚠️ 低 | `002_knowledge_graph.sql` L149-L299 | 每条边独立执行 Cypher MATCH + CREATE，对于大规模数据初始化效率低。当前示例规模（约 30 条边）无问题，但不适合批量导入。**建议**：文档中注明大规模场景应使用 `LOAD CSV` 或批量 CREATE 语法。 |

---

## 三、性能分析

### 3.1 索引策略评估

```
表: vertex_embeddings
├── idx_vertex_embeddings_hnsw      HNSW (embedding vector_cosine_ops)  ← 向量 ANN，m=16
├── idx_vertex_embeddings_name_trgm  GIN  (vertex_name gin_trgm_ops)    ← 模糊文本匹配
└── idx_vertex_embeddings_label      B-tree (graph_name, label_name)    ← 标签过滤加速

表: attribute_embeddings
├── idx_attribute_embeddings_hnsw     HNSW (embedding vector_cosine_ops)  ← 向量 ANN
└── idx_attribute_embeddings_name_trgm GIN  (attr_name gin_trgm_ops)       ← 模糊文本

表: object_attribute_mapping
├── idx_oam_object  B-tree (graph_name, object_vertex_id)  ← 按对象查属性
└── idx_oam_attr    B-tree (attr_id)                        ← 按属性反查对象
```

**评估：索引覆盖完整，各检索路径均有对应索引加速。** HNSW m=16 适合 10 万级数据量，若超过 100 万建议调整为 m=32。

### 3.2 查询性能评估

| 查询模式 | 复杂度 | 索引利用 | 瓶颈 |
|---------|--------|---------|------|
| `search_objects` 向量召回 | O(log N + K) | HNSW 索引 | 取决于 ef_search |
| `search_objects` trigram 召回 | O(N × pattern_len) | GIN trigram 索引 | 长文本匹配 |
| `find_objects_by_attribute` | O(log N + K) | B-tree 索引 | — |
| `search_object_attribute` | O(M × N) | 依赖子查询索引 | CROSS JOIN 笛卡尔积 |

### 3.3 配置调优建议

| 编号 | 建议 | 影响 |
|------|------|------|
| P-01 | `config/postgresql.template.sql` L17 注释 "8GB 内存的 ~6%" 与实际值 512MB 不匹配（512MB/8GB=6.25% 正确，但与建议的 25% 矛盾） | 配置指南误导 |
| P-02 | 生产环境 `shared_buffers` 建议至少 2GB（见 L17 注释），但模板配置仅 512MB | 性能瓶颈 |
| P-03 | `docker-compose.yml` L46 `memory: 512M` 资源限制可能不足，HNSW 索引查询需要额外内存 | 容器 OOM 风险 |
| P-04 | 未配置 `pg_stat_statements` 扩展（ops.md 中有提及），建议默认安装用于性能监控 | 监控盲区 | ✅ 已修复 |

---

## 四、安全隐患检查

### 4.1 认证与授权

| 编号 | 严重程度 | 位置 | 问题描述 | 修复建议 | 状态 |
|------|---------|------|---------|---------|------|
| S-01 | 🔴 高 | `Makefile` L94-L95 | `init-db` 写入 `host all all 0.0.0.0/0 trust`，允许任何 IP 免密连接 | 改为 `md5`，开发环境也应使用密码认证 | ✅ 已修复：改为 `host ... md5` + `local ... md5` |
| S-02 | 🔴 高 | `entrypoint.sh` L38-L39 | `pg_hba.conf` 中 `local all all trust` 允许本地免密登录 | 生产环境改为 `md5` 或 `peer` | ✅ 已修复：Docker 本地改为 `peer` 认证 |
| S-03 | 🟡 中 | `entrypoint.sh` L47-L52 | 密码通过环境变量传递，可能在进程列表中暴露 | 考虑使用 Docker secrets 或 `PGPASSFILE` | ✅ 已修复：改用 `export PGPASSWORD` + heredoc 避免密码出现在进程列表 |
| S-04 | 🟡 中 | `docker-compose.yml` L24 | 默认密码 `ontosql` 为弱密码，且明文写在配置文件中 | 强制要求设置环境变量，移除默认值 | ✅ 已修复：改为 `${POSTGRES_PASSWORD:?err}` 强制必填 |

### 4.2 SQL 注入风险

- **检索函数 (`search_*`)**: 使用参数化查询，`p_label`、`p_graph_name` 等通过函数参数传入而非字符串拼接，**无 SQL 注入风险**。
- **写入函数 (`upsert_*`, `link_*`)**: 同样使用参数化方式，**无 SQL 注入风险**。
- **AGE Cypher 查询**: `002_knowledge_graph.sql` 中的 Cypher 语句均为静态脚本，无外部输入拼接。但在 `examples/usage.sql` 示例 11 中硬编码了对象名，实际应用中需注意 Cypher 的参数化（AGE 支持 `$param` 语法）。

### 4.3 数据安全

| 编号 | 问题 | 风险 | 建议 |
|------|------|------|------|
| S-05 | `vertex_embeddings.metadata` 列使用 `jsonb` 存储扩展信息，可能包含敏感数据（如 `employee_id`） | 数据泄露 | 如需存储 PII，考虑列级加密或脱敏视图 |
| S-06 | `vector_registry` 表无行级安全策略（RLS） | 多租户场景下的数据隔离 | 若需多租户支持，为所有 ontosql 表启用 RLS |

### 4.4 Docker 安全

- ✅ `no-new-privileges:true` 已配置
- ✅ 使用非 root 用户运行（`USER postgres`）
- ✅ 多阶段构建减小镜像攻击面
- ✅ `cap_drop: ALL` 已配置（仅保留 CHOWN/DAC_OVERRIDE/SETGID/SETUID）
- ⚠️ 未配置 `read_only: true` 根文件系统（需权衡：PG 需要写数据目录）

---

## 五、代码质量与最佳实践

### 5.1 优点

1. **注释详尽** — 每个文件、每个表、每个函数均有完整的头部注释，说明用途、参数、算法和注意事项。
2. **幂等设计** — 所有 DDL 使用 `IF NOT EXISTS`，所有写入使用 `ON CONFLICT ... DO UPDATE`，支持重复执行。
3. **Schema 隔离** — `ontosql` schema 与 `public`、`ag_catalog` 分离，命名空间清晰。
4. **函数封装** — 所有能力通过 SQL/PLpgSQL 函数暴露，应用层零 C 代码依赖。
5. **测试完善** — 23 组测试覆盖存在性验证、CRUD、多路召回、边界条件、错误处理。
6. **配置模板化** — `config/postgresql.template.sql` 提供完整的生产环境参数配置。

### 5.2 改进建议

| 编号 | 类别 | 建议 |
|------|------|------|
| Q-01 | 版本管理 | 为 `ontosql` Schema 添加版本号机制（如 `schema_version` 表），便于升级追踪 | ✅ 已实现：添加 `schema_version` 表并初始化 v1.0.0 |
| Q-02 | 迁移脚本 | 当前 `001_core_schema.sql` 只包含初始 DDL，建议添加迁移脚本目录（`migrations/`）处理增量变更 | 规划中 |
| Q-03 | 监控集成 | `ops.md` 中建议安装 `pg_stat_statements`，但未在 `setup.sql` 或 `entrypoint.sh` 中默认安装 | ✅ 已实现：`tests/setup.sql` 和 `entrypoint.sh` 均已默认安装 |
| Q-04 | 日志格式 | `config/postgresql.template.sql` L80 的 `log_line_prefix` 中使用 `%l-1`（会话行号），在高并发下意义有限，建议增加 `%x`（事务 ID） | ✅ 已实现：`log_line_prefix` 已增加 `txid=%x` |
| Q-05 | 连接池 | `ops.md` 中提到 PgBouncer 但未提供配置文件模板 |
| Q-06 | 错误码 | `api.md` 定义了一组错误码（如 `ERR_EMPTY_QUERY`），但实际函数中未返回这些结构化错误码，仅通过返回空集或 RAISE EXCEPTION 处理 |

---

## 六、文档体系评估

### 6.1 现有文档覆盖度

| 文档 | 覆盖度 | 缺失内容 |
|------|--------|---------|
| README.md | ★★★★☆ | 缺少常见问题 (FAQ) 章节 |
| docs/architecture.md | ★★★★★ | — |
| docs/api.md | ★★★★☆ | 缺少 AGE Cypher 查询的 API 说明 |
| docs/ops.md | ★★★★★ | — |
| docs/overview.md | ★★★☆☆ | 与 README.md 有较多重复内容 |
| examples/usage.sql | ★★★★☆ | 缺少 embedding 实际写入的完整示例 |

### 6.2 文档间一致性

| 检查项 | 结果 |
|--------|------|
| README.md 与 docs/overview.md 版本号一致性 | ⚠️ README: PG 17.4, overview: PG 16/17（不一致） |
| api.md 与 001_core_schema.sql 函数签名一致性 | ✅ 一致 |
| architecture.md 与 002_knowledge_graph.sql 图模型一致性 | ✅ 一致 |

---

## 七、检查结论

> **二次审计（2026-05-07）更新**：本次审计发现先前标记为"已修复"的安全项 S-01 实际修复不完整，并发现 8 项新问题，已全部修复。详见下方 7.3 新增修复项。

### 7.1 已修复（高优先级 — 上次审计，本次验证通过）

1. ✅ **S-01**: `Makefile` 中 `init-db` 的 `trust` 认证已改为覆盖写入 + `peer`+`md5`（**二次审计修复**：上次仅改为追加 md5，未被命中）
2. ✅ **S-02**: `entrypoint.sh` 中 `pg_hba.conf` 的 `local trust` 已改为 `peer`
3. ✅ **S-03**: `entrypoint.sh` 密码传递已优化（psql 变量引用 `:'pw'` + heredoc）
4. ✅ **S-04**: `docker-compose.yml` 已移除默认弱密码，强制要求设置
5. ✅ **L-02**: `search_objects` 函数文档已标注 trigram 阈值依赖
6. ✅ **L-03**: `search_object_attribute` 已添加 `LEAST(p_top_k * 2, 50)` guard
7. ✅ **P-01**: `config/postgresql.template.sql` shared_buffers 已修正为 2GB
8. ✅ **P-04**: `pg_stat_statements` 已默认安装
9. ✅ **Q-01**: `schema_version` 表已添加
10. ✅ **Q-03**: `pg_stat_statements` 已在 setup.sql 和 entrypoint.sh 中默认安装
11. ✅ **Q-04**: `log_line_prefix` 已增加 `txid=%x` (事务 ID)

### 7.2 规划中（低优先级）

12. **L-01**: 确认 `p_query_embedding IS NULL` 时的 CTE 优化器行为
13. **L-04**: 大规模边初始化应使用批量语法
14. **Q-02**: 添加迁移脚本目录（`migrations/`）
15. **Q-05**: 提供 PgBouncer 配置文件模板
16. **Q-06**: 错误码规划（已在 api.md 标注为规划项）
17. **P-02/P-03**: Docker 内存限制与生产配置差异（已在 entrypoint.sh 和 ops.md 中说明差异原因）

### 7.3 新增修复（2026-05-07 二次审计）

| 编号 | 严重程度 | 类别 | 描述 | 修复方案 | 状态 |
|------|---------|------|------|---------|------|
| A-01 | 🔴 CRITICAL | 安全 | `Makefile` init-db 追加（`>>`）md5 规则被 initdb 默认 trust 规则遮蔽（pg_hba.conf 首条匹配优先），导致本地连接实际仍为 trust | 改用 `printf >` 覆盖写入整个 pg_hba.conf，规则：`local peer` + `host md5` | ✅ |
| A-02 | 🔴 HIGH | 安全 | `entrypoint.sh` 密码含单引号时 `ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD}'` SQL 语法错误 | 改用 psql 变量引用 `:'pw'` 语法自动转义特殊字符 | ✅ |
| A-03 | 🔴 HIGH | 安全 | `entrypoint.sh` 在 `exec postgres` 时未清除 `POSTGRES_PASSWORD` 环境变量，密码泄露到 PG 主进程环境 | 在 exec 前添加 `unset PGPASSWORD POSTGRES_PASSWORD` | ✅ |
| A-04 | 🟡 MEDIUM | 性能 | `Dockerfile` 硬编码 `--enable-debug --enable-cassert`，降低生产环境 PG 性能约 10-20% | 添加 `ENABLE_DEBUG` / `ENABLE_CASSERT` 构建参数（默认 0），按需开启 | ✅ |
| A-05 | 🟡 MEDIUM | 运维 | `pgbouncer.ini` 中 `client_idle_timeout=0` 导致空闲客户端连接永不超时，存在连接资源泄漏风险 | 设置为 600 秒，与 `server_idle_timeout` 一致 | ✅ |
| A-06 | 🟡 MEDIUM | 文档 | `examples/usage.sql` 文件头声明"13 个典型场景"但实际只有 11 个 | 修正为 11 | ✅ |
| A-07 | ℹ️ LOW | 配置 | `.gitignore` 缺少 `*.dump` 备份文件模式 | 添加 `*.dump` | ✅ |
| A-08 | ℹ️ LOW | 构建 | Makefile `start`/`test`/`psql` 使用硬编码 `$$(whoami)`，peer 认证切换后需明确用户变量 | 添加 `PG_USER` 变量（默认 `$$(whoami)`），支持环境变量覆盖 | ✅ |
