# OntoSQL 核心对象图谱索引

> 本文档系统性地抽取 OntoSQL 项目中所有核心对象（数据表、函数、脚本、配置、构建目标）及其相互关系，构建结构化的索引图谱。用于后续开发和维护工作中快速定位对象、理解依赖关系、减少上下文信息的重复提供。

---

## 一、对象分类总览

```
OntoSQL 对象体系 (总计 69 个核心对象)
│
├── 数据层对象 (12)
│   ├── 数据表 (5):  schema_version, vector_registry, vertex_embeddings, attribute_embeddings, object_attribute_mapping
│   └── 索引 (7):  idx_* (HNSW×2, GIN×2, B-tree×3)
│
├── 函数层对象 (12)
│   ├── 校验函数 (3):  validate_query_text, validate_graph_name, validate_top_k
│   ├── 检索函数 (4):  search_objects, search_attributes, find_objects_by_attribute, search_object_attribute
│   ├── 查询函数 (2):  get_object_attributes, get_related_objects
│   └── 写入函数 (3):  upsert_vertex_embedding, upsert_attribute_embedding, link_object_attribute
│
├── 图模型对象 (9)
│   ├── 图 (1):  ontosql_graph
│   ├── 顶点标签 (4):  Object, Metric, Dimension, Department
│   └── 边标签 (4):  HAS_METRIC, BELONGS_TO, HAS_DIMENSION, RELATED_TO
│
├── 构建层对象 (21)
│   ├── Makefile Target (12):  all, build, build-pg, build-pgvector, build-age, install, init-db, start, stop, clean, test, docs, psql
│   └── Docker 对象 (5):  Dockerfile, Dockerfile.pgbouncer, docker-compose.yml, entrypoint.sh, pgbouncer-entrypoint.sh
│   └── Docker Compose 服务 (2): ontosql, pgbouncer
│
├── 配置层对象 (8)
│   ├── PG 参数组 (6):  memory, connection, WAL, planner, extension, log
│   └── PgBouncer 配置 (2):  pgbouncer.ini 连接池配置
│
└── 测试层对象 (25)
    ├── setup.sql (1)
    └── test_cases.sql → 包含 24 组测试 + 1 组清理逻辑
```

---

## 二、数据层对象关系图谱

### 2.1 核心数据表依赖图

```
                        ┌─────────────────────────┐
                        │    schema_version        │
                        │  (Schema 版本管理)        │
                        │                          │
                        │  PK: version             │
                        │  installed_at: tstz      │
                        └──────────────────────────┘

                        ┌─────────────────────────┐
                        │    vector_registry       │
                        │  (向量表元数据管理)       │
                        │                          │
                        │  PK: id                  │
                        │  UK: table_name          │
                        │  entity_type: enum       │
                        │  index_type: enum        │
                        └────────────┬─────────────┘
                                     │ 管理/描述
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────────────┐
        │ vertex_embeddings │ │attribute_embeddings│ │ object_attribute_mapping │
        │───────────────────│ │───────────────────│ │───────────────────────────│
        │ PK: id            │ │ PK: id (=attr_id) │ │ PK: id                    │
        │ UK: (graph,vid)   │ │ UK: (graph,name)  │ │ UK: (graph,vid,attr_id)   │
        │                   │ │                   │ │ FK: attr_id → ae(id)     │
        │ vertex_id ◄───────┼─┼───────────────────┼─│ object_vertex_id          │
        │ vertex_name       │ │ attr_name         │ │ attr_id ──────────────────┤
        │ label_name        │ │ aliases[]         │ │ object_label              │
        │ embedding ◄───────┼─┼── embedding       │ │ relation_type             │
        │ description       │ │ description       │ │ confidence                │
        │ metadata          │ │ data_type         │ │                           │
        └────────┬──────────┘ └────────┬──────────┘ └───────────────────────────┘
                 │                     │
                 │ (graph_name,        │ (graph_name)
                 │  vertex_id)         │
                 ▼                     ▼
        ┌───────────────────────────────────────────────────┐
        │              AGE 图 (ag_catalog)                   │
        │                                                   │
        │  ag_graph ──▶ ag_label ──▶ ag_vertex              │
        │                      │                            │
        │                      └──▶ ag_edge                 │
        │                                                   │
        │  图名: ontosql_graph                              │
        │  顶点标签: Object, Metric, Dimension, Department  │
        │  边标签: HAS_METRIC, BELONGS_TO, HAS_DIMENSION,   │
        │          RELATED_TO                               │
        └───────────────────────────────────────────────────┘
```

### 2.2 索引关联关系

```
vertex_embeddings
├── idx_vertex_embeddings_hnsw      → embedding (vector_cosine_ops)  [HNSW m=16]
├── idx_vertex_embeddings_name_trgm → vertex_name (gin_trgm_ops)    [GIN]
└── idx_vertex_embeddings_label     → (graph_name, label_name)      [B-tree]

attribute_embeddings
├── idx_attribute_embeddings_hnsw      → embedding (vector_cosine_ops) [HNSW m=16]
└── idx_attribute_embeddings_name_trgm → attr_name (gin_trgm_ops)      [GIN]

object_attribute_mapping
├── idx_oam_object → (graph_name, object_vertex_id)                  [B-tree]
└── idx_oam_attr   → (graph_name, attr_id)                            [B-tree]
```

### 2.3 外键依赖链

```
object_attribute_mapping.attr_id
    │
    └── REFERENCES ──▶ attribute_embeddings.id
                           │
                           └── (被 search_object_attribute 中 EXISTS 子查询引用)
```

---

## 三、函数层对象关系图谱

### 3.1 函数调用层级图

```
                         ┌─────────────────────────────┐
                         │ search_object_attribute()   │  ← 核心入口 (联合检索)
                         │   [SQL, STABLE, PARALLEL]   │
                         └─────────────┬───────────────┘
                                       │ 内部调用 (CROSS JOIN)
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                   ▼
        ┌──────────────────┐ ┌──────────────────┐ ┌───────────────────────────┐
        │ search_objects() │ │search_attributes()│ │ AGE 图 Cypher 验证        │
        │──────────────────│ │──────────────────│ │  (MATCH Object-[r]->prop) │
        │ 向量召回(HNSW)   │ │ 向量召回(HNSW)   │ │                           │
        │ + trigram(GIN)  │ │ + trigram(GIN)   │ │ 判断 is_verified          │
        │ → UNION ALL     │ │ → UNION ALL      │ │ 属性无图顶点 → mapping表  │
        │ → GROUP BY MAX  │ │ → GROUP BY MAX   │ └───────────────────────────┘
        └────────┬─────────┘ └────────┬─────────┘
                 │                    │
                 ▼                    ▼
        ┌──────────────────────────────────────────────┐
        │      vertex_embeddings / attribute_embeddings │
        │      (数据源表，被两个检索函数分别读取)        │
        └──────────────────────────────────────────────┘


┌──────────────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│upsert_vertex_        │     │upsert_attribute_     │     │link_object_attribute │
│  embedding()         │     │  embedding()         │     │  ()                  │
│──────────────────────│     │──────────────────────│     │──────────────────────│
│ [plpgsql, VOLATILE] │     │ [plpgsql, VOLATILE]  │     │ [plpgsql, VOLATILE]  │
│                      │     │                      │     │                      │
│ 写入目标:            │     │ 写入目标:            │     │ 写入目标:            │
│ vertex_embeddings    │     │ attribute_embeddings │     │ object_attribute_    │
│                      │     │                      │     │   mapping            │
│ 返回: void           │     │ 返回: int (attr_id)  │     │                      │
│                      │     │        │             │     │ 返回: void           │
│ 校验: 无             │     │        │             │     │                      │
│                      │     │        └─────────────┼────▶│ 校验:                │
│ 幂等: ON CONFLICT    │     │ 幂等: ON CONFLICT    │     │ ① vertex_embeddings  │
│   (graph,vertex_id)  │     │   (graph,attr_name)  │     │    存在性检查        │
└──────────────────────┘     └──────────────────────┘     │ ② attribute_embeddings│
                                                          │    存在性检查        │
                                                          │ 幂等: ON CONFLICT    │
                                                          │   (graph,vid,attr_id)│
                                                          └──────────────────────┘
```

### 3.2 数据流向图（完整查询链路）

```
                        ┌─────────────────┐
                        │  用户 NL 输入    │
                        │  "张三上月销售额" │
                        └────────┬────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  外部 Embedding 模型     │
                    │  (text-embedding-3-small)│
                    │  输出: vector(1536)      │
                    └────────────┬────────────┘
                                 │ p_query_embedding
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│  search_object_attribute(query_text, graph_name, top_k, embedding) │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Step 1: search_objects()                                     │  │
│  │   ┌──────────────────┐    ┌──────────────────────────────┐   │  │
│  │   │ 向量召回 (HNSW)   │    │ trigram 召回 (GIN + pg_trgm) │   │  │
│  │   │ <=> 余弦距离      │    │ similarity() + % 运算符      │   │  │
│  │   │ LIMIT top_k×3    │    │ LIMIT top_k×3               │   │  │
│  │   └────────┬─────────┘    └──────────────┬───────────────┘   │  │
│  │            └──────────┬─────────────────┘                    │  │
│  │                       ▼                                      │  │
│  │              UNION ALL + GROUP BY + MAX                      │  │
│  │              综合分 = 0.6×向量 + 0.4×trigram                 │  │
│  │              输出: [(vertex_id, name, label, score), ...]    │  │
│  └────────────────────────────┬────────────────────────────────┘  │
│                               │ 候选对象列表                       │
│  ┌────────────────────────────▼────────────────────────────────┐  │
│  │ Step 2: search_attributes()                                  │  │
│  │   (同 Step 1 算法，作用于 attribute_embeddings)              │  │
│  │   输出: [(attr_id, name, desc, score), ...]                  │  │
│  └────────────────────────────┬────────────────────────────────┘  │
│                               │ 候选属性列表                       │
│  ┌────────────────────────────▼────────────────────────────────┐  │
│  │ Step 3: AGE 图 Cypher 批量验证（按图索骥）                  │  │
│  │   MATCH (obj:Object)-[r]->(prop)                            │  │
│  │   WHERE id(obj) IN [候选对象] AND id(prop) IN [候选属性]    │  │
│  │   → 返回图中实际存在的对象-属性边                            │  │
│  │                                                              │  │
│  │   CROSS JOIN + LEFT JOIN 图验证结果                          │  │
│  │   综合分 = 0.5×obj_score + 0.5×attr_score                    │  │
│  │   输出: [(vertex_id, name, attr_name, score, is_verified)]   │  │
│  │                                                              │  │
│  │   属性未建模为图顶点时 → 回退查 object_attribute_mapping     │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
└───────────────────────────────┬────────────────────────────────────┘
                                │ is_verified=true 的结果
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│  AGE Cypher 查询 (获取实际数据)                                     │
│                                                                    │
│  SELECT * FROM cypher('ontosql_graph', $$                          │
│      MATCH (obj:Object {name: '张三'})                             │
│            -[:HAS_METRIC]->(m:Metric {name: '销售额'})             │
│            -[:HAS_DIMENSION]->(d:Dimension {name: '上月'})         │
│      RETURN obj.name, m.name, d.name                               │
│  $$) AS (obj agtype, metric agtype, dim agtype);                   │
│                                                                    │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│  传统 SQL 查询 (业务数据仓库)                                       │
│                                                                    │
│  SELECT SUM(amount) FROM sales_fact                                │
│  WHERE employee_id = 'E001' AND period = '2025-04';               │
│                                                                    │
│  → 返回最终结果给用户                                               │
└────────────────────────────────────────────────────────────────────┘
```

---

## 四、构建层对象关系图谱

### 4.1 Makefile Target 依赖图

```
all
│
└── build ─────────────────────────────────────────────┐
         │                                              │
         ├── build-pg ───── depends on ──▶ upstream/postgresql/
         │       │                                     │
         │       └── produces ──▶ build/pgsql17/      │
         │                                              │
         ├── build-pgvector ── depends on ──▶ build/pgsql17/ + upstream/pgvector/
         │       │                                     │
         │       └── produces ──▶ pgvector.so         │
         │                                              │
         └── build-age ───── depends on ──▶ build/pgsql17/ + upstream/age/
                 │                                     │
                 └── produces ──▶ age.so              │
                                                       │
install ── depends on ──▶ build                        │
    │                                                  │
    └── copies ──▶ sql/*.sql → build/pgsql17/share/   │
                                                       │
init-db                                                │
    │                                                  │
    ├── uses ──▶ build/pgsql17/bin/initdb             │
    ├── writes ──▶ build/data/postgresql.conf          │
    └── writes ──▶ build/data/pg_hba.conf              │
                                                       │
start                                                  │
    ├── depends on ──▶ init-db                         │
    ├── uses ──▶ build/pgsql17/bin/pg_ctl              │
    └── creates ──▶ EXTENSION vector, age              │
                                                       │
stop ─── uses ──▶ build/pgsql17/bin/pg_ctl             │
                                                       │
test                                                   │
    ├── depends on ──▶ start                           │
    ├── runs ──▶ tests/setup.sql                       │
    └── runs ──▶ tests/test_cases.sql                  │
                                                       │
clean                                                  │
    ├── stops ──▶ pg_ctl                                │
    ├── cleans ──▶ upstream/{postgresql,pgvector,age}/ │
    └── removes ──▶ build/pgsql17/ + build/data/       │
                                                       │
docs ─── outputs ──▶ 文档列表                          │
                                                       │
psql ─── uses ──▶ build/pgsql17/bin/psql               │
```

### 4.2 Docker 构建流水线

```
Dockerfile (多阶段构建)
│
├── Stage 1: Builder (debian:bookworm-slim)
│   ├── COPY upstream/postgresql → /tmp/postgresql
│   │   └── ./configure → make → make install → /usr/local/pgsql/
│   ├── COPY upstream/pgvector → /tmp/pgvector
│   │   └── make PG_CONFIG=... → make install
│   └── COPY upstream/age → /tmp/age
│       └── make PG_CONFIG=... → make install
│
└── Stage 2: Runtime (debian:bookworm-slim) [精简]
    ├── COPY --from=builder /usr/local/pgsql/
    ├── COPY docker/entrypoint.sh → /entrypoint.sh
    ├── USER postgres
    └── ENTRYPOINT ["/entrypoint.sh"]
        │
        ├── initdb (首次运行)
        │   ├── CREATE EXTENSION vector
        │   └── CREATE EXTENSION age
        └── exec postgres -D $PGDATA


Dockerfile.pgbouncer
├── Stage 1: Builder (debian:bookworm-slim)
│   └── apt-get install pgbouncer → 安装连接池
│
└── Stage 2: Runtime
    ├── COPY pgbouncer-entrypoint.sh → /entrypoint.sh
    ├── COPY config/pgbouncer.ini → /etc/pgbouncer/
    └── ENTRYPOINT ["/entrypoint.sh"]


docker-compose.yml
├── service: ontosql
│   ├── build: docker/Dockerfile
│   ├── ports: ${PG_PORT:-5432}:5432
│   ├── environment: POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?err}
│   ├── volumes:
│   │   ├── pgdata:/var/lib/pgsql/data
│   │   └── ../sql:/sql:ro
│   ├── healthcheck: pg_isready
│   ├── cap_drop: ALL (仅保留 CHOWN/DAC_OVERRIDE/SETGID/SETUID)
│   └── security: no-new-privileges:true
│
├── service: pgbouncer
│   ├── build: docker/Dockerfile.pgbouncer
│   ├── ports: 6432:6432
│   ├── depends_on: ontosql (service_healthy)
│   └── environment: POSTGRES_PASSWORD, PGBOUNCER_AUTH_TYPE
│
└── volumes: pgdata
```

---

## 五、图模型层对象关系图谱

### 5.1 AGE 图模型结构

```
图: ontosql_graph
│
├── 顶点标签
│   ├── Object ───────── 属性: {name, type, employee_id / product_code / customer_level}
│   │   ├── type='employee':  张三, 李四, 王五, 赵六, 钱七
│   │   ├── type='product':  产品A, 产品B, 产品C
│   │   └── type='customer':  华科科技, 数据之光, 星辰网络
│   │
│   ├── Metric ────────── 属性: {name, unit, data_type, description}
│   │   └── 销售额, 利润率, 客户数, 订单量, 回款率, 客单价, 活跃用户数, 转化率, 库存周转天数
│   │
│   ├── Dimension ─────── 属性: {name, type}
│   │   └── 本月, 上月, 本季度, 上季度, 本年, 去年
│   │
│   └── Department ────── 属性: {name, code}
│       └── 销售部(SALES), 技术部(TECH), 财务部(FINANCE), 市场部(MARKETING)
│
└── 边标签 (关系)
    ├── HAS_METRIC      Object ──────────▶ Metric
    │   ├── 张三 → [销售额, 客户数, 回款率]
    │   ├── 李四 → [活跃用户数, 转化率]
    │   ├── 赵六 → [销售额, 客单价]
    │   ├── 钱七 → [销售额, 订单量]
    │   ├── 产品A → [销售额, 库存周转天数]
    │   ├── 产品B → [销售额]
    │   ├── 产品C → [利润率]
    │   ├── 华科科技 → [销售额]
    │   └── 数据之光 → [订单量]
    │
    ├── BELONGS_TO      Object ──────────▶ Department
    │   ├── 张三, 钱七 → 销售部
    │   ├── 李四 → 技术部
    │   ├── 王五 → 财务部
    │   └── 赵六 → 市场部
    │
    ├── HAS_DIMENSION   Metric ──────────▶ Dimension
    │   ├── 销售额 → [本月, 上月]
    │   └── 客户数 → [本月]
    │
    └── RELATED_TO      Object ──────────▶ Object
        └── 张三 → 钱七 (同部门)
```

### 5.2 图遍历查询路径示例

```
查询: "张三上月销售额多少"

遍历路径:
    (张三:Object)
        │
        ├── BELONGS_TO ──▶ (销售部:Department)
        │
        ├── HAS_METRIC ──▶ (销售额:Metric)
        │                      │
        │                      └── HAS_DIMENSION ──▶ (上月:Dimension)
        │
        └── RELATED_TO ──▶ (钱七:Object)

Cypher 查询:
    MATCH (obj:Object {name: '张三'})
          -[:BELONGS_TO]->(dept:Department)
    MATCH (obj)
          -[:HAS_METRIC]->(m:Metric {name: '销售额'})
          -[:HAS_DIMENSION]->(d:Dimension {name: '上月'})
    RETURN obj.name, dept.name, m.name, d.name
```

---

## 六、配置层对象关系图谱

### 6.1 配置参数分类与影响范围

```
config/postgresql.template.sql
│
├── 1. 内存配置 ──────▶ 影响: 查询性能, 并发能力
│   ├── shared_buffers          → 数据缓存 (影响所有表扫描)
│   ├── effective_cache_size    → 查询计划生成 (影响索引选择)
│   ├── work_mem                → 排序/哈希操作 (影响 search_objects 中 GROUP BY)
│   ├── maintenance_work_mem    → VACUUM/CREATE INDEX (影响 HNSW 索引构建)
│   └── wal_buffers             → WAL 写入性能 (影响 upsert_* 写入速度)
│
├── 2. 连接配置 ──────▶ 影响: 并发用户数
│   ├── max_connections         → 最大并发 (与 work_mem 联动)
│   └── superuser_reserved_connections → 紧急维护通道
│
├── 3. WAL 配置 ───────▶ 影响: 写入性能, 备份恢复
│   ├── wal_level               → replica (支持 pg_basebackup)
│   ├── max_wal_senders         → 0 (单机无需流复制)
│   └── checkpoint_completion_target → IO 压力分散
│
├── 4. 规划器配置 ────▶ 影响: 查询计划质量
│   ├── random_page_cost        → 1.1 (SSD 环境)
│   └── effective_io_concurrency → 200 (SSD 并发)
│
├── 5. 扩展配置 ──────▶ 影响: 向量搜索精度与速度
│   └── hnsw.ef_search          → 100 (影响 search_objects / search_attributes 向量召回精度)
│
└── 6. 日志配置 ──────▶ 影响: 可观测性
    ├── log_min_duration_statement → 1000ms (超过1秒的查询记录)
    └── log_line_prefix          → 日志格式

生效方式: ALTER SYSTEM SET → 写入 postgresql.auto.conf → pg_reload_conf()
```

---

## 七、测试层对象关系图谱

### 7.1 测试依赖与覆盖

```
make test
│
├── 前置: make start (数据库已运行，扩展已加载)
│
├── Step 1: tests/setup.sql
│   ├── CREATE EXTENSION vector (IF NOT EXISTS → 幂等)
│   ├── CREATE EXTENSION age
│   ├── CREATE EXTENSION pg_trgm
│   ├── SET search_path TO ontosql, ag_catalog, public
│   └── \i sql/001_core_schema.sql ──▶ 创建全部 4 张表 + 7 个函数
│
└── Step 2: tests/test_cases.sql (\set ON_ERROR_STOP on, \timing on)
    │
    ├── TEST-1   Schema 存在性         → 覆盖: vector_registry, vertex_embeddings, attribute_embeddings, object_attribute_mapping
    ├── TEST-2   索引存在性             → 覆盖: idx_vertex_embeddings_hnsw, idx_attribute_embeddings_hnsw
    ├── TEST-3   数据类型               → 覆盖: vector 类型, agtype 类型
    ├── TEST-4   upsert_vertex_embedding → 覆盖: INSERT + UPDATE 幂等
    ├── TEST-5   upsert_attribute_embedding → 覆盖: INSERT + UPDATE 幂等
    ├── TEST-6   link_object_attribute  → 覆盖: CREATE + upsert 幂等
    ├── TEST-7   search_objects         → 覆盖: trigram 召回, 空查询边界
    ├── TEST-8   search_attributes      → 覆盖: trigram 召回
    ├── TEST-9   find_objects_by_attribute → 覆盖: 正常匹配, 无效ID边界
    ├── TEST-10  search_object_attribute → 覆盖: 联合检索, is_verified 验证
    ├── TEST-11  pg_trgm 扩展            → 覆盖: similarity() 基础可用性
    ├── TEST-12  边界条件               → 覆盖: 不存在图的查询
    ├── TEST-13  vector_registry 元数据  → 覆盖: 初始化完整性
    └── CLEANUP  数据恢复               → DELETE FROM 三张表 (WHERE graph_name='test_graph')
```

---

## 八、完整对象索引表

### 8.1 数据表对象

| 编号 | 对象名 | 类型 | 位置 | 依赖 | 被依赖 |
|------|--------|------|------|------|--------|
| T-00 | `schema_version` | TABLE | 001_core_schema.sql L25 | — | 维护追踪 |
| T-01 | `vector_registry` | TABLE | 001_core_schema.sql L42 | — | TEST-13 |
| T-02 | `vertex_embeddings` | TABLE | 001_core_schema.sql L65 | — | search_objects, upsert_vertex_embedding, link_object_attribute, TEST-1/4/7 |
| T-03 | `attribute_embeddings` | TABLE | 001_core_schema.sql L98 | — | search_attributes, upsert_attribute_embedding, TEST-1/5/8 |
| T-04 | `object_attribute_mapping` | TABLE | 001_core_schema.sql L126 | attribute_embeddings (FK) | find_objects_by_attribute, search_object_attribute, link_object_attribute, TEST-1/6/9/10 |

### 8.2 索引对象

| 编号 | 对象名 | 类型 | 关联表 | 索引类型 | 位置 |
|------|--------|------|--------|---------|------|
| I-01 | `idx_vertex_embeddings_hnsw` | INDEX | vertex_embeddings | HNSW | L80 |
| I-02 | `idx_vertex_embeddings_name_trgm` | INDEX | vertex_embeddings | GIN | L84 |
| I-03 | `idx_vertex_embeddings_label` | INDEX | vertex_embeddings | B-tree | L88 |
| I-04 | `idx_attribute_embeddings_hnsw` | INDEX | attribute_embeddings | HNSW | L113 |
| I-05 | `idx_attribute_embeddings_name_trgm` | INDEX | attribute_embeddings | GIN | L116 |
| I-06 | `idx_oam_object` | INDEX | object_attribute_mapping | B-tree | L139 |
| I-07 | `idx_oam_attr` | INDEX | object_attribute_mapping | B-tree (graph_name, attr_id) | L142 |

### 8.3 函数对象

| 编号 | 对象名 | 语言 | 易变性 | 并行 | 输入参数 | 返回类型 | 位置 |
|------|--------|------|--------|------|---------|---------|------|
| F-00 | `validate_query_text` | plpgsql | IMMUTABLE | SAFE | text,int | void | L163 |
| F-01 | `validate_graph_name` | plpgsql | IMMUTABLE | SAFE | text | void | L179 |
| F-02 | `validate_top_k` | plpgsql | IMMUTABLE | SAFE | int | void | L195 |
| F-03 | `search_objects` | plpgsql | STABLE | SAFE | text,text,text,int,vector | TABLE(6cols) | L221 |
| F-04 | `search_attributes` | plpgsql | STABLE | SAFE | text,text,int,vector | TABLE(6cols) | L290 |
| F-05 | `find_objects_by_attribute` | plpgsql | STABLE | SAFE | int,text,int | TABLE(4cols) | L379 |
| F-06 | `search_object_attribute` | plpgsql | STABLE | SAFE | text,text,int,vector | TABLE(8cols) | L424 |
| F-07 | `get_object_attributes` | plpgsql | STABLE | SAFE | bigint,text | TABLE(6cols) | L480 |
| F-08 | `get_related_objects` | plpgsql | STABLE | SAFE | bigint,text,text | TABLE(4cols) | L523 |
| F-09 | `upsert_vertex_embedding` | plpgsql | VOLATILE | — | bigint,text,text,text,vector,text,jsonb | void | L577 |
| F-10 | `upsert_attribute_embedding` | plpgsql | VOLATILE | — | text,text,vector,bigint,text[],text,text | int | L628 |
| F-11 | `link_object_attribute` | plpgsql | VOLATILE | — | text,bigint,int,text,float | void | L683 |

### 8.4 图模型对象

| 编号 | 对象名 | 类型 | 关联图 | 位置 |
|------|--------|------|--------|------|
| G-01 | `ontosql_graph` | GRAPH | — | 002_knowledge_graph.sql L28 |
| G-02 | `Object` | VLABEL | ontosql_graph | L35 |
| G-03 | `Metric` | VLABEL | ontosql_graph | L38 |
| G-04 | `Dimension` | VLABEL | ontosql_graph | L41 |
| G-05 | `Department` | VLABEL | ontosql_graph | L44 |
| G-06 | `HAS_METRIC` | ELABEL | ontosql_graph | L51 |
| G-07 | `BELONGS_TO` | ELABEL | ontosql_graph | L54 |
| G-08 | `HAS_DIMENSION` | ELABEL | ontosql_graph | L57 |
| G-09 | `RELATED_TO` | ELABEL | ontosql_graph | L60 |

### 8.5 Makefile 目标对象

| 编号 | 对象名 | 类型 | 前置依赖 | 产物 | 位置 |
|------|--------|------|---------|------|------|
| M-01 | `all` | TARGET | build | — | L32 |
| M-02 | `build` | TARGET | build-pg, build-pgvector, build-age | build/ | L34 |
| M-03 | `build-pg` | TARGET | upstream/postgresql/ | build/pgsql17/ | L48 |
| M-04 | `build-pgvector` | TARGET | build/pgsql17/ | pgvector.so | L61 |
| M-05 | `build-age` | TARGET | build/pgsql17/ | age.so | L70 |
| M-06 | `install` | TARGET | build | sql/ → share/ | L78 |
| M-07 | `init-db` | TARGET | build/pgsql17/bin/initdb | build/data/ | L86 |
| M-08 | `start` | TARGET | init-db | 运行中的 PG 实例 | L99 |
| M-09 | `stop` | TARGET | — | — | L112 |
| M-10 | `test` | TARGET | start | 测试通过/失败 | L130 |
| M-11 | `clean` | TARGET | — | 空 | L119 |
| M-12 | `docs` | TARGET | — | 文档列表输出 | L137 |
| M-13 | `psql` | TARGET | start | 交互终端 | L148 |

### 8.6 Docker 对象

| 编号 | 对象名 | 类型 | 依赖 | 位置 |
|------|--------|------|------|------|
| D-01 | `Dockerfile` | BUILD | upstream/ (三组件) | docker/Dockerfile |
| D-02 | `Dockerfile.pgbouncer` | BUILD | C-02, pgbouncer | docker/Dockerfile.pgbouncer |
| D-03 | `docker-compose.yml` | ORCHESTRATION | D-01, D-02, D-04, D-05 | docker/docker-compose.yml |
| D-04 | `entrypoint.sh` (PG) | SCRIPT | build/pgsql17/ | docker/entrypoint.sh |
| D-05 | `pgbouncer-entrypoint.sh` | SCRIPT | C-02, pgbouncer | docker/pgbouncer-entrypoint.sh |
| SV-01 | `ontosql` (service) | SERVICE | D-01, D-04 | docker-compose.yml L12 |
| SV-02 | `pgbouncer` (service) | SERVICE | D-02, D-05, SV-01 | docker-compose.yml L63 |

### 8.7 文档对象

| 编号 | 对象名 | 类型 | 用途 | 目标受众 |
|------|--------|------|------|---------|
| DOC-01 | `README.md` | README | 项目全貌、快速开始 | 所有人 |
| DOC-02 | `docs/overview.md` | OVERVIEW | 项目定位与能力矩阵 | 产品经理、新成员 |
| DOC-03 | `docs/architecture.md` | ARCHITECTURE | 架构设计与技术决策 | 架构师、核心开发者 |
| DOC-04 | `docs/api.md` | API | 接口参数、返回值、错误处理 | 应用开发者 |
| DOC-05 | `docs/ops.md` | OPS | 部署、调优、备份、升级 | SRE / DBA |
| DOC-06 | `docs/modules.md` | MODULES | 模块功能详细描述 | 开发者 |
| DOC-07 | `docs/data_dictionary.md` | DATA | 数据字典（含表结构与函数清单） | DBA、开发者 |
| DOC-08 | `docs/code_review.md` | REVIEW | 代码审查报告 | 架构师、核心开发者 |
| DOC-09 | `docs/object_index.md` | INDEX | 核心对象图谱索引（本文档） | 全体开发者 |
| DOC-10 | `docs/consistency_audit.md` | AUDIT | 文档一致性检查与代码审计报告 | 架构师、核心开发者 |
| DOC-11 | `docs/agent_guide.md` | AGENT | Agent 三步工作流对接指南 | Agent 开发者 |
| DOC-12 | `docs/knowledge_graph.md` | ONTOLOGY | 本体图谱（Agent 按图索骥索引） | Agent / 全体开发者 |
| DOC-13 | `examples/usage.sql` | EXAMPLE | 11 个典型使用场景 | 开发者 |
| DOC-14 | `tests/test_cases.sql` | TEST | 24 组自动化测试 | QA、开发者 |

---

## 九、交叉引用索引（快速查找）

### 9.1 按功能查找

| 功能需求 | 涉及对象 | 主要文件 |
|---------|---------|---------|
| 安全校验 | F-00, F-01, F-02 | 001_core_schema.sql |
| 对象语义搜索 | F-03, T-02, I-01/02/03 | 001_core_schema.sql |
| 属性语义搜索 | F-04, T-03, I-04/05 | 001_core_schema.sql |
| 属性反查归属 | F-05, T-04, I-06/07 | 001_core_schema.sql |
| 联合检索+验证 | F-06, F-03, F-04, T-04 | 001_core_schema.sql |
| 对象属性列表 | F-07, T-04, T-03 | 001_core_schema.sql |
| 图遍历查询 | F-08, G-01~09 | 001_core_schema.sql |
| 写入对象 embedding | F-09, T-02 | 001_core_schema.sql |
| 写入属性 embedding | F-10, T-03 | 001_core_schema.sql |
| 建立对象-属性关联 | F-11, T-04 | 001_core_schema.sql |
| AGE 图遍历 | G-01~09 | 002_knowledge_graph.sql |
| 编译部署 | M-01~13 | Makefile |
| 容器化部署 | D-01~05, SV-01, SV-02 | docker/ |
| 参数调优 | C-01（postgresql.template.sql）, C-02（pgbouncer.ini） | config/ |
| 性能监控 | (建议安装 pg_stat_statements) | ops.md |

### 9.2 按文件查找

| 文件 | 包含对象 |
|------|---------|
| `001_core_schema.sql` | T-00~04, I-01~07, F-00~11 |
| `002_knowledge_graph.sql` | G-01~09, 示例数据 |
| `config/postgresql.template.sql` | C-01（配置参数组 ×6） |
| `config/pgbouncer.ini` | C-02（连接池配置） |
| `Makefile` | M-01~13, MV-01~04 |
| `docker/Dockerfile` | D-01 |
| `docker/Dockerfile.pgbouncer` | D-02 |
| `docker/docker-compose.yml` | D-03, SV-01, SV-02 |
| `docker/entrypoint.sh` | D-04 |
| `docker/pgbouncer-entrypoint.sh` | D-05 |
| `tests/setup.sql` | 扩展加载 + Schema 导入 |
| `tests/test_cases.sql` | TEST-01~24, CLEANUP |
| `examples/usage.sql` | 示例 01~11 |

---

## 十、维护指南

### 10.1 新增数据表时

1. 在 `vector_registry` 中注册新表元数据
2. 创建相应的 HNSW / GIN / B-tree 索引
3. 更新 `data_dictionary.md` 添加表结构定义
4. 更新本文档（`object_index.md`）添加新对象条目
5. 在 `tests/test_cases.sql` 中添加对应的测试组

### 10.2 新增检索函数时

1. 确定函数语言的易变性级别（STABLE / IMMUTABLE）
2. 标记 PARALLEL SAFE 如果适用
3. 更新 `api.md` 添加函数签名文档
4. 更新 `modules.md` 添加函数功能描述
5. 更新本文档的函数对象表（8.3 节）
6. 更新数据流向图（3.2 节）如影响查询链路

### 10.3 修改 Schema 时

1. 考虑引入迁移脚本机制（建议 `migrations/` 目录）
2. 维护 `schema_version` 表追踪变更
3. 同步更新所有相关文档（api.md, data_dictionary.md, object_index.md）
4. 在测试环境验证后更新测试用例

---

> **版本**: 1.0.0 | **生成日期**: 2026-05-06 | **维护者**: OntoSQL 开发团队
