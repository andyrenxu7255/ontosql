#!/usr/bin/env bash
SKILL_NAME="init-db"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
force=$(json_get "force" "false")
encoding=$(json_get "encoding" "UTF8")
locale=$(json_get "locale" "C.UTF-8")

if [[ -d "${PG_DATA:-${ONTOSQL_ROOT}/build/data}" ]] && [[ "${force}" != "true" ]]; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_success "init-db" "${ELAPSED}" '{"data_directory":"'"${PG_DATA:-${ONTOSQL_ROOT}/build/data}"'","action":"skipped","reason":"already exists"}'
    exit 0
fi

rm -rf "${PG_DATA:-${ONTOSQL_ROOT}/build/data}"
"${PG_HOME}/bin/initdb" -D "${PG_DATA:-${ONTOSQL_ROOT}/build/data}" --encoding="${encoding}" --locale="${locale}" --auth=scram-sha-256 > /dev/null 2>&1 || die_server "ERR_INITDB_FAILED" "initdb failed"

cat >> "${PG_DATA:-${ONTOSQL_ROOT}/build/data}/postgresql.conf" <<'PGCONF'
listen_addresses = '*'
shared_buffers = 256MB
work_mem = 16MB
port = 5432
statement_timeout = 30000
PGCONF

printf 'local   all             all                                     peer\nhost    all             all             0.0.0.0/0               scram-sha-256\nhost    all             all             ::/128                  scram-sha-256\n' > "${PG_DATA:-${ONTOSQL_ROOT}/build/data}/pg_hba.conf"

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "init-db" "${ELAPSED}" '{"data_directory":"'"${PG_DATA:-${ONTOSQL_ROOT}/build/data}"'","action":"initialized","encoding":"'"${encoding}"'","locale":"'"${locale}"'"}'