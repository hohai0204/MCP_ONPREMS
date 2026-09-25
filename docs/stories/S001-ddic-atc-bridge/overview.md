# S001 — DDIC maintenance + real ATC over the RFC bridge

Date: 2026-07-19 · Lane: high-risk (touches ZMCP_* bridge FMs)

## Why

The bridge could only create/update PROGRAMS (`RPY_PROGRAM_*`); specs
needing Z-tables/structures/data elements/domains broke the spec-to-abap
pipeline into manual SE11 work. ATC_CHECK in the dispatcher was a stub.

## What

1. Four new FM sources in `abap/` (adapted from superclaude-for-sap, MIT):
   `ZMCP_ADT_DDIC_TABL` / `_DTEL` / `_DOMA` / `_ACTIVATE`.
2. Real ATC_CHECK implementation in `abap/zmcp_adt_dispatch.abap` using the
   Code Inspector engine (CL_CI_*).
3. Python tools: `sap_write_ddic`, `sap_delete_ddic`, `sap_activate_ddic`
   (`mcp/sap/tools.py`, `mcp/server.py`), write-gated + package whitelist +
   client hook updated.
4. New skill `.claude/skills/create-object/` (DDIC pipeline, bottom-up
   DOMA→DTEL→TABL, approval gate).

## Human-owned step (blocking)

Install/update the FMs on DS4 in SE80/SE37 per `abap/README.md`:
- paste the 4 new DDIC FM bodies (remote-enabled, group ZMCP_ADT_UTILS);
- paste the updated dispatcher body (ATC form replaced).
Until then the new tools return FU_NOT_FOUND and `sap_run_atc` keeps
returning the stub message.
