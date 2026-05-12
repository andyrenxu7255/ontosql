#!/usr/bin/env bash
SKILL_NAME="clean"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
keep_data=$(json_get "keep_data" "false")

"${PG_HOME}/bin/pg_ctl" -D "${PG_DATA:-${ONTOSQL_ROOT}/build/data}" stop 2>/dev/null || true

make -C "${ONTOSQL_ROOT}/upstream/postgresql" clean 2>/dev/null || true
make -C "${ONTOSQL_ROOT}/upstream/pgvector" clean 2>/dev/null || true
make -C "${ONTOSQL_ROOT}/upstream/age" clean 2>/dev/null || true
rm -rf "${PG_HOME}"

if [[ "${keep_data}" != "true" ]]; then
    rm -rf "${PG_DATA:-${ONTOSQL_ROOT}/build/data}"
fi

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "clean" "${ELAPSED}" '{"cleaned":["build/pgsql17/","'"${PG_DATA:-${ONTOSQL_ROOT}/build/data}"'"],"keep_data":'"${keep_data}"'}'