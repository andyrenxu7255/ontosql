# OntoSQL

> 面向「智能问数」的融合数据库 — PostgreSQL 17 + pgvector + Apache AGE
> 全新 Agent-Oriented Architecture — 20 个标准 Skill 组件，纯 CLI/JSON 交互

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

# 应显示: age, plpgsql, vector 三个扩展
# 注意: pg_trgm 在首次执行 sql/001_core_schema.sql 或 tests/setup.sql 时自动创建

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
├── ontosql                         # 统一 CLI 入口（Agent 调用主入口）
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
│   ├── ops.md                      #   部署、优化、备份、升级
│   ├── modules.md                  #   模块功能详细说明
│   ├── data_dictionary.md          #   数据字典（完整表结构定义）
│   ├── object_index.md             #   核心对象图谱索引
│   ├── code_review.md              #   代码审查报告
│   ├── consistency_audit.md        #   文档一致性审计与代码审计
│   ├── agent_guide.md              #   Agent 三步工作流对接指南
│   └── knowledge_graph.md          #   本体图谱（Agent 按图索骥索引）
├── specs/                          # Agent 转型规范
│   └── skill_spec.md               #   Skill 组件设计与交互规范
├── skills/                         # Agent Skill 组件库 (20 Skills)
│   ├── manifest.json               #   Skill 注册与发现清单
│   ├── lib/common.sh               #   共享库（JSON 输出/错误处理/验证）
│   ├── lifecycle/                  #   6 个生命周期 Skill（build/start/stop/...）
│   ├── query/                      #   6 个检索 Skill（search-*/get-*/...）
│   ├── write/                      #   3 个写入 Skill（upsert-*/link-*）
│   ├── ops/                        #   3 个运维 Skill（health-check/backup/apply-config）
│   └── graph/                      #   2 个图操作 Skill
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
| [模块手册](docs/modules.md) | 模块功能详细说明 | 开发者 |
| [Agent 对接指南](docs/agent_guide.md) | Agent 三步工作流对接指南 | Agent 开发者 |
| [本体图谱](docs/knowledge_graph.md) | Agent 按图索骥索引 | Agent / 全体开发者 |
| [Skill 规范](specs/skill_spec.md) | Skill 组件设计与交互规范 | Agent 开发者 / 架构师 |
- [使用示例](examples/usage.sql) — 11 个典型场景示例
- [测试用例](tests/test_cases.sql) — 24 组功能/边界/异常/安全测试
- [数据字典](docs/data_dictionary.md) — 数据模型与函数清单
- [对象索引](docs/object_index.md) — 核心对象关系图谱
- [文档一致性审计](docs/consistency_audit.md) — 代码与文档一致性检查
- [代码审查报告](docs/code_review.md) — 代码质量评估与建议
- [Skill 清单](skills/manifest.json) — 20 个 Skill 的完整注册表

### Agent 快速开始

```bash
# 列出所有可用 Skill
./ontosql list

# 查看某个 Skill 的完整元数据（输入/输出/示例）
./ontosql info search-object-attribute

# 以 JSON 方式调用 Skill（Agent 友好）
echo '{"query_text":"张三的销售额","graph_name":"ontosql_graph"}' | \
  ./ontosql search-object-attribute
```

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
