# Input Schema Format Convention
> Tier 3 Retrieval Document | ≤2000 tokens | id: input_schema_format
>
> This document governs JSON input parameter formatting for all OntoSQL Skills.
> Applies to: query, write, graph category scripts.

## §1 Standard Input Envelope

ALL Skills accept input in exactly these three forms:

```bash
# Form A: --input flag (highest priority)
./ontosql search-objects --input '{"query_text":"sales","graph_name":"ontosql_graph"}'

# Form B: --file flag
./ontosql search-object-attribute --file /path/to/input.json

# Form C: stdin pipe (lowest priority)
echo '{"query_text":"sales"}' | ./ontosql search-objects
```

Priority: `--input` > `--file` > `stdin`. Later forms are ignored if an earlier form is present.

## §2 Parameter Categories

| Category | Shell Type | Validation | Example |
|----------|-----------|------------|---------|
| required_text | string, validated | `validate_query_text()` | `query_text` |
| required_name | string, validated | `validate_graph_name()` | `graph_name` |
| required_int | integer | presence check | `vertex_id`, `attr_id` |
| optional_raw | string, nullable | null check only | `label`, `description` |
| optional_int | integer, default | presence → range check | `top_k` (default 10) |

## §3 Required Parameter Pattern

```bash
val=$(json_get_raw "KEY" "")

# Type 1: required non-null value
if [[ -z "${val}" || "${val}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "KEY is required"
fi

# Type 2: required + regex validation
validate_graph_name "${val}"

# Type 3: required + range validation
# (range enforced by SQL function validate_top_k)
```

## §4 Optional Parameter with Default

```bash
# Default value when absent
val=$(json_get "KEY" "DEFAULT_VALUE")

# Usage: null-aware branching
label_param="NULL"
if [[ -n "${val}" && "${val}" != "null" ]]; then
    label_param="'${val//\'/\'\'}'"
fi
```

## §5 Array and Object Parameters

### Array (JSON array → SQL ARRAY)

```bash
aliases_raw=$(json_get_raw "aliases" "null")

alias_param="NULL"
if [[ -n "${aliases_raw}" && "${aliases_raw}" != "null" ]]; then
    # Convert JSON array to PostgreSQL ARRAY[...]
    alias_param="ARRAY[$(echo "${aliases_raw}" | \
        python3 -c "import sys,json; a=json.loads(sys.stdin.read()); \
        print(','.join(\"'\"+x+\"'\" for x in a))" 2>/dev/null)]"
fi
```

### Object (JSON object → JSONB)

```bash
metadata_raw=$(json_get_raw "metadata" "null")

meta_param="'{}'::jsonb"
if [[ -n "${metadata_raw}" && "${metadata_raw}" != "null" ]]; then
    meta_param="'${metadata_raw}'::jsonb"
fi
```

## §6 Brace/Bracket in Parameter Values

### §6.1 Object parameters: `{ }` curly braces

```json
// CORRECT
{"metadata": {"business_table": "order_records", "join_key": "user_id"}}

// WRONG — bare key-value without object wrapper
{"metadata": "business_table=order_records, join_key=user_id"}
```

### §6.2 Array parameters: `[ ]` square brackets

```json
// CORRECT
{"aliases": ["销售额", "revenue", "sales_amount"]}

// WRONG — comma-separated string
{"aliases": "销售额, revenue, sales_amount"}

// WRONG — curly braces (PostgreSQL native array syntax)
{"aliases": "{销售额, revenue, sales_amount}"}
```

## §7 Multi-field Required Check

When multiple fields must all be present:

```bash
for field in graph_name object_vertex_id attr_id; do
    val=$(json_get_raw "${field}" "")
    if [[ -z "${val}" || "${val}" == "null" ]]; then
        die_client "ERR_INPUT_EMPTY" "${field} is required"
    fi
done
```

NEVER collapse multi-field checks into one message. Each missing field gets its own error.