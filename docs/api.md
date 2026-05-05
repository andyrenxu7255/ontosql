# OntoSQL API 参考文档

## 版本信息

| 项目 | 版本 |
|------|------|
| PostgreSQL | 17.4 (REL_17_STABLE) |
| pgvector | 0.8.1 |
| Apache AGE | 1.7.0-dev (master) |
| OntoSQL Schema | 1.0.0 |

## Schema 说明

所有 OntoSQL 对象位于 `ontosql` schema 下。使用前请确保：

```sql
SET search_path TO ontosql, ag_catalog, public;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
```

---

## 1. 向量注册表管理

### 1.1 vector_registry 表

管理项目中所有向量侧表的元信息。

| 列名 | 类型 | 说明 |
|------|------|------|
| `id` | serial | 主键 |
| `table_name` | text | 向量表名，全局唯一 |
| `graph_name` | text | 所属图名 |
| `entity_type` | text | 实体类型：`vertex`、`edge`、`attribute` |
| `label_or_type` | text | 顶点标签名或属性类型名 |
| `vector_column` | text | 向量列名，默认 `embedding` |
| `vector_dim` | int | 向量维度 |
| `index_type` | text | 索引类型：`hnsw` 或 `ivfflat` |
| `distance_ops` | text | 距离运算符类，如 `vector_cosine_ops` |
| `hnsw_m` | int | HNSW 参数 m，默认 16 |
| `ivfflat_lists` | int | IVFFlat 参数 lists，默认 100 |
| `description` | text | 描述信息 |
| `created_at` | timestamptz | 创建时间 |

---

## 2. 对象检索（对象识别）

### 2.1 search_objects

根据自然语言查询文本，通过**向量 + trigram 多路召回**搜索匹配的图对象。

#### 函数签名

```sql
FUNCTION search_objects(
    query_text          text,           -- NL 查询文本
    p_graph_name        text DEFAULT 'default',  -- 图名
    p_label             text DEFAULT NULL,       -- 可选：按标签过滤
    p_top_k             int  DEFAULT 10,         -- 返回结果数
    p_query_embedding   vector DEFAULT NULL      -- 可选：查询向量，NULL时仅trigram
) RETURNS TABLE(
    vertex_id       bigint,      -- 图顶点 ID
    vertex_name     text,        -- 对象名称
    label_name      text,        -- 对象标签
    vector_score    float,       -- 向量相似度分 (0~1)
    trigram_score   float,       -- trigram 文本相似分 (0~1)
    combined_score  float        -- 综合分数 (0~1)
)
```

#### 返回值说明

| 字段 | 类型 | 含义 |
|------|------|------|
| `vertex_id` | bigint | AGE 图中顶点的唯一标识，可用于 Cypher 查询 |
| `vertex_name` | text | 对象在库中的业务名称 |
| `label_name` | text | 对象的标签类型（如 `Object`、`Department`） |
| `vector_score` | float | 查询 embedding 与对象 embedding 的余弦相似度 |
| `trigram_score` | float | pg_trgm `similarity()` 函数返回值 |
| `combined_score` | float | 向量分 × 0.6 + trigram分 × 0.4 |

#### 使用示例

```sql
-- 搜索对象 "张三"
SELECT * FROM search_objects('张三', 'ontosql_graph');

-- 结果：
--  vertex_id | vertex_name | label_name | vector_score | trigram_score | combined_score
-- -----------+-------------+------------+---------------+--------------+---------------
--   84442... | 张三        | Object     |     0.9231    |    1.0000     |    0.9539
```

#### 错误码

| 错误场景 | 处理方式 |
|----------|----------|
| 查询文本为空 | 返回空结果集 |
| 指定的 graph_name 不存在 | 返回空结果集（不报错） |
| vertex_embeddings 表无数据 | 返回空结果集 |

---

## 3. 属性检索（属性识别）

### 3.1 search_attributes

通过向量 + trigram 多路召回搜索匹配的属性元数据。

#### 函数签名

```sql
FUNCTION search_attributes(
    query_text          text,           -- NL 查询文本
    p_graph_name        text DEFAULT 'default',  -- 图名
    p_top_k             int  DEFAULT 10,         -- 返回结果数
    p_query_embedding   vector DEFAULT NULL      -- 可选：查询向量，NULL时仅trigram
) RETURNS TABLE(
    attr_name       text,        -- 属性名称
    attr_id         int,         -- 属性 ID
    description     text,        -- 属性描述
    vector_score    float,       -- 向量相似度分
    trigram_score   float,       -- trigram 文本相似分
    combined_score  float        -- 综合分数
)
```

#### 使用示例

```sql
-- 搜索属性 "销售额"
SELECT * FROM search_attributes('销售额', 'ontosql_graph');

-- 结果：
--  attr_name | attr_id |    description     | vector_score | trigram_score | combined_score
-- -----------+---------+--------------------+--------------+---------------+---------------
--  销售额    |       1 | 销售产生的总金额    |     0.9512   |    1.0000     |    0.9707
--  客单价    |       6 | 平均每个客户的消费额 |     0.7834   |    0.2500     |    0.5700
```

---

## 4. 属性反查对象

### 4.1 find_objects_by_attribute

根据已知属性的 ID，查出所有拥有该属性的业务对象。

#### 函数签名

```sql
FUNCTION find_objects_by_attribute(
    p_attr_id    int,            -- 属性 ID（来自 search_attributes 结果）
    p_graph_name text DEFAULT 'default',
    p_top_k      int  DEFAULT 20
) RETURNS TABLE(
    object_vertex_id bigint,     -- 对象顶点 ID
    object_name      text,       -- 对象名称
    object_label     text,       -- 对象标签
    relation_type    text        -- 关系类型（如 HAS_ATTRIBUTE）
)
```

#### 使用示例

```sql
-- 已知属性 "销售额" 的 attr_id = 1，反查哪些对象拥有此属性
SELECT * FROM find_objects_by_attribute(1, 'ontosql_graph');

-- 结果：
--  object_vertex_id | object_name | object_label | relation_type
-- -------------------+-------------+--------------+---------------
--   844424930131969  | 张三        | Object       | HAS_ATTRIBUTE
--   844424930131971  | 赵六        | Object       | HAS_ATTRIBUTE
--   844424930131972  | 钱七        | Object       | HAS_ATTRIBUTE
--   844424930131973  | 产品A       | Object       | HAS_ATTRIBUTE
--   844424930131974  | 产品B       | Object       | HAS_ATTRIBUTE
--   844424930131977  | 华科科技    | Object       | HAS_ATTRIBUTE
```

---

## 5. 联合检索（对象+属性同时匹配）

### 5.1 search_object_attribute

**核心接口**：一次调用同时识别 NL 查询中的对象和属性，并验证它们之间是否存在关联。

#### 函数签名

```sql
FUNCTION search_object_attribute(
    query_text          text,           -- NL 查询文本
    p_graph_name        text DEFAULT 'default',
    p_top_k             int  DEFAULT 10,
    p_query_embedding   vector DEFAULT NULL  -- 可选：查询向量
) RETURNS TABLE(
    object_vertex_id bigint,     -- 对象顶点 ID
    object_name      text,       -- 对象名称
    object_label     text,       -- 对象标签
    attr_name        text,       -- 属性名称
    attr_id          int,        -- 属性 ID
    obj_score        float,      -- 对象匹配分
    attr_score       float,      -- 属性匹配分
    combined_score   float,      -- 综合分数
    is_verified      boolean     -- 对象-属性关联是否被图结构验证
)
```

#### 使用示例

```sql
-- 查询 "张三的销售额"
SELECT * FROM search_object_attribute('张三的销售额', 'ontosql_graph');

-- 结果：
--  object_vertex_id | object_name | object_label | attr_name | attr_id | obj_score | attr_score | combined_score | is_verified
-- -------------------+-------------+--------------+-----------+---------+-----------+------------+----------------+-------------
--   844424930131969  | 张三        | Object       | 销售额    |       1 |    0.9539 |     0.9707 |         0.9623 | true
--   844424930131969  | 张三        | Object       | 客单价    |       6 |    0.9539 |     0.5700 |         0.7620 | false

-- 只有 is_verified = true 的结果表示"张三确实有销售额这个属性"
```

---

## 6. 数据写入

### 6.1 upsert_vertex_embedding

插入或更新对象的 embedding。

```sql
FUNCTION upsert_vertex_embedding(
    p_vertex_id     bigint,        -- AGE 顶点 ID
    p_graph_name    text,          -- 图名
    p_label_name    text,          -- 标签名
    p_vertex_name   text,          -- 对象名称
    p_embedding     vector,        -- embedding 向量
    p_description   text DEFAULT NULL,   -- 描述
    p_metadata      jsonb DEFAULT '{}'   -- 扩展元数据
) RETURNS void
```

#### 使用示例

```sql
SELECT upsert_vertex_embedding(
    844424930131969,           -- 张三的 vertex_id
    'ontosql_graph',
    'Object',
    '张三',
    '[0.01, 0.02, ...]'::vector,
    '销售部员工，负责华东区域',
    '{"employee_id": "E001", "level": "P6"}'::jsonb
);
```

### 6.2 upsert_attribute_embedding

插入或更新属性的 embedding。**返回 attr_id**。

```sql
FUNCTION upsert_attribute_embedding(
    p_attr_name      text,        -- 属性名称
    p_graph_name     text,        -- 图名
    p_embedding      vector,      -- embedding 向量
    p_attr_vertex_id bigint DEFAULT NULL,  -- 若属性也建模为顶点，传其 ID
    p_aliases        text[] DEFAULT NULL,  -- 别名数组
    p_description    text DEFAULT NULL,    -- 描述
    p_data_type      text DEFAULT NULL     -- 数据类型
) RETURNS int                     -- 返回 attr_id
```

#### 使用示例

```sql
SELECT upsert_attribute_embedding(
    '销售额',
    'ontosql_graph',
    '[0.05, 0.03, ...]'::vector,
    NULL,
    ARRAY['营收', 'revenue', '销售收入'],
    '销售产生的总金额，含税',
    'numeric'
);
-- 返回: 1 （attr_id）
```

### 6.3 link_object_attribute

建立对象与属性的关联。

```sql
FUNCTION link_object_attribute(
    p_graph_name        text,              -- 图名
    p_object_vertex_id  bigint,           -- 对象顶点 ID
    p_attr_id           int,              -- 属性 ID
    p_relation_type     text DEFAULT 'HAS_ATTRIBUTE',
    p_confidence        float DEFAULT 1.0  -- 关联置信度
) RETURNS void
```

---

## 7. 综合示例：完整智能问数流程

```sql
-- 步骤 1：用户输入 "张三上月销售额多少"
-- 步骤 2：调用联合检索
SELECT * FROM search_object_attribute('张三上月销售额', 'ontosql_graph', 5);
-- 得到结果：张三 + 销售额，is_verified = true

-- 步骤 3：通过 Cypher 查询实际数值
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (obj:Object {name: '张三'})
          -[:HAS_METRIC]->(m:Metric {name: '销售额'})
          -[:HAS_DIMENSION]->(d:Dimension {name: '上月'})
    RETURN obj.name, m.name, d.name
$$) AS (obj_name agtype, metric_name agtype, dim agtype);

-- 步骤 4：结合业务数据仓库返回实际数值
```

---

## 错误码定义

| 错误码 | 分类 | 说明 |
|--------|------|------|
| `0` | 成功 | 操作正常完成 |
| `ERR_EMPTY_QUERY` | 输入错误 | 查询文本为空 |
| `ERR_GRAPH_NOT_FOUND` | 输入错误 | 指定的图名不存在 |
| `ERR_ATTR_NOT_FOUND` | 数据错误 | 属性 ID 不存在 |
| `ERR_DIM_MISMATCH` | 数据错误 | 向量维度不匹配 |
| `ERR_EMBEDDING_NULL` | 数据错误 | embedding 值为 NULL |
| `ERR_DUPLICATE_ENTRY` | 约束错误 | 插入重复的唯一键 |

---

## 性能基准

| 操作 | 数据规模 | 预期延迟 |
|------|---------|---------|
| search_objects | 10 万顶点 | < 10ms (HNSW) |
| search_attributes | 1 万属性 | < 5ms (HNSW) |
| find_objects_by_attribute | 100 万映射 | < 5ms (B-tree) |
| search_object_attribute | 10 万 × 1 万 | < 20ms |
