#!/usr/bin/env bash
SKILL_NAME="search-object-attribute"
SKILL_CATEGORY="query"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

query_text=$(json_get_raw "query_text" "")
graph_name=$(json_get "graph_name" "default")
top_k=$(json_get "top_k" "10")
query_embedding_raw=$(json_get_raw "query_embedding" "null")

validate_query_text "${query_text}"
validate_graph_name "${graph_name}"

embedding_param="NULL"
if [[ "${query_embedding_raw}" != "null" && -n "${query_embedding_raw}" ]]; then
    embedding_param="'${query_embedding_raw}'::vector(1536)"
fi

sql="SELECT json_agg(row_to_json(t)) FROM (
    SELECT object_name, attr_name,
           round(combined_score::numeric, 4) as combined_score,
           is_verified
    FROM ontosql.search_object_attribute(
        '${query_text//\'/\'\'}',
        '${graph_name}',
        ${top_k},
        ${embedding_param}
    )
) t;"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_QUERY_FAILED" "search_object_attribute query failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

rows=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
data=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(json.dumps(d))" 2>/dev/null || echo '[]')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "search-object-attribute" "${ELAPSED}" '{"results":'"${data}"',"count":'"${rows}"'}'