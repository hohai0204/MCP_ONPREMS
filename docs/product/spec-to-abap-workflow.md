# Spec-to-ABAP Workflow

The core product contract: how a technical spec file becomes an activated
customization on SAP.

## 1. Spec intake

When the user provides a technical spec (Word/PDF/Markdown/text):

1. Copy `docs/templates/spec-intake.md` to
   `docs/stories/spec-intake-<slug>.md` and fill it from the spec.
2. Extract: business requirement, affected SAP objects (programs, FMs,
   classes, tables, CDS, dynpros), new Z-objects to create, target
   system/client, transport expectations.
3. Record intake with `.\scripts\bin\harness-cli.exe intake` — the risk
   checklist in `docs/FEATURE_INTAKE.md` decides the lane (see SAP-specific
   risk mapping below).
4. Slice into story packets under `docs/stories/` (one story per activatable
   unit of work).

## 2. Read before write

Before authoring ABAP, ground the design in the live system via MCP read
tools (never guess DDIC or existing code):

- `sap_search_objects`, `sap_read_program`, `sap_read_function_module`,
  `sap_read_class` / `sap_read_method` — existing source.
- `sap_ddic_info` — table/structure field definitions.
- `sap_read_table` — config/customizing values (blocklist applies).
- `sap_where_used` — impact analysis before changing shared objects.
- `sap_read_cds`, `sap_read_screen`, `sap_read_gui_status`,
  `sap_textpool_read` — CDS/dynpro/CUA/texts.

## 3. Author and push

- Author ABAP locally in the story context; follow
  [abap-conventions.md](abap-conventions.md).
- Push with `sap_write_program` (source lands **inactive**) — requires
  `SAP_ALLOW_WRITE=true` on the target profile and the package to pass
  `SAP_ALLOWED_PACKAGES`.
- Dynpro/CUA/textpool changes go through `sap_adt_dispatch` /
  `sap_textpool_write`.
- DDIC objects (tables, structures, data elements, domains) go through
  `sap_write_ddic` (staged inactive) + `sap_activate_ddic`, bottom-up
  DOMA → DTEL → TABL — see the `create-object` skill. Requires the
  `ZMCP_ADT_DDIC_*` FMs on the target system.

## 4. Validation ladder (proof)

Run in this order; each step is evidence for the story:

| Step | Tool | Gate |
| --- | --- | --- |
| 0. Offline lint | `scripts/lint-abap.ps1` (abaplint, no SAP needed) | parser errors must be fixed; style findings advisory |
| 1. Syntax check | `sap_syntax_check` | must be clean before activation |
| 2. Activate | `sap_activate` (dispatcher `ACTIVATE`) | write-gated |
| 3. Read-back | `sap_read_program` etc. | pushed source == intended source |
| 4. Unit tests | `sap_run_unit_tests` (where ABAP Unit exists) | no failed assertions |
| 4b. ATC/SCI check | `sap_run_atc` (dispatcher ATC_CHECK, SCI variant) | no priority-1/E findings; advisory otherwise |
| 5. Runtime smoke | `sap_run_rfc` on the new/changed FM, or user runs in GUI | expected output |
| 6. Dump check | `sap_list_dumps` after smoke | no new ST22 dumps |

Record the result with `harness-cli story update` and paste evidence into the
story's validation section. A story is **implemented** only after activation +
read-back at minimum; steps 4-6 may be waived per story with a written reason.

[Unverified] `sap_run_unit_tests` and `sap_run_atc` wiring exists but the
dispatcher actions were not fully verified on DS4; treat their output as
advisory until verified.

## 5. Human-owned steps

The agent does NOT do these; hand off explicitly in the story:

- Transport release (SE09/SE10) and import to QA/PROD.
- Activation the user reserves for themselves ("user controls object writes").
- Any change on a profile where `SAP_ALLOW_WRITE=false` — the agent prepares
  the source and instructions instead.

## SAP-specific risk mapping (extends FEATURE_INTAKE)

| FEATURE_INTAKE flag | SAP meaning — flag it when the spec touches |
| --- | --- |
| Data model | DDIC changes: tables, structures, data elements, CDS views |
| Existing behavior | Modifying standard-adjacent or productive Z-objects (check `sap_where_used` first) |
| External systems | RFC destinations, IDocs, interfaces, batch jobs |
| Audit/security | Authority checks, sensitive tables, user data |
| Public contracts | Remote-enabled FM signatures, released APIs, OData |
| Multi-domain | Spec spans multiple modules (FI/MM/SD...) or multiple Z-packages |

Hard gate additions: any write targeting a non-DEV profile, any DDIC deletion,
any change to the ZMCP_* bridge FMs themselves → **high-risk lane**.
