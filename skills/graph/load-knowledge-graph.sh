#!/usr/bin/env bash
SKILL_NAME="load-knowledge-graph"
SKILL_CATEGORY="graph"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

graph_name=$(json_get "graph_name" "ontosql_graph")
drop_existing=$(json_get "drop_existing" "false")
validate_graph_name "${graph_name}"

if [[ "${drop_existing}" == "true" ]]; then
    "${PSQL_CMD[@]}" -c "SELECT ag_catalog.drop_graph('${graph_name}', true);" 2>/dev/null || true
fi

result=$("${PSQL_CMD[@]}" -f "${ONTOSQL_ROOT}/sql/002_knowledge_graph.sql" 2>&1)

v_count=$("${PSQL_CMD[@]}" -c "SELECT count(*) FROM ag_catalog.ag_label WHERE graph_name='${graph_name}';" 2>/dev/null | tr -d ' \n' || echo 0)

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "load-knowledge-graph" "${ELAPSED}" '{"graph_name":"'"${graph_name}"'","label_count":'"${v_count}"'}'