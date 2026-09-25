# ABAP helpers for the MCP-RFC bridge

Remote-enabled function modules that run *inside* SAP and expose, over RFC,
capabilities that no standard RFC FM offers (screens, GUI status, syntax check,
activation, CDS source, ABAP Unit, ATC, text elements, DDIC maintenance). The
bridge calls them and converts JSON ⇄ ABAP.

Install these on **any** SAP system you want the bridge to drive — that is how
you reuse the toolset across projects.

| File | Function module | Purpose |
|------|-----------------|---------|
| `zmcp_adt_dispatch.abap` | `ZMCP_ADT_DISPATCH` | Dynpro, GUI status, syntax check, activate, read CDS, unit tests, ATC |
| `zmcp_adt_textpool.abap` | `ZMCP_ADT_TEXTPOOL` | Read/write program text elements |
| `zmcp_adt_ddic_tabl.abap` | `ZMCP_ADT_DDIC_TABL` | Create/update/delete tables & structures |
| `zmcp_adt_ddic_dtel.abap` | `ZMCP_ADT_DDIC_DTEL` | Create/update/delete data elements |
| `zmcp_adt_ddic_doma.abap` | `ZMCP_ADT_DDIC_DOMA` | Create/update/delete domains |
| `zmcp_adt_ddic_activate.abap` | `ZMCP_ADT_DDIC_ACTIVATE` | Activate staged DDIC objects |

All live in function group **`ZMCP_ADT_UTILS`**. The four DDIC FMs are adapted
from [superclaude-for-sap](https://github.com/babamba2/superclaude-for-sap)
(MIT) and drive `sap_write_ddic` / `sap_delete_ddic` / `sap_activate_ddic`.

## Dependency
`/ui2/cl_json` (SAP_UI technology component) — present on S/4HANA and on ECC
systems with the UI2 add-on. If absent, replace the JSON (de)serialization with
your own converter.

## Install (SE80 / SE37)

1. **Create the function group** `ZMCP_ADT_UTILS` (SE80 → Function Group).
2. **Create function module `ZMCP_ADT_DISPATCH`** with this interface:
   - Processing type: **Remote-Enabled Module** ← required
   - Importing: `IV_ACTION TYPE STRING`, `IV_PARAMS TYPE STRING`
   - Exporting: `EV_SUBRC TYPE I`, `EV_MESSAGE TYPE STRING`, `EV_RESULT TYPE STRING`
   - Paste the body from `zmcp_adt_dispatch.abap` (it contains the FUNCTION…
     ENDFUNCTION plus all the FORM routines). Activate.
3. **Create function module `ZMCP_ADT_TEXTPOOL`** with this interface:
   - Processing type: **Remote-Enabled Module** ← required
   - Importing: `IV_ACTION TYPE STRING`, `IV_PROGRAM TYPE STRING`,
     `IV_LANGUAGE TYPE STRING`, `IV_TEXTPOOL_JSON TYPE STRING`
   - Exporting: `EV_SUBRC TYPE STRING`, `EV_MESSAGE TYPE STRING`,
     `EV_RESULT TYPE STRING`  ← note: EV_SUBRC is STRING here
   - Paste the body from `zmcp_adt_textpool.abap`. Activate.
4. **Create the four DDIC function modules** (same group, each
   **Remote-Enabled**), interfaces as documented in the `*"` comment block at
   the top of each `zmcp_adt_ddic_*.abap` file (IMPORTING IV_ACTION/IV_NAME/
   IV_DEVCLASS/IV_TRANSPORT/IV_PAYLOAD_JSON → EXPORTING EV_SUBRC(I)/
   EV_MESSAGE/EV_RESULT; the ACTIVATE FM takes IV_TYPE/IV_NAME). Paste each
   body, activate.
5. Assign to a transport (or `$TMP` for a sandbox) and activate the group.

> Updating an existing install: paste the whole body over the current FM source
> and re-activate — `zmcp_adt_dispatch.abap` already includes the original
> Dynpro/CUA forms plus the newer actions.

## `ZMCP_ADT_DISPATCH` actions

Input `IV_PARAMS` is a JSON string; output `EV_RESULT` is JSON.

| Action | Read/Write | `IV_PARAMS` | ABAP used |
|--------|:---------:|-------------|-----------|
| `DYNPRO_READ`   | R | `{"program","dynpro"}` | `RPY_DYNPRO_READ` |
| `DYNPRO_INSERT` | W | `{"program","dynpro","dynpro_data"}` | `RPY_DYNPRO_INSERT` |
| `DYNPRO_DELETE` | W | `{"program","dynpro"}` | `RPY_DYNPRO_DELETE` |
| `CUA_FETCH`     | R | `{"program","language"}` | `RS_CUA_INTERNAL_FETCH` |
| `CUA_WRITE`     | W | `{"program","language","cua_data"}` | `RS_CUA_INTERNAL_WRITE` |
| `CUA_DELETE`    | W | `{"program"}` | `RS_CUA_DELETE` |
| `SYNTAX_CHECK`  | R | `{"program","source":[...]}` | `SYNTAX-CHECK FOR` |
| `ACTIVATE`      | W | `{"objects":[{"type","name"}]}` | `RS_WORKING_OBJECTS_ACTIVATE` |
| `READ_DDLS`     | R | `{"name","state"}` | `SELECT … FROM DDDDLSRC` |
| `RUN_UNIT_TESTS`| R | `{"class"}` | `CL_AUCV_TEST_RUNNER_STANDARD` |
| `ATC_CHECK`     | R | `{"object_type","object_name","variant"}` | Code Inspector engine (`CL_CI_*`) |
| `PROGRAM_WRITE` | W | `{"program","source":[...],"create"}` | `RPY_PROGRAM_UPDATE` / `RPY_PROGRAM_INSERT` (local call — works around `RPY_PROGRAM_UPDATE` not being remote-enabled on some systems, e.g. S4D) |

## `ZMCP_ADT_TEXTPOOL` actions

| Action | Read/Write | Notes |
|--------|:---------:|-------|
| `READ`           | R | returns rows `{ID,KEY,ENTRY,LENGTH}` |
| `WRITE`          | W | `INSERT TEXTPOOL … STATE 'A'` (active) |
| `WRITE_INACTIVE` | W | `INSERT TEXTPOOL … STATE 'I'` (publishes on activation) |

`ID`: `I` text symbol · `S` selection text · `R` program title · `H` list heading.

## Notes / caveats

* **`ATC_CHECK`** runs the Code Inspector engine (`CL_CI_OBJECTSET` /
  `CL_CI_CHECKVARIANT` / `CL_CI_INSPECTION` — the engine ATC runs on) with a
  GLOBAL SCI check variant (`variant`, default `DEFAULT`). A transient
  inspection is created, run locally, read, and deleted. [Unverified on DS4 —
  syntax-check on paste; adjust per SE24 if CL_CI_* signatures differ.]
* **DDIC FMs**: CREATE/UPDATE stage objects INACTIVE
  (`RS_CORR_INSERT` → `DDIF_*_PUT` → `TR_RECORD_OBJ_CHANGE_TO_REQ`);
  activate via `ZMCP_ADT_DDIC_ACTIVATE` (`DDIF_*_ACTIVATE`). DELETE uses
  `RS_DD_DELETE_OBJ`. Structures = `TABL` with `DD02V-TABCLASS='INTTAB'`.
  TABL activation rc=4 usually means sparse DD03P attributes (see header
  note in `zmcp_adt_ddic_tabl.abap`).
* **`RUN_UNIT_TESTS`** uses `CL_AUCV_TEST_RUNNER_STANDARD`; verify the method
  signatures in SE24 if it does not compile on your release.
* All write actions are additionally gated on the Python side by
  `SAP_ALLOW_WRITE=true`, so a read-only bridge cannot trigger them.
