# Error Response Format
> Tier 3 Retrieval Document | ≤2000 tokens | id: error_response_format
>
> This document governs error JSON output for ALL OntoSQL Skills.
> Every error response must be machine-parseable, not just human-readable text.

## §1 Error Envelope (mandatory)

```json
{
  "status": "error",
  "skill": "<skill-name>",
  "timestamp": "<ISO8601 UTC>",
  "error": {
    "code": "ERR_<CATEGORY>_<SPECIFIC>",
    "message": "<human description, ≤200 chars, no trailing dot>",
    "details": { }
  },
  "meta": {
    "elapsed_ms": 0
  }
}
```

## §2 Complete Error Code Registry

| Code | Exit | Category | When to Use |
|------|------|----------|------------|
| `ERR_INPUT_EMPTY` | 1 | Input | Required parameter missing or empty string |
| `ERR_INPUT_INVALID` | 1 | Input | Parameter format incorrect (regex fail, wrong type) |
| `ERR_INPUT_TOO_LONG` | 1 | Input | Parameter exceeds max_length |
| `ERR_PG_UNREACHABLE` | 2 | Server | pg_isready fails, connection refused |
| `ERR_BUILD_FAILED` | 2 | Server | make/configure returns non-zero |
| `ERR_INITDB_FAILED` | 2 | Server | initdb command fails |
| `ERR_START_FAILED` | 2 | Server | pg_ctl start fails |
| `ERR_QUERY_FAILED` | 2 | Server | SQL function execution error |
| `ERR_WRITE_FAILED` | 2 | Server | upsert/link function execution error |
| `ERR_CYPHER_FAILED` | 2 | Server | Cypher query execution error |
| `ERR_BACKUP_FAILED` | 2 | Server | pg_dump failure |
| `ERR_CONFIG_FAILED` | 2 | Server | Configuration apply failure |
| `ERR_EXTENSION_MISSING` | 2 | Server | Required PG extension not loaded |
| `ERR_GRAPH_NOT_FOUND` | 2 | Data | Specified graph name doesn't exist in ag_catalog |
| `ERR_EMBEDDING_DIM` | 2 | Data | Embedding vector dimension ≠ 1536 |
| `ERR_DUPLICATE_KEY` | 2 | Constraint | Unique constraint violation on upsert |
| `ERR_SKILL_NOT_FOUND` | 4 | Discovery | Skill name not in manifest |

## §3 details Object Conventions

`error.details` provides diagnostic data as key-value pairs:

```json
// Example: invalid graph_name
"details": {
  "field": "graph_name",
  "value": "my-graph-with-dashes",
  "pattern": "^[a-zA-Z_][a-zA-Z0-9_]*$"
}

// Example: SQL execution error
"details": {
  "sql_error": "relation \"ontosql.vertex_embeddings\" does not exist",
  "function": "search_objects"
}

// Example: empty required field
"details": {
  "field": "query_text",
  "provided": ""
}
```

Rules:
- `details` MUST be a JSON object ( `{ }` ). NEVER a string, array, or null.
- Keys are lowercase snake_case.
- Values are descriptive: include what was provided vs what was expected.
- NEVER include raw SQL internals in `message` field — put them in `details.sql_error`.

## §4 Message Field Rules

- Language: English (for LLM consumption), or Chinese (for OntoSQL-internal use).
- Max length: 200 characters.
- Format: sentence case, NO trailing period.
- Content: describe what went wrong, NOT how to fix it.
- Examples:
  - CORRECT: `"Required parameter 'query_text' is missing or empty"`
  - CORRECT: `"search_object_attribute query failed"`
  - WRONG: `"Error: query_text was not provided. Please provide a valid query_text."` (too verbose, has period)

## §5 Brace/Bracket in Error JSON

ALWAYS use `{ }` for objects, `[ ]` for arrays in error detail values:

```json
// CORRECT
"details": {"sql_error": "syntax error at or near \")\""}

// WRONG — bare string without JSON wrapper
"details": "syntax error at or near \")\""
```

The `details` field is ALWAYS `{ }` — even when empty. This ensures the LLM parser never encounters inconsistent brace patterns in error responses.