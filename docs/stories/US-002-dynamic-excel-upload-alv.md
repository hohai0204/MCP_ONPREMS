# US-002 Dynamic Excel Upload ALV Viewer

## Status

planned

## Lane

normal

## Product Contract

A user runs report `ZR_EXCEL_UPLOAD_DYN` (SE38, system DS4, $TMP prototype),
picks any .xlsx file from their PC, and sees its content in a read-only SALV
grid whose structure (column names and types) is derived from the file — no
fixed layout, no code change per file. Column types default to
auto-detection, but can be pinned per column via config table
`ZTB_EXCELMAPPING` when the optional selection keys `P_PROG`/`P_SHEET` are
supplied. This lets numeric-looking identifiers (company code `1000`,
customer `10000001`) be declared `C` (text) so the ALV does not insert
thousands separators.

## Relevant Product Docs

- `docs/product/overview.md`
- `docs/product/spec-to-abap-workflow.md`
- `docs/stories/spec-intake-excel-upload-dyn.md` (mini-spec with full rules)

## Acceptance Criteria

- Arbitrary .xlsx renders in ALV with original headers as column labels.
- Column types auto-detected (date/integer/decimal/text); mixed columns fall
  back to text without data loss; empty cells ignored during detection.
- When `P_PROG`/`P_SHEET` are filled and a `ZTB_EXCELMAPPING` row with
  `TYPE='DATATYPE'` exists, per-column codes (`C`=text `I`=int `D`=date
  `F`=float `P[n]`=packed decimal with n decimals/default 2, positional
  `C0001`..`C00nn`) override auto-detection; blank/unknown codes and
  unconfigured columns still auto-detect (no config → old behaviour
  unchanged).
- Duplicate/empty/>30-char/digit-leading/special-char headers are sanitized
  into valid unique component names without dumps.
- Unreadable file / invalid workbook / no worksheet → S-message displayed
  like error; header-only file → empty typed grid + info message.
- All user-visible texts from textpool (EN); no hardcoded literals.

## Design Notes

- Commands: none (no DB writes).
- Queries: `SELECT SINGLE * FROM ztb_excelmapping` (read-only, client-
  dependent) for the `TYPE='DATATYPE'` row keyed by `P_PROG`/`P_SHEET`;
  skipped entirely when both keys are blank.
- API: local classes `lcl_excel` (file dialog, gui_upload BIN → xstring,
  CL_FDT_XL_SPREADSHEET parse), `lcl_dyn_table` (sanitize_name,
  classify_value, apply_config_types, detect_types, RTTC create_table,
  fill_rows, to_date), `lcl_data` (orchestrator), `lcl_alv`
  (CL_SALV_TABLE), `lcx_error`.
- Tables: reads config `ZTB_EXCELMAPPING` (per-column type codes); output
  is a dynamic internal table via cl_abap_structdescr/tabledescr=>create +
  CREATE DATA ... TYPE HANDLE. Nothing persisted.
- Domain rules: see mini-spec Processing Rules.
- UI surfaces: selection screen (P_FILE, P_HDR, P_PROG, P_SHEET) + SALV
  fullscreen grid.
- Config typing added 2026-07-20 (intake #6) on user request: numeric IDs
  (company code / customer) were rendered with thousands separators because
  auto-detect typed them as numeric; declaring them `C` in ZTB_EXCELMAPPING
  keeps them text. Type-row literal held in constant `c_type_row`.

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | Local test class `ltc_dyn_table` (sanitize/classify/to_date) via ABAP Unit on DS4 |
| Integration | sap_syntax_check pass, activation OK, source+textpool read-back match |
| E2E | WAIVED (manual): user runs SE38 with mixed-type sample .xlsx and confirms ALV; frontend-services program cannot run over RFC |
| Platform | n/a (SAPGUI only) |
| Release | $TMP local object — no transport |

## Harness Delta

None.

## Evidence

- 2026-07-20 — Config-driven typing added (intake #6, lane normal). New
  optional params `P_PROG`/`P_SHEET`; `lcl_dyn_table->apply_config_types`
  reads `ZTB_EXCELMAPPING` (`TYPE='DATATYPE'`) and pins per-column kind
  before auto-detection; `create_table` gained `F`→`get_f`. Offline lint:
  `scripts/lint-abap.ps1` → abaplint 2.120.4, 0 issues (PASS). NOT pushed
  to DS4 (bridge offline; manual SE38 install per repo policy). Pending
  manual: add `ZTB_EXCELMAPPING` DATATYPE row, textpool for P_PROG/P_SHEET,
  SE38 syntax check + activation, runtime smoke.
- 2026-07-19 — Delivery switched to MANUAL mode at the user's request
  ("chưa write data vào sap chỉ đưa source bên ngoài thôi"): no RFC write
  performed, `SAP_ALLOW_WRITE` stays `false` in `mcp/profiles/ds4.env`.
- Source authored at `abap/zr_excel_upload_dyn.prog.abap` (all lines
  <= 72 chars, safe for classic editors and RFC source tables).
- Offline lint: `scripts/lint-abap.ps1` -> abaplint 2.120.4, 0 issues
  (PASS).
- Read-before-write on DS4 (read-only RFC): no `ZR_EXCEL*` program
  exists (no collision); `CL_FDT_XL_SPREADSHEET` and `CL_BCS_CONVERT`
  present; constructor raises `CX_FDT_EXCEL_CORE` (verified in class
  API); date cells emitted as ISO `YYYY-MM-DD[ HH:MM:SS]` (verified in
  method `CONVERT_CELL_VALUE_BY_NUMFMT`).
- Pending (manual, human-owned): SE38 install + textpool maintenance,
  syntax check (SE38 Ctrl+F2), activation, ABAP Unit run (SE80 →
  Ctrl+Shift+F10), runtime smoke with a mixed-type sample .xlsx.
