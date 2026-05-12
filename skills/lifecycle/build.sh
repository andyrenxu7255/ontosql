#!/usr/bin/env bash
SKILL_NAME="build"
SKILL_CATEGORY="lifecycle"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"

START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

clean_first=$(json_get "clean_first" "false")
parallel_jobs=$(json_get "parallel_jobs" "0")

if [[ "${parallel_jobs}" == "0" || -z "${parallel_jobs}" ]]; then
    parallel_jobs=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
fi

if [[ "${clean_first}" == "true" ]]; then
    "${ONTOSQL_ROOT}/skills/lifecycle/clean.sh" --input '{}' 2>/dev/null || true
fi

echo '{"status":"building","component":"postgresql","progress":"starting"}'
cd "${ONTOSQL_ROOT}/upstream/postgresql" && \
    ./configure --prefix="${PG_HOME}" \
        --enable-debug --enable-cassert \
        --with-icu --with-lz4 --with-zstd \
        --with-openssl --with-libxml --with-libxslt > /dev/null 2>&1
make -j"${parallel_jobs}" > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "PostgreSQL build failed"
make install > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "PostgreSQL install failed"

echo '{"status":"building","component":"pgvector","progress":"starting"}'
make -C "${ONTOSQL_ROOT}/upstream/pgvector" PG_CONFIG="${PG_CONFIG:-${PG_HOME}/bin/pg_config}" -j4 > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "pgvector build failed"
make -C "${ONTOSQL_ROOT}/upstream/pgvector" PG_CONFIG="${PG_CONFIG:-${PG_HOME}/bin/pg_config}" install > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "pgvector install failed"

echo '{"status":"building","component":"age","progress":"starting"}'
make -C "${ONTOSQL_ROOT}/upstream/age" PG_CONFIG="${PG_CONFIG:-${PG_HOME}/bin/pg_config}" -j4 > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "Apache AGE build failed"
make -C "${ONTOSQL_ROOT}/upstream/age" PG_CONFIG="${PG_CONFIG:-${PG_HOME}/bin/pg_config}" install > /dev/null 2>&1 || die_server "ERR_BUILD_FAILED" "Apache AGE install failed"

cp "${ONTOSQL_ROOT}/sql/"*.sql "${PG_HOME}/share/" 2>/dev/null || true

ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
output_success "build" "${ELAPSED}" '{"components":["postgresql","pgvector","age"],"pg_home":"'"${PG_HOME}"'","parallel_jobs":'"${parallel_jobs}"'}'