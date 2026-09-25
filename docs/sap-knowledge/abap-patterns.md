# ABAP Patterns and Conventions

Mined from superclaude-for-sap `common/` and adapted to this repo. Where this
overlaps `docs/product/abap-conventions.md`, that product doc wins. The
naming grid below is the superclaude scheme — **confirm with the user before
adopting it as the project standard**; the only hard project rules today are
the Z namespace, package whitelist, and dispatcher protocol.

## Object naming grid [Unverified as team standard]

Pattern `Z{MODULE}{TYPE}{NNNNN}` (module = FI/CO/MM/SD/PP/QM/PM..., 5-digit
sequence, siblings share a number, step +10):

| TYPE | Object | Example |
| --- | --- | --- |
| R | Report/Program | ZFIR00010 |
| S | Structure | ZFIS00010 |
| T | Transparent table | ZFIT00010 |
| Y | Table type | ZFIY00010 |
| E | Data element | ZFIE00010 |
| D | Domain | ZFID00010 |
| V | DDIC view | ZFIV00010 |

Check collisions live (`sap_search_objects`) before assigning a number.

Other objects: classes `ZCL_{MODULE}_{PURPOSE}`, interfaces `ZIF_...`,
exceptions `ZCX_...`, test class `..._TEST`; function groups
`Z{MODULE}FG_{PURPOSE}`, FMs `Z{MODULE}FM_{PURPOSE}`; CDS views
`ZI_/ZC_/ZR_/ZP_{MODULE}_{Name}`. Local classes: `LCL_DATA`, `LCL_ALV`,
`LCL_EVENT`, `LCL_TEST_*`. Variables: `lv_/lt_/ls_/lr_` local,
`gv_/gt_/gs_/go_` global, `iv_/it_/is_` importing, `ev_/et_/es_` exporting,
`cv_/ct_/cs_` changing.

## Main + include structure

Main program holds only: REPORT statement, header comment, INCLUDE lines,
event blocks (INITIALIZATION / START-OF-SELECTION / END-OF-SELECTION)
delegating to forms/methods.

Includes named `{PROG}<suffix>`:

| Suffix | Content |
| --- | --- |
| t | TOP: types, data, constants (declare `gv_okcode TYPE sy-ucomm` when a screen exists) |
| s | Selection screen |
| c | LCL_DATA class (OOP only) |
| a | ALV class |
| o / i | PBO / PAI modules |
| e | ALV event handlers (OOP+ALV only; never in procedural) |
| f | FORM routines |
| _tst | Unit test classes (OOP) |

Order: procedural plain `t→s→f`; procedural screen+ALV `t→s→a→o→i→f`;
OOP full `t→s→c→a→o→i→e→f→_tst`.

RFC-bridge note: `sap_write_program` pushes one program object at a time and
source lands inactive; activation via `sap_activate` must list EVERY include
(LIMU REPS per include) — activating the main program does not cascade.

## OOP report pattern

Two mandatory local classes: `LCL_DATA` (constructor + `get_data`, holds
result tables privately, no UI) and `LCL_ALV` (constructor + `display`,
field catalog, consumes LCL_DATA). Optional `LCL_EVENT` for double_click /
hotspot_click / user_command.

```abap
INITIALIZATION.
  go_data = NEW #( ).
  go_alv  = NEW #( ).
START-OF-SELECTION.
  go_data->get_data( ).
END-OF-SELECTION.
  go_alv->display( ).
```

## ALV rules

- Quick list, no custom toolbar → `CL_SALV_TABLE` (`factory` + `display`),
  no screen/GUI status needed.
- Editable grid / custom toolbar / container embedding → `CL_GUI_ALV_GRID`
  on a custom screen (0100) with docking container and GUI status
  (dynpro/CUA via `sap_adt_dispatch` DYNPRO_INSERT / CUA_WRITE).
- Field catalog: auto-extract via `cl_salv_controller_metadata=>get_lvc_fieldcatalog`
  from a SALV factory even when targeting CL_GUI_ALV_GRID, then customize
  per field (coltext, do_sum, no_out, outputlen, hotspot).
- Avoid REUSE_ALV_* in new code.

## Text element rule

No hardcoded user-visible literals. Every `TEXT-xxx` must exist in the
textpool (`sap_textpool_read` / `sap_textpool_write`, rows
`{ID,KEY,ENTRY,LENGTH}`):

- ID `R` — program title (≥1), `I` — inline symbols, `S` — one per
  PARAMETER/SELECT-OPTION (missing S = technical names on the selection
  screen), `H` — classic list headings only.
- Maintain logon language AND English ('E' safety pass); missing 'E' rows =
  MAJOR review finding.

## Clean ABAP checklist (review gates)

- Descriptive names; booleans `is_/has_/should_`; methods = verbs.
- One unit one purpose; methods ≲30 lines; ≤3 params (else pass a structure).
- No magic numbers → typed constants; string templates `|...{ v }...|` over
  CONCATENATE; backtick literals.
- Guard clauses first; ≤3 nested IFs; CASE over IF/ELSEIF chains.
- Catch what you can handle, propagate the rest; never swallow exceptions;
  keep original sy-subrc/exception when re-raising.
- Open SQL: no `SELECT *`; check sy-subrc; no SELECT in loops (FOR ALL
  ENTRIES with a non-empty-table guard, or joins); filter/aggregate in the
  DB, not in loops.
- Internal tables: HASHED for equality, SORTED for ranges; no DEFAULT KEY;
  `line_exists( )` over READ TABLE TRANSPORTING NO FIELDS.
- ABAP Unit for non-trivial logic; test the public contract.
