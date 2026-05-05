-- ============================================================================
-- OntoSQL 接口使用示例
-- ============================================================================
-- 用途：演示 11 个典型智能问数场景的 SQL 调用方式
-- 前置：已执行 sql/001_core_schema.sql 和 sql/002_knowledge_graph.sql
-- 注意：向量召回需要先写入 embedding 数据（search_objects 传入 p_query_embedding）
--       示例中仅展示了函数调用方式，实际 embedding 由外部模型生成
-- ============================================================================

SET search_path TO ontosql, ag_catalog, public;

-- ============================================================================
-- 示例 1：对象搜索（基础）
-- 场景：用户输入 "张三"，需要识别出知识图谱中的 "张三" 这个对象
-- 方法：search_objects() 向量 + trigram 多路召回
-- ============================================================================

SELECT * FROM search_objects('张三', 'ontosql_graph', p_top_k := 5);

/*
预期输出：
 vertex_id         | vertex_name | label_name | vector_score | trigram_score | combined_score
-------------------+-------------+------------+--------------+---------------+---------------
 844424930131969   | 张三        | Object     |        0.9231 |        1.0000 |         0.9539
 844424930131973   | 钱七        | Object     |        0.4210 |        0.2500 |         0.3526
*/


-- ============================================================================
-- 示例 2：属性搜索（基础）
-- 场景：用户问 "销售额多少"，需要识别出属性 "销售额"
-- 方法：search_attributes() 向量 + trigram 多路召回
-- ============================================================================

SELECT * FROM search_attributes('销售额', 'ontosql_graph', p_top_k := 5);

/*
预期输出：
 attr_name | attr_id |    description     | vector_score | trigram_score | combined_score
-----------+---------+--------------------+--------------+---------------+---------------
 销售额    |       1 | 销售产生的总金额    |        0.9512 |        1.0000 |         0.9707
 客单价    |       6 | 平均每个客户的消费额 |        0.7834 |        0.2500 |         0.5700
*/


-- ============================================================================
-- 示例 3：属性反查对象
-- 场景：识别出属性 "销售额" 后，查出哪些对象拥有这个属性
-- 方法：先 search_attributes() 拿到 attr_id，再 find_objects_by_attribute() 查归属
-- ============================================================================

-- 先找到属性 ID（取 top 1 最匹配的属性）
WITH attr_found AS (
    SELECT attr_id FROM search_attributes('销售额', 'ontosql_graph', 1)
)
-- 再反查该属性属于哪些对象
SELECT * FROM find_objects_by_attribute(
    (SELECT attr_id FROM attr_found),
    'ontosql_graph'
);

/*
预期输出：
 object_vertex_id | object_name | object_label | relation_type
-------------------+-------------+--------------+---------------
 844424930131969   | 张三        | Object       | HAS_ATTRIBUTE
 844424930131971   | 赵六        | Object       | HAS_ATTRIBUTE
 844424930131972   | 钱七        | Object       | HAS_ATTRIBUTE
 844424930131973   | 产品A       | Object       | HAS_ATTRIBUTE
 844424930131974   | 产品B       | Object       | HAS_ATTRIBUTE
 844424930131977   | 华科科技    | Object       | HAS_ATTRIBUTE
*/


-- ============================================================================
-- 示例 4：联合检索（核心接口）
-- 场景：用户输入 "张三的销售额"，一次调用同时识别对象和属性
-- 方法：search_object_attribute() 交叉组合 + 关联验证
-- ============================================================================

SELECT * FROM search_object_attribute('张三的销售额', 'ontosql_graph', p_top_k := 5);

/*
预期输出：
 object_vertex_id  | object_name | object_label | attr_name | attr_id | obj_score | attr_score | combined_score | is_verified
--------------------+-------------+--------------+-----------+---------+-----------+------------+----------------+-------------
 844424930131969    | 张三        | Object       | 销售额    |       1 |    0.9539 |     0.9707 |         0.9623 | true

说明：is_verified = true 说明张三确实具有销售额属性（在图中有 HAS_METRIC 边）
*/


-- ============================================================================
-- 示例 5：多维度区分（同义词匹配）
-- 场景：用户用不同措辞 "营业收入" 提问，应能通过向量语义召回匹配到 "销售额"
-- 说明：向量模型能捕获近义词语义（营收 ≈ 销售额），而 trigram 只能做字符级匹配
-- ============================================================================

-- "营业收入" 的向量 embedding 应更接近 "销售额" 而非 "客户数"
SELECT * FROM search_attributes('营业收入', 'ontosql_graph');

-- "上月的营收是多少" 应匹配：销售额 + 上月维度
SELECT * FROM search_object_attribute('上月的营收', 'ontosql_graph');


-- ============================================================================
-- 示例 6：错别字容错场景
-- 场景：用户输入 "销首额"（手误），需通过 trigram + 向量双路仍能匹配
-- 说明：trigram 子串匹配有一定容错能力（similarity > pg_trgm.similarity_threshold）
--       向量召回不受字符错误影响（语义 embedding 不变）
-- ============================================================================

-- trigram 对错字的相似度通常较低（~0.2），配合向量仍可召回
SELECT similarity('销售额', '销首额') AS trigram_sim;


-- ============================================================================
-- 示例 7：数据写入 — 完整新增对象流程
-- 场景：向知识图谱中添加新员工及其指标关联
-- 流程：AGE 创建顶点 → ontosql 写入 embedding → 建立图边 → 写入映射表
-- ============================================================================

/*
-- Step 1：在 AGE 图中创建新顶点 "孙八"
-- Cypher CREATE 返回新顶点的 graphid（vertex_id）
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Object {name: '孙八', type: 'employee', employee_id: 'E006'})
    RETURN id(created_vertex)
$$) AS (vertex_id agtype);

-- Step 2：写入对象 embedding（embedding 由外部模型生成）
SELECT upsert_vertex_embedding(
    p_vertex_id   := <上一步返回的 vertex_id>,
    p_graph_name  := 'ontosql_graph',
    p_label_name  := 'Object',
    p_vertex_name := '孙八',
    p_embedding   := array_fill(0.01::float, ARRAY[1536])::vector,
    p_description := '2025年新入职员工'
);

-- Step 3：写入属性 embedding（如果是新指标）
SELECT upsert_attribute_embedding(
    p_attr_name  := '客户满意度',
    p_graph_name := 'ontosql_graph',
    p_embedding  := <模型生成的向量>,
    p_aliases    := ARRAY['CSAT', '客户评分'],
    p_description := '客户对服务的综合满意度评分'
) AS new_attr_id;

-- Step 4：建立对象-属性映射（用于 search_object_attribute 的 is_verified 验证）
SELECT link_object_attribute(
    p_graph_name       := 'ontosql_graph',
    p_object_vertex_id := <vertex_id>,
    p_attr_id          := <new_attr_id>,
    p_relation_type    := 'HAS_ATTRIBUTE'
);
*/


-- ============================================================================
-- 示例 8：图验证 — 排除非法关联
-- 场景：向量匹配到了 张三+利润率，但张三实际没有利润率属性
-- 结论：is_verified = false 的结果应当被排除
-- ============================================================================

SELECT * FROM search_object_attribute('张三利润率', 'ontosql_graph');
-- 预期：张三 + 利润率 → is_verified = false（无关），应排除


-- ============================================================================
-- 示例 9：按标签过滤搜索
-- 场景：不限对象类别全局搜索，或限定某一类对象
-- 方法：p_label 参数过滤，p_label = NULL 表示不限
-- ============================================================================

-- 不限标签的全局搜索
SELECT * FROM search_objects('销售', 'ontosql_graph');

-- 仅搜索 Department 类型的对象
SELECT * FROM search_objects('销售', 'ontosql_graph', p_label := 'Department');


-- ============================================================================
-- 示例 10：批量向量近邻搜索（相似对象发现）
-- 场景：找到与 "张三" 最相似的 Top-5 对象（同级同事、同部门等）
-- 方法：直接用 HNSW 索引对 vertex_embeddings 做 <=> 余弦距离 ANN
-- ============================================================================

-- 以张三的 embedding 为锚点，找最近的其他对象
SELECT target.vertex_name,
       1 - (target.embedding <=> source.embedding) AS cosine_sim  -- 余弦距离 → 相似度
FROM vertex_embeddings source,
     vertex_embeddings target
WHERE source.vertex_name = '张三'
  AND target.vertex_name != '张三'
  AND target.graph_name = 'ontosql_graph'
ORDER BY target.embedding <=> source.embedding   -- 按余弦距离升序（越近越相似）
LIMIT 5;
-- 预期结果：同一部门（销售部）的 钱七 可能会排在前面


-- ============================================================================
-- 示例 11：通过 AGE Cypher 查询实际业务数据
-- 场景：search_object_attribute 确认 (张三, 销售额, 上月) 关联可靠后，
--       用 Cypher 图查询获取结构化路径和关联维度
-- ============================================================================

-- 查询 "张三 → 销售部" 归属路径 + "张三 → 销售额 → 上月" 指标路径
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (obj:Object {name: '张三'})
          -[:BELONGS_TO]->(dept:Department)
    MATCH (obj)
          -[:HAS_METRIC]->(m:Metric {name: '销售额'})
          -[:HAS_DIMENSION]->(d:Dimension {name: '上月'})
    RETURN obj.name, dept.name, m.name, d.name
$$) AS (obj_name agtype, dept_name agtype, metric agtype, dim agtype);

-- 预期返回：
--  obj_name | dept_name | metric  | dim
--  张三     | 销售部    | 销售额  | 上月
