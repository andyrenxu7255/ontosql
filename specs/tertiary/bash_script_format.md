# Bash Script Formatting Convention
> Tier 3 Retrieval Document | ≤2000 tokens | id: bash_script_format
>
> This document governs ALL shell scripts in the OntoSQL Skills layer.
> Applies to: lifecycle, ops, graph category scripts.

## §1 Shebang and Header

```bash
#!/usr/bin/env bash
# ============================================================================
# <Skill Name> — <One-line description>
# ============================================================================
set -euo pipefail
```

Rules:
- **Shebang**: `#!/usr/bin/env bash` (portable). NOT `#!/bin/bash`.
- **set flags**: ALWAYS `set -euo pipefail` on line 1 after shebang.
- **Comment block**: 80-char `=` separator line, Skill name, dash, description. Same pattern on closing line.

## §2 Skill Metadata Variables

Following the header, before any logic:

```bash
SKILL_NAME="<name>"
SKILL_CATEGORY="<category>"
source "${ONTOSQL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/skills/lib/common.sh"
parse_input "$@"
```

- `SKILL_NAME`: MUST match manifest.json `name` field exactly.
- `SKILL_CATEGORY`: one of `lifecycle|query|write|ops|graph`.
- The `source` line MUST be one line. DO NOT split across lines.
- `parse_input "$@"`: ALWAYS called immediately after source.

## §3 Timing

```bash
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
# ... skill logic ...
ELAPSED=$(python3 -c "import time; print(int(time.time()*1000) - ${START_MS})")
```

- `START_MS` placed immediately after `parse_input`.
- `ELAPSED` placed immediately before `output_success`/`output_error`.
- `START_MS` uses single quotes; `ELAPSED` uses double quotes (for variable expansion).
- DO NOT use `$SECONDS` or `date +%s%3N`. Use python3 for portability across macOS/Linux.

## §4 Brace and Bracket Consistency for Bash

**CRITICAL: The following rules MUST be applied identically by ALL models including v4pro.**

### §4.1 Variable Expansion Braces

ALWAYS use `{}` for variable expansion, NEVER omit:
```bash
# CORRECT
echo "${ONTOSQL_ROOT}"
echo "${PG_DATA:-${ONTOSQL_ROOT}/build/data}"

# WRONG — will be rejected in code review
echo "$ONTOSQL_ROOT"
echo "$PG_DATA:-${ONTOSQL_ROOT}/build/data"
```

### §4.2 Command Substitution

ALWAYS use `$()` syntax. NEVER use backticks:
```bash
# CORRECT
result=$(echo "${json}" | python3 -c "import sys,json; ...")

# WRONG
result=`echo "${json}" | python3 -c "import sys,json; ..."`
```

### §4.3 Array Initialization

ALWAYS use `()` parentheses, NEVER bare assignment:
```bash
# CORRECT
PSQL_CMD=("${PG_HOME}/bin/psql" -h "${PG_HOST}" -p "${PG_PORT}")

# WRONG
PSQL_CMD="${PG_HOME}/bin/psql -h ${PG_HOST} -p ${PG_PORT}"
```

### §4.4 Conditional Blocks

ALWAYS use `[[ ]]` double brackets. NEVER single brackets except for POSIX compatibility:
```bash
# CORRECT
if [[ -z "${val}" || "${val}" == "null" ]]; then

# WRONG
if [ -z "${val}" -o "${val}" == "null" ]; then
```

### §4.5 EOF/heredoc Delimiters

When embedding Python/SQL in heredocs, the delimiter MUST be uppercase and descriptive:
```bash
# CORRECT
python3 <<PYEOF
import json
...

PYEOF

# WRONG
python3 <<EOF
...
EOF
```

## §5 Output Call

```bash
output_success "${SKILL_NAME}" "${ELAPSED}" '<valid JSON data>'
output_error "${SKILL_NAME}" "ERR_CODE" "message" "${ELAPSED}" '<json details>'
```

- Data/detail arguments MUST be **valid JSON as a single-quoted string**.
- Never pass unquoted shell variables into JSON data (injection risk).