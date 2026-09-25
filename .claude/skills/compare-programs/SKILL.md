---
name: compare-programs
description: Compare two ABAP objects, or a repo source file against the live system version (drift check). Read-only. Triggers - "compare ZPROG_A and ZPROG_B", "diff these programs", "is the repo version in sync with the system", "so sánh hai chương trình", "so sánh code trên hệ thống với repo".
---

# Compare Programs

Read-only logical comparison. Two modes:

## Mode A — two live objects

1. Read both: `sap_read_program` (+ includes) / `sap_read_class` /
   `sap_read_method` / `sap_read_function_module` as fits each object.
2. Compare in layers, not just text:
   - **Interface**: selection screens (`sap_textpool_read` S rows,
     PARAMETERS/SELECT-OPTIONS), FM/method signatures.
   - **Data**: tables read/written by each; highlight one-sided access.
   - **Logic**: walk the main flow of each; identify shared blocks,
     renamed-but-identical routines, and genuinely divergent logic.
   - **UI/texts**: screens (`sap_read_screen`), GUI status, text pools.
3. Output: side-by-side summary table + "meaningful differences" list,
   each with source line references, then a verdict (e.g. B is a copy of A
   with X added; or unrelated).

## Mode B — repo file vs live system (drift check)

Typical case: `abap/zmcp_adt_dispatch.abap` vs live `ZMCP_ADT_DISPATCH`
(the repo copy is the reference; `docs/product/abap-conventions.md`
requires them in sync).

1. Read the repo file (Read tool) and the live object
   (`sap_read_function_module` — note RPY readers may need the _NEW
   variant for wide sources; the bridge handles this).
2. Normalize obvious noise (leading/trailing blanks, case of keywords) but
   NOT identifiers or literals.
3. Report: in-sync / repo-ahead (list actions/forms present in repo only,
   e.g. WHEN branches not yet pasted into the system) / system-ahead
   (changes made in SE80 not backported) / diverged.
4. Known reference point: the dispatcher cua_fetch/cua_write
   `rsmpe_tit` → `rsmpe_titt` bug (`docs/product/sap-systems.md`) — check
   which side has the fix.

If drift requires changing either side, that is new work → harness intake;
this skill only reports.
