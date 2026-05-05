-- ============================================================================
-- OntoSQL 生产环境 PostgreSQL 参数配置模板
-- ============================================================================
-- 用法：psql -U postgres -d postgres -f config/postgresql.template.sql
-- 注意：以下配置基于 8GB 内存的服务器，实际部署请根据硬件调整
-- ============================================================================

-- ============================================================================
-- 1. 内存配置
-- ============================================================================
-- shared_buffers：PG 共享缓冲池，建议物理内存的 25%
-- effective_cache_size：操作系统文件缓存估算，建议物理内存的 75%
-- work_mem：单个排序/哈希操作的内存，复杂查询可能需要调大
-- maintenance_work_mem：VACUUM/CREATE INDEX 等维护操作的内存
-- wal_buffers：WAL 写入缓冲区

ALTER SYSTEM SET shared_buffers = '512MB';         -- 8GB 内存的 ~6%，生产环境建议 2GB+
ALTER SYSTEM SET effective_cache_size = '2GB';     -- 8GB 内存的 25%
ALTER SYSTEM SET work_mem = '32MB';                -- 按连接数调整：总 work_mem = 此值 × max_connections
ALTER SYSTEM SET maintenance_work_mem = '256MB';   -- 维护操作专用内存
ALTER SYSTEM SET wal_buffers = '16MB';             -- 默认 -1（shared_buffers 的 1/32）

-- ============================================================================
-- 2. 连接配置
-- ============================================================================
-- max_connections：最大并发连接数，需与 work_mem 联动
-- superuser_reserved_connections：为超级用户预留的连接数（紧急维护用）

ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET superuser_reserved_connections = 5;

-- ============================================================================
-- 3. WAL（Write-Ahead Log）配置
-- ============================================================================
-- wal_level = 'replica'：支持 pg_basebackup 和逻辑复制的最低级别
-- max_wal_senders = 0：无流复制需求时设为 0，降低资源消耗
-- max_wal_size / min_wal_size：自动 checkpoint 的 WAL 大小阈值
-- checkpoint_completion_target：checkpoint 分散在目标比例的 checkpoint 间隔中

ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 0;              -- 无流复制需求时设为 0，需要流复制时改为 >0
ALTER SYSTEM SET max_wal_size = '4GB';             -- 超过此值触发自动 checkpoint
ALTER SYSTEM SET min_wal_size = '1GB';             -- checkpoint 后回收到此大小
ALTER SYSTEM SET checkpoint_completion_target = 0.9; -- 分散 IO 压力，避免突发写入

-- ============================================================================
-- 4. 规划器（Planner）配置
-- ============================================================================
-- random_page_cost：随机页读取成本（SSD 设为 1.1，HDD 设为 4.0）
-- effective_io_concurrency：并发 IO 请求数（SSD 可设 200+，HDD 设 2）
-- default_statistics_target：ANALYZE 采样的默认桶数（影响查询计划质量）

ALTER SYSTEM SET random_page_cost = 1.1;           -- SSD 环境
ALTER SYSTEM SET effective_io_concurrency = 200;   -- SSD 并发能力
ALTER SYSTEM SET default_statistics_target = 100;  -- 提高查询计划估算精度

-- ============================================================================
-- 5. 扩展专有配置
-- ============================================================================
-- hnsw.ef_search：HNSW 索引的搜索精度（越大越精确但越慢）
-- 生产环境推荐 100~200，对精度不敏感可设 40

ALTER SYSTEM SET hnsw.ef_search = 100;

-- ============================================================================
-- 6. 日志配置
-- ============================================================================
-- logging_collector：启用后台日志收集进程
-- log_rotation_age/size：日志文件轮转策略
-- log_min_duration_statement：记录超过阈值的慢查询（单位 ms）
-- log_line_prefix：日志行前缀格式（便于日志分析）

ALTER SYSTEM SET log_destination = 'stderr';
ALTER SYSTEM SET logging_collector = 'on';
ALTER SYSTEM SET log_directory = 'pg_log';
ALTER SYSTEM SET log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log';
ALTER SYSTEM SET log_rotation_age = '1d';           -- 每天轮转
ALTER SYSTEM SET log_rotation_size = '100MB';       -- 或超过 100MB 时轮转
ALTER SYSTEM SET log_min_duration_statement = 1000; -- 记录超过 1s 的查询
ALTER SYSTEM SET log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ';
-- 格式说明：时间 [PID]: [行号] user=用户名,db=数据库,app=应用名,client=客户端IP

-- ============================================================================
-- 7. 应用更改
-- ============================================================================
-- pg_reload_conf() 向 postmaster 发 SIGHUP 信号，重新加载配置文件
-- 无需重启数据库即可使大多数参数生效

SELECT pg_reload_conf();
