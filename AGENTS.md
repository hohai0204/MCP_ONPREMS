# Agent Instructions

## Project Notes

This repo turns technical spec files into ABAP customizations on SAP systems
via an MCP-RFC bridge (`mcp/`). Before any SAP work read
`docs/product/overview.md`; specs enter through
`docs/product/spec-to-abap-workflow.md` (intake → story → read-before-write →
push inactive → syntax check → activate → proof). Writes are profile-gated
(`SAP_ALLOW_WRITE`); transport release and QA/PROD imports are human-owned.

Claude Code skills live in `.claude/skills/` (entry point: `spec-to-abap`;
plus create-program, create-object (DDIC), analyze-code, program-to-spec,
compare-programs, sap-doctor, ask-consultant) and read-only subagents in
`.claude/agents/`
(sap-analyst, sap-planner, sap-code-reviewer, sap-debugger,
sap-module-consultant). They wrap — never replace — the harness workflow
above. SAP module reference knowledge: `docs/sap-knowledge/`. For ABAP
keyword/syntax questions prefer the `sap-abap-docs` MCP server (official
docs) over memory; lint authored ABAP offline with `scripts/lint-abap.ps1`
before any SAP round-trip.

Reusable, verified SAP workflows (connect, headless CLI, program/FM/DDIC
writes, client-360 test runs, SEGW OData, package analysis, GUI scripting)
are skills in `../.claude/skills/sap-*` (source of truth:
`../.llmwiki/skills/`, index `../.llmwiki/skills/README.md`). Each one lists
the errors already hit — read its "Lỗi đã gặp" table before retrying a path.

## Agent rules (from /orca-eval 2026-09-24)

- Run Python with `PYTHONIOENCODING=utf-8` (SAP data is Vietnamese; the
  Windows console default cp1252 raises `UnicodeEncodeError`).
- Call the bridge headless with `python mcp/sap_cli.py --profile <p> <tool>
  <json|@file.json>` instead of re-creating ad-hoc wrappers in scratchpad.
- Before `read_table` on an unfamiliar table, list its fields first
  (`ddic_info` / DD03L). Keep WHERE clauses in classic Open SQL (no `@`, no
  new syntax); `FIELD_NOT_VALID` = wrong field name, `SAPSQL_PARSE_ERROR` =
  bad WHERE.
- ABAP authored for this user: split logic into small `FORM` routines, and
  write business-readable messages (no technical field names such as
  `EKKO-BSART` in message text).
- When porting logic from an existing program into a new purpose (e.g. a
  push job → a read/query API), list every filter or row-exclusion rule you
  copy and confirm with the user whether it still applies.

<!-- HARNESS:BEGIN -->
## Harness

Choose the request class before any Harness operation.

- When the requested outcome is only an answer, explanation, review, diagnosis,
  plan, or status report: inspect only the material needed to respond. Keep the
  task read-only. Do not bootstrap, initialize or migrate a database, record
  intake, or record a trace.
- When the user explicitly asks to change, build, fix, or write repository
  artifacts: first run `scripts/bootstrap-harness.sh`
  on macOS/Linux or `.\scripts\bootstrap-harness.ps1` on Windows. Then use
  `docs/FEATURE_INTAKE.md` to classify and record the request, query
  `scripts/bin/harness-cli query matrix --active --summary` on macOS/Linux or
  `.\scripts\bin\harness-cli.exe query matrix --active --summary` on Windows,
  and retrieve only the lane- and task-specific context described in
  `docs/CONTEXT_RULES.md`.
<!-- HARNESS:END -->
