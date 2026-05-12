#!/usr/bin/env bash
SKILL_NAME="get-object-attributes"
SKILL_CATEGORY="query"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

object_vertex_id=$(json_get "object_vertex_id" "")
graph_name=$(json_get "graph_name" "default")

if [[ -z "${object_vertex_id}" || "${object_vertex_id}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "object_vertex_id is required"
fi
validate_graph_name "${graph_name}"

sql="SELECT json_agg(row_to_json(t)) FROM (
    SELECT attr_id, attr_name, COALESCE(data_type,'unknown') as data_type,
           COALESCE(description,'') as description,
           relation_type,
           round(confidence::numeric, 4) as confidence
    FROM ontosql.get_object_attributes(
        ${object_vertex_id},
        '${graph_name}'
    )
) t;"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_QUERY_FAILED" "get_object_attributes query failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

rows=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
data=$(echo "${result}" | python3 -c "import sys,json; raw=sys.stdin.read().strip(); d=json.loads(raw) if raw and raw!='NULL' else []; print(json.dumps(d))" 2>/dev/null || echo '[]')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "get-object-attributes" "${ELAPSED}" '{"results":'"${data}"',"count":'"${rows}"'}'