---
name: program-to-spec
description: Reverse-engineer a live ABAP object into a technical spec document (markdown). Use when the user wants documentation of existing code. Triggers - "reverse engineer", "document this program", "generate spec from program", "tạo spec từ chương trình", "viết tài liệu cho chương trình".
---

# Program to Spec

Read-only: turn an existing SAP object into a spec document under
`docs/stories/spec-from-<object>-<yyyymmdd>.md`. No harness intake row (this
is documentation output, not repo behavior change).

## Step 1 — one bundled question set (ask once, then work)

Ask the user in ONE message (skip anything already stated):
1. **Audience**: functional (business language), technical (developer
   handover), or both?
2. **Depth**: L1 overview / L2 + logic flow per include-method / L3 + line
   annotated pseudo-code of core routines?
3. **Language of the document**: Vietnamese or English?

Defaults if the user says "up to you": both, L2, Vietnamese.

## Step 2 — full read of the object

- Source: `sap_read_program` (+ its includes) or `sap_read_class` /
  `sap_read_method`; FMs via `sap_read_function_module`.
- Selection screen and texts: `sap_textpool_read` (S rows = selection
  labels, R = title), screens `sap_read_screen`, menus/toolbars
  `sap_read_gui_status`.
- Data model: `sap_ddic_info` on every custom table/structure used and the
  central standard ones.
- Integration: `sap_where_used` (who calls it), calls it makes (RFC
  destinations, BAPIs), transports touching it recently
  (`sap_list_transports` / `sap_read_transport`) for change history.

## Step 3 — write the spec

Sections (trim to audience/depth):
1. Overview — purpose, module area, trigger (tcode/job/RFC).
2. Selection screen — parameter table with labels from the textpool.
3. Processing logic — narrative flow; L2+: per include/method; L3:
   annotated core routines.
4. Data model — tables read/written with field-level notes for custom ones.
5. Outputs — ALV/list/screen/files/interfaces.
6. Error handling & authorization — checks found (or explicitly "none
   found" — that is a finding).
7. Dependencies & impact — callers, called objects, RFC/BAPI usage.
8. Open questions — anything the code leaves ambiguous.

Everything must trace to read evidence; label interpretation [Inference].
Offer the `sap-module-consultant` agent for business-context enrichment of
module-specific sections.
