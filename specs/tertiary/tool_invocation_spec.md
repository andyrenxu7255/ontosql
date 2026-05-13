# OntoSQL Tool Invocation Specification
> Tier 3 Retrieval Document | ≤2000 tokens | id: tool_invocation_spec
>
> This document specifies ALL preconditions, environment variables, and
> invocation contracts for the `ontosql` CLI and its Skill scripts.

## §1 Pre-Flight Requirements

Before ANY Skill invocation, the following must be satisfied:

### §1.1 Filesystem

| Checklist Item | Verification |
|---------------|-------------|
| Project root exists | `[[ -d "${ONTOSQL_ROOT}" ]]` |
| CLI entry is executable | `[[ -x "${ONTOSQL_ROOT}/ontosql" ]]` |
| Shared library is readable | `[[ -r "${ONTOSQL_ROOT}/skills/lib/common.sh" ]]` |
| manifest.json is valid JSON | `python3 -c "import json; json.load(open('${ONTOSQL_ROOT}/skills/manifest.json'))"` |

### §1.2 Runtime Dependencies

| Dependency | Version Check | Required By |
|-----------|--------------|-------------|
| `bash` | ≥4.0 (for associative arrays) | All Skills |
| `python3` | ≥3.8 (for `json` module) | Input parsing, timing, json_agg processing |
| `psql` (PG client) | 17.x (must match server) | Query/Write Skills |
| `pg_isready` | 17.x | Lifecycle Skills |
| `pg_ctl` | 17.x | Lifecycle Skills |
| `pg_dump` | 17.x | backup Skill |
| `make` | ≥4.0 | build Skill |

### §1.3 Database Availability (Precondition Matrix)

| Skill Category | PG Required? | Behavior if PG Unavailable |
|---------------|-------------|---------------------------|
| lifecycle (except start/status) | No | Proceeds normally (build, clean, init-db, stop are PG-independent) |
| lifecycle: start | No | Attempts to start PG; errors only if pg_ctl fails |
| lifecycle: status | No | Reports `running: false` if pg_isready fails |
| query | YES | `die_server "ERR_PG_UNREACHABLE"` |
| write | YES | `die_server "ERR_PG_UNREACHABLE"` |
| ops: health-check | Optional | Reports `pg_ready: false` in data |
| ops: backup | YES | `die_server "ERR_PG_UNREACHABLE"` |
| ops: apply-config | YES | `die_server "ERR_PG_UNREACHABLE"` |
| graph | YES | `die_server "ERR_PG_UNREACHABLE"` |

## §2 Environment Variable Reference

### §2.1 Required (with defaults from [common.sh](file:///Users/liuruiqi/ontosql/skills/lib/common.sh))

| Variable | Default Value | Description | Required By |
|----------|--------------|-------------|-------------|
| `ONTOSQL_ROOT` | `$(cd "$(dirname "$0")/../.." && pwd)` | Project root directory | ALL Skills (auto-resolved) |
| `PG_HOME` | `${ONTOSQL_ROOT}/build/pgsql17` | PG installation prefix | Lifecycle, query, write, ops, graph |
| `PG_DATA` | `${ONTOSQL_ROOT}/build/data` | PG data directory | lifecycle (init-db, start, stop, clean) |

### §2.2 Connection Variables

| Variable | Default | Source Lines | Description |
|----------|---------|-------------|-------------|
| `PG_HOST` | `localhost` | [common.sh:L18](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L18) | Database host (unix socket uses localhost) |
| `PG_PORT` | `5432` | [common.sh:L17](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L17) | Database port |
| `PG_USER` | `$(whoami)` | [common.sh:L19](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L19) | Database user |
| `PG_DB` | `postgres` | [common.sh:L20](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L20) | Target database |
| `PG_PASSWORD` | *(empty)* | [common.sh:L22](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L22) | Password (sets `PGPASSWORD` env if non-empty) |
| `PGPASSWORD` | auto-set from PG_PASSWORD | [common.sh:L25-L27](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L25-L27) | PostgreSQL password (libpq convention) |

### §2.3 Docker Overrides

When used via `docker-compose`, these variables override:

| Variable | Docker Default | Notes |
|----------|---------------|-------|
| `POSTGRES_PASSWORD` | *(required, no default)* | Maps to PG_PASSWORD, mandatory per compose `?:err` syntax |
| `PG_PORT` | `5432` | Exposed host port |
| `PGBOUNCER_AUTH_TYPE` | `scram-sha-256` | PgBouncer auth method |

## §3 Invocation Contract

### §3.1 Standard Invocation Forms

```bash
# Form A: inline JSON input (highest priority)
./ontosql search-objects --input '{"query_text":"sales","graph_name":"ontosql_graph"}'

# Form B: file input
./ontosql upsert-vertex --file /path/to/vertex_input.json

# Form C: stdin pipe (lowest priority)
echo '{"query_text":"revenue"}' | ./ontosql search-attributes

# Form D: minimal (parameters with defaults only)
./ontosql status
```

Priority: `--input` > `--file` > `stdin`. The `parse_input` function in [common.sh:L44-L61](file:///Users/liuruiqi/ontosql/skills/lib/common.sh#L44-L61) resolves this.

### §3.2 Stdout Contract

ALL Skills write exactly ONE JSON object to stdout. No other output.

```json
// Success
{"status":"success","skill":"<name>","timestamp":"...","data":{...},"meta":{"elapsed_ms":42}}

// Error
{"status":"error","skill":"<name>","timestamp":"...","error":{"code":"ERR_...","message":"...","details":{...}},"meta":{"elapsed_ms":42}}
```

### §3.3 Stderr Contract

Stderr is used for diagnostic/progress messages ONLY during `build` and `init-db` Skills. All other Skills suppress stderr via `2>/dev/null` or redirect to error.details.

### §3.4 Exit Code Contract

| Code | Meaning | When |
|------|---------|------|
| 0 | Success | All preconditions met, operation completed |
| 1 | Client error | Invalid input (missing required field, format mismatch, range violation) |
| 2 | Server error | PG unreachable, SQL execution failed, build/init failure |
| 3 | Config error | Missing required env var, invalid config file path |
| 4 | Not found | Skill name not in manifest |

## §4 Signal Handling

| Signal | Handled By | Behavior |
|--------|-----------|----------|
| `SIGINT` (Ctrl+C) | bash `set -e` | Script exits immediately, PG connection closed |
| `SIGTERM` | docker-compose `stop_grace_period` | See execution_constraints.md §5 |
| `SIGPIPE` | bash `pipefail` | If stdout pipe closes early (client disconnect), script exits |
| `SIGUSR1`, `SIGUSR2` | NOT handled | Default behavior (terminate) |

## §5 Minimum Viable Invocation Examples

### Query (no PG needed to check syntax)
```bash
# Only verifies CLI and args — PG must be running for actual results
./ontosql list                          # Discovery (zero PG dependency)
./ontosql info search-objects           # Metadata lookup (zero PG dependency)
```

### Lifecycle (build → init → start → use)
```bash
./ontosql build                                    # Step 1: compile
./ontosql init-db                                  # Step 2: init data dir
./ontosql start --input '{"wait":true}'            # Step 3: start PG
./ontosql load-knowledge-graph                     # Step 4: load sample graph
echo '{"query_text":"销售额"}' | ./ontosql search-object-attribute  # Step 5: query
```

### Write (PG must be running)
```bash
./ontosql upsert-vertex --file vertex.json   # vertex.json contains required fields
./ontosql upsert-attribute --file attr.json  # attr.json contains required fields
echo '{"graph_name":"ontosql_graph","object_vertex_id":42,"attr_id":7}' | \
  ./ontosql link-object-attribute
```