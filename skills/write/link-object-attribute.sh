#!/usr/bin/env bash
SKILL_NAME="link-object-attribute"
SKILL_CATEGORY="write"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

graph_name=$(json_get "graph_name" "")
object_vertex_id=$(json_get "object_vertex_id" "")
attr_id=$(json_get "attr_id" "")
relation_type=$(json_get "relation_type" "HAS_ATTRIBUTE")
confidence=$(json_get "confidence" "1.0")

for field in graph_name object_vertex_id attr_id; do
    val=$(json_get_raw "${field}" "")
    if [[ -z "${val}" || "${val}" == "null" ]]; then
        die_client "ERR_INPUT_EMPTY" "${field} is required"
    fi
done
validate_graph_name "${graph_name}"

sql="SELECT ontosql.link_object_attribute(
    '${graph_name}', ${object_vertex_id}, ${attr_id},
    '${relation_type}', ${confidence}
);"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_WRITE_FAILED" "link_object_attribute failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "link-object-attribute" "${ELAPSED}" '{"linked":true,"object_vertex_id":'"${object_vertex_id}"',"attr_id":'"${attr_id}"',"relation_type":"'"${relation_type}"'"}'