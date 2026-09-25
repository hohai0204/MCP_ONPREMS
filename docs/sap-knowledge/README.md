# SAP Knowledge Base

Reference knowledge for agents and skills working SAP tasks in this repo.
Adapted from [superclaude-for-sap](https://github.com/babamba2/superclaude-for-sap)
and general SAP knowledge, reshaped for this repo's RFC bridge.

## Validation rule (mandatory)

Everything in the module files below is **[Unverified] general SAP knowledge
until validated against the live target system**. Before relying on any
entry:

- Tables/structures → verify with `sap_ddic_info`.
- BAPIs/FMs → verify existence and RFC-enablement with
  `sap_search_objects` / `sap_read_function_module`.
- When an entry is confirmed live, append `(verified: DS4 <date>)` to it.

Release matters: DS4 is S/4HANA (BASIS 758) — some classic ECC tables are
replaced/redirected there (e.g. KONV → PRCD_ELEMENTS, MKPF/MSEG → MATDOC
compatibility views). The module files flag known S/4 deltas.

## Files

| File | Covers |
| --- | --- |
| [abap-patterns.md](abap-patterns.md) | Naming grid, include structure, OOP report pattern, ALV rules, text elements, clean ABAP checklist |
| [fi-co.md](fi-co.md) | Financial Accounting + Controlling: tables, BAPIs, t-codes |
| [mm-sd.md](mm-sd.md) | Materials Management + Sales & Distribution |
| [pp-qm-pm.md](pp-qm-pm.md) | Production Planning, Quality Management, Plant Maintenance |

Where this folder overlaps `docs/product/abap-conventions.md`, **that file
wins** — it is the product contract; this folder is supporting reference.

## Official documentation lookup

The project registers the `sap-abap-docs` MCP server (`.mcp.json`, hosted
endpoint of [mcp-sap-docs](https://github.com/marianfoo/mcp-sap-docs)) which
indexes the official ABAP Keyword Documentation, cheat sheets, and style
guides. For ABAP syntax/keyword questions, prefer querying that server over
answering from memory. Privacy note: it is a public third-party endpoint —
documentation queries leave this machine; never send code containing
credentials or business data, only language/keyword questions. A local
Docker/npm deployment is available if that becomes a concern.
