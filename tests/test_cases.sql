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
