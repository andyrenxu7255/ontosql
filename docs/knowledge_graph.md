# OntoSQL 结构化知识图谱 (Agent-Oriented)

> **用途**: 为 Agent 提供系统性的本体论对象索引，支持按图索骥式代码检索与渐进式上下文加载。
> **格式**: 纯 Markdown（适合中等复杂度系统，确保可读性与可维护性）
> **版本**: 1.0.0 | **生成日期**: 2026-05-11

---

## 〇、项目身份卡 (Project Identity)

| 属性 | 值 |
|------|-----|
| **项目名称** | OntoSQL — 面向智能问数的融合数据库平台 |
| **技术栈** | PostgreSQL 17.4 + pgvector 0.8.1 + Apache AGE 1.7.0-dev + pg_trgm |
| **编程范式** | 声明式（SQL/PLpgSQL），零 C 代码依赖 |
| **核心能力** | 关系查询 + 图遍历 (openCypher) + 向量语义搜索 (HNSW) |
| **设计原则** | 零侵入 / 浅层集成 / 多路召回 / 函数封装 |
| **Schema 版本** | v1.0.0 |
| **源码入口** | [sql/001_core_schema.sql](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql) |
| **构建入口** | [Makefile](file:///Users/liuruiqi/ontosql/Makefile) |

---

## 一、概念本体论 (Conceptual Ontology)

```
OntoSQL 领域模型
═══════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────┐
│                    智能问数领域 (NL2SQL)                      │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ 业务对象  │───▶│ 指标属性  │───▶│ 分析维度  │              │
│  │ Object   │    │ Metric   │    │Dimension │              │
│  └────┬─────┘    └──────────┘    └──────────┘              │
│       │                                                     │
│       ▼                                                     │
│  ┌──────────┐                                              │
│  │ 组织归属  │    Department                               │
│  └──────────┘                                              │
│                                                             │
│  四大关系类型:                                               │
│  Object -[:HAS_METRIC]-> Metric       (对象拥有指标)        │
│  Object -[:BELONGS_TO]-> Department   (对象归属部门)        │
│  Metric -[:HAS_DIMENSION]-> Dimension (指标关联维度)        │
│  Object -[:RELATED_TO]-> Object       (对象间关系)          │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ 双存储架构
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  AGE 图存储 (ag_catalog)          │  向量侧表 (ontosql)      │
│  ──────────────────────────       │  ──────────────────────  │
│  ag_graph / ag_label              │  vertex_embeddings       │
│  ag_vertex / ag_edge              │  attribute_embeddings    │
│  图遍历 + 关系验证 (Cypher)       │  语义搜索 (HNSW + trigram)│
│  按图索骥精准定位 is_verified     │  object_attribute_mapping │
│                                    │  (图关系物化缓存)          │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ 三大扩展引擎
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  pgvector            pg_trgm             Apache AGE         │
│  vector(1536)        similarity()        agtype              │
│  HNSW/IVFFlat        GIN trigram         openCypher          │
│  <=> 余弦距离         % 运算符            图顶点/边           │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、实体目录 (Entity Catalog)

> **重要性等级**: ⭐⭐⭐ 核心（系统运行必需）| ⭐⭐ 重要（常用功能）| ⭐ 辅助（配置/工具）
> **定义位置格式**: `文件:L起始行-L结束行`

### 2.1 数据表实体 (5 张表)

#### T-00 | `schema_version` ⭐
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L25-L30](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L25-L30) |
| **Schema** | `ontosql` |
| **用途** | Schema 版本追踪，支持升级与回滚 |
| **主键** | `version` (text) |
| **关键列** | `version`, `description`, `installed_by`, `installed_at` |
| **被依赖** | 元数据查询、迁移脚本 |
| **初始数据** | 1 行 (`v1.0.0`) |

#### T-01 | `vector_registry` ⭐
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L42-L56](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L42-L56) |
| **Schema** | `ontosql` |
| **用途** | 统一管理所有向量侧表的元数据 |
| **主键** | `id` (serial) |
| **唯一约束** | `table_name` |
| **CHECK 约束** | `entity_type IN ('vertex','edge','attribute')` |
| **CHECK 约束** | `index_type IN ('hnsw','ivfflat')` |
| **被依赖** | TEST-13（元数据完整性验证） |
| **初始数据** | 2 行（vertex_embeddings, attribute_embeddings） |

#### T-02 | `vertex_embeddings` ⭐⭐⭐
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L65-L77](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L65-L77) |
| **Schema** | `ontosql` |
| **用途** | 存储图中每个顶点的 embedding 向量，支持语义相似度搜索 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, vertex_id)` |
| **关键列** | `vertex_id`, `vertex_name`, `label_name`, `embedding vector(1536)`, `metadata jsonb` |
| **关联** | `(graph_name, vertex_id)` ⇔ AGE 图顶点 |
| **被谁读取** | `search_objects` (向量+trigram召回), `find_objects_by_attribute` (LEFT JOIN), `upsert_vertex_embedding` (写入), `link_object_attribute` (校验), `get_related_objects` (间接) |
| **索引** | HNSW(`embedding vector_cosine_ops` m=16) + GIN(`vertex_name gin_trgm_ops`) + B-tree(`graph_name, label_name`) |

#### T-03 | `attribute_embeddings` ⭐⭐⭐
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L98-L111](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L98-L111) |
| **Schema** | `ontosql` |
| **用途** | 存储指标/维度等属性的 embedding 向量，支持语义属性识别 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, attr_name)` |
| **关键列** | `attr_name`, `graph_name`, `aliases text[]`, `embedding vector(1536)`, `data_type`, `description` |
| **被谁读取** | `search_attributes` (向量+trigram+alias召回), `get_object_attributes` (JOIN), `upsert_attribute_embedding` (写入), `link_object_attribute` (校验) |
| **索引** | HNSW(`embedding vector_cosine_ops` m=16) + GIN(`attr_name gin_trgm_ops`) |

#### T-04 | `object_attribute_mapping` ⭐⭐⭐
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L126-L136](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L126-L136) |
| **Schema** | `ontosql` |
| **用途** | 物化对象与属性的关联关系，加速反查和验证 |
| **主键** | `id` (bigserial) |
| **唯一约束** | `(graph_name, object_vertex_id, attr_id)` |
| **外键** | `attr_id → attribute_embeddings(id)` |
| **关键列** | `object_vertex_id`, `attr_id`, `relation_type`, `confidence float [0,1]` |
| **被谁读取** | `find_objects_by_attribute` (反查), `search_object_attribute` (属性无图顶点时回退验证), `get_object_attributes` (JOIN), `link_object_attribute` (写入) |
| **索引** | B-tree(`graph_name, object_vertex_id`) + B-tree(`graph_name, attr_id`) |

### 2.2 索引实体 (7 个索引)

| ID | 索引名 | 类型 | 关联表 | 定义位置 |
|----|--------|------|--------|----------|
| I-01 | `idx_vertex_embeddings_hnsw` | HNSW m=16 | T-02 | [L80-L81](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L80-L81) |
| I-02 | `idx_vertex_embeddings_name_trgm` | GIN trigram | T-02 | [L84-L85](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L84-L85) |
| I-03 | `idx_vertex_embeddings_label` | B-tree | T-02 | [L88-L89](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L88-L89) |
| I-04 | `idx_attribute_embeddings_hnsw` | HNSW m=16 | T-03 | [L113-L114](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L113-L114) |
| I-05 | `idx_attribute_embeddings_name_trgm` | GIN trigram | T-03 | [L116-L117](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L116-L117) |
| I-06 | `idx_oam_object` | B-tree | T-04 | [L139-L140](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L139-L140) |
| I-07 | `idx_oam_attr` | B-tree | T-04 | [L142-L143](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L142-L143) |

### 2.3 函数实体 (12 个函数)

#### F-00 | `validate_query_text` ⭐⭐ (安全校验)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L163-L177](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L163-L177) |
| **签名** | `validate_query_text(query_text text, max_length int DEFAULT 1000) → void` |
| **语言/易变性** | plpgsql / IMMUTABLE |
| **校验规则** | 非 NULL → 长度 ≤ max_length → 不含控制字符 |
| **调用者** | F-03, F-04, F-06 |

#### F-01 | `validate_graph_name` ⭐⭐ (安全校验)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L179-L193](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L179-L193) |
| **签名** | `validate_graph_name(graph_name text) → void` |
| **语言/易变性** | plpgsql / IMMUTABLE |
| **校验规则** | 非 NULL → 正则 `^[a-zA-Z_][a-zA-Z0-9_]*$` → 长度 ≤ 63 |
| **调用者** | F-03, F-04, F-05, F-06, F-07, F-08, F-09, F-10, F-11 |

#### F-02 | `validate_top_k` ⭐⭐ (安全校验)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L195-L202](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L195-L202) |
| **签名** | `validate_top_k(p_top_k int) → void` |
| **语言/易变性** | plpgsql / IMMUTABLE |
| **校验规则** | 非 NULL 且 1 ≤ p_top_k ≤ 1000 |
| **调用者** | F-03, F-04, F-05, F-06 |

#### F-03 | `search_objects` ⭐⭐⭐ (核心检索)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L221-L280](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L221-L280) |
| **签名** | `search_objects(query_text text, p_graph_name text DEFAULT 'ontosql_graph', p_label text DEFAULT NULL, p_top_k int DEFAULT 10, p_query_embedding vector DEFAULT NULL) → TABLE(vertex_id bigint, vertex_name text, label_name text, vector_score float, trigram_score float, combined_score float)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | 向量 HNSW ANN (×3 扩容) + trigram GIN (×3 扩容) → UNION ALL → GROUP BY MAX → 加权 0.6×向量+0.4×trigram → LIMIT |
| **读取表** | T-02 |
| **调用函数** | F-00, F-01, F-02 |
| **被调用者** | F-06, 外部 Agent |

#### F-04 | `search_attributes` ⭐⭐⭐ (核心检索)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L290-L368](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L290-L368) |
| **签名** | `search_attributes(query_text text, p_graph_name text DEFAULT 'ontosql_graph', p_top_k int DEFAULT 10, p_query_embedding vector DEFAULT NULL) → TABLE(attr_name text, attr_id int, description text, vector_score float, trigram_score float, combined_score float)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | 同 F-03 双路召回 + alias 别名扩展召回 |
| **读取表** | T-03 |
| **调用函数** | F-00, F-01, F-02 |
| **被调用者** | F-06, 外部 Agent |

#### F-05 | `find_objects_by_attribute` ⭐⭐ (属性反查)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L379-L407](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L379-L407) |
| **签名** | `find_objects_by_attribute(p_attr_id int, p_graph_name text DEFAULT 'ontosql_graph', p_top_k int DEFAULT 20) → TABLE(object_vertex_id bigint, object_name text, object_label text, relation_type text)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | T-04 LEFT JOIN T-02（补全名称） |
| **读取表** | T-04, T-02 |

#### F-06 | `search_object_attribute` ⭐⭐⭐ (核心入口)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L424-L469](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L424-L469) |
| **签名** | `search_object_attribute(query_text text, p_graph_name text DEFAULT 'ontosql_graph', p_top_k int DEFAULT 10, p_query_embedding vector DEFAULT NULL) → TABLE(object_vertex_id bigint, object_name text, object_label text, attr_name text, attr_id int, obj_score float, attr_score float, combined_score float, is_verified boolean)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | F-03(×2扩容) + F-04(×2扩容) → CROSS JOIN 笛卡尔积 → AGE 图 Cypher 批量验证 → 综合分 0.5×obj+0.5×attr |
| **读取表** | G-01 (AGE 图 Cypher 查询), T-04 (回退：属性无图顶点时) |
| **调用函数** | F-00, F-01, F-02, F-03, F-04 |
| **被调用者** | 外部 Agent（三步工作流 Step 1） |

#### F-07 | `get_object_attributes` ⭐⭐ (对象属性列表)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L480-L509](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L480-L509) |
| **签名** | `get_object_attributes(p_object_vertex_id bigint, p_graph_name text DEFAULT 'ontosql_graph') → TABLE(attr_id int, attr_name text, data_type text, description text, relation_type text, confidence float)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | T-04 JOIN T-03，按 confidence DESC |
| **被调用者** | 外部 Agent（三步工作流 Step 2a） |

#### F-08 | `get_related_objects` ⭐⭐ (图遍历)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L523-L564](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L523-L564) |
| **签名** | `get_related_objects(p_vertex_id bigint, p_graph_name text DEFAULT 'ontosql_graph', p_relation_type text DEFAULT NULL) → TABLE(related_vertex_id bigint, related_name text, related_label text, relation_type text)` |
| **语言/易变性** | plpgsql / STABLE PARALLEL SAFE |
| **算法** | 动态拼接 Cypher `MATCH (a)-[r]->(b) WHERE id(a)=...` → `cypher()` 函数 |
| **依赖** | AGE `cypher()` 函数, `search_path` 需包含 `ag_catalog` |
| **被调用者** | 外部 Agent（三步工作流 Step 2b） |

#### F-09 | `upsert_vertex_embedding` ⭐⭐ (写入)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L577-L619](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L577-L619) |
| **签名** | `upsert_vertex_embedding(p_vertex_id bigint, p_graph_name text, p_label_name text, p_vertex_name text, p_embedding vector, p_description text DEFAULT NULL, p_metadata jsonb DEFAULT '{}') → void` |
| **语言/易变性** | plpgsql / VOLATILE |
| **校验** | label_name/vertex_name 非空, embedding 非 NULL, 维度 = 1536 |
| **写入** | T-02 (ON CONFLICT UPSERT), description COALESCE 保留旧值 |

#### F-10 | `upsert_attribute_embedding` ⭐⭐ (写入)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L628-L670](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L628-L670) |
| **签名** | `upsert_attribute_embedding(p_attr_name text, p_graph_name text, p_embedding vector, p_attr_vertex_id bigint DEFAULT NULL, p_aliases text[] DEFAULT NULL, p_description text DEFAULT NULL, p_data_type text DEFAULT NULL) → int` |
| **语言/易变性** | plpgsql / VOLATILE |
| **返回** | `attr_id`（供后续 F-11 调用） |
| **写入** | T-03 (ON CONFLICT UPSERT) |

#### F-11 | `link_object_attribute` ⭐⭐ (写入)
| 属性 | 值 |
|------|-----|
| **定义位置** | [001_core_schema.sql:L683-L726](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L683-L726) |
| **签名** | `link_object_attribute(p_graph_name text, p_object_vertex_id bigint, p_attr_id int, p_relation_type text DEFAULT 'HAS_METRIC', p_confidence float DEFAULT 1.0) → void` |
| **语言/易变性** | plpgsql / VOLATILE |
| **双重校验** | ① vertex_id 在 T-02 中存在 ② attr_id 在 T-03 中存在且同图 ③ p_relation_type 白名单校验 |
| **写入** | T-04 (ON CONFLICT UPSERT) + G-01 (AGE 图 MERGE 创建边，属性有图顶点时) |

### 2.4 图模型实体 (1 图 + 4 顶点标签 + 4 边标签)

| ID | 名称 | 类型 | 所属图 | 定义位置 | 重要性 |
|----|------|------|--------|----------|--------|
| G-01 | `ontosql_graph` | GRAPH | — | [002_knowledge_graph.sql:L30-L41](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L30-L41) | ⭐⭐⭐ |
| G-02 | `Object` | VLABEL | ontosql_graph | [L48](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L48) | ⭐⭐⭐ |
| G-03 | `Metric` | VLABEL | ontosql_graph | [L51](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L51) | ⭐⭐⭐ |
| G-04 | `Dimension` | VLABEL | ontosql_graph | [L54](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L54) | ⭐⭐ |
| G-05 | `Department` | VLABEL | ontosql_graph | [L57](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L57) | ⭐⭐ |
| G-06 | `HAS_METRIC` | ELABEL | ontosql_graph | [L64](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L64) | ⭐⭐⭐ |
| G-07 | `BELONGS_TO` | ELABEL | ontosql_graph | [L67](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L67) | ⭐⭐ |
| G-08 | `HAS_DIMENSION` | ELABEL | ontosql_graph | [L70](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L70) | ⭐⭐ |
| G-09 | `RELATED_TO` | ELABEL | ontosql_graph | [L73](file:///Users/liuruiqi/ontosql/sql/002_knowledge_graph.sql#L73) | ⭐ |

### 2.5 构建层实体 (Makefile + Docker)

| ID | 名称 | 类型 | 定义位置 | 依赖 | 重要性 |
|----|------|------|----------|------|--------|
| M-01 | `all` | TARGET | [Makefile:L32](file:///Users/liuruiqi/ontosql/Makefile#L32) | → M-02 | ⭐ |
| M-02 | `build` | TARGET | [Makefile:L34](file:///Users/liuruiqi/ontosql/Makefile#L34) | → M-03, M-04, M-05 | ⭐⭐⭐ |
| M-03 | `build-pg` | TARGET | [Makefile:L50-L58](file:///Users/liuruiqi/ontosql/Makefile#L50-L58) | upstream/postgresql/ | ⭐⭐⭐ |
| M-04 | `build-pgvector` | TARGET | [Makefile:L63-L66](file:///Users/liuruiqi/ontosql/Makefile#L63-L66) | → M-03 | ⭐⭐ |
| M-05 | `build-age` | TARGET | [Makefile:L72-L75](file:///Users/liuruiqi/ontosql/Makefile#L72-L75) | → M-03 | ⭐⭐ |
| M-06 | `install` | TARGET | [Makefile:L80-L82](file:///Users/liuruiqi/ontosql/Makefile#L80-L82) | → M-02 | ⭐ |
| M-07 | `init-db` | TARGET | [Makefile:L91-L100](file:///Users/liuruiqi/ontosql/Makefile#L91-L100) | build/pgsql17/ | ⭐⭐ |
| M-08 | `start` | TARGET | [Makefile:L105-L113](file:///Users/liuruiqi/ontosql/Makefile#L105-L113) | → M-07 | ⭐⭐⭐ |
| M-09 | `stop` | TARGET | [Makefile:L118-L119](file:///Users/liuruiqi/ontosql/Makefile#L118-L119) | — | ⭐ |
| M-10 | `test` | TARGET | [Makefile:L136-L138](file:///Users/liuruiqi/ontosql/Makefile#L136-L138) | → M-08 | ⭐⭐ |
| M-11 | `clean` | TARGET | [Makefile:L125-L130](file:///Users/liuruiqi/ontosql/Makefile#L125-L130) | — | ⭐ |
| M-12 | `docs` | TARGET | [Makefile:L143-L154](file:///Users/liuruiqi/ontosql/Makefile#L143-L154) | — | ⭐ |
| M-13 | `psql` | TARGET | [Makefile:L159-L160](file:///Users/liuruiqi/ontosql/Makefile#L159-L160) | → M-08 | ⭐ |
| D-01 | `Dockerfile` (PG) | BUILD | [docker/Dockerfile](file:///Users/liuruiqi/ontosql/docker/Dockerfile) | upstream/三组件 | ⭐⭐ |
| D-02 | `Dockerfile.pgbouncer` | BUILD | [docker/Dockerfile.pgbouncer](file:///Users/liuruiqi/ontosql/docker/Dockerfile.pgbouncer) | C-02, D-04 | ⭐⭐ |
| D-03 | `docker-compose.yml` | ORCHESTRATION | [docker/docker-compose.yml](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml) | D-01, D-02, D-04, D-05 | ⭐⭐ |
| D-04 | `entrypoint.sh` (PG) | SCRIPT | [docker/entrypoint.sh](file:///Users/liuruiqi/ontosql/docker/entrypoint.sh) | build/pgsql17/ | ⭐⭐⭐ |
| D-05 | `pgbouncer-entrypoint.sh` | SCRIPT | [docker/pgbouncer-entrypoint.sh](file:///Users/liuruiqi/ontosql/docker/pgbouncer-entrypoint.sh) | C-02, pgbouncer | ⭐⭐ |
| SV-01 | `ontosql` (service) | SERVICE | [docker-compose.yml:L12-L61](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L12-L61) | D-01, D-04, pgdata volume | ⭐⭐⭐ |
| SV-02 | `pgbouncer` (service) | SERVICE | [docker-compose.yml:L63-L97](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L63-L97) | D-02, D-05, SV-01 | ⭐⭐ |
| MV-01 | `PG_HOME` / `PG_CONFIG` | MAKE_VAR | [Makefile:L14-L16](file:///Users/liuruiqi/ontosql/Makefile#L14-L16) | — | ⭐⭐ |
| MV-02 | `PG_DATA` / `PG_LOG` / `PG_PORT` | MAKE_VAR | [Makefile:L18-L22](file:///Users/liuruiqi/ontosql/Makefile#L18-L22) | — | ⭐⭐ |
| MV-03 | `PG_USER` | MAKE_VAR | [Makefile:L24](file:///Users/liuruiqi/ontosql/Makefile#L24) | OS whoami | ⭐ |
| MV-04 | `PG_SRC` / `PGV_SRC` / `AGE_SRC` | MAKE_VAR | [Makefile:L27-L29](file:///Users/liuruiqi/ontosql/Makefile#L27-L29) | upstream/ | ⭐⭐ |

### 2.6 配置实体

#### C-01 | `postgresql.template.sql` (生产环境 PG 参数配置) ⭐⭐
| 参数组 | 关键参数 | 定义位置 |
|--------|---------|----------|
| 内存配置 (5) | `shared_buffers`, `effective_cache_size`, `work_mem`, `maintenance_work_mem`, `wal_buffers` | [config/postgresql.template.sql](file:///Users/liuruiqi/ontosql/config/postgresql.template.sql) |
| 连接配置 (2) | `max_connections`, `superuser_reserved_connections` | 同上 |
| WAL 配置 (5) | `wal_level`, `max_wal_size`, `checkpoint_completion_target` | 同上 |
| 规划器配置 (3) | `random_page_cost`, `effective_io_concurrency` | 同上 |
| 扩展配置 (1) | `hnsw.ef_search` | 同上 |
| 日志配置 (8) | `log_min_duration_statement`, `log_line_prefix` | 同上 |

#### C-02 | `pgbouncer.ini` (PgBouncer 连接池配置) ⭐⭐
| 关键参数 | 值 | 用途 |
|---------|-----|------|
| `pool_mode` | `transaction` | 事务级连接池复用 |
| `default_pool_size` | `25` | 默认连接池大小 |
| `max_client_conn` | `100` | 最大客户端连接数 |
| `auth_type` | `scram-sha-256` | 认证加密方式 |
| `server_idle_timeout` | `600` | 服务端空闲超时(秒) |
| **定义位置** | [config/pgbouncer.ini](file:///Users/liuruiqi/ontosql/config/pgbouncer.ini) | |

### 2.7 文档实体 (11 个)

| ID | 名称 | 类型 | 位置 | 重要性 |
|----|------|------|------|--------|
| DOC-01 | `README.md` | DOC | [/README.md](file:///Users/liuruiqi/ontosql/README.md) | ⭐⭐⭐ |
| DOC-02 | `agent_guide.md` | DOC | [docs/agent_guide.md](file:///Users/liuruiqi/ontosql/docs/agent_guide.md) | ⭐⭐⭐ |
| DOC-03 | `api.md` | DOC | [docs/api.md](file:///Users/liuruiqi/ontosql/docs/api.md) | ⭐⭐ |
| DOC-04 | `architecture.md` | DOC | [docs/architecture.md](file:///Users/liuruiqi/ontosql/docs/architecture.md) | ⭐⭐ |
| DOC-05 | `data_dictionary.md` | DOC | [docs/data_dictionary.md](file:///Users/liuruiqi/ontosql/docs/data_dictionary.md) | ⭐⭐ |
| DOC-06 | `modules.md` | DOC | [docs/modules.md](file:///Users/liuruiqi/ontosql/docs/modules.md) | ⭐⭐ |
| DOC-07 | `ops.md` | DOC | [docs/ops.md](file:///Users/liuruiqi/ontosql/docs/ops.md) | ⭐⭐ |
| DOC-08 | `object_index.md` | DOC | [docs/object_index.md](file:///Users/liuruiqi/ontosql/docs/object_index.md) | ⭐⭐ |
| DOC-09 | `code_review.md` | DOC | [docs/code_review.md](file:///Users/liuruiqi/ontosql/docs/code_review.md) | ⭐ |
| DOC-10 | `consistency_audit.md` | DOC | [docs/consistency_audit.md](file:///Users/liuruiqi/ontosql/docs/consistency_audit.md) | ⭐ |
| DOC-11 | `overview.md` | DOC | [docs/overview.md](file:///Users/liuruiqi/ontosql/docs/overview.md) | ⭐ |
| DOC-12 | `knowledge_graph.md` | DOC | [docs/knowledge_graph.md](file:///Users/liuruiqi/ontosql/docs/knowledge_graph.md) | ⭐⭐⭐ |

### 2.8 测试与示例实体

| ID | 名称 | 类型 | 位置 | 重要性 |
|----|------|------|------|--------|
| TEST-01 | `setup.sql` | TEST | [tests/setup.sql](file:///Users/liuruiqi/ontosql/tests/setup.sql) | ⭐⭐ |
| TEST-02 | `test_cases.sql` | TEST | [tests/test_cases.sql](file:///Users/liuruiqi/ontosql/tests/test_cases.sql) | ⭐⭐ |
| EX-01 | `usage.sql` | EXAMPLE | [examples/usage.sql](file:///Users/liuruiqi/ontosql/examples/usage.sql) | ⭐⭐ |
| GI-01 | `.gitignore` | META | [/.gitignore](file:///Users/liuruiqi/ontosql/.gitignore) | ⭐ |

---

## 三、关系图谱 (Relationship Graph)

### 3.1 关系类型分类

| 关系类型 | 符号 | 含义 | 示例 |
|---------|------|------|------|
| **CALLS** | `→` | 函数 A 内部调用函数 B | F-06 → F-03 |
| **READS** | `⇢` | 函数读表数据 | F-03 ⇢ T-02 |
| **WRITES** | `⇢` | 函数写表数据 | F-09 ⇢ T-02 |
| **REFERENCES** | `⥇` | 表外键引用 | T-04 ⥇ T-03 |
| **DEPENDS** | `⇒` | 构建目标依赖 | M-08 ⇒ M-07 |
| **BELONGS_TO** | `∈` | 索引/约束属于表 | I-01 ∈ T-02 |
| **MANAGES** | `⊳` | 元数据管理 | T-01 ⊳ T-02 |

### 3.2 函数调用图

```
                          ┌──────────────────────────────┐
                          │  F-06 search_object_attribute │  ← ⭐⭐⭐ 核心入口
                          │  [L424-L469]                  │
                          └──────────────┬───────────────┘
                                         │ CALLS (CROSS JOIN 内部)
                    ┌────────────────────┼────────────────────┐
                    ▼                    ▼                     ▼
          ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
          │ F-03            │  │ F-04            │  │ T-04                 │
          │ search_objects  │  │ search_attributes│  │ object_attribute_    │
          │ [L221-L280]     │  │ [L290-L368]     │  │   mapping (EXISTS)   │
          └────────┬────────┘  └────────┬────────┘  └──────────────────────┘
                   │                    │
                   │ CALLS              │ CALLS
                   ▼                    ▼
          ┌─────────────────────────────────────────┐
          │  F-00 validate_query_text  [L163-L177]  │
          │  F-01 validate_graph_name  [L179-L193]  │
          │  F-02 validate_top_k       [L195-L202]  │
          └─────────────────────────────────────────┘
```

### 3.3 数据读写图

```
函数 (Function)                        表 (Table)
══════════════                        ═══════════

F-03 search_objects ───── READ ────▶ T-02 vertex_embeddings
F-04 search_attributes ── READ ────▶ T-03 attribute_embeddings
F-05 find_objects_by_attr ─ READ ──▶ T-04 object_attribute_mapping
                       ── READ ────▶ T-02 (LEFT JOIN)
F-06 search_obj_attr ──── READ ────▶ AGE 图 G-01 (Cypher 批量验证)
                   ──── READ ────▶ T-04 (回退：属性无图顶点时)
F-07 get_object_attrs ── READ ────▶ T-04 JOIN T-03
F-08 get_related_objs ─── READ ────▶ AGE 图 (Cypher)
F-09 upsert_vertex ───── WRITE ───▶ T-02 (UPSERT)
F-10 upsert_attribute ── WRITE ───▶ T-03 (UPSERT)
F-11 link_obj_attr ───── VALIDATE ─▶ T-02, T-03 (存在性检查)
                   ───── WRITE ───▶ T-04 (UPSERT)
                   ───── WRITE ───▶ AGE 图 G-01 (创建 HAS_METRIC 等边)
```

### 3.4 外键依赖链

```
T-04.object_attribute_mapping
  │
  └── attr_id ── REFERENCES ──▶ T-03.attribute_embeddings.id
                                    │
                                    └── (被 F-06 中 EXISTS 子查询间接引用)
```

### 3.5 构建依赖拓扑图

```
upstream/postgresql/
        │
        ▼
    M-03 build-pg ──────────────────────▶ build/pgsql17/
        │                                       │
        ├──▶ M-04 build-pgvector ──▶ pgvector.so │
        │                                       │
        └──▶ M-05 build-age ────────▶ age.so     │
                │                                 │
                └──────────┬──────────────────────┘
                           ▼
                      M-02 build
                           │
                           ▼
                      M-06 install ──▶ sql/* → share/
                           │
                           ▼
                      M-07 init-db ──▶ build/data/
                           │
                           ▼
                      M-08 start ──▶ 运行中 PG 实例
                           │
                           ├──▶ M-10 test ──▶ TEST-01 → TEST-02
                           │
                           └──▶ M-13 psql

Docker 构建与编排层级:
    D-01 Dockerfile (多阶段) ──▶ ontosql 镜像
        │                              │
        └──▶ D-04 entrypoint.sh ──────▶ SV-01 ontosql service
                                           │
    D-02 Dockerfile.pgbouncer ──▶ pgbouncer 镜像  │
        │                              │          │
        ├──▶ C-02 pgbouncer.ini        │          │
        └──▶ D-05 pgbouncer- ─────────▶ SV-02 pgbouncer service
              entrypoint.sh                (depends_on SV-01 healthy)
```

### 3.6 Agent 三步工作流 (端到端数据流)

```
用户 NL 输入: "张三上月销售额多少"
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ Step 1: F-06 search_object_attribute()                    │
│   ├── F-03 search_objects()   ⇢ T-02 (HNSW + trigram)    │
│   ├── F-04 search_attributes() ⇢ T-03 (HNSW + trigram)   │
│   └── AGE 图 Cypher 批量验证 ⇢ G-01 图                   │
│       MATCH (obj:Object)-[r]->(prop)                      │
│       WHERE id(obj) IN [...] AND id(prop) IN [...]        │
│       → is_verified = true/false                          │
│   输出: (张三, 销售额, score=0.96, is_verified=true)      │
└──────────────────────────┬────────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────────┐
│ Step 2a: F-07 get_object_attributes()                     │
│   └── JOIN T-04 + T-03 ⇢ 列出张三的全部属性               │
│ Step 2b: F-08 get_related_objects()                       │
│   └── cypher() ⇢ AGE 图 ⇢ 找部门、同事                   │
└──────────────────────────┬────────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────────┐
│ Step 3: Agent 读 metadata ⇢ 生成业务 SQL                  │
│   └── T-02.metadata → {business_table, join_key, value}   │
│   └── T-03.metadata → {business_table, business_column,   │
│                         aggregation}                       │
│   → SELECT SUM(amount) FROM sales_fact WHERE ...          │
└───────────────────────────────────────────────────────────┘
```

---

## 四、Agent 导航路径 (Navigation Paths)

### 4.1 按功能意图检索

| Agent 意图 | 导航路径 | 关键入口 |
|-----------|---------|---------|
| **理解项目全貌** | DOC-01 → DOC-02 → DOC-04 | README.md |
| **理解数据模型** | T-02 → T-03 → T-04 → 参考 DOC-05 | vertex_embeddings |
| **理解检索机制** | F-06 → F-03 → F-04 → 参考 DOC-02 | search_object_attribute |
| **理解写入流程** | F-09 → F-10 → F-11 | upsert_vertex_embedding |
| **理解图模型** | G-01 → G-02~G-09 → 参考 DOC-06 §三 | ontosql_graph |
| **理解构建部署** | M-02 → M-03 → M-08 → 参考 DOC-04 §扩展架构 | Makefile |
| **写测试用例** | TEST-01 → TEST-02 → 参考 DOC-05 §三 | test_cases.sql |
| **排查检索错误** | F-06 → F-03 → F-04 → I-01~I-05 | search_object_attribute |
| **新增数据表** | T-01 → 参考 DOC-08 §十 | vector_registry |
| **Docker 部署** | D-01 → D-03 → SV-01 → SV-02 | docker-compose.yml |
| **连接池配置** | D-02 → D-05 → C-02 | pgbouncer-entrypoint.sh |
| **运维操作** | DOC-07 (备份/监控/安全加固) | ops.md |

### 4.2 渐进式上下文加载策略

```
Level 0 (13 个关键对象) — 首次加载，理解系统骨架:
  ├── T-02 vertex_embeddings       ← 数据核心
  ├── T-03 attribute_embeddings     ← 数据核心
  ├── T-04 object_attribute_mapping ← 关联核心
  ├── F-00 validate_query_text      ← 安全校验
  ├── F-01 validate_graph_name      ← 安全校验
  ├── F-02 validate_top_k           ← 安全校验
  ├── F-03 search_objects           ← 检索入口
  ├── F-04 search_attributes        ← 检索入口
  ├── F-06 search_object_attribute  ← 核心入口
  ├── G-01 ontosql_graph            ← 图核心
  ├── G-06 HAS_METRIC               ← 核心关系
  ├── DOC-02 agent_guide.md         ← Agent 必读
  └── DOC-03 api.md                 ← 接口参考

Level 1 (展开到 ~28 个对象) — 需要理解具体功能时:
  + F-05, F-07, F-08                ← 辅助检索
  + F-09, F-10, F-11                ← 写入函数
  + G-02~G-09                       ← 全图模型
  + I-01~I-07                       ← 索引结构
  + DOC-05 data_dictionary.md       ← 数据字典

Level 2 (全部 ~86 个对象) — 需要修改/扩展系统时:
  + M-01~M-13                       ← 构建系统
  + MV-01~MV-04                      ← Makefile 路径变量
  + D-01~D-05                        ← Docker 镜像与脚本
  + SV-01, SV-02                     ← docker-compose 服务实体
  + C-01~C-02                        ← 配置模板（含参数组详情）
  + TEST-01, TEST-02                 ← 测试
  + DOC-06~DOC-12                    ← 模块/运维/审查文档
  + GI-01                            ← .gitignore 元信息
```

---

## 五、快速检索索引 (Quick Retrieval Index)

### 5.1 按文件查找对象

| 文件 | 包含实体 ID |
|------|------------|
| `sql/001_core_schema.sql` | T-00~T-04, I-01~I-07, F-00~F-11 |
| `sql/002_knowledge_graph.sql` | G-01~G-09 |
| `Makefile` | M-01~M-13 |
| `docker/Dockerfile` | D-01 |
| `docker/Dockerfile.pgbouncer` | D-02 |
| `docker/docker-compose.yml` | D-03, SV-01, SV-02 |
| `docker/entrypoint.sh` | D-04 |
| `docker/pgbouncer-entrypoint.sh` | D-05 |
| `config/postgresql.template.sql` | C-01 |
| `config/pgbouncer.ini` | C-02 |
| `tests/setup.sql` | TEST-01 |
| `tests/test_cases.sql` | TEST-02 |
| `examples/usage.sql` | EX-01 |
| `.gitignore` | GI-01 |

### 5.2 按标签/类型检索

| 标签 | 实体列表 |
|------|---------|
| `@core` (系统运行必需) | T-02, T-03, T-04, F-03, F-04, F-06, G-01, D-04 |
| `@write` (数据写入) | F-09, F-10, F-11 |
| `@read` (数据检索) | F-03, F-04, F-05, F-06, F-07, F-08 |
| `@validate` (安全校验) | F-00, F-01, F-02 |
| `@graph` (图模型) | G-01~G-09 |
| `@build` (构建系统) | M-01~M-13, MV-01~MV-04 |
| `@docker` (容器化) | D-01~D-05, SV-01, SV-02 |
| `@index` (索引结构) | I-01~I-07 |
| `@config` (配置项) | C-01, C-02 |
| `@test` (测试相关) | TEST-01, TEST-02 |
| `@doc` (文档) | DOC-01~DOC-11 |
| `@meta` (元信息) | GI-01 |

### 5.3 调用链查找 (给定函数，查调用者/被调用者)

| 函数 | 调用者 (谁调它) | 被调用者 (它调谁) | 读取表 |
|------|---------------|-----------------|--------|
| F-00 | F-03, F-04, F-06 | — | — |
| F-01 | F-03~F-11 (全部检索/写入) | — | — |
| F-02 | F-03, F-04, F-05, F-06 | — | — |
| F-03 | F-06 | F-00, F-01, F-02 | T-02 |
| F-04 | F-06 | F-00, F-01, F-02 | T-03 |
| F-05 | 外部 Agent | F-01, F-02 | T-04, T-02 |
| F-06 | 外部 Agent | F-00, F-01, F-02, F-03, F-04 | T-04 |
| F-07 | 外部 Agent | F-01 | T-04, T-03 |
| F-08 | 外部 Agent | F-01, cypher() | AGE 图 |
| F-09 | 外部 Agent | F-01 | T-02 (WRITE) |
| F-10 | 外部 Agent | F-01 | T-03 (WRITE) |
| F-11 | 外部 Agent | F-01 | T-04 (WRITE), T-02, T-03 (VALIDATE), AGE 图 (WRITE 创建边) |

### 5.4 关键设计决策速查

| 决策 | 方案 | 影响对象 |
|------|------|---------|
| 向量与图分开存储 | 独立侧表 T-02/T-03 + AGE 图 | T-02, T-03, G-01 |
| 关联物化表 | T-04 避免每次 Cypher MATCH | T-04, F-05, F-06, F-07 |
| 多路召回权重 | 向量 0.6 + trigram 0.4 | F-03, F-04 |
| 联合检索 + 图验证 | CROSS JOIN + AGE Cypher 批量验证 | F-06 |
| 扩容因子 ×3 | candidate_pool = top_k × 3 | F-03, F-04 |
| 图关系权威来源 | AGE 图是 is_verified 的权威来源；映射表为缓存 | F-06, F-11 |
| COALESCE 保留旧值 | upsert 时 description 非覆盖 | F-09, F-10 |
| AGE 版本守卫 | `#if PG_VERSION_NUM` 兼容 PG 17 | M-05 |

---

## 六、示例数据规模

| 实体类型 | 数量 | 示例 |
|---------|------|------|
| Department | 4 | 销售部, 技术部, 财务部, 市场部 |
| Object (employee) | 5 | 张三, 李四, 王五, 赵六, 钱七 |
| Object (product) | 3 | 产品A, 产品B, 产品C |
| Object (customer) | 3 | 华科科技, 数据之光, 星辰网络 |
| Metric | 9 | 销售额, 利润率, 客户数, 订单量, 回款率, 客单价, 活跃用户数, 转化率, 库存周转天数 |
| Dimension | 6 | 本月, 上月, 本季度, 上季度, 本年, 去年 |
| Edges (关系) | ~30 | HAS_METRIC, BELONGS_TO, HAS_DIMENSION, RELATED_TO |

---

> **使用说明**: Agent 在阅读代码时应先查阅 §一（概念本体论）理解系统骨架，再根据具体任务类型查阅 §四（导航路径）确定需要加载哪些对象，最后通过 §五（快速检索索引）定位到具体文件和行号。对于首次接触系统的 Agent，建议按 Level 0 → Level 1 → Level 2 渐进式加载上下文。