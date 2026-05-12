#!/usr/bin/env bash
SKILL_NAME="upsert-vertex"
SKILL_CATEGORY="write"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

vertex_id=$(json_get "vertex_id" "")
graph_name=$(json_get "graph_name" "")
label_name=$(json_get "label_name" "")
vertex_name=$(json_get "vertex_name" "")
embedding_raw=$(json_get_raw "embedding" "")
description=$(json_get_raw "description" "null")
metadata_raw=$(json_get_raw "metadata" "null")

for field in vertex_id graph_name label_name vertex_name; do
    val=$(json_get_raw "${field}" "")
    if [[ -z "${val}" || "${val}" == "null" ]]; then
        die_client "ERR_INPUT_EMPTY" "${field} is required"
    fi
done

if [[ -z "${embedding_raw}" || "${embedding_raw}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "embedding is required (1536-dim vector)"
fi
validate_graph_name "${graph_name}"

desc_param="NULL"
if [[ -n "${description}" && "${description}" != "null" ]]; then
    desc_param="'${description//\'/\'\'}'"
fi

meta_param="'{}'::jsonb"
if [[ -n "${metadata_raw}" && "${metadata_raw}" != "null" ]]; then
    meta_param="'${metadata_raw}'::jsonb"
fi

sql="SELECT ontosql.upsert_vertex_embedding(
    ${vertex_id}, '${graph_name}', '${label_name}',
    '${vertex_name}', '${embedding_raw}'::vector,
    ${desc_param}, ${meta_param}
);"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_WRITE_FAILED" "upsert_vertex_embedding failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "upsert-vertex" "${ELAPSED}" '{"vertex_id":'"${vertex_id}"',"vertex_name":"'"${vertex_name}"'","graph_name":"'"${graph_name}"'"}'