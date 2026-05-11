-- ============================================================================
-- OntoSQL 测试环境初始化
-- ============================================================================
-- 功能：创建必需扩展 + pg_trgm + 加载 ontosql Schema
-- 执行：psql -U <user> -d postgres -f tests/setup.sql
-- 说明：此脚本在 make test 的测试流程第一步自动执行
-- ============================================================================

-- 创建必需扩展（IF NOT EXISTS 确保幂等）
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 设置搜索路径：先搜索 ontosql（业务表），再 ag_catalog（AGE 系统表），最后 public
SET search_path TO ontosql, ag_catalog, public;

-- 加载核心 Schema（创建表、索引、函数）
-- 相对路径：从项目根目录运行时自动解析
\i ../sql/001_core_schema.sql

-- 初始化成功提示
DO $$
BEGIN
    RAISE NOTICE 'Test environment initialized successfully';
END;
$$;
