# Product Overview

## What this project is

MCP_SAP_PRIVATE is a pipeline that turns **technical specification files into
ABAP customizations on SAP systems**, executed by a coding agent (Claude Code)
through an MCP server that talks to SAP over RFC/SAProuter.

```text
technical spec (file)
    -> harness intake (docs/FEATURE_INTAKE.md, spec-intake template)
    -> story packet(s) with validation expectations
    -> ABAP source authored/edited by the agent
    -> MCP tools push to SAP (write inactive -> syntax check -> activate)
    -> proof recorded (harness-cli story/trace)
```

## Who uses it

- ABAP developer (chinhhn / Fpt_abap) driving Claude Code against S/4HANA
  systems reachable only via RFC/SAProuter (no ADT/HTTP access).

## Components

| Component | Location | Role |
| --- | --- | --- |
| MCP server | `mcp/server.py` (FastMCP, stdio) | Exposes ~26 SAP tools to the agent |
| SAP bridge | `mcp/sap/` (config/connection/tools) | pyrfc + NW RFC SDK, profile-based multi-system |
| ABAP dispatcher | `abap/zmcp_adt_dispatch.abap` (Z-FM on target system) | Escape hatch for RFC-blocked features: syntax check, activation, CDS read, dynpro/CUA |
| Textpool FM | `abap/zmcp_adt_textpool.abap` | Text element read/write |
| Harness | `AGENTS.md`, `docs/`, `harness.db` | Work classification, stories, decisions, proof |

## Non-negotiable constraints

- **RFC-only transport.** Only remote-enabled FMs are callable. Features that
  need ADT REST (debugger, ATC full, LSP) are out of scope; gaps are closed by
  extending the Z dispatcher FM.
- **Write safety.** All mutations are gated by `SAP_ALLOW_WRITE` per profile;
  DEV writable, QA/PROD read-only. Sensitive-table blocklist and FM deny list
  stay active even when writes are allowed.
- **Windows-only** runtime (decision 2026-07-17); NW RFC SDK is vendored.
- New objects go to allowed packages (`SAP_ALLOWED_PACKAGES`) or `$TMP`.

## Related product docs

- [spec-to-abap-workflow.md](spec-to-abap-workflow.md) — how a spec becomes activated ABAP.
- [sap-systems.md](sap-systems.md) — target systems, profiles, write policy.
- [abap-conventions.md](abap-conventions.md) — naming, packages, dispatcher protocol.
