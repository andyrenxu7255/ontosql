# OntoSQL System Adaptation Matrix
> Tier 3 Retrieval Document | ≤2000 tokens | id: system_adaptation
>
> This document defines the OS, CPU, compiler, and dependency compatibility
> matrix. Agent MUST check system compatibility before invoking `build` Skill.

## §1 Operating System Compatibility

### §1.1 Verified Platforms

| OS | Version | Arch | Status | Known Issues |
|----|---------|------|--------|-------------|
| macOS | 13+ (Ventura) | arm64 (Apple Silicon) | ✅ Primary | `sysctl -n hw.ncpu` for CPU count; configure may need `--without-llvm` |
| macOS | 13+ (Ventura) | x86_64 (Intel) | ✅ Supported | Rosetta 2 not tested; use native x86_64 build |
| macOS | 14+ (Sonoma) | arm64 | ✅ Verified | Same as Ventura |
| macOS | 15+ (Sequoia) | arm64 | ⚠️ Untested | Expected to work; compiler toolchain unchanged |
| Ubuntu | 22.04 LTS | x86_64 | ✅ Supported | Primary Linux target; all apt packages available |
| Ubuntu | 24.04 LTS | x86_64 | ⚠️ Untested | GCC 14 may introduce new warnings |
| Debian | 12 (bookworm) | x86_64 | ✅ Verified | Docker base image (bookworm-slim) |
| Debian | 12 (bookworm) | arm64 | ⚠️ Untested | Expected to work for ARM cloud instances |

### §1.2 NOT Supported

| Platform | Reason |
|----------|--------|
| Windows (native) | PostgreSQL requires POSIX; use WSL2 or Docker |
| macOS < 12 (Monterey) | Xcode/CLT versions too old for PG 17 |
| Ubuntu < 20.04 | libicu/liblz4 versions insufficient |
| Alpine Linux | musl libc incompatibility with PG extensions (use Debian-slim in Docker) |

## §2 Compiler Compatibility

### §2.1 Verified Compilers

From [Dockerfile:L15-L35](file:///Users/liuruiqi/ontosql/docker/Dockerfile#L15-L35) and [build.sh:L22-L25](file:///Users/liuruiqi/ontosql/skills/lifecycle/build.sh#L22-L25):

| Compiler | Minimum Version | Platform | Status |
|----------|----------------|----------|--------|
| GCC | 12.x (Debian 12 default) | Linux | ✅ Verified |
| Clang/Apple Clang | 15.x (Xcode 15 CLT) | macOS | ✅ Verified |
| GCC | 13.x / 14.x | Ubuntu 24.04 | ⚠️ Untested |

### §2.2 Build Toolchain

| Tool | Minimum | Check Command | Required By |
|------|---------|--------------|-------------|
| `make` | 4.0+ | `make --version` | PG build |
| `bison` | 3.0+ | `bison --version` | PG SQL parser |
| `flex` | 2.6+ | `flex --version` | PG SQL lexer |
| `pkg-config` | 0.29+ | `pkg-config --version` | Dependency resolution |

## §3 Library Dependencies

### §3.1 Build-Time Libraries

From [Dockerfile:L13-L36](file:///Users/liuruiqi/ontosql/docker/Dockerfile#L13-L36) (Debian package names):

| Library | Debian Package | macOS (Homebrew) | PG Configure Flag | Required |
|---------|---------------|-----------------|-------------------|----------|
| Readline | `libreadline-dev` | `readline` | *(auto-detected)* | YES |
| zlib | `zlib1g-dev` | *(built-in)* | *(auto-detected)* | YES |
| OpenSSL | `libssl-dev` | `openssl@3` | `--with-openssl` | Strongly recommended |
| ICU | `libicu-dev` | `icu4c` | `--with-icu` | Strongly recommended |
| libxml2 | `libxml2-dev` | `libxml2` | `--with-libxml` | Optional |
| libxslt | `libxslt1-dev` | `libxslt` | `--with-libxslt` | Optional |
| lz4 | `liblz4-dev` | `lz4` | `--with-lz4` | Recommended |
| zstd | `libzstd-dev` | `zstd` | `--with-zstd` | Recommended |
| Perl | `libperl-dev` | *(built-in macOS)* | *(auto-detected)* | Optional |
| Python3 | `python3-dev` | *(built-in macOS)* | *(auto-detected)* | Optional |
| Tcl | `tcl-dev` | `tcl-tk` | *(auto-detected)* | Optional |
| systemd | `libsystemd-dev` | *(N/A macOS)* | *(auto-detected)* | Linux only |

### §3.2 macOS Homebrew Quick Setup

```bash
brew install make bison flex readline zlib openssl@3 icu4c \
    libxml2 libxslt lz4 zstd pkg-config
```

Note: macOS ships BSD `make`; install GNU `make` via Homebrew and use `gmake`.

### §3.3 Ubuntu/Debian Quick Setup

```bash
sudo apt-get install -y build-essential bison flex \
    libreadline-dev zlib1g-dev libssl-dev libicu-dev \
    libxml2-dev libxslt1-dev liblz4-dev libzstd-dev \
    libperl-dev python3-dev tcl-dev pkg-config
```

## §4 CPU Architecture Compatibility

| Architecture | Status | Notes |
|-------------|--------|-------|
| x86_64 (Intel/AMD) | ✅ **Primary** | All upstream projects (PG, pgvector, AGE) support x86_64 natively |
| arm64 (Apple Silicon M1/M2/M3/M4) | ✅ **Verified** | macOS arm64 builds verified; Docker arm64 via `--platform linux/arm64` |
| arm64 (AWS Graviton, Ampere) | ⚠️ **Untested** | Linux arm64 should work (PG has arm64 support) but not specifically tested |

### §4.1 CPU Feature Requirements

| Feature | Required? | Check |
|---------|----------|-------|
| SSE4.2 (x86_64) | No | PG can build without; performance degrades |
| NEON (arm64) | No | PG can build without; performance degrades |
| AVX2 | No | pgvector HNSW index benefits but not required |

## §5 Resource Minimums (Verified)

From [README.md:L38-L47](file:///Users/liuruiqi/ontosql/README.md#L38-L47) and [docker-compose.yml:L47-L50](file:///Users/liuruiqi/ontosql/docker/docker-compose.yml#L47-L50):

| Resource | Minimum | Verified On | Notes |
|----------|---------|------------|-------|
| CPU cores | 4 (physical or virtual) | M1 Pro (8-core), AWS t3.xlarge (4 vCPU) | Build uses parallel jobs; 2-core works but slow |
| RAM (build) | 8 GB | M1 Pro (16GB), AWS t3.xlarge (16GB) | 4GB possible with `-j1` but not recommended |
| RAM (runtime, empty) | 256 MB | Docker Compose defaults | shared_buffers=256M + work_mem=16M overhead |
| RAM (runtime, production) | 2–8 GB | Depends on shared_buffers | Formula: shared_buffers + (work_mem × max_connections) + OS overhead |
| Disk (build) | 20 GB | Verified | PG + pgvector + AGE ≈ 2GB; upstream source ≈ 500MB |
| Disk (runtime) | depends on data | N/A | Each 1536-dim embedding ≈ 6KB; 1M embeddings ≈ 6GB |

## §6 Version Compatibility Matrix

| Component | Version Used | Minimum Compatible | Upgrade Path |
|-----------|-------------|-------------------|-------------|
| PostgreSQL | 17.4 (REL_17_STABLE) | 16.x (partial: pgvector compatible, AGE untested) | `pg_upgrade --link` major version upgrade |
| pgvector | 0.8.1 | 0.7.x (HNSW support added in 0.7.0) | Rebuild from source; no data migration needed |
| Apache AGE | 1.7.0-dev (master) | 1.5.x (Cypher function signatures differ) | Export/import graph via `ag_catalog.ag_graph` |
| pg_trgm | PG 17 built-in | PG 16+ (built-in, no separate install) | Included in PG upgrade |
| PgBouncer | 1.22.x (Debian 12) | 1.18+ (scram-sha-256 support) | Replace binary + config |

## §7 Pre-Build Adaption Checklist

Agent MUST verify the following before invoking `build`:

```
□ OS is macOS 13+ or Ubuntu 22.04+/Debian 12
□ build-essential / Xcode CLT installed
□ bison ≥ 3.0, flex ≥ 2.6 available in PATH
□ libreadline, zlib, libssl installed (header files present)
□ 8GB+ RAM available
□ 20GB+ free disk space
□ ./ontosql list returns without error (CLI self-check)
□ upstream/ directory contains postgresql/, pgvector/, age/ subdirs
```

**macOS-specific**: If `./configure` fails with "C compiler cannot create executables":
```bash
xcode-select --install           # Install Command Line Tools
export SDKROOT=$(xcrun --show-sdk-path)
```

**Linux-specific**: If `./configure` fails with "readline library not found":
```bash
sudo apt-get install -y libreadline-dev
```