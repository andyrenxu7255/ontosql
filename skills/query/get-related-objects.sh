#!/usr/bin/env bash
SKILL_NAME="get-related-objects"
SKILL_CATEGORY="query"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

vertex_id=$(json_get "vertex_id" "")
graph_name=$(json_get "graph_name" "ontosql_graph")
relation_type_raw=$(json_get_raw "relation_type" "null")

if [[ -z "${vertex_id}" || "${vertex_id}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "vertex_id is required"
fi
validate_graph_name "${graph_name}"

rel_param="NULL"
if [[ -n "${relation_type_raw}" && "${relation_type_raw}" != "null" ]]; then
    rel_param="'${relation_type_raw}'"
fi

sql="SELECT json_agg(row_to_json(t)) FROM (
    SELECT related_vertex_id, related_name, related_label, relation_type
    FROM ontosql.get_related_objects(
        ${vertex_id},
        '${graph_name}',
        ${rel_param}
    )
) t;"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_QUERY_FAILED" "get_related_objects query failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

rows=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
data=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(json.dumps(d))" 2>/dev/null || echo '[]')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "get-related-objects" "${ELAPSED}" '{"results":'"${data}"',"count":'"${rows}"'}'