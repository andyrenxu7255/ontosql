# SQL Query Format Convention
> Tier 3 Retrieval Document | ≤2000 tokens | id: sql_query_format
>
> This document governs ALL SQL generation within OntoSQL Skills.
> Applies to: query, write, graph category scripts.

## §1 Parameter Binding (mandatory)

NEVER concatenate user input into SQL strings. ALWAYS use parameterized psql variables:

```bash
# CORRECT — variable substitution at bash level, single-quoted in SQL
sql="SELECT * FROM ontosql.search_objects(
    '${query_text//\'/\'\'}',
    '${graph_name}',
    ${label_param},
    ${top_k},
    ${embedding_param}
) t;"

# WRONG — direct concatenation (SQL injection risk)
sql="SELECT * FROM ontosql.search_objects('"${query_text}"', ...)"
```

### Escape Rules

| Input Source | Escape Method |
|-------------|---------------|
| User text (query_text, vertex_name...) | `${var//\'/\'\'}` — double single-quotes |
| Graph names (graph_name) | validated by `validate_graph_name` regex first, then `${var}` |
| Integers (top_k, vertex_id) | No quoting, direct `${var}` |
| Arrays (embedding vector) | `::vector(1536)` cast suffix |
| JSONB (metadata) | `::jsonb` cast suffix |

## §2 Function Call Format

All OntoSQL SQL functions are called via `ontosql.<function_name>(<params>)`.

```sql
SELECT json_agg(row_to_json(t)) FROM (
    SELECT <columns> AS <aliases>
    FROM ontosql.<function_name>(
        <param1>, <param2>, ...
    )
) t;
```

Rules:
- ALWAYS wrap in `json_agg(row_to_json(t))` subquery for structured output.
- ALWAYS use `AS` for column aliases, never implicit naming.
- ALWAYS end SQL statement with `;` (not included in parameter substitution).
- NEVER put SQL string onto multiple lines with unescaped newlines inside single quotes.

## §3 NULL vs Default Params

```bash
# CORRECT — NULL as SQL literal when parameter is absent
embedding_param="NULL"
if [[ "${query_embedding_raw}" != "null" && -n "${query_embedding_raw}" ]]; then
    embedding_param="'${query_embedding_raw}'::vector(1536)"
fi
```

- Default for absent params is SQL `NULL` literal (no quotes).
- Present value gets `'<quoted_value>'::<type>`.
- Boolean logic for "is absent": check for bash-empty AND JSON-null.

## §4 Brace/Bracket Rules for SQL Generation

### §4.1 Single Quotes around Values

ALL string values in SQL use single quotes `'`:
```sql
-- CORRECT
'${query_text//\'/\'\'}'

-- WRONG
"${query_text}"
```

### §4.2 Parentheses for Function Calls

Function call parameters wrapped in `( )` WITHOUT space after function name:
```sql
-- CORRECT
ontosql.search_objects('text', 'graph_name', NULL, 10, NULL)

-- WRONG
ontosql.search_objects ('text', 'graph_name', NULL, 10, NULL)
```

### §4.3 Subquery Wrapping

Subquery `t` alias after `) t;` — closing paren, space, alias, semicolon:
```sql
-- CORRECT
SELECT json_agg(row_to_json(t)) FROM (
    SELECT ... FROM ontosql.func(...)
) t;

-- WRONG
SELECT json_agg(row_to_json(t)) FROM (
    SELECT ... FROM ontosql.func(...))t;
-- WRONG
SELECT json_agg(row_to_json(t)) FROM (
    SELECT ... FROM ontosql.func(...)
) AS t;
```

## §5 Error Handling

```bash
result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || {
    err_msg=$(echo "${result}" | head -1)
    die_server "ERR_QUERY_FAILED" "query failed" \
      "{\"sql_error\":$(python3 -c \"import sys,json; print(json.dumps('${err_msg//\'/\'\'}')\") 2>/dev/null || echo '\"\"')}"
}
```

- ALWAYS capture both stdout and stderr via `2>&1`.
- ALWAYS check exit code via `||` block.
- Error details must be valid JSON, using python3 for safe escaping.