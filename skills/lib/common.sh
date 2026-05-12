#!/usr/bin/env bash
# ============================================================================
# OntoSQL Skill Shared Library
# ============================================================================
# Provides JSON output helpers, error handling, and DB connection utilities
# for all Agent-oriented Skills. Designed for machine consumption.
# ============================================================================
set -euo pipefail

# ----------------------------------------------------------------------------
# 0. Environment Resolution
# ----------------------------------------------------------------------------
ONTOSQL_ROOT="${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
PG_HOME="${PG_HOME:-${ONTOSQL_ROOT}/build/pgsql17}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-$(whoami)}"
PG_DB="${PG_DB:-postgres}"
PG_HOST="${PG_HOST:-localhost}"
PG_PASSWORD="${PG_PASSWORD:-}"

PSQL_CMD=("${PG_HOME}/bin/psql" -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" -X -q -t -A)

# Add password if set
if [[ -n "${PG_PASSWORD}" ]]; then
    export PGPASSWORD="${PG_PASSWORD}"
fi

# ----------------------------------------------------------------------------
# 1. JSON Output Helpers
# ----------------------------------------------------------------------------

# Output a successful response
output_success() {
    local skill="${1:-unknown}"
    local elapsed_ms="${2:-0}"
    local data="${3:-{}}"
    cat <<EOF
{"status":"success","skill":"${skill}","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","data":${data},"meta":{"elapsed_ms":${elapsed_ms}}}
EOF
}

# Output an error response
output_error() {
    local skill="${1:-unknown}"
    local err_code="${2:-ERR_UNKNOWN}"
    local err_message="${3:-An unknown error occurred}"
    local elapsed_ms="${4:-0}"
    local details="${5:-{}}"
    cat <<EOF
{"status":"error","skill":"${skill}","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","error":{"code":"${err_code}","message":"${err_message}","details":${details}},"meta":{"elapsed_ms":${elapsed_ms}}}
EOF
}

# ----------------------------------------------------------------------------
# 2. Error Handlers
# ----------------------------------------------------------------------------

die_client()     { output_error "${SKILL_NAME}" "$1" "$2" 0 "${3:-{}}"; exit 1; }
die_server()     { output_error "${SKILL_NAME}" "$1" "$2" 0 "${3:-{}}"; exit 2; }
die_config()     { output_error "${SKILL_NAME}" "$1" "$2" 0 "${3:-{}}"; exit 3; }

# ----------------------------------------------------------------------------
# 3. Input Parsing
# ----------------------------------------------------------------------------

# Parse --input or --file from command line. Sets INPUT_JSON variable.
parse_input() {
    INPUT_JSON="{}"
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input) INPUT_JSON="${2:-}"; shift 2 ;;
            --file)  INPUT_JSON="$(<"${2}")"; shift 2 ;;
            --format) shift 2 ;;  # consumed for compatibility
            *)       positional+=("$1"); shift ;;
        esac
    done
    set -- "${positional[@]}"

    # If stdin is not a terminal and no explicit input, read from stdin
    if [[ "${INPUT_JSON}" == "{}" ]] && [[ ! -t 0 ]]; then
        INPUT_JSON="$(cat)"
    fi
}

# Extract a field from INPUT_JSON using python3 (available on macOS)
json_get() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(echo "${INPUT_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(json.dumps(d.get('${key}', ${default})))
except:
    print(json.dumps(${default}))
" 2>/dev/null)
    # Unwrap JSON string
    val=$(echo "${val}" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()))" 2>/dev/null || echo "${val}")
    echo "${val}"
}

json_get_raw() {
    local key="$1"
    local default="${2:-null}"
    echo "${INPUT_JSON}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('${key}', ${default})
    if isinstance(v, str):
        print(v)
    else:
        print(json.dumps(v))
except:
    print('')
" 2>/dev/null
}

# ----------------------------------------------------------------------------
# 4. Validation
# ----------------------------------------------------------------------------

validate_required() {
    local key="$1"
    local val
    val=$(json_get_raw "${key}" "null")
    if [[ -z "${val}" || "${val}" == "null" ]]; then
        die_client "ERR_INPUT_EMPTY" "Required parameter '${key}' is missing or empty"
    fi
}

validate_graph_name() {
    local name="$1"
    if [[ ! "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        die_client "ERR_INPUT_INVALID" "graph_name contains invalid characters: ${name}" "{\"field\":\"graph_name\",\"value\":\"${name}\"}"
    fi
    if [[ ${#name} -gt 63 ]]; then
        die_client "ERR_INPUT_TOO_LONG" "graph_name exceeds 63 characters" "{\"field\":\"graph_name\",\"length\":${#name}}"
    fi
}

validate_query_text() {
    local text="$1"
    if [[ -z "${text}" ]]; then
        die_client "ERR_INPUT_EMPTY" "query_text is required"
    fi
    if [[ ${#text} -gt 1000 ]]; then
        die_client "ERR_INPUT_TOO_LONG" "query_text exceeds 1000 characters" "{\"field\":\"query_text\",\"length\":${#text}}"
    fi
}

# ----------------------------------------------------------------------------
# 5. Database Helpers
# ----------------------------------------------------------------------------

# Execute a SQL query and capture JSON output
db_query_json() {
    local sql="$1"
    local skill_name="${SKILL_NAME:-unknown}"
    local result
    result=$("${PSQL_CMD[@]}" -c "${sql}" 2>&1) || {
        die_server "ERR_PG_UNREACHABLE" "Database query failed" "{\"sql_error\":$(echo "${result}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null || echo '""')}"
    }
    echo "${result}"
}

# Check if PG is reachable
pg_is_available() {
    "${PG_HOME}/bin/pg_isready" -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DB}" -q 2>/dev/null
}

# Require PG availability
require_pg() {
    if ! pg_is_available; then
        die_server "ERR_PG_UNREACHABLE" "PostgreSQL is not available at ${PG_HOST}:${PG_PORT}"
    fi
}

# ----------------------------------------------------------------------------
# 6. Skill Introspection
# ----------------------------------------------------------------------------

# Print skill metadata for --help or info commands
print_skill_help() {
    local name="$1"
    local desc="$2"
    local category="$3"
    local input_schema="$4"
    cat <<EOF
Skill: ${name}
Category: ${category}
Description: ${desc}
Input: ${input_schema}
Output: {"status":"success|error","data":{...},"error":{"code":"...","message":"..."}}
EOF
}