#!/usr/bin/env bash
SKILL_NAME="health-check"
SKILL_CATEGORY="ops"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

if ! pg_is_available; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_error "health-check" "ERR_PG_UNREACHABLE" "PostgreSQL not reachable" "${ELAPSED}" '{"pg_ready":false}'
    exit 2
fi

ext_vector=$("${PSQL_CMD[@]}" -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='vector');" 2>/dev/null | tr -d ' \n')
ext_age=$("${PSQL_CMD[@]}" -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='age');" 2>/dev/null | tr -d ' \n')
ext_trgm=$("${PSQL_CMD[@]}" -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_trgm');" 2>/dev/null | tr -d ' \n')

latency_start=$(python3 -c 'import time; print(int(time.time()*1_000_000))')
"${PSQL_CMD[@]}" -c "SELECT 1 AS health_ping;" > /dev/null 2>&1
latency_ms=$(python3 -c "import time; print(int((time.time()*1_000_000 - ${latency_start}) // 1000))")

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "health-check" "${ELAPSED}" "{\"pg_ready\":true,\"extensions\":{\"vector\":${ext_vector},\"age\":${ext_age},\"pg_trgm\":${ext_trgm}},\"query_latency_ms\":${latency_ms}}"