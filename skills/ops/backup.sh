#!/usr/bin/env bash
SKILL_NAME="backup"
SKILL_CATEGORY="ops"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

output_dir=$(json_get "output_dir" "${ONTOSQL_ROOT}/backups")
compress=$(json_get "compress" "true")
timestamp=$(date -u +%Y%m%d_%H%M%S)

mkdir -p "${output_dir}"

backup_file="${output_dir}/ontosql_${timestamp}.sql"
"${PG_HOME}/bin/pg_dump" -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" \
    -n ontosql --no-owner --no-acl -f "${backup_file}" 2>&1 || die_server "ERR_BACKUP_FAILED" "pg_dump failed"

size_bytes=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}" 2>/dev/null || echo 0)

if [[ "${compress}" == "true" ]]; then
    gzip -f "${backup_file}"
    backup_file="${backup_file}.gz"
    size_bytes=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}" 2>/dev/null || echo 0)
fi

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "backup" "${ELAPSED}" '{"backup_file":"'"${backup_file}"'","size_bytes":'"${size_bytes}"',"timestamp":"'"${timestamp}"'"}'