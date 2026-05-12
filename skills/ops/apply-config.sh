#!/usr/bin/env bash
SKILL_NAME="apply-config"
SKILL_CATEGORY="ops"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
require_pg
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

config_file=$(json_get "config_file" "${ONTOSQL_ROOT}/config/postgresql.template.sql")
dry_run=$(json_get "dry_run" "false")

if [[ ! -f "${config_file}" ]]; then
    die_client "ERR_INPUT_INVALID" "Config file not found: ${config_file}"
fi

params_applied=$(grep -c '^[A-Z]' "${config_file}" 2>/dev/null || echo 0)

if [[ "${dry_run}" == "true" ]]; then
    ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
    output_success "apply-config" "${ELAPSED}" "{\"dry_run\":true,\"params_to_apply\":${params_applied},\"config_file\":\"${config_file}\"}"
    exit 0
fi

"${PSQL_CMD[@]}" -f "${config_file}" 2>&1 || die_server "ERR_CONFIG_FAILED" "Failed to apply config"

"${PSQL_CMD[@]}" -c "SELECT pg_reload_conf();" > /dev/null 2>&1 || true

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "apply-config" "${ELAPSED}" "{\"params_applied\":${params_applied},\"needs_reload\":false,\"config_file\":\"${config_file}\"}"