#!/usr/bin/env bash
SKILL_NAME="start"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
wait_flag=$(json_get "wait" "true")

if pg_is_available; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_success "start" "${ELAPSED}" '{"port":'"${PG_PORT}"',"extensions":["vector","age"],"action":"already_running"}'
    exit 0
fi

"${PG_HOME}/bin/pg_ctl" -D "${PG_DATA:-${ONTOSQL_ROOT}/build/data}" -l "${PG_DATA:-${ONTOSQL_ROOT}/build/data}/pg.log" start > /dev/null 2>&1 || die_server "ERR_START_FAILED" "pg_ctl start failed"

sleep 2

if [[ "${wait_flag}" == "true" ]]; then
    for i in $(seq 1 30); do
        if pg_is_available; then break; fi
        sleep 1
    done
fi

"${PSQL_CMD[@]}" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || true
"${PSQL_CMD[@]}" -c "CREATE EXTENSION IF NOT EXISTS age;" 2>/dev/null || true

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "start" "${ELAPSED}" '{"port":'"${PG_PORT}"',"extensions":["vector","age"],"action":"started"}'