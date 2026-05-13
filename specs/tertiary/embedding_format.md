# Embedding Vector Format
> Tier 3 Retrieval Document | ≤2000 tokens | id: embedding_format
>
> This document governs embedding vector formatting for pgvector operations.
> Applies to: write category scripts (upsert-vertex, upsert-attribute).

## §1 Dimension Specification

ALL embeddings in OntoSQL use dimension **1536** (OpenAI text-embedding-3-large compatible).

| Property | Value |
|----------|-------|
| Dimension | 1536 |
| Storage type | `vector(1536)` PostgreSQL column |
| Cast suffix | `::vector(1536)` |
| Validation | Server-side via function `check_embedding_dimension()` (if enabled) |

## §2 Input Format (from Agent to Skill)

Embeddings arrive as JSON arrays in the `--input` field:

```json
{
  "embedding": [0.0123, -0.0456, 0.0789, ..., -0.0012],
  "vertex_id": 42,
  "graph_name": "ontosql_graph",
  "vertex_name": "SalesReport",
  "label_name": "Object"
}
```

- Array length MUST be exactly 1536.
- Values are float64 precision.
- No truncation, no rounding before passing to PG.

## §3 SQL Cast Format

When constructing SQL, the embedding array is converted to a pgvector literal:

```bash
embedding_raw=$(json_get_raw "embedding" "")

# CORRECT — cast at SQL level
sql="SELECT ontosql.upsert_vertex_embedding(
    ..., '${embedding_raw}'::vector, ...
);"
```

The `${embedding_raw}` string is the raw JSON array like `[0.0123, -0.0456, ...]`.
PostgreSQL + pgvector parse this as a vector literal.

### WRONG patterns (will fail):

```sql
-- WRONG: ARRAY[...] constructor
embedding_param="ARRAY[${values}]::vector"

-- WRONG: vector() constructor
embedding_param="vector(${json_string})"

-- WRONG: string literal
embedding_param="'(${json_string})'"
```

## §4 NULL vs Zero Vector

An absent embedding is SQL `NULL`, NOT a zero vector:

```sql
-- CORRECT: embedding is required, so absent = client error
embedding_param="NULL" → die_client "ERR_INPUT_EMPTY" "embedding is required"

-- WRONG: substituting zero vector silently
embedding_param="'[0.0, 0.0, ... 1536 times]'::vector"
```

Rule: embedding is ALWAYS required for write Skills. If absent, fail loudly with ERR_INPUT_EMPTY.

## §5 Dimension Validation (Server-side)

The SQL function `upsert_vertex_embedding` internally checks:

```sql
IF array_length(p_embedding::float8[], 1) != 1536 THEN
    RAISE EXCEPTION 'embedding dimension must be 1536, got %',
        array_length(p_embedding::float8[], 1);
END IF;
```

Skills do NOT duplicate this check. Trust the server-side validation and report errors from PG.

## §6 Brace Rules for Vector Arrays

**CRITICAL:** The JSON array syntax uses `[ ]` square brackets:

```json
// CORRECT
[0.0123, -0.0456, 0.0789]

// WRONG — curly braces (PostgreSQL native array syntax, NOT for pgvector)
{0.0123, -0.0456, 0.0789}

// WRONG — parentheses
(0.0123, -0.0456, 0.0789)
```

The `[ ]` square bracket form is the ONLY accepted format. The pgvector extension parses JSON array syntax, not PostgreSQL native array syntax.