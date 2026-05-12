# OntoSQL Agent-Oriented Architecture (AOA) Specification
> version: 2.1.0 | date: 2026-05-11

## 0. Three-Tier Format Knowledge Base

OntoSQL uses a hierarchical three-tier architecture to separate format specifications
from skill implementation logic. This ensures consistent code generation across all LLM models.

**Problem**: LLMs (including v4pro) exhibit inconsistent brace/bracket usage when
generating JSON, bash, and SQL code. Embedding formatting rules in primary skill
scripts leads to redundancy and staleness.

**Solution**: Format rules are extracted into standalone tertiary retrieval documents,
each ≤2000 tokens for precise context injection.

```
Tier 1: Primary Skill Layer (skills/**/*.sh)
├── Contains: business logic, function calls
├── References: format rules via # @format: <doc-id> tags
└── NEVER embeds: formatting rules inline

Tier 2: Reference Specification Layer (specs/format/)
├── Contains: format manifest, retrieval index
├── Maps: Skill category → required format docs
└── Controls: which docs get injected per task

Tier 3: Tertiary Retrieval Layer (specs/tertiary/)
├── Contains: granular format + constraint docs (≤2000 tokens each)
├── Eleven docs:
│   ├── Format: json_output, bash_script, sql_query,
│   │           embedding, error_response, input_schema
│   ├── Constraint: execution_constraints, tool_invocation_spec
│   ├── Security: permission_model
│   ├── Compat:   system_adaptation
│   └── Cross-cut: brace_bracket_guide
└── Retrieved: on-demand per task, max 4 docs at once
```

### LLM Retrieval Workflow

```
1. Agent reads skills/manifest.json → identifies target Skill
2. Agent reads specs/format/manifest.json → finds required format docs
3. Agent retrieves 2-4 tertiary docs based on Skill category
4. Agent generates code with format rules applied
5. brace_bracket_guide.md is ALWAYS included (cross-cutting)
```

### `# @format:` Tag Convention

Each Skill script declares its format dependencies via comment tags:

```bash
# @format: json_output_format, sql_query_format, brace_bracket_guide
```

The tag is a comment line (no runtime impact) that the format manifest resolver
parses to determine which tertiary docs to inject.

## 1. Design Principles

| # | Principle | Description |
|---|-----------|-------------|
| P1 | **Zero Human UI** | Every interface is designed for machine consumption (JSON + exit codes + structured logs), never for human readability as primary goal |
| P2 | **Idempotency First** | Every Skill is safe to retry; state-changing operations use ON CONFLICT or pre-check |
| P3 | **Fail Loud** | Errors produce machine-parseable JSON with error codes, not just text messages |
| P4 | **Stateless by Default** | Skills carry no internal state between invocations; all context passed via args/stdin |
| P5 | **Discoverable** | A `manifest.json` enables agents to introspect available Skills without scanning filesystem |
| P6 | **Composable** | Skills can be piped: output of one Skill is valid input to another (JSON-in, JSON-out) |
| P7 | **Secure by Construction** | Input validation on every Skill; no shell injection; no secrets in logs |
| P8 | **Format-Isolated** | Formatting conventions live in tertiary docs, never embedded in primary skill layer |

## 2. Skill Component Architecture

```
                        ┌─────────────────────────┐
                        │   Agent (LLM / MCP)     │
                        │                         │
                        │  Reads manifest.json    │
                        │  Plans task topology     │
                        │  Calls skills via CLI   │
                        └───────────┬─────────────┘
                                    │
                        ┌───────────▼─────────────┐
                        │   ontosql CLI Gateway   │
                        │   (unified entry point) │
                        └───────────┬─────────────┘
                                    │
        ┌───────────────┬───────────┼───────────────┬───────────────┐
        ▼               ▼           ▼               ▼               ▼
   ┌─────────┐    ┌─────────┐  ┌─────────┐    ┌─────────┐    ┌─────────┐
   │lifecycle│    │  query  │  │  write  │    │   ops   │    │  graph  │
   │ Skills  │    │ Skills  │  │ Skills  │    │ Skills  │    │ Skills  │
   └────┬────┘    └────┬────┘  └────┬────┘    └────┬────┘    └────┬────┘
        │               │           │               │               │
        └───────────────┴───────────┴───────────────┴───────────────┘
                                    │
                        ┌───────────▼─────────────┐
                        │   PostgreSQL 17.4       │
                        │   + pgvector + AGE      │
                        │   + pg_trgm             │
                        └─────────────────────────┘
```

## 3. Skill Catalog (20 Skills)

### 3.1 Lifecycle Skills (6)

| ID | Name | Operation | Idempotent |
|----|------|-----------|------------|
| L-01 | `build` | Compile PG + pgvector + AGE | Partial |
| L-02 | `init-db` | Initialize data directory | Yes (skips if exists) |
| L-03 | `start` | Start PG instance + create extensions | Yes |
| L-04 | `stop` | Stop PG instance gracefully | Yes |
| L-05 | `status` | Check PG instance health | Yes |
| L-06 | `clean` | Remove all build artifacts | Yes |

### 3.2 Query Skills (6)

| ID | Name | Wraps SQL Function | Read-only |
|----|------|-------------------|-----------|
| Q-01 | `search-objects` | `search_objects()` | Yes |
| Q-02 | `search-attributes` | `search_attributes()` | Yes |
| Q-03 | `find-objects-by-attribute` | `find_objects_by_attribute()` | Yes |
| Q-04 | `search-object-attribute` | `search_object_attribute()` | Yes |
| Q-05 | `get-object-attributes` | `get_object_attributes()` | Yes |
| Q-06 | `get-related-objects` | `get_related_objects()` | Yes |

### 3.3 Write Skills (3)

| ID | Name | Wraps SQL Function |
|----|------|-------------------|
| W-01 | `upsert-vertex` | `upsert_vertex_embedding()` |
| W-02 | `upsert-attribute` | `upsert_attribute_embedding()` |
| W-03 | `link-object-attribute` | `link_object_attribute()` |

### 3.4 Operations Skills (3)

| ID | Name | Operation |
|----|------|-----------|
| O-01 | `health-check` | Deep health probe (PG + extensions + query latency) |
| O-02 | `backup` | Logical backup (pg_dump) |
| O-03 | `apply-config` | Apply PG parameter config |

### 3.5 Graph Skills (2)

| ID | Name | Operation |
|----|------|-----------|
| G-01 | `load-knowledge-graph` | Load knowledge graph schema + data |
| G-02 | `cypher-query` | Execute arbitrary openCypher query |

## 4. CLI Command Specification

### 4.1 Entry Point
```
ontosql <skill-name> [--input <json>] [--file <path>] [--format json|jsonl]
```

### 4.2 Input Format
All Skills accept input via one of:
- `--input '{"key":"value"}'` — inline JSON
- `--file path/to/input.json` — JSON from file
- `stdin` (when no --input/--file) — piped JSON

### 4.3 Output Format (JSON Schema)
```json
{
  "status": "success" | "error",
  "skill": "<skill-name>",
  "timestamp": "ISO8601",
  "data": { ... },
  "meta": {
    "elapsed_ms": 42,
    "rows_affected": 5
  },
  "error": {
    "code": "ERR_XXX",
    "message": "human-readable",
    "details": {}
  }
}
```

### 4.4 Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Client error (invalid input) |
| 2 | Server error (PG unavailable) |
| 3 | Config error (missing env vars) |
| 4 | Not found (skill doesn't exist) |

### 4.5 Discovery
```
ontosql list                      # List all skills with one-line descriptions
ontosql info <skill-name>         # Show skill signature, params, examples
ontosql manifest                  # Output full manifest.json
```

## 5. Security Specifications

| Rule | Enforcement |
|------|-------------|
| S-01 | All SQL parameters use parameterized queries (`psql -v`) |
| S-02 | No shell injection: input validated with regex before any `eval`/`exec` |
| S-03 | Secrets read from env vars only, never from args |
| S-04 | Input max lengths enforced: query_text ≤ 1000, graph_name ≤ 63 |
| S-05 | Embedding dimensions validated server-side (vector_dims check) |
| S-06 | Connection uses scram-sha-256 authentication |

## 6. Error Code Registry
| Code | Category | Description |
|------|----------|-------------|
| ERR_INPUT_EMPTY | Input | Required parameter missing |
| ERR_INPUT_INVALID | Input | Parameter format invalid |
| ERR_INPUT_TOO_LONG | Input | Parameter exceeds max length |
| ERR_PG_UNREACHABLE | Server | PostgreSQL not accessible |
| ERR_EXTENSION_MISSING | Server | Required extension not loaded |
| ERR_GRAPH_NOT_FOUND | Data | Specified graph does not exist |
| ERR_EMBEDDING_DIM | Data | Embedding dimension mismatch |
| ERR_DUPLICATE_KEY | Constraint | Unique constraint violation |
| ERR_SKILL_NOT_FOUND | Discovery | Skill name not in manifest |