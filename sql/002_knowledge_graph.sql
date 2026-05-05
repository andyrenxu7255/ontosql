-- ============================================================================
-- OntoSQL 知识图谱初始化 — 智能问数示例
-- ============================================================================
-- 功能：创建示例知识图谱，演示对象/属性/关系的 AGE 图模型
-- 前置：已执行 sql/001_core_schema.sql
-- 执行：psql -U <user> -d postgres -f sql/002_knowledge_graph.sql
-- ============================================================================
-- 图模型说明：
--   Object（业务对象）  — 员工、产品、客户等具体实体
--   Metric（指标属性）   — 销售额、利润率等可查询的数值指标
--   Dimension（分析维度） — 本月、上月等时间/地域维度
--   Department（组织）   — 部门层级结构
--
-- 关系说明：
--   Object -[:HAS_METRIC]-> Metric        对象拥有哪些指标
--   Object -[:BELONGS_TO]-> Department    对象属于哪个部门
--   Metric -[:HAS_DIMENSION]-> Dimension  指标关联哪些分析维度
--   Object -[:RELATED_TO]-> Object        对象间的其他关系
-- ============================================================================

SET search_path TO ontosql, ag_catalog, public;

-- ============================================================================
-- 1. 创建图
-- ============================================================================

-- 创建名为 ontosql_graph 的图，后续所有顶点和边都归属此图
SELECT create_graph('ontosql_graph');

-- ============================================================================
-- 2. 创建顶点标签
-- ============================================================================

-- 业务对象标签：员工、产品、客户等具体实体
SELECT create_vlabel('ontosql_graph', 'Object');

-- 指标标签：将属性建模为独立图顶点，支持独立检索和图结构验证
SELECT create_vlabel('ontosql_graph', 'Metric');

-- 维度标签：时间/地区等分析维度（如本月、上月、华东区）
SELECT create_vlabel('ontosql_graph', 'Dimension');

-- 部门标签：组织层级归属
SELECT create_vlabel('ontosql_graph', 'Department');

-- ============================================================================
-- 3. 创建边标签（关系类型）
-- ============================================================================

-- 对象拥有指标的关系
SELECT create_elabel('ontosql_graph', 'HAS_METRIC');

-- 对象从属组织的关系
SELECT create_elabel('ontosql_graph', 'BELONGS_TO');

-- 指标关联维度的关系
SELECT create_elabel('ontosql_graph', 'HAS_DIMENSION');

-- 对象间的通用关系
SELECT create_elabel('ontosql_graph', 'RELATED_TO');

-- ============================================================================
-- 4. 插入顶点数据
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 部门数据（4 个部门）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Department {name: '销售部', code: 'SALES'})
    CREATE (:Department {name: '技术部', code: 'TECH'})
    CREATE (:Department {name: '财务部', code: 'FINANCE'})
    CREATE (:Department {name: '市场部', code: 'MARKETING'})
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 4.2 员工数据（5 名员工，type='employee'）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Object {name: '张三', type: 'employee', employee_id: 'E001'})
    CREATE (:Object {name: '李四', type: 'employee', employee_id: 'E002'})
    CREATE (:Object {name: '王五', type: 'employee', employee_id: 'E003'})
    CREATE (:Object {name: '赵六', type: 'employee', employee_id: 'E004'})
    CREATE (:Object {name: '钱七', type: 'employee', employee_id: 'E005'})
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 4.3 产品数据（3 个产品，type='product'）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Object {name: '产品A', type: 'product', product_code: 'P001'})
    CREATE (:Object {name: '产品B', type: 'product', product_code: 'P002'})
    CREATE (:Object {name: '产品C', type: 'product', product_code: 'P003'})
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 4.4 客户数据（3 个客户，type='customer'）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Object {name: '华科科技', type: 'customer', customer_level: 'A'})
    CREATE (:Object {name: '数据之光', type: 'customer', customer_level: 'B'})
    CREATE (:Object {name: '星辰网络', type: 'customer', customer_level: 'A'})
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 4.5 指标数据（9 个指标，支持多维度分析）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Metric {name: '销售额', unit: '元', data_type: 'numeric',
                     description: '销售产生的总金额'})
    CREATE (:Metric {name: '利润率', unit: '%', data_type: 'numeric',
                     description: '利润占销售额的比例'})
    CREATE (:Metric {name: '客户数', unit: '个', data_type: 'integer',
                     description: '服务的客户总量'})
    CREATE (:Metric {name: '订单量', unit: '笔', data_type: 'integer',
                     description: '产生的订单总数'})
    CREATE (:Metric {name: '回款率', unit: '%', data_type: 'numeric',
                     description: '已回款占总应收款比例'})
    CREATE (:Metric {name: '客单价', unit: '元', data_type: 'numeric',
                     description: '平均每个客户的消费额'})
    CREATE (:Metric {name: '活跃用户数', unit: '个', data_type: 'integer',
                     description: '月活跃用户总量'})
    CREATE (:Metric {name: '转化率', unit: '%', data_type: 'numeric',
                     description: '访问到购买的转化比例'})
    CREATE (:Metric {name: '库存周转天数', unit: '天', data_type: 'numeric',
                     description: '库存从进入到售出的平均天数'})
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 4.6 时间维度数据（6 个常用时间维度）
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    CREATE (:Dimension {name: '本月', type: 'time'})
    CREATE (:Dimension {name: '上月', type: 'time'})
    CREATE (:Dimension {name: '本季度', type: 'time'})
    CREATE (:Dimension {name: '上季度', type: 'time'})
    CREATE (:Dimension {name: '本年', type: 'time'})
    CREATE (:Dimension {name: '去年', type: 'time'})
$$) AS (v agtype);

-- ============================================================================
-- 5. 插入边（关系）— 构建图结构
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 员工 → 部门 归属关系
--    张三、钱七 → 销售部；李四 → 技术部；王五 → 财务部；赵六 → 市场部
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (d:Department)
    WHERE e.name = '张三' AND d.name = '销售部'
    CREATE (e)-[:BELONGS_TO]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (d:Department)
    WHERE e.name = '李四' AND d.name = '技术部'
    CREATE (e)-[:BELONGS_TO]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (d:Department)
    WHERE e.name = '王五' AND d.name = '财务部'
    CREATE (e)-[:BELONGS_TO]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (d:Department)
    WHERE e.name = '赵六' AND d.name = '市场部'
    CREATE (e)-[:BELONGS_TO]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (d:Department)
    WHERE e.name = '钱七' AND d.name = '销售部'
    CREATE (e)-[:BELONGS_TO]->(d)
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 5.2 员工 → 指标 关联关系
--    张三：销售额、客户数、回款率
--    李四：活跃用户数、转化率
--    赵六：销售额、客单价
--    钱七：销售额、订单量
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '张三' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '张三' AND m.name = '客户数'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '张三' AND m.name = '回款率'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '李四' AND m.name = '活跃用户数'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '李四' AND m.name = '转化率'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '赵六' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '赵六' AND m.name = '客单价'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '钱七' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '钱七' AND m.name = '订单量'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 5.3 产品 → 指标 关联关系
--    产品A：销售额、库存周转天数
--    产品B：销售额
--    产品C：利润率
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '产品A' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '产品A' AND m.name = '库存周转天数'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '产品B' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '产品C' AND m.name = '利润率'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 5.4 客户 → 指标 关联关系
--    华科科技：销售额
--    数据之光：订单量
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '华科科技' AND m.name = '销售额'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (e:Object), (m:Metric)
    WHERE e.name = '数据之光' AND m.name = '订单量'
    CREATE (e)-[:HAS_METRIC]->(m)
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 5.5 指标 → 维度 关联关系（时间维度的下钻能力）
--    销售额 关联 本月/上月；客户数 关联 本月
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (m:Metric), (d:Dimension)
    WHERE m.name = '销售额' AND d.name = '本月'
    CREATE (m)-[:HAS_DIMENSION]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (m:Metric), (d:Dimension)
    WHERE m.name = '销售额' AND d.name = '上月'
    CREATE (m)-[:HAS_DIMENSION]->(d)
$$) AS (v agtype);
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (m:Metric), (d:Dimension)
    WHERE m.name = '客户数' AND d.name = '本月'
    CREATE (m)-[:HAS_DIMENSION]->(d)
$$) AS (v agtype);

-- ----------------------------------------------------------------------------
-- 5.6 员工 → 员工 关系（同部门同事关系）
--    张三 和 钱七 同在销售部
-- ----------------------------------------------------------------------------
SELECT * FROM cypher('ontosql_graph', $$
    MATCH (a:Object), (b:Object)
    WHERE a.name = '张三' AND b.name = '钱七'
    CREATE (a)-[:RELATED_TO {type: '同部门'}]->(b)
$$) AS (v agtype);

-- ============================================================================
-- 初始化完成
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Knowledge graph initialized successfully';
END;
$$;
