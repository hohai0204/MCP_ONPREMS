# US-003 Demo purchasing price condition via BAPI (ZPG_TEST_PRICEMEK1)

## Status

changed — object pushed AND active via RFC (root cause found and
worked around, no manual paste needed); pending user RUN (F8 in SE38 —
no RFC-enabled way to execute a plain REPORT) and read-back proof

## Lane

normal

## Product Contract

A standalone ABAP report `ZPG_TEST_PRICEMEK1` demonstrates creating one
purchasing price condition record (functional equivalent of transaction
MEK1) by calling `BAPI_PRICES_CONDITIONS` with hardcoded test values, on
profile s4d-100 (client 100, write-enabled). One-shot demo, not a reusable
tool — no selection screen.

## Relevant Product Docs

- `docs/stories/spec-intake-price-mek1.md`
- `docs/sap-knowledge/mm-sd.md` (BAPI_PRICES_CONDITIONS entry to be added)

## Acceptance Criteria

- Program activates and runs without dump on s4d-100.
- `BAPI_PRICES_CONDITIONS` call with hardcoded test data (MATNR
  000000000000001000, LIFNR 0000102278, EKORG 1000, WERKS 1100 —
  sourced from s4d-360 per explicit user instruction; EKORG/WERKS/unit
  independently re-verified valid on s4d-100, MATNR/LIFNR are not real
  master data there) returns no E/A messages and commits.
- On any BAPI error, the program rolls back and prints the error message.
- Created condition record is readable back via `sap_read_table` on `A017`
  for the built VARKEY.

## Design Notes

- Commands: local `CALL FUNCTION 'BAPI_PRICES_CONDITIONS'` (not RFC —
  `remote_enabled = false` per TFDIR, verified by sap-module-consultant).
- Tables: `A017` (condition table, TABLE_NO '017'), application `M`,
  condition type `PB00`, access sequence `ZCTC` (custom, verified via
  T685).
- Domain rules: VARKEY built manually as `LIFNR(10) + MATNR(40) + EKORG(4)
  + WERKS(4) + ESOKZ(1)` per A017 key order — no discrete key fields on
  the BAPI structures.
- UI surfaces: none (plain `WRITE` output).

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | none (BAPI side-effect call, not unit-testable in isolation) |
| Integration | `sap_syntax_check` + `sap_run_rfc` or GUI run; read-back via `sap_read_table` on A017 |
| E2E | n/a |
| Platform | n/a |
| Release | manual, human-owned (transport release if moved out of $TMP) |

## Harness Delta

Add `BAPI_PRICES_CONDITIONS` (verified, not remote-enabled) to
`docs/sap-knowledge/mm-sd.md` during authoring.

Bridge blocker discovered (sap-doctor run 2026-09-21/22): `ZMCP_ADT_DISPATCH`
/`ZMCP_ADT_TEXTPOOL` are not installed on the system reachable via
s4d-100/s4d-360 (same physical system, cross-client repository) — so
`sap_syntax_check`/`sap_activate` are unusable right now. Also:
`sap_write_program`'s plain `RPY_PROGRAM_INSERT` call (no
`DEVELOPMENT_CLASS`/`SUPPRESS_DIALOG`) fails over RFC with
`DYNPRO_SEND_IN_BACKGROUND` when creating a genuinely new program —
worked around via `sap_run_rfc` calling `RPY_PROGRAM_INSERT` directly with
`SUPPRESS_DIALOG='X'` + `DEVELOPMENT_CLASS='$TMP'`. Both are candidate
`docs/FEATURE_INTAKE.md` "Harness improvement" follow-ups (fix
`mcp/sap/tools.py:write_program` to always pass these; install the bridge
FMs) — not applied here since only read-only/this-story's own write was
in scope.

## Evidence

- `RPY_PROGRAM_INSERT` via `sap_run_rfc` on s4d-100: no exception raised;
  `TRDIR`/`PROGDIR`(states A+I)/`TADIR` confirm the object shell exists
  (`DEVCLASS=$TMP`, `CNAM=<rfc-user>`, `CDAT=20260922`) — but the actual
  source (`INSERT REPORT ... FROM source.` inside the FM) never
  persisted: `RPY_PROGRAM_READ(READ_LATEST_VERSION='X')` returns an empty
  `SOURCE` table for both active and inactive state.
- `sap_write_program(create=false)` (→ `RPY_PROGRAM_UPDATE`) fails hard:
  `CALL_FUNCTION_NOT_REMOTE` — that FM is not RFC-enabled on this system,
  so there is no remote "update existing program source" path at all.
- Isolated with two disposable probe programs (`ZPG_TEST_RFCPROBE`,
  `ZPG_TEST_RFCPROBE2`, both $TMP, 2-line source): reproduced the same
  empty-source result with **both** `SAVE_INACTIVE='X'` (inactive) and
  `SAVE_INACTIVE=' '` (direct active) paths — rules out payload size and
  the inactive-working-area mechanism specifically; the underlying
  `INSERT REPORT` statement itself does not persist over this RFC path
  on this system/release (S/4HANA kernel 781, release 755). These two
  probe objects are empty $TMP clutter pending user cleanup (SE38 →
  delete) — harmless but not auto-deletable (no remote delete FM found:
  `RPY_PROGRAM_DELETE` does not exist on this system either).
- Matches prior project precedent: `docs/stories/US-002-dynamic-excel-
  upload-alv.md` already recorded the identical fallback ("bridge
  offline; manual SE38 install per repo policy") for the same target
  system — this is not a new regression, it's the established pattern.
- **Root cause found:** the `SOURCE` TABLES parameter (structure
  `ABAPSOURCE`, legacy 72-char line type `EDPLINE`) silently fails to
  persist via `INSERT REPORT` on this release, regardless of
  active/inactive path — reproduced with two disposable 2-line probes.
  Switching to the `SOURCE_EXTENDED` TABLES parameter (structure
  `ABAPTXT255`, 255-char line type `TEXT255`) works correctly — verified
  with a third probe (`ZPG_TEST_RFCPROBE3`), then applied to the real
  object.
- **Resolution applied:** user deleted the empty `ZPG_TEST_PRICEMEK1`
  shell via SE38 (ALREADY_EXISTS blocks re-insert on the same name, and
  no remote-enabled delete FM exists — `RS_DELETE_PROGRAM`/
  `RS_TOOL_ACCESS` are both `remote_enabled: false`). Re-created via
  `sap_run_rfc` → `RPY_PROGRAM_INSERT` with `SOURCE_EXTENDED` (full
  129-line source), `SAVE_INACTIVE=' '` (direct active path — the only
  one proven to persist), `SUPPRESS_DIALOG='X'`, `DEVELOPMENT_CLASS=
  '$TMP'`. Read back via `sap_read_program`: 129 lines, exact match.
  `PROGDIR` confirms single row `STATE='A'` (active), no stray inactive
  row.
- **Caveat:** the direct-active path does not run a syntax check before
  going active (unlike normal SE80 activation) — only offline `abaplint`
  (PASS, 0 issues) backs this. `sap_syntax_check` is still unusable
  (bridge dispatcher missing, see Harness Delta above). Recommend the
  user glance at it in SE38 before running, though the source was built
  from live-verified DDIC/BAPI structures field-by-field.
- Fix candidate for `mcp/sap/tools.py:write_program`/`_source_to_lines`:
  use `SOURCE_EXTENDED`/`ABAPTXT255` (255-char lines) instead of
  `SOURCE`/`ABAPSOURCE` (72-char lines) — not applied here, out of this
  story's scope; worth a "Harness improvement" intake if this recurs.

### Fix 2026-09-23 — Purch. Org / Plant missing from the created record

- Symptom (read-back `A017`, client 100): record `KNUMH 0000006908`
  (DATAB 20260922) has `LIFNR`/`MATNR` filled but `EKORG`, `WERKS`,
  `ESOKZ` blank.
- Root cause: the key was passed in legacy `VARKEY` (CHAR100).
  `CND_MAP_BAPICONDCT_2_COND_RECS` only uses the key as-is when
  `VARKEY_LONG` is filled; otherwise it re-maps `VARKEY` via
  `CL_COND_VAKEY_SRV=>DETERMINE_VAKEY_255`, which assumes an 18-char
  MATNR — so the 40-char-MATNR layout shifted EKORG/WERKS/ESOKZ out of
  the key.
- Fix: build the key into `VAKEY_LONG` and pass it via
  `BAPICONDCT-VARKEY_LONG` / `BAPICONDHD-VARKEY_LONG` (legacy `VARKEY`
  left blank). abaplint PASS; `sap_syntax_check` on client 100 "Syntax
  OK" (negative probe with a bogus component correctly rejected).
- Write path: `ZMCP_ADT_DISPATCH` action `PROGRAM_WRITE` fails with
  `CX_SY_DYN_CALL_ILLEGAL_TYPE` (FORM passes `TABLE OF string` into
  `RPY_PROGRAM_UPDATE` TABLES `SOURCE`) — dispatcher bug, not fixed here.
  Used remote-enabled `SIW_RFC_WRITE_REPORT` instead (`INSERT REPORT
  ... STATE 'A'`, CHAR255 lines, keeps text pool, TADIR untouched):
  read-back 133/133 lines exact match, `PROGDIR` STATE A, UDAT
  20260923, DEVCLASS `$TMP`.
- Pending: user RUN (F8 in SE38) + read-back of the new `A017` row with
  EKORG 1000 / WERKS 1100. Old record 6908 (blank EKORG/WERKS) is still
  in `A017` — delete via MEK2/MEK3 if not wanted.
