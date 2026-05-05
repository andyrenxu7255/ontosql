# OntoSQL

> 面向「智能问数」的融合数据库 — PostgreSQL 17 + pgvector + Apache AGE

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17.4-blue)](https://www.postgresql.org/)
[![pgvector](https://img.shields.io/badge/pgvector-0.8.1-green)](https://github.com/pgvector/pgvector)
[![Apache AGE](https://img.shields.io/badge/Apache_AGE-1.7.0--dev-orange)](https://github.com/apache/age)
[![License](https://img.shields.io/badge/license-PostgreSQL-blue)](LICENSE)

## 项目简介

OntoSQL 是一个集成了**关系查询**、**图遍历**、**向量语义搜索**三大能力的融合数据库平台，专为 Natural Language to Structured Query（NL2Query）「智能问数」场景设计。

### 能力矩阵

| 能力 | 底层引擎 | 使用方式 | 典型场景 |
|------|---------|---------|---------|
| 标准 SQL 查询 | PostgreSQL 内核 | SQL | 聚合统计、条件过滤 |
| 图遍历 | Apache AGE | openCypher | 对象关系查询、路径发现 |
| 向量语义搜索 | pgvector | SQL + HNSW/IVFFlat | 语义相似匹配、歧义消除 |
| 模糊文本匹配 | pg_trgm | SQL `similarity()` | 错别字容错、拼音检索 |
| 对象识别 | 向量 + trigram 多路召回 | `ontosql.search_objects()` | NL 中识别业务对象 |
| 属性识别 | 向量 + trigram 多路召回 | `ontosql.search_attributes()` | NL 中识别指标/维度 |
| 属性反查对象 | AGE 图结构遍历 | `ontosql.find_objects_by_attribute()` | "这个指标属于谁" |
| 联合检索+验证 | 向量 + trigram + 图验证 | `ontosql.search_object_attribute()` | 一步完成对象+属性匹配 |

### 设计原则

1. **零侵入** — 不对上游源码做功能修改，仅做编译兼容性修复
2. **浅层集成** — 向量侧表独立于图结构，职责分明，互不耦合
3. **多路召回** — 向量语义 + trigram 文本 + 图结构验证 = 高召回率 + 低误判
4. **函数封装** — 所有查询能力通过 SQL/PLpgSQL 函数暴露，应用层零 C 代码依赖

---

## 快速开始

### 环境要求

| 项目 | 要求 |
|------|------|
| 操作系统 | macOS 13+ / Ubuntu 22.04+ |
| CPU | 4 核+ |
| 内存 | 8 GB+ |
| 磁盘 | 20 GB（不含数据） |
| 编译工具 | gcc/clang, make, bison, flex |
| 运行时库 | readline, zlib, OpenSSL, ICU |

### 一键部署

```bash
# 克隆项目
git clone <this-repo> ontosql && cd ontosql

# 编译 PostgreSQL + pgvector + Apache AGE
make build

# 初始化数据目录并启动
make init-db
make start

# 初始化 OntoSQL Schema
make test     # 自动加载 Schema 并运行测试
```

### 验证安装

```bash
# 检查已安装的扩展
build/pgsql17/bin/psql -p 5432 -d postgres -c "\dx"

# 应显示: age, pg_trgm, plpgsql, vector 四个扩展

# 创建示例知识图谱
build/pgsql17/bin/psql -p 5432 -d postgres -f sql/002_knowledge_graph.sql

# 测试查询
build/pgsql17/bin/psql -p 5432 -d postgres -c "
SET search_path TO ontosql, ag_catalog, public;
SELECT * FROM search_object_attribute('张三的销售额', 'ontosql_graph');
"
```

---

## 项目结构

```
ontosql/
├── README.md                       # 项目全貌（本文件）
├── Makefile                        # 顶层构建、启动、测试入口
├── upstream/                       # 上游源码（不做功能修改）
│   ├── postgresql/                 #   PostgreSQL REL_17_STABLE
│   ├── pgvector/                   #   pgvector v0.8.1
│   └── age/                        #   Apache AGE master
├── build/                          # 编译产物
│   ├── pgsql17/                    #   PG 安装目录
│   └── data/                       #   数据库数据目录
├── sql/                            # SQL Schema 与函数定义
│   ├── 001_core_schema.sql         #   核心：向量表 + 多路召回函数 + 写入接口
│   └── 002_knowledge_graph.sql     #   示例：AGE 图初始化（对象/指标/维度）
├── config/                         # 配置模板
│   └── postgresql.template.sql     #   生产环境 PG 参数配置
├── docs/                           # 项目文档
│   ├── overview.md                 #   项目定位与查询流程
│   ├── architecture.md             #   架构总览与设计决策
│   ├── api.md                      #   接口参数、返回值、错误码
│   └── ops.md                      #   部署、优化、备份、升级
├── examples/                       # 使用示例
│   └── usage.sql                   #   11 个典型场景 SQL 示例
├── tests/                          # 测试用例
│   ├── setup.sql                   #   测试环境初始化
│   └── test_cases.sql              #   13 组功能/边界/异常测试
└── docker/                         # Docker 容器化支持
    ├── Dockerfile                  #   多阶段构建镜像
    ├── docker-compose.yml          #   一键启动服务
    └── entrypoint.sh               #   容器入口脚本
```

---

## 核心查询流程

```
用户 NL 输入: "张三上月销售额多少"
    │
    ├─→ ontosql.search_objects("张三上月销售额")
    │      向量语义 + trigram 文本 → 候选: [张三, 钱七, ...]
    │
    ├─→ ontosql.search_attributes("张三上月销售额")
    │      向量语义 + trigram 文本 → 候选: [销售额, 客单价, ...]
    │
    └─→ ontosql.search_object_attribute("张三上月销售额")
           CROSS JOIN 候选对象 × 候选属性
           └─ 查询 object_attribute_mapping 验证关联
               ├─ 张三 + 销售额 → is_verified = true  ✅
               ├─ 张三 + 客单价 → is_verified = false ❌
               └─ 钱七 + 销售额 → is_verified = true  ✅
                   │
                   └─→ AGE Cypher:
                       MATCH (张三)-[:HAS_METRIC]->(销售额)
                             -[:HAS_DIMENSION]->(上月)
                       RETURN value
```

---

## 文档索引

| 文档 | 用途 | 受众 |
|------|------|------|
| [架构总览](docs/architecture.md) | 理解系统架构与设计决策 | 架构师、核心开发者 |
| [API 参考](docs/api.md) | 接口参数、返回值、错误码 | 应用开发者 |
| [运维手册](docs/ops.md) | 部署、调优、备份、升级 | SRE / DBA |
| [项目定位](docs/overview.md) | 项目背景与能力矩阵 | 产品经理、新成员 |
| [使用示例](examples/usage.sql) | 可执行的 SQL 示例 | 开发者 |
| [测试用例](tests/test_cases.sql) | 功能验证和回归测试 | QA、开发者 |

---

## 技术栈

| 组件 | 版本 | 许可证 |
|------|------|--------|
| PostgreSQL | 17.4 (REL_17_STABLE) | PostgreSQL License |
| pgvector | 0.8.1 | PostgreSQL License |
| Apache AGE | master (1.7.0-dev) | Apache 2.0 |
| pg_trgm | PG 17 内置 | PostgreSQL License |

---

## 许可证

本项目 SQL Schema、文档和构建脚本遵循 PostgreSQL License。
上游组件 PostgreSQL、pgvector 遵循 PostgreSQL License，Apache AGE 遵循 Apache 2.0 License。
