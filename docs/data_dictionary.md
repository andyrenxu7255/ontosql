# OntoSQL 数据字典

> 本文档定义 OntoSQL 项目中所有数据表、视图、索引的完整结构，包括字段类型、约束和业务含义。

---

## 一、Schema 概览

```
Database: postgres
├── Schema: ontosql (业务 Schema)
│   ├── schema_version           — Schema 版本管理
│   ├── vector_registry          — 向量注册表
│   ├── vertex_embeddings        — 对象向量侧表
│   ├── attribute_embeddings     — 属性向量侧表
│   └── object_attribute_mapping — 对象-属性关联表
│
├── Schema: ag_catalog (AGE 系统 Schema)
│   ├── ag_graph                 — 图元数据
│   ├── ag_label                 — 标签元数据
│   ├── ag_vertex                — 顶点存储
│   └── ag_edge                  — 边存储
│
└── Schema: public (默认 Schema)
    └── 用户自定义业务数据表
```

---

## 二、ontosql Schema — 详细定义

### 2.0 `schema_version` — Schema 版本管理表

**用途**: 追踪 Schema 变更历史，支持版本升级、兼容性检查和回滚。

| 列名 | 类型 | 约束 | 默认值 | 说明 |
|------|------|------|--------|------|
| `version` | `text` | PRIMARY KEY | — | 版本号（如 `1.0.0`） |
| `description` | `text` | — | — | 版本变更说明 |
| `installed_by` | `text` | — | `current_user` | 执行者 |
| `installed_at` | `timestamptz` | NOT NULL | `now()` | 安装时间 |

**初始化数据**:
```sql
('1.0.0', 'Initial schema with vector embeddings, multi-path recall functions, and write interfaces')
```

---

### 2.1 `vector_registry` — 向量注册表

**用途**: 管理项目中所有向量侧表的元数据，支持动态注册新表。

| 列名 | 类型 | 约束 | 默认值 | 说明 |
|------|------|------|--------|------|
| `id` | `serial` | PRIMARY KEY | auto | 自增主键 |
| `table_name` | `text` | NOT NULL, UNIQUE | — | 向量表名，全局唯一 |
| `graph_name` | `text` | NOT NULL | — | 所属知识图谱名称 |
| `entity_type` | `text` | NOT NULL, CHECK IN ('vertex','edge','attribute') | — | 实体类型 |
| `label_or_type` | `text` | NOT NULL | — | 顶点标签名或属性类型名 |
| `vector_column` | `text` | NOT NULL | `'embedding'` | 向量列名 |
| `vector_dim` | `int` | NOT NULL | — | 向量维度（如 1536） |
| `index_type` | `text` | NOT NULL, CHECK IN ('hnsw','ivfflat') | `'hnsw'` | 向量索引类型 |
| `distance_ops` | `text` | NOT NULL | `'vector_cosine_ops'` | 距离运算符类 |
| `hnsw_m` | `int` | NOT NULL | `16` | HNSW 参数 m（每层邻居数） |
| `ivfflat_lists` | `int` | NOT NULL | `100` | IVFFlat 聚类中心数 |
| `description` | `text` | — | — | 表用途描述 |
| `created_at` | `timestamptz` | NOT NULL | `now()` | 创建时间 |

**初始化数据**:
```sql
('vertex_embeddings',    'default', 'vertex',    'ALL', 'embedding', 1536, 'hnsw', 'vector_cosine_ops')
('attribute_embeddings', 'default', 'attribute', 'ALL', 'embedding', 1536, 'hnsw', 'vector_cosine_ops')
```

---

### 2.2 `vertex_embeddings` — 对象向量侧表

**用途**: 为 AGE 图中的每个业务对象存储向量表示，支持语义相似度搜索。

| 列名 | 类型 | 约束 | 默认值 | 说明 |
|------|------|------|--------|------|
| `id` | `bigserial` | PRIMARY KEY | auto | 自增主键 |
| `vertex_id` | `bigint` | NOT NULL | — | AGE 图顶点的 graphid，关联 ag_vertex |
| `graph_name` | `text` | NOT NULL | — | 所属图名 |
| `label_name` | `text` | NOT NULL | — | 顶点标签（如 Object, Department） |
| `vertex_name` | `text` | NOT NULL | — | 业务名称（冗余存储，加速展示） |
| `description` | `text` | — | — | 对象语义描述（embedding 生成的源文本） |
| `embedding` | `vector(1536)` | — | — | OpenAI text-embedding-3-small 默认维度 |
| `metadata` | `jsonb` | — | — | 扩展元数据（如 employee_id, level） |
| `created_at` | `timestamptz` | NOT NULL | `now()` | 创建时间 |
| `updated_at` | `timestamptz` | NOT NULL | `now()` | 最后更新时间 |

**约束**:
| 约束名 | 类型 | 列 |
|--------|------|-----|
| `vertex_embeddings_graph_name_vertex_id_key` | UNIQUE | `(graph_name, vertex_id)` |

**索引**:
| 索引名 | 类型 | 列 | 说明 |
|--------|------|-----|------|
| `idx_vertex_embeddings_hnsw` | HNSW | `(embedding vector_cosine_ops)` WITH (m=16) | 向量近似最近邻搜索 |
| `idx_vertex_embeddings_name_trgm` | GIN | `(vertex_name gin_trgm_ops)` | 模糊文本匹配 |
| `idx_vertex_embeddings_label` | B-tree | `(graph_name, label_name)` | 按图和标签过滤加速 |
| `vertex_embeddings_pkey` | B-tree | `(id)` | 主键索引 |

---

### 2.3 `attribute_embeddings` — 属性向量侧表

**用途**: 为指标/维度等属性存储向量表示，支持语义属性识别。

| 列名 | 类型 | 约束 | 默认值 | 说明 |
|------|------|------|--------|------|
| `id` | `bigserial` | PRIMARY KEY | auto | 自增主键，即 attr_id |
| `attr_name` | `text` | NOT NULL | — | 属性业务名称（如 "销售额"） |
| `graph_name` | `text` | NOT NULL | — | 所属图名 |
| `attr_vertex_id` | `bigint` | — | — | 若属性建模为图顶点，关联其 graphid |
| `aliases` | `text[]` | — | — | 别名数组（如 ARRAY['营收','revenue']） |
| `description` | `text` | — | — | 语义描述（embedding 生成的源文本） |
| `data_type` | `text` | — | — | 数据类型（numeric, integer, text 等） |
| `embedding` | `vector(1536)` | — | — | 向量表示 |
| `metadata` | `jsonb` | — | — | 扩展元数据 |
| `created_at` | `timestamptz` | NOT NULL | `now()` | 创建时间 |
| `updated_at` | `timestamptz` | NOT NULL | `now()` | 最后更新时间 |

**约束**:
| 约束名 | 类型 | 列 |
|--------|------|-----|
| `attribute_embeddings_graph_name_attr_name_key` | UNIQUE | `(graph_name, attr_name)` |

**索引**:
| 索引名 | 类型 | 列 | 说明 |
|--------|------|-----|------|
| `idx_attribute_embeddings_hnsw` | HNSW | `(embedding vector_cosine_ops)` WITH (m=16) | 向量近似最近邻搜索 |
| `idx_attribute_embeddings_name_trgm` | GIN | `(attr_name gin_trgm_ops)` | 模糊文本匹配 |
| `attribute_embeddings_pkey` | B-tree | `(id)` | 主键索引 |

---

### 2.4 `object_attribute_mapping` — 对象-属性关联表

**用途**: 物化对象与属性的关联关系，加速反查（`find_objects_by_attribute`）和关联验证（`is_verified`）。

| 列名 | 类型 | 约束 | 默认值 | 说明 |
|------|------|------|--------|------|
| `id` | `bigserial` | PRIMARY KEY | auto | 自增主键 |
| `graph_name` | `text` | NOT NULL | — | 图名 |
| `object_vertex_id` | `bigint` | NOT NULL | — | 对象在 AGE 图中的 vertex_id |
| `object_label` | `text` | NOT NULL | — | 对象标签类型 |
| `attr_id` | `int` | NOT NULL, REFERENCES attribute_embeddings(id) | — | 属性 ID（外键） |
| `relation_type` | `text` | NOT NULL | `'HAS_ATTRIBUTE'` | 关系类型 |
| `confidence` | `float` | NOT NULL | `1.0` | 关联置信度 [0, 1] |
| `created_at` | `timestamptz` | NOT NULL | `now()` | 创建时间 |

**约束**:
| 约束名 | 类型 | 列 |
|--------|------|-----|
| `object_attribute_mapping_graph_name_object_vertex_id__key` | UNIQUE | `(graph_name, object_vertex_id, attr_id)` |
| `object_attribute_mapping_attr_id_fkey` | FOREIGN KEY | `(attr_id) → attribute_embeddings(id)` |

**索引**:
| 索引名 | 类型 | 列 | 说明 |
|--------|------|-----|------|
| `idx_oam_object` | B-tree | `(graph_name, object_vertex_id)` | 按对象查询其全部属性 |
| `idx_oam_attr` | B-tree | `(graph_name, attr_id)` | 按图+属性反查拥有该属性的全部对象 |
| `object_attribute_mapping_pkey` | B-tree | `(id)` | 主键索引 |

---

## 三、函数清单

### 3.1 校验函数

| 函数名 | 返回类型 | 语言 | 易变性 | 说明 |
|--------|---------|------|--------|------|
| `validate_query_text(text, int)` | `void` | plpgsql | IMMUTABLE | 校验查询文本（非 NULL、最大长度、不含控制字符） |
| `validate_graph_name(text)` | `void` | plpgsql | IMMUTABLE | 校验图名格式（正则 + 长度限制 ≤63） |
| `validate_top_k(int)` | `void` | plpgsql | IMMUTABLE | 校验 top_k 范围 [1, 1000] |

### 3.2 检索函数

| 函数名 | 返回类型 | 语言 | 易变性 | 并行安全 |
|--------|---------|------|--------|---------|
| `search_objects(text, text, text, int, vector)` | TABLE(...) | plpgsql | STABLE | SAFE |
| `search_attributes(text, text, int, vector)` | TABLE(...) | plpgsql | STABLE | SAFE |
| `find_objects_by_attribute(int, text, int)` | TABLE(...) | plpgsql | STABLE | SAFE |
| `search_object_attribute(text, text, int, vector)` | TABLE(...) | plpgsql | STABLE | SAFE |
| `get_object_attributes(bigint, text)` | TABLE(...) | plpgsql | STABLE | SAFE |
| `get_related_objects(bigint, text, text)` | TABLE(...) | plpgsql | STABLE | SAFE |

### 3.3 写入函数

| 函数名 | 返回类型 | 语言 | 说明 |
|--------|---------|------|------|
| `upsert_vertex_embedding(bigint, text, text, text, vector, text, jsonb)` | `void` | plpgsql | 插入或更新对象 embedding |
| `upsert_attribute_embedding(text, text, vector, bigint, text[], text, text)` | `int` | plpgsql | 插入或更新属性 embedding，返回 attr_id |
| `link_object_attribute(text, bigint, int, text, float)` | `void` | plpgsql | 建立对象-属性关联 |

---

## 四、ER 图（实体关系）

```
┌─────────────────────────────┐
│     vector_registry         │
│─────────────────────────────│
│ PK │ id                     │
│ UK │ table_name             │
│    │ graph_name             │
│    │ entity_type            │
│    │ vector_dim             │
│    │ index_type             │
│    │ ...                    │
└─────────────────────────────┘
           │ (管理元数据)
           ▼
┌─────────────────────────────┐       ┌─────────────────────────────┐
│    vertex_embeddings        │       │   attribute_embeddings      │
│─────────────────────────────│       │─────────────────────────────│
│ PK │ id                     │       │ PK │ id                     │
│ UK │ (graph_name,vertex_id) │       │ UK │ (graph_name,attr_name) │
│    │ vertex_name            │       │    │ attr_name              │
│    │ label_name             │       │    │ aliases[]              │
│    │ description            │       │    │ description            │
│    │ embedding vector(1536) │       │    │ embedding vector(1536) │
│    │ metadata jsonb         │       │    │ data_type              │
│    │ created_at / updated_at│       │    │ created_at / updated_at│
└──────────┬──────────────────┘       └─────────────┬───────────────┘
           │                                        │
           │  (vertex_id)                           │ (id = attr_id)
           │                                        │
           ▼                                        ▼
┌─────────────────────────────────────────────────────────────┐
│               object_attribute_mapping                      │
│─────────────────────────────────────────────────────────────│
│ PK │ id                                                     │
│ UK │ (graph_name, object_vertex_id, attr_id)                │
│ FK │ attr_id → attribute_embeddings(id)                     │
│    │ object_vertex_id (关联 vertex_embeddings.vertex_id)    │
│    │ object_label                                           │
│    │ relation_type                                          │
│    │ confidence float [0,1]                                 │
│    │ created_at                                             │
└─────────────────────────────────────────────────────────────┘
           │
           │ (通过 graph_name, vertex_id 关联)
           ▼
┌─────────────────────────────────────────────────────────────┐
│              AGE 图 (ag_catalog Schema)                     │
│─────────────────────────────────────────────────────────────│
│  ag_graph   │  ag_label  │  ag_vertex  │  ag_edge           │
│  图元数据   │  标签定义   │  顶点数据   │  边数据            │
└─────────────────────────────────────────────────────────────┘
```
