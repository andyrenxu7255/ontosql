# OntoSQL 模块功能手册

> 本文档按模块详细描述 OntoSQL 项目各组件的功能、职责边界、输入输出及调用关系。

---

## 一、模块总览

```
OntoSQL 项目
├── 1. 核心 Schema 模块 (sql/001_core_schema.sql)        — 数据存储、检索、写入
├── 2. 知识图谱模块 (sql/002_knowledge_graph.sql)        — 图模型定义与示例数据
├── 3. 配置管理模块 (config/postgresql.template.sql)     — 生产环境参数模板
├── 4. 构建部署模块 (Makefile + docker/)                  — 编译、安装、容器化
├── 5. 测试模块 (tests/)                                  — 自动化测试套件
├── 6. 示例模块 (examples/usage.sql)                      — 使用演示
└── 7. 文档模块 (docs/ + README.md)                       — 项目文档
```

---

## 二、核心 Schema 模块

**文件**: [sql/001_core_schema.sql](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql)

### 2.1 模块职责

提供 OntoSQL 的核心数据存储、多路召回检索、数据写入三大能力。所有对象位于 `ontosql` Schema 下。

### 2.2 数据表

#### 2.2.0 `schema_version` — Schema 版本管理

| 项目 | 说明 |
|------|------|
| **用途** | 追踪 Schema 变更历史，支持版本升级和回滚 |
| **主键** | `version` (text) |
| **行数** | 初始 1 行 (v1.0.0) |

#### 2.2.1 `vector_registry` — 向量注册表

| 项目 | 说明 |
|------|------|
| **用途** | 统一管理项目中所有向量侧表的元数据 |
| **主键** | `id` (serial) |
| **唯一约束** | `table_name` |
| **CHECK 约束** | `entity_type IN ('vertex', 'edge', 'attribute')` |
| **CHECK 约束** | `index_type IN ('hnsw', 'ivfflat')` |
| **行数** | 初始 2 行（vertex_embeddings + attribute_embeddings） |

#### 2.2.2 `vertex_embeddings` — 对象向量侧表

| 项目 | 说明 |
|------|------|
| **用途** | 存储图中每个顶点的 embedding 向量，支持语义相似度搜索 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, vertex_id)` |
| **关联** | 通过 `(graph_name, vertex_id)` 与 AGE 图顶点一一对应 |
| **索引** | HNSW (向量) + GIN trigram (文本) + B-tree (标签过滤) |

#### 2.2.3 `attribute_embeddings` — 属性向量侧表

| 项目 | 说明 |
|------|------|
| **用途** | 存储指标/维度等属性的 embedding 向量，支持语义属性识别 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, attr_name)` |
| **特性** | 支持别名数组 `aliases text[]`，提高同义词召回率 |
| **索引** | HNSW (向量) + GIN trigram (文本) |

#### 2.2.4 `object_attribute_mapping` — 图关系的物化缓存

| 项目 | 说明 |
|------|------|
| **用途** | 物化 AGE 图中的对象-属性关联，作为图遍历的读优化缓存。AGE 图是权威来源 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, object_vertex_id, attr_id)` |
| **外键** | `attr_id → attribute_embeddings(id)` |
| **特性** | `link_object_attribute` 同时维护本表和 AGE 图边；`confidence` 支持概率化关联 |
| **索引** | 按对象查询 + 按属性反查 |

### 2.3 检索函数（4 个公开函数）

#### 2.3.1 `search_objects(query_text, p_graph_name, p_label, p_top_k, p_query_embedding)`

```
┌──────────────────────────────────────────────────┐
│ 功能：对象识别（多路召回：向量 + trigram）         │
│                                                   │
│ 输入：                                            │
│   query_text          NL 查询文本                 │
│   p_graph_name        图名 (default: 'ontosql_graph')   │
│   p_label             标签过滤 (NULL = 不限)      │
│   p_top_k             返回数量 (default: 10)      │
│   p_query_embedding   查询向量 (NULL = 仅trigram) │
│                                                   │
│ 输出：                                            │
│   vertex_id, vertex_name, label_name,             │
│   vector_score, trigram_score, combined_score     │
│                                                   │
│ 算法：                                            │
│   向量 HNSW ANN (p_top_k × 3)                     │
│     + trigram GIN 匹配 (p_top_k × 3)              │
│     → UNION ALL → GROUP BY → MAX → LIMIT          │
│   综合分 = 0.6 × vector_score + 0.4 × trigram     │
│                                                   │
│ 语言：plpgsql STABLE PARALLEL SAFE                  │
└──────────────────────────────────────────────────┘
```

#### 2.3.2 `search_attributes(query_text, p_graph_name, p_top_k, p_query_embedding)`

```
┌──────────────────────────────────────────────────┐
│ 功能：属性识别（多路召回：向量 + trigram）         │
│                                                   │
│ 输入：                                            │
│   query_text          NL 查询文本                 │
│   p_graph_name        图名                        │
│   p_top_k             返回数量                    │
│   p_query_embedding   查询向量                    │
│                                                   │
│ 输出：                                            │
│   attr_name, attr_id, description,                │
│   vector_score, trigram_score, combined_score     │
│                                                   │
│ 算法：同 search_objects，作用于 attribute_embeddings│
│        trigram 召回同时检查 attr_name 和 aliases 数组 │
│                                                   │
│ 语言：plpgsql STABLE PARALLEL SAFE                  │
└──────────────────────────────────────────────────┘
```

#### 2.3.3 `find_objects_by_attribute(p_attr_id, p_graph_name, p_top_k)`

```
┌──────────────────────────────────────────────────┐
│ 功能：属性反查对象                                │
│                                                   │
│ 输入：                                            │
│   p_attr_id           属性 ID                     │
│   p_graph_name        图名                        │
│   p_top_k             返回数量上限                │
│                                                   │
│ 输出：                                            │
│   object_vertex_id, object_name,                  │
│   object_label, relation_type                     │
│                                                   │
│ 算法：                                            │
│   object_attribute_mapping (物化表)               │
│     LEFT JOIN vertex_embeddings (补全名称)        │
│                                                   │
│ 语言：plpgsql STABLE PARALLEL SAFE                  │
└──────────────────────────────────────────────────┘
```

#### 2.3.4 `search_object_attribute(query_text, p_graph_name, p_top_k, p_query_embedding)` — **核心接口**

```
┌──────────────────────────────────────────────────┐
│ 功能：语义召回 + AGE 图验证（按图索骥）          │
│                                                   │
│ 输入：                                            │
│   query_text          NL 查询文本                 │
│   p_graph_name        图名                        │
│   p_top_k             返回数量                    │
│   p_query_embedding   查询向量                    │
│                                                   │
│ 输出：                                            │
│   object_vertex_id, object_name, object_label,    │
│   attr_name, attr_id, obj_score, attr_score,      │
│   combined_score, is_verified                     │
│                                                   │
│ 算法：                                            │
│   1. search_objects()  ×2 扩容候选对象            │
│   2. search_attributes() ×2 扩容候选属性          │
│   3. AGE 图 Cypher 批量验证：                     │
│      MATCH (obj:Object)-[r]->(prop)               │
│      WHERE id(obj) IN [...] AND id(prop) IN [...] │
│   4. 属性未建模为图顶点时，回退查 mapping 表      │
│   5. CROSS JOIN + 综合分 = 0.5×obj + 0.5×attr     │
│                                                   │
│ 语言：plpgsql STABLE PARALLEL SAFE                  │
│ 注意：CROSS JOIN 产生 O(N×M) 候选对               │
└──────────────────────────────────────────────────┘
```

### 2.4 写入函数（3 个公开函数）

#### 2.4.1 `upsert_vertex_embedding(p_vertex_id, p_graph_name, p_label_name, p_vertex_name, p_embedding, p_description, p_metadata)` → void

- **语言**: PL/pgSQL
- **行为**: INSERT ON CONFLICT DO UPDATE（upsert）
- **特性**: 更新时 `description` 使用 COALESCE 保留旧值

#### 2.4.2 `upsert_attribute_embedding(p_attr_name, p_graph_name, p_embedding, p_attr_vertex_id, p_aliases, p_description, p_data_type)` → int

- **语言**: PL/pgSQL
- **行为**: INSERT ON CONFLICT DO UPDATE
- **返回**: `attr_id`（用于后续调用 `link_object_attribute()`）

#### 2.4.3 `link_object_attribute(p_graph_name, p_object_vertex_id, p_attr_id, p_relation_type, p_confidence)` → void

- **语言**: PL/pgSQL
- **行为**: 同时写入 `object_attribute_mapping` 映射表 + AGE 图（若属性已建模为图顶点）
- **校验**:
  1. 检查 `vertex_id` 在 `vertex_embeddings` 中存在
  2. 检查 `attr_id` 在 `attribute_embeddings` 中存在
  3. 校验失败抛出 EXCEPTION
- **图同步**: 若属性有 `attr_vertex_id`，同步在 AGE 图中创建 `Object -[HAS_METRIC]-> Metric` 边

---

## 三、知识图谱模块

**文件**: [sql/002_knowledge_graph.sql](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql)

### 3.1 模块职责

提供「智能问数」场景的示例知识图谱，演示 AGE 图模型的定义和使用。

### 3.2 图模型

```
图名: ontosql_graph

顶点标签（Vertex Labels）:
┌──────────────┬──────────────────────────────────┐
│ 标签         │ 含义                             │
├──────────────┼──────────────────────────────────┤
│ Object       │ 业务对象（员工、产品、客户）       │
│ Metric       │ 指标属性（销售额、利润率等）       │
│ Dimension    │ 分析维度（本月、上月等）           │
│ Department   │ 组织部门（销售部、技术部等）       │
└──────────────┴──────────────────────────────────┘

边标签（Edge Labels）:
┌─────────────────┬───────────────────────────────┐
│ 标签            │ 含义                          │
├─────────────────┼───────────────────────────────┤
│ HAS_METRIC      │ 对象拥有指标                  │
│ BELONGS_TO      │ 对象归属部门                  │
│ HAS_DIMENSION   │ 指标关联维度                  │
│ RELATED_TO      │ 对象间通用关系                │
└─────────────────┴───────────────────────────────┘
```

### 3.3 示例数据规模

| 实体类型 | 数量 | 示例 |
|---------|------|------|
| Department | 4 | 销售部、技术部、财务部、市场部 |
| Object (employee) | 5 | 张三、李四、王五、赵六、钱七 |
| Object (product) | 3 | 产品A、产品B、产品C |
| Object (customer) | 3 | 华科科技、数据之光、星辰网络 |
| Metric | 9 | 销售额、利润率、客户数、订单量... |
| Dimension | 6 | 本月、上月、本季度... |
| Edges (关系) | ~30 | HAS_METRIC, BELONGS_TO, ... |

### 3.4 使用方式

```sql
SET search_path TO ontosql, ag_catalog, public;

-- 查询所有员工
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (o:Object {type: 'employee'}) RETURN o.name
$$) AS (name agtype);

-- 查询张三的指标
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (o:Object {name: '张三'})-[:HAS_METRIC]->(m:Metric)
    RETURN m.name, m.unit
$$) AS (name agtype, unit agtype);
```

---

## 四、配置管理模块

**文件**: [config/postgresql.template.sql](file:///Users/liuruiqi/ontosql/config/postgresql.template.sql)

### 4.1 模块职责

提供生产环境 PostgreSQL 参数配置模板，涵盖内存、连接、WAL、规划器、扩展、日志六大类配置。

### 4.2 配置分类

| 分类 | 参数数量 | 关键参数 |
|------|---------|---------|
| 内存配置 | 5 | shared_buffers, effective_cache_size, work_mem |
| 连接配置 | 2 | max_connections, superuser_reserved_connections |
| WAL 配置 | 5 | wal_level, max_wal_size, checkpoint_completion_target |
| 规划器配置 | 3 | random_page_cost, effective_io_concurrency |
| 扩展配置 | 1 | hnsw.ef_search |
| 日志配置 | 8 | log_min_duration_statement, log_line_prefix |

### 4.3 使用方式

```sql
-- 加载配置模板
psql -U postgres -d postgres -f config/postgresql.template.sql

-- 配置通过 ALTER SYSTEM SET 写入 postgresql.auto.conf
-- pg_reload_conf() 使其生效（大多数参数无需重启）
```

---

## 五、构建部署模块

### 5.1 Makefile

**文件**: [Makefile](file:///Users/liuruiqi/ontosql/Makefile)

| Target | 功能 | 依赖 |
|--------|------|------|
| `all` / `build` | 编译全部组件 | build-pg → build-pgvector → build-age |
| `build-pg` | 编译 PostgreSQL 17.4 | upstream/postgresql 源码 |
| `build-pgvector` | 编译 pgvector 0.8.1 | PG 已安装 |
| `build-age` | 编译 Apache AGE | PG 已安装 |
| `install` | 复制 SQL 文件到 PG 共享目录 | build |
| `init-db` | 初始化数据库实例 | 无 |
| `start` | 启动数据库 + 创建扩展 | init-db |
| `stop` | 停止数据库 | 无 |
| `clean` | 清理所有编译产物 | 无 |
| `test` | 运行测试套件 | start |
| `psql` | 进入交互终端 | start |
| `docs` | 显示文档索引 | 无 |

### 5.2 Docker 容器化

| 文件 | 功能 |
|------|------|
| [Dockerfile](file:///Users/liuruiqi/ontosql/docker/Dockerfile) | 多阶段构建（builder → runtime），编译 PG + 扩展 |
| [docker-compose.yml](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml) | 服务编排，端口映射，数据持久化，健康检查，资源限制 |
| [entrypoint.sh](file:///Users/liuruiqi/ontosql/docker/entrypoint.sh) | 首次启动初始化数据目录、配置认证、创建扩展、启动 PG |

---

## 六、测试模块

**文件**: [tests/setup.sql](file:///Users/liuruiqi/ontosql/tests/setup.sql), [tests/test_cases.sql](file:///Users/liuruiqi/ontosql/tests/test_cases.sql)

### 6.1 测试架构

```
tests/setup.sql
  ├── 创建扩展 (vector, age, pg_trgm)
  ├── 设置 search_path
  └── 加载 001_core_schema.sql

tests/test_cases.sql
  ├── ON_ERROR_STOP on + timing on
  └── 匿名 DO 块 (PL/pgSQL)
       ├── TEST-1   Schema 存在性验证 (3 项)
       ├── TEST-2   索引存在性验证 (2 项)
       ├── TEST-3   数据类型验证 (vector, agtype)
       ├── TEST-4   upsert_vertex_embedding (insert + update)
       ├── TEST-5   upsert_attribute_embedding (insert + update)
       ├── TEST-6   link_object_attribute (create + upsert)
       ├── TEST-7   search_objects (功能 + 空查询边界)
       ├── TEST-8   search_attributes (功能)
       ├── TEST-9   find_objects_by_attribute (功能 + 无效ID边界)
       ├── TEST-10  search_object_attribute (功能 + 验证)
       ├── TEST-11  pg_trgm extension 功能
       ├── TEST-12  边界条件：不存在的图
       ├── TEST-13  vector_registry 元数据完整性
       ├── TEST-14  安全校验：validate_query_text
       ├── TEST-15  安全校验：search_objects 参数验证
       ├── TEST-16  安全校验：search_object_attribute 参数验证
       ├── TEST-17  安全校验：upsert/link 函数校验
       ├── TEST-18  NULL 参数补充测试
       ├── TEST-19  embedding 维度校验
       ├── TEST-20  link_object_attribute 置信度校验
       ├── TEST-21  get_object_attributes (功能+边界)
       ├── TEST-22  get_related_objects (功能)
       ├── TEST-23  search_objects 标签过滤
       ├── TEST-24  p_label 参数安全测试
       ├── TEST-25  控制字符安全测试
       └── CLEANUP  删除测试数据 (非测试项，数据恢复逻辑)
```

### 6.2 测试运行

```bash
make test
```

---

## 七、示例模块

**文件**: [examples/usage.sql](file:///Users/liuruiqi/ontosql/examples/usage.sql)

### 7.1 示例列表

| 编号 | 场景 | 涉及函数 |
|------|------|---------|
| 1 | 对象搜索（基础） | search_objects |
| 2 | 属性搜索（基础） | search_attributes |
| 3 | 属性反查对象 | search_attributes + find_objects_by_attribute |
| 4 | 联合检索（核心） | search_object_attribute |
| 5 | 同义词匹配 | search_attributes |
| 6 | 错别字容错 | similarity() |
| 7 | 数据写入流程 | upsert_* + link_* |
| 8 | 图验证排除非法关联 | search_object_attribute |
| 9 | 按标签过滤搜索 | search_objects(p_label) |
| 10 | 批量向量近邻搜索 | <=> 余弦距离 |
| 11 | AGE Cypher 业务查询 | cypher() |
