# OntoSQL

> 面向「智能问数」的融合数据库 — PostgreSQL 16/17 + pgvector + Apache AGE

## 项目定位

OntoSQL 是一个集成了 **关系查询**、**图遍历**、**向量搜索** 三大能力的融合数据库平台，专为 Natural Language to Structured Query（NL2Query）「智能问数」场景设计。

## 能力矩阵

| 能力 | 底层引擎 | 使用方式 |
|------|---------|---------|
| 标准 SQL 查询 | PostgreSQL 内核 | SQL |
| 图遍历 | Apache AGE | openCypher |
| 向量语义搜索 | pgvector | SQL + HNSW/IVFFlat |
| 模糊文本匹配 | pg_trgm | SQL similarity() |
| 对象识别 | 向量 + trigram 多路召回 | ontosql.search_objects() |
| 属性识别 | 向量 + trigram 多路召回 | ontosql.search_attributes() |
| 属性反查对象 | AGE 图结构 | ontosql.find_objects_by_attribute() |
| 联合检索+验证 | 向量 + trigram + 图 | ontosql.search_object_attribute() |

## 快速开始

```bash
# 1. 克隆并编译
git clone <this-repo> ontosql && cd ontosql
make build          # 编译 PG + pgvector + AGE
make init-db        # 初始化数据库
make start          # 启动

# 2. 初始化 Schema
build/pgsql17/bin/psql -p 5432 -d postgres -f sql/001_core_schema.sql

# 3. 创建知识图谱（示例）
build/pgsql17/bin/psql -p 5432 -d postgres -f sql/002_knowledge_graph.sql

# 4. 测试查询
build/pgsql17/bin/psql -p 5432 -d postgres -c \
  "SET search_path TO ontosql, ag_catalog, public; SELECT * FROM search_object_attribute('张三的销售额', 'ontosql_graph');"
```

## 项目结构

```
ontosql/
├── upstream/            # 上游源码（不修改，仅编译）
│   ├── postgresql/      # PostgreSQL REL_17_STABLE
│   ├── pgvector/        # pgvector 0.8.1
│   └── age/             # Apache AGE master
├── build/               # 编译产物
├── sql/                 # SQL Schema 和函数
│   ├── 001_core_schema.sql      # 向量表 + 检索函数
│   └── 002_knowledge_graph.sql  # AGE 图结构
├── config/              # 配置模板
├── docs/                # 文档
│   ├── api.md           # API 参考
│   ├── ops.md           # 运维手册
│   └── architecture.md  # 架构总览
├── examples/            # 使用示例
├── tests/               # 测试用例
│   ├── setup.sql
│   └── test_cases.sql
├── docker/              # Docker 支持
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── entrypoint.sh
├── Makefile             # 顶层构建
└── README.md
```

## 设计原则

1. **零侵入**：不对上游源码做功能修改，仅做编译兼容性修复
2. **浅层集成**：向量侧表 + 图遍历，职责分明
3. **多路召回**：向量语义 + trigram 文本 + 图结构验证 = 高召回率
4. **函数封装**：所有查询能力通过 SQL 函数暴露，应用层零 C 代码依赖

## 查询流程

```
用户 NL 输入
    │
    ├─→ ontosql.search_objects()     对象识别（向量 + trigram）
    ├─→ ontosql.search_attributes()  属性识别（向量 + trigram）
    │
    └─→ ontosql.search_object_attribute()
        ├─ 交叉组合候选对象 × 候选属性
        ├─ 查询 object_attribute_mapping 验证关联
        └─ 返回 {is_verified: true/false} 结果
            │
            └─→ AGE Cypher 查询获取实际数据
```

## 文档索引

- [API 参考](docs/api.md) — 接口参数、返回值、错误码
- [运维手册](docs/ops.md) — 部署、优化、排障、升级
- [架构总览](docs/architecture.md) — 架构设计决策和组件关系
- [使用示例](examples/usage.sql) — 11 个典型场景示例
- [测试用例](tests/test_cases.sql) — 13 组功能/边界/异常测试
