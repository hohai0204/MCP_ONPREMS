---
name: spec-to-abap
description: Master pipeline turning a technical spec into activated ABAP on SAP - intake, live analysis, planning, user approval gate, push inactive, review, validation ladder. Use when the user provides a spec document or asks to implement a spec. Triggers - "implement this spec", "spec to abap", "build from this spec", "làm theo spec này", "triển khai spec", "viết ABAP từ spec".
---

# Spec to ABAP

The flagship pipeline. It WRAPS the harness — the authoritative contract is
`docs/product/spec-to-abap-workflow.md`; lanes and risk flags come from
`docs/FEATURE_INTAKE.md`. Follow the phases in order; do not skip gates.

## Phase 0 — Preflight

`sap_ping`. Confirm profile, system, client. If the target profile has
`SAP_ALLOW_WRITE=false` (check `mcp/profiles/<name>.env`), tell the user now:
the pipeline will produce source + manual SE38/SE80 install instructions
instead of pushing.

## Phase 1 — Intake (before ANY other work product)

1. Read the spec file the user provided.
2. Copy `docs/templates/spec-intake.md` → `docs/stories/spec-intake-<slug>.md`
   and fill it.
3. Run the FEATURE_INTAKE risk checklist using the SAP mapping table in
   `docs/product/spec-to-abap-workflow.md`; record the row:
   `.\scripts\bin\harness-cli.exe intake --type "Spec slice" ...` with lane,
   flags, docs.
4. Slice into stories (one per activatable unit) from
   `docs/templates/story.md`; high-risk lane → use
   `docs/templates/high-risk-story/`.

## Phase 2 — Analysis (delegate)

- Send the spec to the **sap-analyst** agent: verified objects, open
  questions, risk evidence, acceptance criteria.
- Module semantics unclear? Consult the **sap-module-consultant** agent
  (it loads `docs/sap-knowledge/`).
- **Ambiguity gate**: put sap-analyst's open questions to the user in ONE
  bundled message. Do not proceed to authoring with unresolved blockers.

## Phase 3 — Planning (delegate)

Send analysis results to the **sap-planner** agent: reuse-first findings,
object plan with names checked for collisions, package/transport note,
ordered steps, validation expectations per story.

## Phase 4 — APPROVAL GATE (hard stop)

Present to the user: the plan, per-story mini-spec, objects to be
created/modified, and the validation plan. Then WAIT.

- Proceed only on an explicit approval keyword: **approve / proceed /
  đồng ý / duyệt / triển khai đi**. A bare "ok", "ừ", or a question is NOT
  approval — ask again.
- Any scope change requested here → back to Phase 3 (and re-record intake
  if the lane changes).

## Phase 5 — Author + push (main loop, NOT an agent)

Per story, in the planner's order:
1. Read-before-write: read current source of every object you modify.
2. Author per `docs/product/abap-conventions.md` +
   `docs/sap-knowledge/abap-patterns.md` (include structure, OOP pattern,
   text elements, clean ABAP). For uncertain syntax/keyword semantics,
   query the `sap-abap-docs` MCP server (official ABAP Keyword
   Documentation) instead of relying on memory — keyword questions only,
   never paste business code or credentials there.
3. Offline lint first: save the source to a scratch file and run
   `.\scripts\lint-abap.ps1 <file>` (`-Kind fugr|clas|intf` for non-report
   sources) — fix parser errors before touching SAP. Then
   `sap_syntax_check` the source BEFORE pushing.
4. Push: `sap_write_program` (lands INACTIVE; `create=true` for new).
   Dynpro/CUA via `sap_adt_dispatch`; texts via `sap_textpool_write`
   (default inactive).
5. If a write is refused (gate/package): stop pushing, deliver the source
   files + manual install steps, and continue the pipeline in "manual
   apply" mode with the user doing the writes.

## Phase 6 — Review gate (delegate, mandatory)

Send the pushed objects to the **sap-code-reviewer** agent.
- FAIL → fix in the main loop, re-push, re-review. After 2 consecutive
  FAILs on the same root cause, delegate to **sap-debugger** for
  root-cause, then fix.
- Do not activate anything that has not PASSed.

## Phase 7 — Validation ladder (main loop)

Per `docs/product/spec-to-abap-workflow.md` §4, in order:
1. `sap_syntax_check` (final source)
2. `sap_activate` — list EVERY object AND include (LIMU units; activation
   does not cascade)
3. Read-back: re-read each object; confirm it matches what was pushed
4. `sap_run_unit_tests` where test classes exist
5. Runtime smoke: `sap_run_rfc` for RFC-enabled units, else ask the user to
   run in GUI and report
6. `sap_list_dumps` (days=1) — no new dumps from our objects

Record: `harness-cli.exe story update` with proof status; paste evidence
into the story validation section.

## Phase 8 — Handoff report

Summarize: objects created/modified (with packages), validation evidence,
what remains human-owned (transport release SE09/SE10, QA/PROD import),
knowledge-file entries verified along the way. Record a decision
(`docs/decisions/` + `harness-cli decision add`) if architecture/contracts
changed meaningfully.
