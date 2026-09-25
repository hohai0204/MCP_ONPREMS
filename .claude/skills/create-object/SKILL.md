---
name: create-object
description: Create or change DDIC objects (Z-tables, structures, data elements, domains) on SAP via the ZMCP_ADT_DDIC bridge FMs - staged inactive, then activated. Use for dictionary objects; for programs use create-program. Triggers - "create a Z table", "add a field to Z table", "create data element/domain", "tạo bảng Z", "tạo structure", "tạo data element", "tạo domain".
---

# Create Object (DDIC)

DDIC pipeline over RFC. Objects are staged INACTIVE by `sap_write_ddic` and
go live only via `sap_activate_ddic`. Everything here is write-gated
(SAP_ALLOW_WRITE + package whitelist + client-side hook) and follows the
harness: intake before writes, approval before push.

Prerequisite: FMs `ZMCP_ADT_DDIC_TABL/DTEL/DOMA/ACTIVATE` installed
(group ZMCP_ADT_UTILS, remote-enabled — sources in `abap/`, guide in
`abap/README.md`). If a call returns FU_NOT_FOUND, report that and hand the
user the install guide instead of retrying.

## Order of creation (bottom-up, activate each level before the next)

domain (DOMA) → data element (DTEL) → table/structure (TABL). Reuse
standard domains/data elements when they fit — check with `sap_ddic_info`
and the `sap-module-consultant` agent before minting new ones.

## Steps

1. **Intake** — DDIC = "Data model" risk flag (docs/FEATURE_INTAKE.md);
   record with `harness-cli.exe intake` (normal lane at minimum; DDIC
   deletion or changing a productive table = high-risk).
2. **Design** — from the spec/request: field list with types. For each
   field decide reuse-vs-new dtel/domain (`sap_ddic_info` on candidates).
   Present the object design (name per naming grid, package, fields,
   keys, technical settings) and WAIT for the approval keyword
   (approve / đồng ý / duyệt).
3. **Collision check** — `sap_search_objects` / `sap_ddic_info` on every
   new name: must not exist.
4. **Push, bottom-up** — `sap_write_ddic` per object:
   - DOMA payload: `{"dd01v": {"DATATYPE":"CHAR","LENG":"000010",
     "OUTPUTLEN":"000010","DDTEXT":"..."}, "dd07v": [fixed values]}`
   - DTEL payload: `{"dd04v": {"DOMNAME":"...","DDTEXT":"...",
     "REPTEXT":"...","SCRTEXT_S/M/L":"..."}}`
   - TABL payload: `{"dd02v": {"TABCLASS":"TRANSP","CONTFLAG":"A",
     "DDTEXT":"..."}, "dd03p": [{"FIELDNAME":"...","ROLLNAME":"...",
     "KEYFLAG":"X","POSITION":"0001"}, ...]}` — structures use
     TABCLASS=INTTAB. Transparent tables also need technical settings
     defaults; first field MANDT (KEYFLAG X, ROLLNAME MANDT) for
     client-dependent tables.
   - devclass from the story (SAP_ALLOWED_PACKAGES applies); transport
     number when the package is transportable.
5. **Activate** — `sap_activate_ddic` per object in the same bottom-up
   order. rc=4 warnings on TABL usually mean sparse DD03P attributes —
   see the note in `abap/zmcp_adt_ddic_tabl.abap`; fill full DD03P for a
   clean rc=0.
6. **Verify** — `sap_ddic_info` on each object: fields/types match the
   approved design. Record proof with `harness-cli.exe story update`.

## Hard rules

- Never DELETE without explicit user confirmation naming the object —
  deletion is destructive and always high-risk.
- Never modify SAP standard DDIC objects (append structures are separate
  work, not covered by this bridge yet).
- Client-dependent business data tables need archival/authorization
  thinking — surface those in the design step, don't decide silently.
