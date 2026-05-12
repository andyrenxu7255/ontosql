#!/usr/bin/env bash
SKILL_NAME="stop"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
mode=$(json_get "mode" "smart")

if ! pg_is_available; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_success "stop" "${ELAPSED}" '{"stopped":true,"action":"already_stopped"}'
    exit 0
fi

"${PG_HOME}/bin/pg_ctl" -D "${PG_DATA:-${ONTOSQL_ROOT}/build/data}" stop -m "${mode}" 2>/dev/null || true

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "stop" "${ELAPSED}" '{"stopped":true,"mode":"'"${mode}"'","action":"stopped"}'