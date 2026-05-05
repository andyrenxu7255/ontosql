-- ============================================================================
-- OntoSQL 核心 Schema 初始化脚本
-- ============================================================================
-- 功能：创建知识图谱向量侧表、多路召回检索函数、数据写入接口
-- 前置：已安装 postgresql 17 + pgvector 0.8.1 + apache age + pg_trgm
-- 执行：psql -U <user> -d postgres -f sql/001_core_schema.sql
-- ============================================================================

\set ONTOSQL_SCHEMA 'ontosql'

-- 1. 创建 ontosql 主 schema
-- 所有 OntoSQL 对象集中在此 schema 下，与 public/ag_catalog 隔离
CREATE SCHEMA IF NOT EXISTS :ONTOSQL_SCHEMA;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
SET search_path TO :ONTOSQL_SCHEMA, ag_catalog, public;

-- ============================================================================
-- 2. 向量注册表 — 管理所有向量侧表的元数据
-- ============================================================================
-- 用途：统一管理项目中的向量侧表，支持动态注册新表
-- 查询：SELECT * FROM vector_registry WHERE entity_type = 'vertex';

CREATE TABLE IF NOT EXISTS vector_registry (
    id              serial PRIMARY KEY,
    table_name      text NOT NULL UNIQUE,                 -- 向量表名（全局唯一）
    graph_name      text NOT NULL,                        -- 所属知识图谱名称
    entity_type     text NOT NULL CHECK (entity_type IN ('vertex', 'edge', 'attribute')),
    label_or_type   text NOT NULL,                        -- 顶点标签名或属性类型名
    vector_column   text NOT NULL DEFAULT 'embedding',    -- 向量列名
    vector_dim      int  NOT NULL,                        -- 向量维度（如 1536）
    index_type      text NOT NULL DEFAULT 'hnsw' CHECK (index_type IN ('hnsw', 'ivfflat')),
    distance_ops    text NOT NULL DEFAULT 'vector_cosine_ops',  -- 距离运算符类
    hnsw_m          int  NOT NULL DEFAULT 16,             -- HNSW 参数 m（每层邻居数）
    ivfflat_lists   int  NOT NULL DEFAULT 100,            -- IVFFlat 聚类中心数
    description     text,                                 -- 表用途说明
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- ============================================================================
-- 3. 对象向量侧表 — 存储图中顶点的 embedding
-- ============================================================================
-- 用途：为 AGE 图中的每个业务对象存储向量表示，支持语义相似度搜索
-- 关联：通过 (graph_name, vertex_id) 与 AGE 图中的顶点一一对应
-- 索引：HNSW 向量索引（语义搜索）+ GIN trigram 索引（文本匹配）+ B-tree 标签索引（过滤加速）

CREATE TABLE IF NOT EXISTS vertex_embeddings (
    id              bigserial PRIMARY KEY,
    vertex_id       bigint NOT NULL,                      -- AGE 图顶点的 graphid
    graph_name      text NOT NULL,                        -- 所属图名
    label_name      text NOT NULL,                        -- 顶点标签（Object, Department, ...）
    vertex_name     text NOT NULL,                        -- 业务名称（冗余存储，加速结果展示）
    description     text,                                 -- 描述文本（embedding 生成的源文本）
    embedding       vector(1536),                         -- OpenAI text-embedding-3-small 默认维度
    metadata        jsonb,                                -- 扩展元数据（员工ID、级别等）
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (graph_name, vertex_id)                        -- 每个图中 vertex_id 唯一
);

-- HNSW 向量索引：加速余弦相似度最近邻搜索（ANN），适合高维向量
CREATE INDEX IF NOT EXISTS idx_vertex_embeddings_hnsw
    ON vertex_embeddings USING hnsw (embedding vector_cosine_ops) WITH (m = 16);

-- GIN trigram 索引：加速模糊文本匹配（LIKE / similarity()），支持错别字容错
CREATE INDEX IF NOT EXISTS idx_vertex_embeddings_name_trgm
    ON vertex_embeddings USING gin (vertex_name gin_trgm_ops);

-- B-tree 索引：加速按图和标签过滤的查询
CREATE INDEX IF NOT EXISTS idx_vertex_embeddings_label
    ON vertex_embeddings (graph_name, label_name);

-- ============================================================================
-- 4. 属性向量侧表 — 存储属性元数据的 embedding
-- ============================================================================
-- 用途：为指标/维度等属性存储向量表示，支持语义属性识别
-- 特点：属性可独立建模为 AGE 图顶点（attr_vertex_id），也可仅在此表存在
-- 别名：支持多别名（aliases），提高同义词召回率

CREATE TABLE IF NOT EXISTS attribute_embeddings (
    id              bigserial PRIMARY KEY,
    attr_name       text NOT NULL,                        -- 属性业务名称（如 "销售额"）
    graph_name      text NOT NULL,                        -- 所属图名
    attr_vertex_id  bigint,                               -- 若属性建模为图顶点，关联其 graphid
    aliases         text[],                               -- 别名数组（如 ARRAY['营收','revenue']）
    description     text,                                 -- 语义描述（embedding 生成的源文本）
    data_type       text,                                 -- 数据类型（numeric, integer, text, ...）
    embedding       vector(1536),                         -- 向量表示
    metadata        jsonb,                                -- 扩展元数据
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (graph_name, attr_name)                        -- 同图同属性名唯一
);

CREATE INDEX IF NOT EXISTS idx_attribute_embeddings_hnsw
    ON attribute_embeddings USING hnsw (embedding vector_cosine_ops) WITH (m = 16);

CREATE INDEX IF NOT EXISTS idx_attribute_embeddings_name_trgm
    ON attribute_embeddings USING gin (attr_name gin_trgm_ops);

-- ============================================================================
-- 5. 对象-属性关联表 — 记录对象拥有的属性
-- ============================================================================
-- 用途：物化对象与属性的关联关系，加速反查（find_objects_by_attribute）和关联验证（is_verified）
-- 来源：可从 AGE 图中自动派生（MATCH (obj)-[:HAS_METRIC]->(metric)），也可手动维护
-- 置信度：confidence 字段支持概率化的关联（如 NLP 推断的关联可能 < 1.0）

CREATE TABLE IF NOT EXISTS object_attribute_mapping (
    id              bigserial PRIMARY KEY,
    graph_name      text NOT NULL,
    object_vertex_id bigint NOT NULL,                     -- 对象在 AGE 图中的 vertex_id
    object_label    text NOT NULL,                        -- 对象标签类型
    attr_id         int NOT NULL REFERENCES attribute_embeddings(id),  -- 属性 ID（外键）
    relation_type   text NOT NULL DEFAULT 'HAS_ATTRIBUTE', -- 关系类型
    confidence      float NOT NULL DEFAULT 1.0,           -- 关联置信度 [0, 1]
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (graph_name, object_vertex_id, attr_id)        -- 同一对象-属性对不重复
);

-- 按对象查询其全部属性
CREATE INDEX IF NOT EXISTS idx_oam_object
    ON object_attribute_mapping (graph_name, object_vertex_id);
-- 按属性反查拥有该属性的全部对象
CREATE INDEX IF NOT EXISTS idx_oam_attr
    ON object_attribute_mapping (attr_id);

-- ============================================================================
-- 6. 注册初始化记录
-- ============================================================================

INSERT INTO vector_registry (table_name, graph_name, entity_type, label_or_type, vector_column, vector_dim, index_type, distance_ops)
VALUES
    ('vertex_embeddings',   'default', 'vertex',    'ALL',    'embedding', 1536, 'hnsw', 'vector_cosine_ops'),
    ('attribute_embeddings','default', 'attribute', 'ALL',    'embedding', 1536, 'hnsw', 'vector_cosine_ops')
ON CONFLICT (table_name) DO NOTHING;

-- ============================================================================
-- 7. 核心检索函数
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7.1 search_objects — 对象识别（多路召回：向量 + trigram）
-- ----------------------------------------------------------------------------
-- 功能：输入 NL 查询文本，返回匹配的图对象及其相似度分数
-- 算法：
--   1. 向量召回：查询 embedding 与 vertex_embeddings 做 ANN（HNSW）搜索
--   2. trigram 召回：查询文本与 vertex_name 做 pg_trgm similarity() 匹配
--   3. 合并去重：UNION ALL + GROUP BY + 加权综合分（0.6×向量 + 0.4×trigram）
-- 注意：
--   - p_query_embedding 为 NULL 时，仅使用 trigram 召回
--   - 查询文本为空时，trigram 召回不生效，返回空结果
--   - 扩容因子 p_top_k × 3 保证合并后有足够候选
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION search_objects(
    query_text          text,                   -- NL 查询文本（如 "张三"）
    p_graph_name        text DEFAULT 'default', -- 目标图名
    p_label             text DEFAULT NULL,      -- 可选标签过滤（如 'Object'）
    p_top_k             int  DEFAULT 10,        -- 返回结果数量
    p_query_embedding   vector DEFAULT NULL     -- 查询文本的 embedding 向量（由外部模型生成）
) RETURNS TABLE(
    vertex_id       bigint,      -- 图顶点 ID
    vertex_name     text,        -- 对象名称
    label_name      text,        -- 对象标签
    vector_score    float,       -- 向量余弦相似度 [0, 1]
    trigram_score   float,       -- trigram 文本相似度 [0, 1]
    combined_score  float        -- 综合加权分数 [0, 1]
) LANGUAGE sql STABLE PARALLEL SAFE AS $$
    WITH vec_scores AS (
        SELECT ve.vertex_id, ve.vertex_name, ve.label_name,
               1 - (ve.embedding <=> p_query_embedding) AS score  -- <=> 是余弦距离运算符
        FROM vertex_embeddings ve
        WHERE ve.graph_name = p_graph_name
          AND (p_label IS NULL OR ve.label_name = p_label)
          AND p_query_embedding IS NOT NULL
        ORDER BY ve.embedding <=> p_query_embedding
        LIMIT p_top_k * 3    -- 扩大候选集，为合并去重留余量
    ),
    trigram_scores AS (
        SELECT ve.vertex_id, ve.vertex_name, ve.label_name,
               similarity(ve.vertex_name, query_text) AS score   -- pg_trgm 文本相似度
        FROM vertex_embeddings ve
        WHERE ve.graph_name = p_graph_name
          AND (p_label IS NULL OR ve.label_name = p_label)
          AND ve.vertex_name % query_text          -- % 运算符 = similarity > 阈值
          AND length(query_text) > 0
        ORDER BY similarity(ve.vertex_name, query_text) DESC
        LIMIT p_top_k * 3
    ),
    merged AS (
        SELECT vertex_id, vertex_name, label_name, score AS vector_score, 0::float AS trigram_score,
               CASE WHEN p_query_embedding IS NOT NULL THEN score * 0.6 ELSE 0 END AS combined_score
        FROM vec_scores
        UNION ALL
        SELECT vertex_id, vertex_name, label_name, 0::float AS vector_score, score AS trigram_score,
               CASE WHEN p_query_embedding IS NULL THEN score ELSE score * 0.4 END AS combined_score
        FROM trigram_scores
    )
    SELECT vertex_id, vertex_name, label_name,
           MAX(vector_score) AS vector_score,        -- 同一对象取最高向量分
           MAX(trigram_score) AS trigram_score,      -- 同一对象取最高 trigram 分
           MAX(combined_score) AS combined_score     -- 同一对象取最高综合分
    FROM merged
    GROUP BY vertex_id, vertex_name, label_name
    ORDER BY combined_score DESC
    LIMIT p_top_k;
$$;

-- ----------------------------------------------------------------------------
-- 7.2 search_attributes — 属性识别（多路召回：向量 + trigram）
-- ----------------------------------------------------------------------------
-- 功能：输入 NL 查询文本，返回匹配的属性及其相似度
-- 算法：与 search_objects 相同，对 attribute_embeddings 做向量 + trigram 双路召回
-- 返回：attr_id 可用于后续 find_objects_by_attribute() 反查对象
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION search_attributes(
    query_text          text,                   -- NL 查询文本
    p_graph_name        text DEFAULT 'default', -- 目标图名
    p_top_k             int  DEFAULT 10,        -- 返回结果数量
    p_query_embedding   vector DEFAULT NULL     -- 查询文本的 embedding 向量
) RETURNS TABLE(
    attr_name       text,        -- 属性名称
    attr_id         int,         -- 属性主键 ID
    description     text,        -- 属性语义描述
    vector_score    float,       -- 向量余弦相似度
    trigram_score   float,       -- trigram 文本相似度
    combined_score  float        -- 综合加权分数
) LANGUAGE sql STABLE PARALLEL SAFE AS $$
    WITH vec_scores AS (
        SELECT ae.attr_name, ae.id AS attr_id, ae.description,
               1 - (ae.embedding <=> p_query_embedding) AS score
        FROM attribute_embeddings ae
        WHERE ae.graph_name = p_graph_name
          AND p_query_embedding IS NOT NULL
        ORDER BY ae.embedding <=> p_query_embedding
        LIMIT p_top_k * 3
    ),
    trigram_scores AS (
        SELECT ae.attr_name, ae.id AS attr_id, ae.description,
               similarity(ae.attr_name, query_text) AS score
        FROM attribute_embeddings ae
        WHERE ae.graph_name = p_graph_name
          AND ae.attr_name % query_text
          AND length(query_text) > 0
        ORDER BY similarity(ae.attr_name, query_text) DESC
        LIMIT p_top_k * 3
    ),
    merged AS (
        SELECT attr_name, attr_id, description, score AS vector_score, 0::float AS trigram_score,
               CASE WHEN p_query_embedding IS NOT NULL THEN score * 0.6 ELSE 0 END AS combined_score
        FROM vec_scores
        UNION ALL
        SELECT attr_name, attr_id, description, 0::float AS vector_score, score AS trigram_score,
               CASE WHEN p_query_embedding IS NULL THEN score ELSE score * 0.4 END AS combined_score
        FROM trigram_scores
    )
    SELECT attr_name, attr_id, description,
           MAX(vector_score) AS vector_score,
           MAX(trigram_score) AS trigram_score,
           MAX(combined_score) AS combined_score
    FROM merged
    GROUP BY attr_name, attr_id, description
    ORDER BY combined_score DESC
    LIMIT p_top_k;
$$;

-- ----------------------------------------------------------------------------
-- 7.3 find_objects_by_attribute — 属性反查对象
-- ----------------------------------------------------------------------------
-- 功能：已知属性的 attr_id，查出所有拥有该属性的业务对象
-- 算法：从 object_attribute_mapping 物化表查询，LEFT JOIN vertex_embeddings 补全名称
-- 用途：属性识别后，需要知道"这个指标属于哪些对象"
-- 注意：使用 LEFT JOIN + COALESCE，即使 vertex_embeddings 中无记录也能返回基本信息
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION find_objects_by_attribute(
    p_attr_id       int,                    -- 属性 ID（来自 search_attributes 结果）
    p_graph_name    text DEFAULT 'default', -- 目标图名
    p_top_k         int  DEFAULT 20         -- 返回结果数量上限
) RETURNS TABLE(
    object_vertex_id bigint,     -- 对象顶点 ID
    object_name      text,       -- 对象名称
    object_label     text,       -- 对象标签类型
    relation_type    text        -- 关联关系类型（HAS_ATTRIBUTE 等）
) LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT oam.object_vertex_id,
           COALESCE(ve.vertex_name, 'unknown')::text AS object_name,
           COALESCE(ve.label_name, oam.object_label)::text AS object_label,
           oam.relation_type
    FROM object_attribute_mapping oam
    LEFT JOIN vertex_embeddings ve                  -- LEFT JOIN 保证映射表有数据就能返回
        ON ve.vertex_id = oam.object_vertex_id
       AND ve.graph_name = oam.graph_name
    WHERE oam.graph_name = p_graph_name
      AND oam.attr_id = p_attr_id
    ORDER BY ve.vertex_name
    LIMIT p_top_k;
$$;

-- ----------------------------------------------------------------------------
-- 7.4 search_object_attribute — 联合检索（核心接口）
-- ----------------------------------------------------------------------------
-- 功能：一次调用同时识别 NL 查询中的对象和属性，并验证它们之间是否存在关联（is_verified）
-- 算法：
--   1. 调用 search_objects() 获取候选对象（2×扩容）
--   2. 调用 search_attributes() 获取候选属性（2×扩容）
--   3. CROSS JOIN 生成候选对（笛卡尔积）
--   4. 查询 object_attribute_mapping 判断每个对象-属性对是否有真实关联
--   5. 综合分 = 0.5×对象分 + 0.5×属性分
-- 优势：一次 SQL 调用完成对象识别 + 属性识别 + 关联验证，减少网络往返
-- 注意：CROSS JOIN 可能产生 O(obj_count × attr_count) 候选对，需要合理控制 p_top_k
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION search_object_attribute(
    query_text          text,                   -- NL 查询文本
    p_graph_name        text DEFAULT 'default', -- 目标图名
    p_top_k             int  DEFAULT 10,        -- 返回结果数量
    p_query_embedding   vector DEFAULT NULL     -- 查询文本的 embedding 向量
) RETURNS TABLE(
    object_vertex_id bigint,     -- 对象顶点 ID
    object_name      text,       -- 对象名称
    object_label     text,       -- 对象标签
    attr_name        text,       -- 属性名称
    attr_id          int,        -- 属性 ID
    obj_score        float,      -- 对象匹配分（search_objects 的综合分）
    attr_score       float,      -- 属性匹配分（search_attributes 的综合分）
    combined_score   float,      -- 联合综合分 [0, 1]
    is_verified      boolean     -- 图结构是否确认此对象-属性关联（true = 可靠，false = 需排除）
) LANGUAGE sql STABLE PARALLEL SAFE AS $$
    WITH objs AS (
        SELECT * FROM search_objects(query_text, p_graph_name, NULL, p_top_k * 2, p_query_embedding)
    ),
    attrs AS (
        SELECT * FROM search_attributes(query_text, p_graph_name, p_top_k * 2, p_query_embedding)
    )
    SELECT
        o.vertex_id, o.vertex_name, o.label_name,
        a.attr_name, a.attr_id,
        o.combined_score AS obj_score,
        a.combined_score  AS attr_score,
        (o.combined_score * 0.5 + a.combined_score * 0.5) AS combined_score,
        EXISTS (
            SELECT 1 FROM object_attribute_mapping oam
            WHERE oam.graph_name = p_graph_name
              AND oam.object_vertex_id = o.vertex_id
              AND oam.attr_id = a.attr_id
        ) AS is_verified                     -- EXISTS 子查询检查物化关联表
    FROM objs o
    CROSS JOIN attrs a                       -- 笛卡尔积生成所有候选对
    ORDER BY combined_score DESC
    LIMIT p_top_k;
$$;

-- ============================================================================
-- 8. 数据写入接口
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 8.1 upsert_vertex_embedding — 插入或更新顶点 embedding
-- ----------------------------------------------------------------------------
-- 功能：向 vertex_embeddings 表写入/更新一条对象向量记录
-- 行为：INSERT ... ON CONFLICT (graph_name, vertex_id) DO UPDATE（upsert）
-- 注意：更新时 description 使用 COALESCE 保留旧值（若新值为 NULL）
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION upsert_vertex_embedding(
    p_vertex_id     bigint,                -- AGE 图顶点 ID（graphid）
    p_graph_name    text,                  -- 所属图名
    p_label_name    text,                  -- 顶点标签
    p_vertex_name   text,                  -- 业务名称（搜索展示用）
    p_embedding     vector,                -- embedding 向量（1536 维）
    p_description   text DEFAULT NULL,     -- 对象描述
    p_metadata      jsonb DEFAULT '{}'::jsonb  -- 扩展元数据（JSON 格式）
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO vertex_embeddings
        (vertex_id, graph_name, label_name, vertex_name, description, embedding, metadata)
    VALUES
        (p_vertex_id, p_graph_name, p_label_name, p_vertex_name, p_description, p_embedding, p_metadata)
    ON CONFLICT (graph_name, vertex_id) DO UPDATE SET
        vertex_name = EXCLUDED.vertex_name,
        label_name  = EXCLUDED.label_name,
        description = COALESCE(EXCLUDED.description, vertex_embeddings.description),  -- 新值优先，NULL 保留旧值
        embedding   = EXCLUDED.embedding,
        metadata    = EXCLUDED.metadata,
        updated_at  = now();
END;
$$;

-- ----------------------------------------------------------------------------
-- 8.2 upsert_attribute_embedding — 插入或更新属性 embedding
-- ----------------------------------------------------------------------------
-- 功能：向 attribute_embeddings 表写入/更新一条属性向量记录
-- 返回：attr_id（便于后续调用 link_object_attribute() 建立关联）
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION upsert_attribute_embedding(
    p_attr_name     text,                  -- 属性名称（如 "销售额"）
    p_graph_name    text,                  -- 所属图名
    p_embedding     vector,                -- embedding 向量
    p_attr_vertex_id bigint DEFAULT NULL,  -- 若属性建模为图顶点，关联其 graphid
    p_aliases       text[] DEFAULT NULL,   -- 别名数组（ARRAY['营收','revenue']）
    p_description   text DEFAULT NULL,     -- 属性语义描述
    p_data_type     text DEFAULT NULL      -- 数据类型（numeric/text/integer）
) RETURNS int LANGUAGE plpgsql AS $$       -- 返回 attr_id
DECLARE
    v_attr_id int;
BEGIN
    INSERT INTO attribute_embeddings
        (attr_name, graph_name, attr_vertex_id, aliases, description, data_type, embedding)
    VALUES
        (p_attr_name, p_graph_name, p_attr_vertex_id, p_aliases, p_description, p_data_type, p_embedding)
    ON CONFLICT (graph_name, attr_name) DO UPDATE SET
        attr_vertex_id = COALESCE(EXCLUDED.attr_vertex_id, attribute_embeddings.attr_vertex_id),
        aliases        = COALESCE(EXCLUDED.aliases, attribute_embeddings.aliases),
        description    = COALESCE(EXCLUDED.description, attribute_embeddings.description),
        data_type      = COALESCE(EXCLUDED.data_type, attribute_embeddings.data_type),
        embedding      = EXCLUDED.embedding,
        updated_at     = now()
    RETURNING id INTO v_attr_id;           -- 返回 INSERT 或 UPDATE 后的 id
    RETURN v_attr_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- 8.3 link_object_attribute — 建立对象-属性关联
-- ----------------------------------------------------------------------------
-- 功能：将对象（vertex_id）与属性（attr_id）建立关联，写入 object_attribute_mapping 表
-- 行为：ON CONFLICT DO UPDATE（支持重复调用，幂等）
-- 安全：
--   1. 校验 vertex_id 在 vertex_embeddings 中存在（防止关联不存在的对象）
--   2. 校验 attr_id 在 attribute_embeddings 中存在（防止关联不存在的属性）
-- 异常：校验失败时抛出 EXCEPTION，调用方应捕获处理
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION link_object_attribute(
    p_graph_name        text,                          -- 图名
    p_object_vertex_id  bigint,                       -- 对象顶点 ID
    p_attr_id           int,                          -- 属性 ID
    p_relation_type     text DEFAULT 'HAS_ATTRIBUTE', -- 关联关系类型
    p_confidence        float DEFAULT 1.0             -- 置信度 [0, 1]（NLP 推断关联可 < 1.0）
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_label text;
BEGIN
    -- 校验：vertex_id 必须在 vertex_embeddings 中存在
    SELECT label_name INTO v_label
    FROM vertex_embeddings
    WHERE graph_name = p_graph_name AND vertex_id = p_object_vertex_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'vertex_id=% not found in vertex_embeddings for graph=%',
            p_object_vertex_id, p_graph_name;
    END IF;

    -- 校验：attr_id 必须在 attribute_embeddings 中存在
    IF NOT EXISTS (SELECT 1 FROM attribute_embeddings WHERE id = p_attr_id) THEN
        RAISE EXCEPTION 'attr_id=% not found in attribute_embeddings', p_attr_id;
    END IF;

    -- 写入：重复插入时更新 relation_type 和 confidence
    INSERT INTO object_attribute_mapping
        (graph_name, object_vertex_id, object_label, attr_id, relation_type, confidence)
    VALUES
        (p_graph_name, p_object_vertex_id, v_label, p_attr_id, p_relation_type, p_confidence)
    ON CONFLICT (graph_name, object_vertex_id, attr_id) DO UPDATE SET
        relation_type = EXCLUDED.relation_type,
        confidence    = EXCLUDED.confidence;
END;
$$;

-- ============================================================================
-- 初始化完成
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'OntoSQL core schema initialized successfully';
END;
$$;
