# Spec Intake — Demo Purchasing Price Condition via BAPI (MEK1-equivalent)

## Source

Ad-hoc user request (2026-09-21, Vietnamese): "tạo program test
ZPG_TEST_PRICEMEK1 viết example tạo bảng giá MEK1 cho material bằng bapi ở
client 100."
Interview answers: demo/test only, hardcoded input values (not a
selection-screen tool); BAPI/condition table looked up live via
`sap-module-consultant` rather than assumed; result pushed through the MCP
pipeline (inactive → syntax check → review → wait for explicit approval
before activate/execute).

## Summary

A standalone ABAP test report `ZPG_TEST_PRICEMEK1` that demonstrates, with
hardcoded values, how to create one purchasing price condition record
(the functional equivalent of what transaction **MEK1** — "Create Purchasing
Conditions" — does interactively) by calling `BAPI_PRICES_CONDITIONS`
locally (not RFC — this FM is not remote-enabled per
`sap-module-consultant` verification against `TFDIR` on s4d-100). The
program prints the BAPI's return messages and, on success, the generated
condition number.

## sap-module-consultant findings (verified live on s4d-100, 2026-09-21)

- BAPI: `BAPI_PRICES_CONDITIONS` (function group `CND_PRICES_INBOUND`).
  `remote_enabled = false` in `TFDIR` — callable only as a local
  `CALL FUNCTION` from a program running inside S4D, not over an external
  RFC destination. No RFC-enabled alternative exists for this use case
  (`BAPI_PRICES_CONDITIONS_MAINTAIN` does not exist — name would exceed the
  30-char `TFDIR-FUNCNAME` limit).
- Condition type: `PB00`, application `M` (purchasing). Access sequence per
  `T685` on this system is **`ZCTC`** (custom) — not the SAP-standard
  `0002`. [Unverified] whether `ZCTC`'s access order matches `0002`; author
  must build `VARKEY` per the actual `A017` field order, not assume.
- Condition table: `A017` (TABLE_NO `'017'`), key fields (verified via
  `sap_ddic_info`): `MANDT, KAPPL, KSCHL, LIFNR(10), MATNR(40), EKORG(4),
  WERKS(4), ESOKZ(1), DATBI`; non-key `DATAB, KNUMH`.
- Parameter tables to fill: `TI_BAPICONDHD` (header: `COND_USAGE='A'`,
  `TABLE_NO='017'`, `APPLICATIO='M'`, `COND_TYPE='PB00'`, `VARKEY`,
  `VALID_FROM/TO`, temp `COND_NO` starting `$`), `TI_BAPICONDIT` (item:
  `COND_VALUE`, `CONDCURR`, `COND_P_UNT`, `COND_UNIT`, `COND_NO`). No
  discrete `MATNR`/`EKORG`/`LIFNR` fields exist on these structures —
  `VARKEY` (CHAR100) must be built by concatenating `LIFNR(10) + MATNR(40)
  + EKORG(4) + WERKS(4) + ESOKZ(1)` per `A017`'s key order, left-padded per
  field length (this is the highest-risk detail — mis-ordering silently
  creates an unreadable/wrong condition record).
- **Data provenance note:** the `sap-module-consultant` subagent's tool
  binding is hardcoded to profile `s4d-360` only (see its allowed-tools
  list), so its "live test data" (`INFNR 5300000042`, `MATNR
  000000000000001000`, `LIFNR 0000102278`, `EKORG 1000`, `WERKS 1100`,
  unit `PCS`) was read from **client 360**, not client 100. The
  BAPI/DDIC/Customizing findings (`BAPI_PRICES_CONDITIONS`, `A017`
  layout, access sequence `ZCTC` for `PB00`/`M`) were independently
  re-verified directly against s4d-100 and hold there too (same system,
  shared Customizing).
- **User decision (2026-09-21):** keep the client-360-sourced business
  keys (`MATNR = '000000000000001000'`, `LIFNR = '0000102278'`, `EKORG
  = '1000'`, `WERKS = '1100'`, unit `PCS`) hardcoded in the program, and
  execute/push it against s4d-100 (client 100) — explicitly accepted
  even though `MATNR`/`LIFNR` are not present as master data in client
  100's `MARA`/`LFA1`. Re-verified independently on client 100:
  `EKORG 1000` exists (`T024E`, "Coteccons Group"), `WERKS 1100` exists
  (`T001W`, "Kho dự án", same company code `1000` as plant `1000`), unit
  `PCS` exists (`T006`). `A017` has zero rows on client 100 today (no
  validity-period collision risk). Company code `1000`'s currency
  (`T001-WAERS`) is `VND` — used for `CONDCURR`.
  `BAPI_PRICES_CONDITIONS` writes the condition table directly (via
  `CND_GENERAL_CONDITIONS_SAVE`/`CND_PRICES_DETAILS_SAVE`) without
  validating `MATNR`/`LIFNR` against `MARA`/`LFA1`, so the missing
  master data is not expected to block the BAPI call — but the resulting
  condition record will reference non-existent material/vendor keys
  (acceptable for this demo per explicit user instruction; flagged here
  so it isn't mistaken for a bug later).

## Processing (hardcoded demo, no selection screen)

1. Hardcode: `MATNR = '000000000000001000'`, `LIFNR = '0000102278'`,
   `EKORG = '1000'`, `WERKS = '1100'`, `ESOKZ = '0'` (standard), price
   `COND_VALUE` (e.g. `100.00`), currency `CONDCURR = 'VND'` (company
   code 1000's currency per `T001`, applies to both plant 1000 and
   1100), `COND_P_UNT = 1`, `COND_UNIT = 'PCS'` (valid per `T006` on
   client 100), `VALID_FROM = sy-datum`, `VALID_TO = '99991231'`.
2. Build `VARKEY` per the A017 field order/lengths above.
3. Fill `TI_BAPICONDCT`/`TI_BAPICONDHD`/`TI_BAPICONDIT` (one row each,
   `OPERATION = '009'` = insert) and call `BAPI_PRICES_CONDITIONS`
   (tables-only interface, no `SAVE` parameter — the FM writes directly
   via `CND_GENERAL_CONDITIONS_SAVE`/`CND_PRICES_DETAILS_SAVE`).
4. Inspect `RETURN`/message table: any `E`/`A` → roll back
   (`BAPI_TRANSACTION_ROLLBACK`) and display errors; else
   `BAPI_TRANSACTION_COMMIT` and display the created condition number.
5. Output via `WRITE` (this is a demo, not a tool — no ALV needed per
   interview answer).

## Output Layout

Plain list output (`WRITE`): one line per BAPI return message
(type/id/number/message text), and on success a final line with the
created condition record key (`KNUMH`/condition number) and the `VARKEY`
used.

## Data Sources

Read: `A017` (condition table structure only, no direct read needed at
runtime — BAPI handles it), `EINA`/`EINE`/`LFM1` were read only during
analysis to source valid test keys. Write: one condition record row created
via `BAPI_PRICES_CONDITIONS` (application M, table 017) on client 100.

## Acceptance Criteria

- Program activates and runs without dump.
- BAPI call with the hardcoded test data returns no `E`/`A` messages and
  commits; a condition record is created (visible afterward via MEK3 /
  `sap_read_table` on `A017` for the built `VARKEY`) even though the
  referenced `MATNR`/`LIFNR` are not real master data on client 100 —
  per explicit user instruction to keep the client-360-sourced keys.
- On any BAPI error, the program rolls back and prints the error message
  (never silently swallows failures).
- This is a one-shot demo program: no selection screen, no reuse of
  hardcoded values across runs implied (rerunning may hit a
  duplicate/overlap validity error — acceptable for a demo, to be surfaced
  as a normal BAPI error message, not treated as a program bug).

## Harness Delta

None expected. If `docs/sap-knowledge/mm-sd.md` does not yet document
`BAPI_PRICES_CONDITIONS`, add a verified entry during authoring (per
sap-module-consultant's suggestion) — non-remote-enabled, application
M/SD condition maintenance, VARKEY built manually per condition table.
