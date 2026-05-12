#!/usr/bin/env bash
SKILL_NAME="upsert-attribute"
SKILL_CATEGORY="write"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

attr_name=$(json_get_raw "attr_name" "")
graph_name=$(json_get "graph_name" "")
embedding_raw=$(json_get_raw "embedding" "")
attr_vertex_id=$(json_get_raw "attr_vertex_id" "null")
aliases_raw=$(json_get_raw "aliases" "null")
description=$(json_get_raw "description" "null")
data_type=$(json_get_raw "data_type" "null")

if [[ -z "${attr_name}" || "${attr_name}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "attr_name is required"
fi
if [[ -z "${graph_name}" || "${graph_name}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "graph_name is required"
fi
if [[ -z "${embedding_raw}" || "${embedding_raw}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "embedding is required (1536-dim vector)"
fi
validate_graph_name "${graph_name}"

vid_param="NULL"
[[ -n "${attr_vertex_id}" && "${attr_vertex_id}" != "null" ]] && vid_param="${attr_vertex_id}"

alias_param="NULL"
[[ -n "${aliases_raw}" && "${aliases_raw}" != "null" ]] && alias_param="ARRAY[$(echo "${aliases_raw}" | python3 -c "import sys,json; a=json.loads(sys.stdin.read()); print(','.join(\"'\"+x+\"'\" for x in a))" 2>/dev/null)]"

desc_param="NULL"
[[ -n "${description}" && "${description}" != "null" ]] && desc_param="'${description//\'/\'\'}'"

dtype_param="NULL"
[[ -n "${data_type}" && "${data_type}" != "null" ]] && dtype_param="'${data_type}'"

sql="SELECT ontosql.upsert_attribute_embedding(
    '${attr_name//\'/\'\'}', '${graph_name}',
    '${embedding_raw}'::vector,
    ${vid_param}, ${alias_param}, ${desc_param}, ${dtype_param}
);"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_WRITE_FAILED" "upsert_attribute_embedding failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

attr_id=$(echo "${result}" | tr -d ' \n')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "upsert-attribute" "${ELAPSED}" '{"attr_id":'"${attr_id}"',"attr_name":"'"${attr_name}"'","graph_name":"'"${graph_name}"'"}'