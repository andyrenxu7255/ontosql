# OntoSQL Agent 对接指南

## 概述

本指南描述外部 Agent（大模型推理引擎）如何基于 OntoSQL 的三个步骤完成「从自然语言到业务 SQL」的完整链路。

**核心思想**：OntoSQL 负责元数据层的检索和图验证（Steps 1-2），Agent 负责最终业务 SQL 的拼装（Step 3）。元数据到业务表的映射通过 `metadata` jsonb 字段承载，无需额外 DSL。

## 三步工作流

```
用户输入: "张三上月销售额多少"
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 1 — 语义召回 + AGE 图验证                            │
│                                                             │
│  调用: search_object_attribute('张三上月销售额',             │
│                                'ontosql_graph', 10, NULL)    │
│                                                             │
│  内部执行:                                                  │
│  1. search_objects() → 候选对象: [张三, 钱七, ...]         │
│  2. search_attributes() → 候选属性: [销售额, 客单价, ...]   │
│  3. AGE 图 Cypher 批量验证:                                 │
│     MATCH (obj:Object)-[:HAS_METRIC]->(m:Metric)            │
│     WHERE id(obj) IN [...] AND id(m) IN [...]              │
│  4. CROSS JOIN + 图验证 → is_verified                      │
│                                                             │
│  返回:                                                       │
│  ┌──────────┬────────┬──────────┬─────────────┐             │
│  │ object   │ attr   │ score    │ is_verified │             │
│  ├──────────┼────────┼──────────┼─────────────┤             │
│  │ 张三     │ 销售额 │  0.9623  │    true     │ ✅ 取这个   │
│  │ 张三     │ 客单价 │  0.7620  │    false    │ ❌ 丢弃     │
│  └──────────┴────────┴──────────┴─────────────┘             │
│                                                             │
│  Agent 动作：过滤 is_verified = true，拿到 object + attr    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 2 — 图结构按图索骥（属性列表 + 图遍历）              │
│                                                             │
│  2a. 列出对象的全部属性字段:                                 │
│  调用: get_object_attributes(张三.vertex_id,                 │
│                              'ontosql_graph')                │
│  返回:                                                      │
│  ┌────────┬──────────┬───────────┬──────────────────────┐   │
│  │ attr   │ data_type│ relation  │ description          │   │
│  ├────────┼──────────┼───────────┼──────────────────────┤   │
│  │ 销售额 │ numeric  │HAS_METRIC │ 销售产生的总金额      │   │
│  │ 客户数 │ integer  │HAS_METRIC │ 服务的客户总量        │   │
│  │ 回款率 │ numeric  │HAS_METRIC │ 已回款占总应收款比例  │   │
│  └────────┴──────────┴───────────┴──────────────────────┘   │
│                                                             │
│  2b. AGE 图遍历：按关系类型找关联对象/维度                  │
│  调用: get_related_objects(张三.vertex_id,                   │
│                            'ontosql_graph')                  │
│  返回:                                                      │
│  ┌──────────────┬────────┬──────────────┐                   │
│  │ related_name │ label  │ relation     │                   │
│  ├──────────────┼────────┼──────────────┤                   │
│  │ 销售额       │ Metric │ HAS_METRIC   │ ← 拥有的指标     │
│  │ 客户数       │ Metric │ HAS_METRIC   │                   │
│  │ 回款率       │ Metric │ HAS_METRIC   │                   │
│  │ 钱七         │ Object │ RELATED_TO   │ ← 同部门同事     │
│  │ 销售部       │ Dept   │ BELONGS_TO   │ ← 所属部门       │
│  └──────────────┴────────┴──────────────┘                   │
│                                                             │
│  Agent 动作：                                               │
│  1. 对比 Step 1 的"销售额"和 Step 2a 的列表 → 确认匹配     │
│  2. 通过图关系查"上月"维度：                                │
│     MATCH (销售额:Metric)-[:HAS_DIMENSION]->(上月:Dimension)│
│  3. 沿图路径 Object → HAS_METRIC → Metric → HAS_DIMENSION   │
│     → Dimension 精准定位字段                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 3 — 读 metadata 映射 → 生成业务 SQL                   │
│                                                             │
│  Agent 读取 vertex_embeddings.metadata:                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ {"business_table": "employees",                       │   │
│  │  "join_key": "employee_id",                           │   │
│  │  "value": "E001"}                                     │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Agent 读取 attribute_embeddings.metadata:                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ {"business_table": "sales_fact",                       │   │
│  │  "business_column": "amount",                          │   │
│  │  "aggregation": "SUM"}                                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Agent 组合生成:                                             │
│  SELECT SUM(s.amount)                                       │
│  FROM sales_fact s                                          │
│  JOIN employees e ON e.employee_id = s.employee_id          │
│  WHERE e.employee_id = 'E001'                               │
│    AND s.period = '2025-04'                                 │
└─────────────────────────────────────────────────────────────┘
```

## 函数速查

| 函数 | 用途 | 步骤 |
|------|------|------|
| `search_object_attribute(query, graph, top_k, embedding)` | 联合检索对象 + 属性 + 图验证 | Step 1 |
| `search_objects(query, graph, label, top_k, embedding)` | 仅检索对象 | Step 1（单独用） |
| `search_attributes(query, graph, top_k, embedding)` | 仅检索属性 | Step 1（单独用） |
| `get_object_attributes(vertex_id, graph)` | 列出对象的所有属性字段 | Step 2 |
| `get_related_objects(vertex_id, graph, relation_type)` | 图遍历找关联对象 | Step 2 |
| `find_objects_by_attribute(attr_id, graph, top_k)` | 属性反查对象 | Step 2（反向） |

## metadata 字段约定

`vertex_embeddings.metadata` 和 `attribute_embeddings.metadata` 均为 `jsonb` 类型，用于存储业务映射信息。

### 对象（vertex_embeddings）metadata 推荐结构

```json
{
  "business_table": "employees",
  "join_key": "employee_id",
  "value": "E001"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `business_table` | 是 | 该对象对应的业务数据表名 |
| `join_key` | 是 | 该表的主键/关联键列名 |
| `value` | 否 | 该对象对应的具体键值（若已知） |

### 属性（attribute_embeddings）metadata 推荐结构

```json
{
  "business_table": "sales_fact",
  "business_column": "amount",
  "aggregation": "SUM"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `business_table` | 是 | 该属性所在的业务数据表名 |
| `business_column` | 是 | 该属性对应的列名 |
| `aggregation` | 否 | 聚合函数：`SUM` / `AVG` / `COUNT` / `MAX` / `MIN`（NULL = 不聚合） |

## 完整示例（Agent 视角）

用户输入：**"张三上月销售额多少"**

```sql
SET search_path TO ontosql, ag_catalog, public;

-- Step 1: 联合检索
SELECT object_name, attr_name, combined_score, is_verified
FROM search_object_attribute('张三上月销售额', 'ontosql_graph', 10);
-- 结果: (张三, 销售额, 0.9623, true) ← 取 is_verified = true 的行

-- Step 2a: 列出张三的属性（确认销售额在其中）
SELECT attr_name, data_type, description
FROM get_object_attributes(
    (SELECT vertex_id FROM vertex_embeddings WHERE vertex_name = '张三' LIMIT 1),
    'ontosql_graph'
);
-- 结果包含: 销售额(numeric)、客户数(integer)、回款率(numeric)

-- Step 2b: 找出张三的部门
SELECT related_name, relation_type
FROM get_related_objects(
    (SELECT vertex_id FROM vertex_embeddings WHERE vertex_name = '张三' LIMIT 1),
    'ontosql_graph',
    'BELONGS_TO'
);
-- 结果: (销售部, BELONGS_TO)

-- Step 3: 读 metadata，生成业务 SQL
SELECT metadata FROM vertex_embeddings WHERE vertex_name = '张三';
-- → {"business_table": "employees", "join_key": "employee_id", "value": "E001"}

SELECT metadata FROM attribute_embeddings WHERE attr_name = '销售额';
-- → {"business_table": "sales_fact", "business_column": "amount", "aggregation": "SUM"}

-- Agent 理解到：
--   对象"张三" → 表 employees，键 employee_id = 'E001'
--   属性"销售额" → 表 sales_fact，列 amount，聚合 SUM
--   维度"上月" → WHERE period = '2025-04'

-- Agent 生成最终 SQL:
SELECT SUM(s.amount) AS 销售额
FROM sales_fact s
JOIN employees e ON e.employee_id = s.employee_id
WHERE e.employee_id = 'E001'
  AND s.period = '2025-04';
```

## 维度处理建议

时间/地域等分析维度（如"上月"、"华东区"）的处理方式：

1. **图内处理**：维度已作为 AGE 图顶点存储，可通过 `get_related_objects()` 按 `HAS_DIMENSION` 关系找到
2. **时间解析**：Agent 自行将自然语言时间词（上月/本季度）转为具体值（`2025-04` / `2025-Q1`）
3. **维度表查询**：若业务数据库有独立的维度表（如 `dim_period`），可在 metadata 中指定 `dimension_table` 和 `dimension_column`

## 注意事项

1. **search_path 设置**：调用 `get_related_objects()` 前确保 `search_path` 包含 `ag_catalog`（AGE Cypher 函数所在 schema）
2. **embedding 生成**：`p_query_embedding` 由外部 Embedding 服务生成（如 `text-embedding-3-small`），维度需与表定义一致（1536）
3. **空 query_text**：传入空字符串时，trigram 召回不生效，仅向量召回（若 embedding 非 NULL）
4. **metadata 维护**：数据写入时务必同步更新 metadata，否则 Agent 无法完成 Step 3 映射
