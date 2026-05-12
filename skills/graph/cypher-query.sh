#!/usr/bin/env bash
SKILL_NAME="cypher-query"
SKILL_CATEGORY="graph"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

graph_name=$(json_get "graph_name" "")
cypher=$(json_get_raw "cypher" "")

if [[ -z "${graph_name}" || "${graph_name}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "graph_name is required"
fi
if [[ -z "${cypher}" || "${cypher}" == "null" ]]; then
    die_client "ERR_INPUT_EMPTY" "cypher is required"
fi
validate_graph_name "${graph_name}"

sql="SET search_path = ag_catalog, ontosql;
SELECT * FROM cypher('${graph_name}', \$\$${cypher}\$\$) AS (result agtype);"

result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || die_server "ERR_CYPHER_FAILED" "Cypher query failed" "{\"sql_error\":\"$(echo "${result}" | head -1 | sed 's/"/\\"/g')\"}"

data=$(echo "${result}" | python3 -c "
import sys,json
lines = [l.strip() for l in sys.stdin.read().strip().split('\n') if l.strip() and not l.strip().startswith('(')]
data = [{'result': l} for l in lines]
print(json.dumps(data))
" 2>/dev/null || echo '[]')
rows=$(echo "${data}" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(len(d))" 2>/dev/null || echo 0)

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "cypher-query" "${ELAPSED}" '{"results":'"${data}"',"row_count":'"${rows}"'}'