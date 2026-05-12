#!/usr/bin/env bash
SKILL_NAME="status"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

if ! pg_is_available; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_success "status" "${ELAPSED}" '{"running":false,"port":'"${PG_PORT}"',"uptime_seconds":0}'
    exit 0
fi

uptime=$("${PSQL_CMD[@]}" -c "SELECT extract(epoch from now() - pg_postmaster_start_time())::int;" 2>/dev/null | tr -d ' ')

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "status" "${ELAPSED}" '{"running":true,"port":'"${PG_PORT}"',"uptime_seconds":'"$(echo "${uptime:-0}" | head -1)"'}'