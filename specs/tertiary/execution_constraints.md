# OntoSQL Execution Constraints
> Tier 3 Retrieval Document | ≤2000 tokens | id: execution_constraints
>
> This document governs ALL execution-time constraints for OntoSQL Skills.
> Agent MUST retrieve and apply these constraints before executing any Skill.

## §1 Timeout Constraints

### §1.1 Per-Skill Timeout (from manifest.json)

| Skill | timeout_ms | Notes |
|-------|-----------|-------|
| `build` | 600,000 (10min) | Full PG + pgvector + AGE compilation |
| `init-db` | 30,000 (30s) | initdb + pg_hba + postgresql.conf write |
| `start` | 30,000 (30s) | pg_ctl start + 30s readiness loop |
| `stop` | 30,000 (30s) | Graceful smart shutdown |
| `status` | 5,000 (5s) | pg_isready + uptime query |
| `clean` | 60,000 (1min) | Remove build/ and optional data/ |
| `search-objects` | 5,000 (5s) | Vector + trigram multi-path recall |
| `search-attributes` | 5,000 (5s) | Same as above for attribute table |
| `find-objects-by-attribute` | 5,000 (5s) | Reverse lookup via mapping table |
| `search-object-attribute` | 10,000 (10s) | CROSS JOIN + graph verify |
| `get-object-attributes` | 5,000 (5s) | List attributes for one object |
| `get-related-objects` | 10,000 (10s) | AGE Cypher graph traversal |
| `upsert-vertex` | 5,000 (5s) | Single row ON CONFLICT UPSERT |
| `upsert-attribute` | 5,000 (5s) | Same, with array parameter handling |
| `link-object-attribute` | 5,000 (5s) | Mapping row ON CONFLICT UPSERT |
| `health-check` | 10,000 (10s) | pg_isready + extension check + query ping |
| `backup` | 300,000 (5min) | pg_dump with optional gzip |
| `apply-config` | 10,000 (10s) | pg_reload_conf |
| `load-knowledge-graph` | 30,000 (30s) | Full 002_knowledge_graph.sql execution |
| `cypher-query` | 30,000 (30s) | Arbitrary openCypher execution |

### §1.2 PostgreSQL-Level Timeout

Applied by `init-db` and `apply-config` Skills. These are server-side, not Skill-enforced:

| Parameter | Default (init-db) | Production (template) | Effect |
|-----------|-------------------|----------------------|--------|
| `statement_timeout` | not set (unlimited) | 30,000ms | Kills queries exceeding limit |
| `idle_in_transaction_session_timeout` | not set | 600,000ms (10min) | Kills idle-with-lock sessions |
| `idle_session_timeout` | not set | 1,800,000ms (30min) | Kills completely idle sessions |

**Skill-level timeout vs PG-level timeout conflict rule**: When both exist, the PG-level timeout (`statement_timeout`) takes precedence. The Skill timeout is a CLI-level watchdog that kills the psql process if it hangs before PG returns a timeout error.

## §2 Resource Constraints

### §2.1 Memory

| Component | Minimum | Docker Limit | Production Recommendation |
|-----------|---------|-------------|--------------------------|
| OntoSQL (PG + vector + AGE) | 256MB | 1GB | 2GB–8GB (depends on shared_buffers) |
| PgBouncer | 10MB | 128MB | 64MB–128MB |
| Build process | 2GB | N/A (host) | 4GB for parallel make |

**shared_buffers scaling rule** (source: [init-db.sh:L22-L24](file:///Users/liuruiqi/ontosql/skills/lifecycle/init-db.sh#L22-L24)):
- dev/default: 256MB
- production (8GB host): 2GB (≈25% of host memory, from [postgresql.template.sql:L17](file:///Users/liuruiqi/ontosql/config/postgresql.template.sql#L17))

### §2.2 Disk

| Resource | Minimum | Notes |
|----------|---------|-------|
| Build artifacts | 5GB | PG + pgvector + AGE binaries |
| Data directory | 1GB | Empty init, grows with embeddings |
| WAL | 1GB–4GB | min_wal_size=1G, max_wal_size=4G (production template) |
| Backups | Variable | Logical backup ≈ data size; physical backup ≈ WAL + data |

### §2.3 CPU (Build Only)

Build uses parallel jobs: `make -j<N>` where N = `sysctl -n hw.ncpu` (macOS) or `nproc` (Linux), with fallback to 4. Controlled by `parallel_jobs` input parameter (default: 0 = auto).

## §3 Concurrency Constraints

### §3.1 Database Connections

| Parameter | Value | Source |
|-----------|-------|--------|
| `max_connections` | 200 (production), default (dev) | [postgresql.template.sql:L29](file:///Users/liuruiqi/ontosql/config/postgresql.template.sql#L29) |
| PgBouncer default_pool_size | 20 per user | [pgbouncer.ini](file:///Users/liuruiqi/ontosql/config/pgbouncer.ini) |
| PgBouncer max_client_conn | 100 | [pgbouncer.ini](file:///Users/liuruiqi/ontosql/config/pgbouncer.ini) |

### §3.2 Concurrent Skill Invocation

The system does NOT guarantee safety of concurrent write Skills. Specifically:
- `upsert-vertex`, `upsert-attribute`, `link-object-attribute` use `ON CONFLICT` for row-level safety
- But concurrent `upsert-attribute` + `link-object-attribute` pairs may race: an attribute may be deleted between the upsert and link
- **Recommendation**: serialize write operations per graph_name

### §3.3 Read/Write Isolation

Write Skills (`W-01`, `W-02`, `W-03`) write to `vertex_embeddings`, `attribute_embeddings`, `object_attribute_mapping` tables. Query Skills read from these same tables. PostgreSQL MVCC ensures consistent reads, but agents should not assume read-after-write visibility within the same Skill invocation.

## §4 Retry and Idempotency

| Skill | Safe to Retry? | Idempotency Mechanism |
|-------|---------------|----------------------|
| `build` | Partial | Rebuilds clean or incremental depending on `clean_first` |
| `init-db` | Yes | Skips if data directory exists + `force=false` |
| `start` | Yes | Skips if pg_isready returns true |
| `stop` | Yes | Skips if pg_isready returns false |
| `status` | Yes | Read-only |
| `clean` | Yes | Removes dirs if they exist |
| All Query Skills | Yes | Read-only |
| `upsert-vertex` | Yes | `ON CONFLICT (vertex_id, graph_name) DO UPDATE` |
| `upsert-attribute` | Yes | `ON CONFLICT (attr_name, graph_name) DO UPDATE` |
| `link-object-attribute` | Yes | `ON CONFLICT (graph_name, object_vertex_id, attr_id) DO UPDATE` |
| `health-check` | Yes | Read-only probe |
| `backup` | No (generates new file) | Each call produces unique timestamped file |
| `apply-config` | Yes | `ALTER SYSTEM SET` is idempotent |
| `load-knowledge-graph` | No | Append-only, use `drop_existing=true` for idempotent reload |
| `cypher-query` | Depends on query | Read-only queries are safe |

## §5 Graceful Shutdown

| Signal | Behavior |
|--------|----------|
| `SIGTERM` | `pg_ctl stop -m smart` (wait for active transactions to finish, then shut down) |
| `SIGINT` | Same as SIGTERM for `stop` Skill |
| `SIGQUIT` | `pg_ctl stop -m immediate` (abort all, requires crash recovery on next start) |

Docker Compose `stop_grace_period` default: 10s (Docker engine default for SIGTERM → SIGKILL escalation). Ensure `pg_ctl stop -m fast` completes within this window for containers with many active connections.

## §6 Error State Recovery

| Failure Scenario | Recovery Action |
|-----------------|----------------|
| `pg_ctl start` fails | Check pg.log → fix config → retry `start` |
| SQL query timeout | PG kills query, connection remains alive → retry with smaller `top_k` |
| `upsert` failure (dimension mismatch) | Fix embedding vector (must be 1536) → retry `upsert-vertex` |
| `link-object-attribute` failure (foreign key) | Ensure both vertex_id and attr_id exist → retry `link` |
| `build` failure (compile error) | Clean with `clean_first=true` → retry `build` |
| `init-db` failure (existing data) | Use `force=true` to reinitialize (DESTRUCTIVE) |