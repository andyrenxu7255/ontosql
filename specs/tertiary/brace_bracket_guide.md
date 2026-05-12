# Brace and Bracket Consistency Guide
> Tier 3 Retrieval Document | ≤2000 tokens | id: brace_bracket_guide
>
> **CRITICAL: This document is cross-cutting. ALL models (including v4pro)**
> **MUST retrieve and apply this document when generating ANY code for OntoSQL.**
>
> Observed issue: models show inconsistency in `{ }` vs `[ ]` vs `( )` usage
> across JSON, bash, and SQL contexts. This document is the single source of truth.

## §1 The Three Contexts

| Context | Primary Bracket | Example | NEVER Use |
|---------|----------------|---------|-----------|
| JSON (data) | `{ }` objects, `[ ]` arrays | `{"key": [1, 2, 3]}` | `( )` for grouping |
| Bash (script) | `{ }` for vars, `( )` for arrays, `[[ ]]` for tests | `"${var}"`, `arr=()`, `[[ -z ]]` | `[ ]` for tests |
| SQL (query) | `( )` for funcs, `' '` for strings | `func('val', 1)` | `" "` for strings |

## §2 JSON: Object `{ }` and Array `[ ]` — The Only Two

JSON has exactly TWO structural delimiters. No exceptions.

### §2.1 Objects: `{ }`

```json
{
  "status": "success",
  "data": {
    "results": [ ]
  }
}
```

**Rules:**
- Opening `{` on same line as key or on new line after `:`.
- Closing `}` on its own line, aligned with the opening context.
- NEVER use `(` `)` for JSON objects.

### §2.2 Arrays: `[ ]`

```json
{
  "results": [
    {"vertex_id": 1},
    {"vertex_id": 2}
  ]
}
```

**Rules:**
- Opening `[` on same line as key value or on its own line.
- Closing `]` aligned with opening.
- NEVER use `{ }` for arrays.

### §2.3 v4pro-specific JSON Issues (observed)

| Issue | Wrong | Correct |
|-------|-------|---------|
| Trailing comma in array | `[1, 2, 3,]` | `[1, 2, 3]` |
| Single quotes for keys | `{'key': 'val'}` | `{"key": "val"}` |
| Bare true/false without quotes as string values | `"running": true` | `"running": true` (bare for boolean) but `"action": "inserted"` (quoted for string) |
| Object as bare string | `"details": "..."` | `"details": {"key": "..."}` |
| Null instead of empty object | `"data": null` | `"data": {}` |

### §2.4 Quick Validation

Before emitting JSON: every `{` must have matching `}`. Every `[` must have matching `]`. Count must be zero-balanced. No nesting more than 4 levels deep.

## §3 Bash: Three Bracket Types, Three Purposes

### §3.1 `{ }` — Variable Expansion

```bash
echo "${ONTOSQL_ROOT}"          # simple expansion
echo "${PG_DATA:-${ONTOSQL_ROOT}/build/data}"  # default value
echo "${query_text//\'/\'\'}"   # substitution
```

NEVER omit `{ }` for anything except positional parameters `$1 $2 $@`.

### §3.2 `( )` — Array Definition and Subshell

```bash
# Array initialization
PSQL_CMD=("${PG_HOME}/bin/psql" -h "${PG_HOST}")

# Subshell
result=$(echo "hello" | tr '[:lower:]' '[:upper:]')
```

### §3.3 `[[ ]]` — Conditional Tests

```bash
# ALWAYS double brackets
if [[ -z "${val}" || "${val}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "..."
fi

# NEVER single brackets for non-trivial conditions
# WRONG: if [ -z "${val}" -o "${val}" == "null" ]
```

## §4 SQL: `( )` for Functions, `' '` for Strings

```sql
-- CORRECT
SELECT ontosql.search_objects(
    'query text here',
    'graph_name',
    NULL,
    10,
    NULL
);

-- WRONG patterns:
-- 1. Double quotes for strings: "query text here"
-- 2. Curly braces for function args: func{'val', 1}
-- 3. Square brackets for args: func['val', 1]
```

## §5 Cross-Context Consistency Checklist

When generating code that spans multiple contexts (bash script that generates SQL and outputs JSON):

| Check | Context |
|-------|---------|
| `{ }` balance in all JSON strings | JSON |
| `' '` single quotes for all SQL string literals | SQL |
| `[[ ]]` for all bash conditionals | Bash |
| `"${VAR}"` braces for all bash variable expansions | Bash |
| No trailing commas in JSON arrays | JSON |
| No `' '` single quotes in JSON keys/values | JSON |
| All JSON output ends with complete `}` or `]` | JSON |

## §6 Quick Reference Card

```
JSON:   {"key": "val", "arr": [1, 2]}    ← double quotes, { } objects, [ ] arrays
Bash:   "${VAR}", arr=(), [[ test ]]      ← { } for vars, ( ) for arrays, [[ ]] for tests
SQL:    func('str', 1);                   ← ( ) for funcs, ' ' for strings
```

**If in doubt: retrieve this document.** It is the authoritative source for brace/bracket rules across all OntoSQL contexts.