#!/usr/bin/env bash
SKILL_NAME="search-objects"
SKILL_CATEGORY="query"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

query_text=$(json_get_raw "query_text" "")
graph_name=$(json_get "graph_name" "ontosql_graph")
label=$(json_get_raw "label" "null")
top_k=$(json_get "top_k" "10")
query_embedding_raw=$(json_get_raw "query_embedding" "null")

validate_query_text "${query_text}"
validate_graph_name "${graph_name}"

label_param="NULL"
if [[ -n "${label}" && "${label}" != "null" ]]; then
    label_param="'${label//\'/\'\'}'"
fi

embedding_param="NULL"
if [[ "${query_embedding_raw}" != "null" && -n "${query_embedding_raw}" ]]; then
    embedding_param="'${query_embedding_raw}'::vector(1536)"
fi

sql="SELECT json_agg(row_to_json(t)) FROM (
    SELECT vertex_id, vertex_name, label_name,
           round(vector_score::numeric, 4) as vector_score,
           round(trigram_score::numeric, 4) as trigram_score,
           round(combined_score::numeric, 4) as combined_score
    FROM ontosql.search_objects(
        '${query_text//\'/\'\'}',
        '${graph_name}',
        ${label_param},
        ${top_k},
        ${embedding_param}
    )
) t;"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || {
    err_msg=$(echo "${result}" | head -1)
    die_server "ERR_QUERY_FAILED" "search_objects query failed" "{\"sql_error\":$(python3 -c "import sys,json; print(json.dumps('${err_msg//\'/\'\'}'))" 2>/dev/null || echo '""')}"
}

rows=$(echo "${result}" | python3 -c "
import sys,json
raw = sys.stdin.read().strip()
data = json.loads(raw) if raw and raw != 'NULL' else []
print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null || echo 0)

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
data=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(json.dumps(d))" 2>/dev/null || echo '[]')
output_success "search-objects" "${ELAPSED}" '{"results":'"${data}"',"count":'"${rows}"'}'