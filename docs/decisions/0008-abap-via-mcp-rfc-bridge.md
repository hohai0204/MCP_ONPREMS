# 0008 — ABAP customizations are delivered through the MCP-RFC bridge

Date: 2026-07-18
Status: accepted

## Context

The product goal is: take a technical spec file and produce customizations
(ABAP) on SAP systems. Target systems are reachable only over RFC through a
SAProuter; ADT/HTTP is not available. The repo already contains a working,
live-verified MCP server (`mcp/`) wrapping pyrfc + NW RFC SDK, plus custom
remote-enabled Z-FMs (`abap/`) that close RFC gaps (syntax check, activation,
CDS read, dynpro/CUA, textpool).

## Decision

- Delivery stack: **ABAP authored by the agent, pushed via the MCP-RFC
  bridge** (`sap_write_program`, `sap_adt_dispatch`, `sap_textpool_write`),
  validated with the ladder in
  `docs/product/spec-to-abap-workflow.md`.
- RFC-blocked capabilities are added by extending `ZMCP_ADT_DISPATCH`
  (Z-FM proxy pattern), not by adopting ADT/HTTP transports.
- Write access is profile-scoped (`SAP_ALLOW_WRITE`): DEV writable, QA/PROD
  read-only. Transport release and QA/PROD import stay human-owned.
- Runtime is Windows-only (reaffirms commit b2638b8).

## Consequences

- Every spec-driven story depends on the bridge FMs being installed and
  correct on the target system (`docs/product/sap-systems.md`).
- Debugger, full ATC, and LSP-grade checks are out of scope over RFC; proof
  relies on syntax check + activation + read-back + ABAP Unit + dump check.
- Changes to the bridge FMs themselves are classified high-risk.
