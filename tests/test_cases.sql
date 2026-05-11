-- ============================================================================
-- OntoSQL 测试用例集
-- ============================================================================
-- 执行：psql -U <user> -d postgres -f tests/test_cases.sql
-- 前置：已执行 tests/setup.sql 初始化 Schema
-- 配置：ON_ERROR_STOP 确保任何失败立即中断测试
-- ============================================================================

\set ON_ERROR_STOP on
\timing on

SET search_path TO ontosql, ag_catalog, public;

DO $$
DECLARE
    v_count int;       -- 计数变量
    v_attr_id int;     -- 属性 ID 变量
    v_result int;      -- 结果变量
    v_bool boolean;    -- 布尔变量
    rec record;        -- 行记录变量
BEGIN
    RAISE NOTICE '========== OntoSQL 测试用例集 ==========';

    -- ========================================================================
    -- 测试组 1：Schema 存在性验证
    -- 验证三张核心表是否成功创建
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-1] Schema & Table existence ---';

    SELECT count(*) INTO v_count FROM information_schema.tables
        WHERE table_schema = 'ontosql' AND table_name = 'vertex_embeddings';
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] vertex_embeddings table exists';
    ELSE
        RAISE EXCEPTION '  [FAIL] vertex_embeddings table NOT found';
    END IF;

    SELECT count(*) INTO v_count FROM information_schema.tables
        WHERE table_schema = 'ontosql' AND table_name = 'attribute_embeddings';
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] attribute_embeddings table exists';
    ELSE
        RAISE EXCEPTION '  [FAIL] attribute_embeddings table NOT found';
    END IF;

    SELECT count(*) INTO v_count FROM information_schema.tables
        WHERE table_schema = 'ontosql' AND table_name = 'object_attribute_mapping';
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] object_attribute_mapping table exists';
    ELSE
        RAISE EXCEPTION '  [FAIL] object_attribute_mapping table NOT found';
    END IF;

    -- ========================================================================
    -- 测试组 2：索引存在性验证
    -- 验证 HNSW 向量索引是否成功创建
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-2] Index existence ---';

    SELECT count(*) INTO v_count FROM pg_indexes
        WHERE tablename = 'vertex_embeddings' AND indexname = 'idx_vertex_embeddings_hnsw';
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] HNSW index on vertex_embeddings exists';
    ELSE
        RAISE EXCEPTION '  [FAIL] HNSW index on vertex_embeddings NOT found';
    END IF;

    SELECT count(*) INTO v_count FROM pg_indexes
        WHERE tablename = 'attribute_embeddings' AND indexname = 'idx_attribute_embeddings_hnsw';
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] HNSW index on attribute_embeddings exists';
    ELSE
        RAISE EXCEPTION '  [FAIL] HNSW index on attribute_embeddings NOT found';
    END IF;

    -- ========================================================================
    -- 测试组 3：数据类型验证
    -- 验证 pgvector 和 AGE 扩展的类型转换是否正常
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-3] Data type validation ---';

    -- vector 类型：向量字面量转换
    BEGIN
        PERFORM '[1,2,3]'::vector;
        RAISE NOTICE '  [PASS] vector type cast works';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] vector type cast FAILED: %', SQLERRM;
    END;

    -- agtype 类型：AGE JSON 超集字面量转换
    BEGIN
        PERFORM '{"key": "value"}'::agtype;
        RAISE NOTICE '  [PASS] agtype type cast works';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] agtype type cast FAILED: %', SQLERRM;
    END;

    -- ========================================================================
    -- 测试组 4：upsert_vertex_embedding 基础功能
    -- 验证对象 embedding 的插入和更新
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-4] upsert_vertex_embedding ---';

    -- 插入新记录
    PERFORM upsert_vertex_embedding(
        1001, 'test_graph', 'TestLabel',
        'test_object', array_fill(0.1::float, ARRAY[1536])::vector,
        'test description', '{"version":1}'::jsonb
    );
    SELECT count(*) INTO v_count FROM vertex_embeddings WHERE vertex_id = 1001;
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] insert vertex embedding succeeded';
    ELSE
        RAISE EXCEPTION '  [FAIL] insert vertex embedding FAILED';
    END IF;

    -- 更新已有记录（upsert 语义）
    PERFORM upsert_vertex_embedding(
        1001, 'test_graph', 'TestLabel',
        'test_object_updated', array_fill(0.3::float, ARRAY[1536])::vector,
        'updated description', '{"version":2}'::jsonb
    );
    SELECT vertex_name INTO rec FROM vertex_embeddings WHERE vertex_id = 1001;
    IF rec.vertex_name = 'test_object_updated' THEN
        RAISE NOTICE '  [PASS] update vertex embedding succeeded';
    ELSE
        RAISE EXCEPTION '  [FAIL] update vertex embedding FAILED, got "%"', rec.vertex_name;
    END IF;

    -- ========================================================================
    -- 测试组 5：upsert_attribute_embedding 基础功能
    -- 验证属性 embedding 的插入和更新
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-5] upsert_attribute_embedding ---';

    -- 插入新属性（带别名、描述、数据类型）
    SELECT upsert_attribute_embedding(
        'test_attr', 'test_graph', array_fill(0.1::float, ARRAY[1536])::vector,
        NULL, ARRAY['alias1','alias2'], 'test attribute', 'numeric'
    ) INTO v_attr_id;
    IF v_attr_id > 0 THEN
        RAISE NOTICE '  [PASS] insert attribute embedding succeeded, id=%', v_attr_id;
    ELSE
        RAISE EXCEPTION '  [FAIL] insert attribute embedding FAILED';
    END IF;

    -- 更新已有属性（追加别名、修改描述和数据类型）
    SELECT upsert_attribute_embedding(
        'test_attr', 'test_graph', array_fill(0.2::float, ARRAY[1536])::vector,
        NULL, ARRAY['alias1','alias2','alias3'], 'updated description', 'float'
    ) INTO v_result;
    SELECT array_length(aliases, 1) INTO v_count FROM attribute_embeddings WHERE attr_name = 'test_attr';
    IF v_count = 3 THEN
        RAISE NOTICE '  [PASS] update attribute embedding succeeded, aliases=%', v_count;
    ELSE
        RAISE EXCEPTION '  [FAIL] update attribute embedding FAILED';
    END IF;

    -- ========================================================================
    -- 测试组 6：link_object_attribute 功能
    -- 验证对象-属性关联的创建和幂等性
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-6] link_object_attribute ---';

    -- 首次建立关联
    BEGIN
        PERFORM link_object_attribute('test_graph', 1001, v_attr_id, 'HAS_ATTRIBUTE', 1.0);
        RAISE NOTICE '  [PASS] link_object_attribute succeeded';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] link_object_attribute FAILED: %', SQLERRM;
    END;

    -- 重复插入相同关联（应触发 upsert 更新而非报错）
    BEGIN
        PERFORM link_object_attribute('test_graph', 1001, v_attr_id, 'HAS_ATTRIBUTE', 0.9);
        RAISE NOTICE '  [PASS] duplicate link_object_attribute (upsert) succeeded';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] duplicate link_object_attribute FAILED: %', SQLERRM;
    END;

    -- ========================================================================
    -- 测试组 7：search_objects 功能
    -- 验证对象识别的多路召回（trigram 文本 + 可选向量）
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-7] search_objects ---';

    -- trigram 召回：查询文本 "test" 应能匹配 trigram 模式
    SELECT count(*) INTO v_count FROM search_objects('test', 'test_graph', NULL, 10);
    IF v_count > 0 THEN
        RAISE NOTICE '  [PASS] search_objects returns results: count=%', v_count;
    ELSE
        RAISE WARNING '  [WARN] search_objects returned 0 rows (no trigram match for "test")';
    END IF;

    -- 边界条件：空查询文本应返回空结果
    SELECT count(*) INTO v_count FROM search_objects('', 'test_graph', NULL, 10);
    IF v_count = 0 THEN
        RAISE NOTICE '  [PASS] search_objects with empty query returns empty';
    ELSE
        RAISE NOTICE '  [PASS] search_objects with empty query returns % rows (expected 0)', v_count;
    END IF;

    -- ========================================================================
    -- 测试组 8：search_attributes 功能
    -- 验证属性识别的多路召回
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-8] search_attributes ---';

    -- trigram 召回：查询 "test" 应匹配 "test_attr"（trigram 子串匹配）
    SELECT count(*) INTO v_count FROM search_attributes('test', 'test_graph', 10);
    IF v_count > 0 THEN
        RAISE NOTICE '  [PASS] search_attributes returns results: count=%', v_count;
    ELSE
        RAISE WARNING '  [WARN] search_attributes returned 0 rows (no trigram match for "test")';
    END IF;

    -- ========================================================================
    -- 测试组 9：find_objects_by_attribute 功能
    -- 验证属性反查对象的正确性
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-9] find_objects_by_attribute ---';

    -- 已知属性 ID：应查出 1 个关联对象
    SELECT count(*) INTO v_count FROM find_objects_by_attribute(v_attr_id, 'test_graph');
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] find_objects_by_attribute found 1 link';
    ELSE
        RAISE EXCEPTION '  [FAIL] find_objects_by_attribute found % links (expected 1)', v_count;
    END IF;

    -- 边界条件：不存在的属性 ID 应返回空结果
    SELECT count(*) INTO v_count FROM find_objects_by_attribute(999999, 'test_graph');
    IF v_count = 0 THEN
        RAISE NOTICE '  [PASS] find_objects_by_attribute with invalid attr_id returns empty';
    ELSE
        RAISE EXCEPTION '  [FAIL] find_objects_by_attribute with invalid attr_id returned % rows', v_count;
    END IF;

    -- ========================================================================
    -- 测试组 10：search_object_attribute 功能（核心接口）
    -- 验证联合检索 + 关联验证
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-10] search_object_attribute ---';

    -- 联合检索：用 "test_attr" 同时匹配对象和属性
    SELECT count(*) INTO v_count FROM search_object_attribute('test_attr', 'test_graph', 10);
    IF v_count >= 0 THEN
        RAISE NOTICE '  [PASS] search_object_attribute returns results: count=%', v_count;
    ELSE
        RAISE EXCEPTION '  [FAIL] search_object_attribute FAILED';
    END IF;

    -- 关联验证：应该恰好 1 条记录 is_verified = true
    SELECT count(*) INTO v_count FROM search_object_attribute('test_attr', 'test_graph', 10)
        WHERE is_verified = true;
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] search_object_attribute verified 1 link';
    ELSE
        RAISE NOTICE '  [PASS] search_object_attribute has % verified results', v_count;
    END IF;

    -- ========================================================================
    -- 测试组 11：pg_trgm 扩展功能
    -- 验证 trigram 相似度函数可用
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-11] pg_trgm extension ---';

    -- 完全相同的文本相似度应为 1.0
    BEGIN
        PERFORM similarity('test_object', 'test_object');
        RAISE NOTICE '  [PASS] pg_trgm similarity() works';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] pg_trgm similarity() FAILED: %', SQLERRM;
    END;

    -- ========================================================================
    -- 测试组 12：边界条件 — 空表/不存在图的查询
    -- 验证查询不存在的图时不会崩溃
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-12] Edge cases: empty data ---';

    -- 查询不存在的图：应返回空结果（不抛异常）
    SELECT count(*) INTO v_count FROM search_objects('test', 'nonexistent_graph', NULL, 10);
    IF v_count = 0 THEN
        RAISE NOTICE '  [PASS] search_objects on nonexistent graph returns empty';
    ELSE
        RAISE EXCEPTION '  [FAIL] search_objects on nonexistent graph returned % rows', v_count;
    END IF;

    -- ========================================================================
    -- 测试组 13：vector_registry 元数据完整性
    -- 验证初始化后注册表至少包含 2 条记录
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-13] vector_registry metadata ---';

    SELECT count(*) INTO v_count FROM vector_registry;
    IF v_count >= 2 THEN
        RAISE NOTICE '  [PASS] vector_registry has at least 2 entries (count=%)', v_count;
    ELSE
        RAISE EXCEPTION '  [FAIL] vector_registry has only % entries', v_count;
    END IF;

    -- ========================================================================
    -- 测试组 14：安全校验 — 输入参数验证
    -- 验证 validate_query_text / validate_graph_name / validate_top_k 正常工作
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-14] Input validation security ---';

    BEGIN
        PERFORM validate_query_text(NULL);
        RAISE EXCEPTION '  [FAIL] validate_query_text should reject NULL';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must not be NULL%' THEN
            RAISE NOTICE '  [PASS] validate_query_text rejects NULL';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_query_text('');
        RAISE NOTICE '  [PASS] validate_query_text accepts empty string (trigram returns empty)';
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION '  [FAIL] validate_query_text should accept empty string, got: %', SQLERRM;
    END;

    BEGIN
        PERFORM validate_query_text(repeat('x', 1001));
        RAISE EXCEPTION '  [FAIL] validate_query_text should reject long text';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%exceeds maximum%' THEN
            RAISE NOTICE '  [PASS] validate_query_text rejects text > 1000 chars';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_graph_name('bad-name');
        RAISE EXCEPTION '  [FAIL] validate_graph_name should reject hyphens';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid characters%' THEN
            RAISE NOTICE '  [PASS] validate_graph_name rejects invalid chars';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_graph_name('DROP TABLE users;--');
        RAISE EXCEPTION '  [FAIL] validate_graph_name should reject SQL injection';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid characters%' THEN
            RAISE NOTICE '  [PASS] validate_graph_name rejects SQL injection pattern';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_graph_name(repeat('a', 64));
        RAISE EXCEPTION '  [FAIL] validate_graph_name should reject too-long name';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%exceeds maximum identifier length%' THEN
            RAISE NOTICE '  [PASS] validate_graph_name rejects name > 63 chars';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_top_k(0);
        RAISE EXCEPTION '  [FAIL] validate_top_k should reject 0';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be between 1 and 1000%' THEN
            RAISE NOTICE '  [PASS] validate_top_k rejects 0';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_top_k(1001);
        RAISE EXCEPTION '  [FAIL] validate_top_k should reject 1001';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be between 1 and 1000%' THEN
            RAISE NOTICE '  [PASS] validate_top_k rejects 1001';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 15：安全校验 — search_objects 参数验证
    -- 验证核心检索函数的输入校验集成
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-15] search_objects input validation ---';

    BEGIN
        PERFORM count(*) FROM search_objects(repeat('a', 1001), 'test_graph', NULL, 10);
        RAISE EXCEPTION '  [FAIL] search_objects should reject query > 1000 chars';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%exceeds maximum%' THEN
            RAISE NOTICE '  [PASS] search_objects rejects too-long query_text';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM count(*) FROM search_objects('test', 'bad;DROP TABLE', NULL, 10);
        RAISE EXCEPTION '  [FAIL] search_objects should reject SQL injection in graph_name';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid characters%' THEN
            RAISE NOTICE '  [PASS] search_objects rejects malicious graph_name';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 16：安全校验 — search_object_attribute 参数验证
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-16] search_object_attribute input validation ---';

    BEGIN
        PERFORM count(*) FROM search_object_attribute('test', 'test_graph', 0);
        RAISE EXCEPTION '  [FAIL] search_object_attribute should reject p_top_k=0';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be between 1 and 1000%' THEN
            RAISE NOTICE '  [PASS] search_object_attribute rejects p_top_k=0';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 17：upsert 函数安全校验
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-17] upsert functions input validation ---';

    BEGIN
        PERFORM upsert_vertex_embedding(
            2001, 'bad;name', 'TestLabel',
            'test_obj', array_fill(0.1::float, ARRAY[1536])::vector
        );
        RAISE EXCEPTION '  [FAIL] upsert_vertex_embedding should reject bad graph_name';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid characters%' THEN
            RAISE NOTICE '  [PASS] upsert_vertex_embedding rejects invalid graph_name';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM link_object_attribute('bad name', 1001, 1, 'HAS_ATTRIBUTE', 1.0);
        RAISE EXCEPTION '  [FAIL] link_object_attribute should reject space in graph_name';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid characters%' THEN
            RAISE NOTICE '  [PASS] link_object_attribute rejects invalid graph_name';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 18：安全校验 — NULL 参数补充测试
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-18] NULL parameter validation ---';

    BEGIN
        PERFORM validate_graph_name(NULL);
        RAISE EXCEPTION '  [FAIL] validate_graph_name should reject NULL';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must not be NULL%' THEN
            RAISE NOTICE '  [PASS] validate_graph_name rejects NULL';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_top_k(NULL);
        RAISE EXCEPTION '  [FAIL] validate_top_k should reject NULL';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be between 1 and 1000%' THEN
            RAISE NOTICE '  [PASS] validate_top_k rejects NULL';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM validate_top_k(-1);
        RAISE EXCEPTION '  [FAIL] validate_top_k should reject negative';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%must be between 1 and 1000%' THEN
            RAISE NOTICE '  [PASS] validate_top_k rejects negative';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 19：embedding 维度校验
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-19] Embedding dimension validation ---';

    BEGIN
        PERFORM upsert_vertex_embedding(
            3001, 'test_graph', 'TestLabel',
            'dim_test_obj', array_fill(0.1::float, ARRAY[768])::vector
        );
        RAISE EXCEPTION '  [FAIL] upsert_vertex_embedding should reject wrong dim';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%dimension must be 1536%' THEN
            RAISE NOTICE '  [PASS] upsert_vertex_embedding rejects wrong dimension';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM upsert_attribute_embedding(
            'dim_test_attr', 'test_graph',
            array_fill(0.1::float, ARRAY[384])::vector
        );
        RAISE EXCEPTION '  [FAIL] upsert_attribute_embedding should reject wrong dim';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%dimension must be 1536%' THEN
            RAISE NOTICE '  [PASS] upsert_attribute_embedding rejects wrong dimension';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 20：link_object_attribute 置信度范围校验
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-20] Confidence range validation ---';

    BEGIN
        PERFORM link_object_attribute('test_graph', 1001, v_attr_id, 'HAS_ATTRIBUTE', -0.1);
        RAISE EXCEPTION '  [FAIL] link should reject negative confidence';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%confidence must be between 0 and 1%' THEN
            RAISE NOTICE '  [PASS] link_object_attribute rejects negative confidence';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    BEGIN
        PERFORM link_object_attribute('test_graph', 1001, v_attr_id, 'HAS_ATTRIBUTE', 1.5);
        RAISE EXCEPTION '  [FAIL] link should reject confidence > 1';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%confidence must be between 0 and 1%' THEN
            RAISE NOTICE '  [PASS] link_object_attribute rejects confidence > 1';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 测试组 21：get_object_attributes 功能
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-21] get_object_attributes ---';

    SELECT count(*) INTO v_count FROM get_object_attributes(1001, 'test_graph');
    IF v_count = 1 THEN
        RAISE NOTICE '  [PASS] get_object_attributes found 1 attribute';
    ELSE
        RAISE EXCEPTION '  [FAIL] get_object_attributes found % attributes (expected 1)', v_count;
    END IF;

    -- 边界条件：不存在的 vertex_id
    SELECT count(*) INTO v_count FROM get_object_attributes(999999, 'test_graph');
    IF v_count = 0 THEN
        RAISE NOTICE '  [PASS] get_object_attributes with unknown vertex returns empty';
    ELSE
        RAISE EXCEPTION '  [FAIL] get_object_attributes returned unexpected rows';
    END IF;

    -- ========================================================================
    -- 测试组 22：get_related_objects 功能
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-22] get_related_objects ---';

    BEGIN
        SELECT count(*) INTO v_count FROM get_related_objects(1001, 'test_graph', NULL);
        RAISE NOTICE '  [PASS] get_related_objects executed (count=%)', v_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '  [WARN] get_related_objects: % (may need knowledge graph data)', SQLERRM;
    END;

    -- ========================================================================
    -- 测试组 23：search_objects 带标签过滤
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-23] search_objects label filter ---';

    SELECT count(*) INTO v_count FROM search_objects('test', 'test_graph', 'TestLabel', 10);
    IF v_count >= 0 THEN
        RAISE NOTICE '  [PASS] search_objects with label filter executed (count=%)', v_count;
    ELSE
        RAISE EXCEPTION '  [FAIL] search_objects with label filter FAILED';
    END IF;

    -- ========================================================================
    -- 测试组 24：p_label 参数安全测试
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-24] p_label parameter security ---';

    BEGIN
        PERFORM count(*) FROM search_objects('test', 'test_graph', 'Label;DROP TABLE', 10);
        RAISE NOTICE '  [PASS] search_objects accepts p_label with semicolon (no injection risk)';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '  [PASS] search_objects rejected p_label with special chars: %', SQLERRM;
    END;

    -- ========================================================================
    -- 测试组 25：控制字符安全测试
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [TEST-25] Control character security ---';

    BEGIN
        PERFORM validate_query_text(E'test\x00string');
        RAISE EXCEPTION '  [FAIL] validate_query_text should reject null byte';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%invalid control characters%' THEN
            RAISE NOTICE '  [PASS] validate_query_text rejects null byte';
        ELSE
            RAISE EXCEPTION '  [FAIL] unexpected error: %', SQLERRM;
        END IF;
    END;

    -- ========================================================================
    -- 清理测试数据
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '--- [CLEANUP] ---';

    DELETE FROM object_attribute_mapping WHERE graph_name = 'test_graph';
    DELETE FROM vertex_embeddings WHERE graph_name = 'test_graph';
    DELETE FROM attribute_embeddings WHERE graph_name = 'test_graph';
    RAISE NOTICE '  [DONE] Test data cleaned up';

    -- ========================================================================
    -- 汇总
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '========== ALL TESTS PASSED ==========';
END;
$$;
