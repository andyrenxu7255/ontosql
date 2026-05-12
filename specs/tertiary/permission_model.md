# OntoSQL Permission Model
> Tier 3 Retrieval Document | ≤2000 tokens | id: permission_model
>
> This document defines the four-layer permission model for OntoSQL.
> Agent MUST understand these boundaries before executing privileged operations.

## §1 Permission Layers

```
┌─────────────────────────────────────────────┐
│ Network Layer     │ pg_hba.conf             │
│                   │ scram-sha-256           │
├─────────────────────────────────────────────┤
│ Database Layer    │ PG roles + search_path  │
│                   │ ontosql schema privs    │
├─────────────────────────────────────────────┤
│ Process Layer     │ cap_drop/cap_add        │
│                   │ no-new-privileges       │
├─────────────────────────────────────────────┤
│ Filesystem Layer │ File ownership           │
│                   │ data directory perms    │
└─────────────────────────────────────────────┘
```

## §2 Network Layer: Authentication

### §2.1 pg_hba.conf (from [init-db.sh:L29](file:///Users/liuruiqi/ontosql/skills/lifecycle/init-db.sh#L29))

```
local   all   all               peer
host    all   all   0.0.0.0/0   scram-sha-256
host    all   all   ::/128      scram-sha-256
```

| Connection Type | Auth Method | Notes |
|----------------|-------------|-------|
| Unix socket (local) | `peer` | OS user must match PG role name |
| TCP/IP (IPv4, any host) | `scram-sha-256` | Requires password via `PGPASSWORD` |
| TCP/IP (IPv6, localhost only) | `scram-sha-256` | Same as above |

**Agent implications**: 
- If connecting via Unix socket (default on macOS): OS user must have a matching PG role
- If connecting via TCP (`PG_HOST` ≠ localhost): MUST set `PG_PASSWORD` env var
- Docker: `PG_HOST=localhost` still uses TCP (not Unix socket), so password is REQUIRED

### §2.2 PgBouncer (from [pgbouncer.ini](file:///Users/liuruiqi/ontosql/config/pgbouncer.ini))

| Parameter | Value | Source Lines |
|-----------|-------|-------------|
| `auth_type` | `scram-sha-256` | config/pgbouncer.ini |
| `auth_user` | `true` | config/pgbouncer.ini |
| `pool_mode` | `session` | config/pgbouncer.ini |

## §3 Process Layer: Docker Security

### §3.1 Container Capabilities (from [docker-compose.yml:L55-L61](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L55-L61))

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL         # Drop ALL kernel capabilities
cap_add:
  - CHOWN       # Required: pg_ctl changes data dir ownership on startup
  - DAC_OVERRIDE # Required: access files owned by postgres user (uid 999)
  - SETGID      # Required: pg_ctl setgid to postgres
  - SETUID      # Required: pg_ctl setuid to postgres
```

**Dropped capabilities** (the system runs WITHOUT these):

| Dropped | Risk if Present |
|---------|----------------|
| `SYS_ADMIN` | Container escape |
| `NET_ADMIN` | Network manipulation |
| `SYS_PTRACE` | Process injection |
| `KILL` | Kill host processes |
| `SYS_RAWIO` | Raw disk access |
| All others | Defense-in-depth |

### §3.2 Container Running User

Dockerfile creates `postgres` user (uid 999) at runtime. pg_ctl setuid/setgid to this user. Skills invoked on the **host** (not in container) run as the invoking OS user — they do NOT switch to postgres user.

## §4 Filesystem Layer

### §4.1 Write Permission Matrix

| Path | Write Required By | Owner | Permissions |
|------|------------------|-------|------------|
| `build/pgsql17/` | `build` Skill | Host user | 0755 dirs, 0644 files |
| `build/data/` | `init-db`, `start`, `stop` | `postgres` (PG uid) | 0700 dirs |
| `build/data/pg.log` | `start` | `postgres` (PG uid) | 0600 file |
| `backups/` | `backup` Skill | Host user | 0755 dir |
| `config/postgresql.template.sql` | `apply-config` | N/A (read-only) | 0644 file |

### §4.2 Container Volume Permissions

From [docker-compose.yml:L31-L32, L91-L92](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L31-L32):

| Volume | Mount Type | Access | Notes |
|--------|-----------|--------|-------|
| `pgdata` → `/var/lib/pgsql/data` | Named volume | rw | Persists across container rebuilds |
| `../sql` → `/sql` | Bind mount | **ro** (read-only) | SQL files loaded at entrypoint |
| `../config` → `/config` | NOT mounted | N/A | Config applied via `apply-config` Skill connecting to PG |

### §4.3 PgBouncer Filesystem (from [docker-compose.yml:L90-L92](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L90-L92))

```yaml
read_only: true      # Root filesystem is READ-ONLY
tmpfs:
  - /var/run/pgbouncer:size=10M,mode=0700,uid=999
```

PgBouncer cannot write to disk. Runtime state goes to tmpfs (in-memory).

## §5 Database Layer: Role and Schema

### §5.1 Minimum Required Privileges

| Privilege | Why |
|-----------|-----|
| `CONNECT` on database | All Skills |
| `USAGE` on schema `ontosql` | All Skills using ontosql.* functions |
| `EXECUTE` on ALL functions in schema `ontosql` | Query/Write/Graph Skills |
| `SELECT` on `vertex_embeddings` | Query Skills |
| `SELECT` on `attribute_embeddings` | Query Skills |
| `SELECT` on `object_attribute_mapping` | Query Skills |
| `INSERT, UPDATE` on `vertex_embeddings` | Write Skills (upsert-vertex) |
| `INSERT, UPDATE` on `attribute_embeddings` | Write Skills (upsert-attribute) |
| `INSERT, UPDATE` on `object_attribute_mapping` | Write Skills (link-object-attribute) |
| `USAGE` on `ag_catalog` schema | graph Skills (AGE Cypher) |
| `SELECT` on ALL tables in `ag_catalog` | graph Skills (AGE Cypher) |

### §5.2 search_path Convention

From [001_core_schema.sql L1-L5](file:///Users/liuruiqi/ontosql/sql/001_core_schema.sql#L1-L5):
```
SET search_path TO ontosql, ag_catalog, public;
```

The `ontosql` schema is first in search_path. All Skills use schema-qualified function calls (`ontosql.search_objects(...)`) so search_path is not required for correctness but present for convenience.

## §6 Security Boundaries for Agent

| Operation | Boundary | Rule |
|-----------|----------|------|
| Write to `build/data/` | Filesystem | PG process runs as `postgres` user; agent must ensure correct ownership |
| Read `PG_PASSWORD` | Environment | NEVER pass password via `--input` JSON or command-line argument |
| Execute `upsert-*` | Database | `ON CONFLICT` prevents corruption but does NOT prevent incorrect data from being written |
| Execute `cypher-query` | Database | Arbitrary Cypher execution; agent MUST validate input before calling |
| Run `force=true` on `init-db` | Filesystem | DESTRUCTIVE: erases all database files |
| Run `drop_existing=true` on `load-knowledge-graph` | Database | DESTRUCTIVE: drops entire AGE graph |

## §7 Minimum Privilege Principle Summary

| Skill | Minimum Permissions |
|-------|-------------------|
| `list`, `info`, `manifest` | Read access to `skills/manifest.json` only |
| `build` | Write access to `build/`, `upstream/` subdirs |
| `init-db`, `start`, `stop`, `status`, `clean` | Write access to `build/data/` as appropriate OS user |
| All Query Skills | PG `CONNECT` + `EXECUTE ontosql.search_*` + `SELECT` on 3 tables |
| All Write Skills | Plus `INSERT, UPDATE` on relevant tables |
| `health-check` | PG `CONNECT` + `SELECT pg_extension` |
| `backup` | PG `CONNECT` + `SELECT` on ontosql schema + filesystem write to `backups/` |
| `apply-config` | PG `CONNECT` + `EXECUTE pg_reload_conf`