# OntoSQL Format Specification Index (Tier 2: Reference Layer)
>
> This file maps each Skill type to the tertiary retrieval documents
> that contain the actual formatting rules and execution constraints.
> LLM agents read this index to discover which doc(s) to retrieve for
> a given task.
>
> **Design principle**: format rules and constraints never live in
> primary skill layer. Skills reference docs via `# @format:` tags.
> Actual rules are in Tier 3, each ≤2000 tokens for precise retrieval.

## Retrieval Index Map

| Format Doc ID | Doc File | Applies To | Token Budget |
|---------------|----------|------------|--------------|
| `json_output_format` | [json_output_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/json_output_format.md) | ALL Skills | ≤2000 |
| `bash_script_format` | [bash_script_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/bash_script_format.md) | lifecycle, ops, graph | ≤2000 |
| `sql_query_format` | [sql_query_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/sql_query_format.md) | ALL Skills | ≤2000 |
| `embedding_format` | [embedding_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/embedding_format.md) | write Skills | ≤2000 |
| `error_response_format` | [error_response_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/error_response_format.md) | ALL Skills | ≤2000 |
| `input_schema_format` | [input_schema_format.md](file:///Users/liuruiqi/ontosql/specs/tertiary/input_schema_format.md) | ALL Skills | ≤2000 |
| `brace_bracket_guide` | [brace_bracket_guide.md](file:///Users/liuruiqi/ontosql/specs/tertiary/brace_bracket_guide.md) | ALL Skills (cross-cutting) | ≤2000 |
| `execution_constraints` | [execution_constraints.md](file:///Users/liuruiqi/ontosql/specs/tertiary/execution_constraints.md) | ALL Skills (cross-cutting) | ≤2000 |
| `tool_invocation_spec` | [tool_invocation_spec.md](file:///Users/liuruiqi/ontosql/specs/tertiary/tool_invocation_spec.md) | ALL Skills (cross-cutting) | ≤2000 |
| `permission_model` | [permission_model.md](file:///Users/liuruiqi/ontosql/specs/tertiary/permission_model.md) | ALL Skills (cross-cutting) | ≤2000 |
| `system_adaptation` | [system_adaptation.md](file:///Users/liuruiqi/ontosql/specs/tertiary/system_adaptation.md) | lifecycle Skills | ≤2000 |

## Per-Skill Format Requirements

| Skill Category | Required Format Docs |
|----------------|---------------------|
| lifecycle | `json_output_format` `bash_script_format` `error_response_format` `brace_bracket_guide` `execution_constraints` `tool_invocation_spec` `system_adaptation` |
| query | `json_output_format` `sql_query_format` `error_response_format` `input_schema_format` `brace_bracket_guide` `execution_constraints` `permission_model` |
| write | `json_output_format` `sql_query_format` `embedding_format` `error_response_format` `input_schema_format` `brace_bracket_guide` `execution_constraints` `permission_model` |
| ops | `json_output_format` `bash_script_format` `error_response_format` `brace_bracket_guide` `execution_constraints` `tool_invocation_spec` |
| graph | `json_output_format` `sql_query_format` `bash_script_format` `error_response_format` `input_schema_format` `brace_bracket_guide` `execution_constraints` `permission_model` |

## LLM Retrieval Strategy

```
Agent receives task → reads manifest.json → identifies required Skills
    │
    ├─→ For each Skill, read @format tags → lookup in this index
    │      │
    │      └─→ Retrieve only the needed tertiary docs (NOT all of them)
    │             │
    │             └─→ Inject doc content into context (≤2000 tokens each)
    │
    └─→ cross-cutting: always retrieve brace_bracket_guide
                         always retrieve execution_constraints
                         always retrieve tool_invocation_spec (env vars + contract)
```

**Rule**: max 4 docs per task based on `# @format:` tags plus cross-cutting docs.