#!/usr/bin/env bash
SKILL_NAME="find-objects-by-attribute"
SKILL_CATEGORY="query"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

attr_id=$(json_get "attr_id" "")
graph_name=$(json_get "graph_name" "ontosql_graph")
top_k=$(json_get "top_k" "20")

if [[ -z "${attr_id}" || "${attr_id}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "attr_id is required"
fi
validate_graph_name "${graph_name}"

sql="SELECT json_agg(row_to_json(t)) FROM (
    SELECT object_vertex_id, object_name, object_label, relation_type
    FROM ontosql.find_objects_by_attribute(
        ${attr_id},
        '${graph_name}',
        ${top_k}
    )
) t;"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_QUERY_FAILED" "find_objects_by_attribute query failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

rows=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
data=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(json.dumps(d))" 2>/dev/null || echo '[]')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "find-objects-by-attribute" "${ELAPSED}" '{"results":'"${data}"',"count":'"${rows}"'}'