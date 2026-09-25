---
name: create-program
description: Create a new ABAP program/report ad-hoc when there is no spec file - short interview builds a mini-spec, then the spec-to-abap pipeline runs. Triggers - "create a Z report", "write an ABAP program", "make a program that...", "viết chương trình ABAP", "tạo report", "tạo chương trình".
---

# Create Program

Second entry door into the same pipeline: the user wants a program but has
no spec document. Interview → mini-spec → hand over to `spec-to-abap` at its
Phase 1. Never start coding from a one-line request.

## Step 1 — Interview (ONE bundled message, adapt to what's already known)

Business side:
1. Purpose — what business question/process does it serve? Which module
   area (FI/CO, MM/SD, PP/QM/PM, cross)?
2. Users & trigger — who runs it, how (tcode, background job, RFC)?
3. Inputs — selection criteria (which fields, single/range, mandatory?).
4. Outputs — ALV list? totals? file? update to tables (which)?

Technical side:
5. Data sources — known tables/CDS, or should we find them? (module
   questions → `sap-module-consultant` agent)
6. Volume — rough row counts (drives performance choices).
7. Paradigm — OOP (default, per `docs/sap-knowledge/abap-patterns.md`) or
   procedural to match an existing family?
8. Package + naming — target package (must be in SAP_ALLOWED_PACKAGES) and
   name (propose per the naming grid, check collision with
   `sap_search_objects`).

Defaults when the user says "up to you": OOP + SALV, module inferred from
the tables involved, name per the grid.

## Step 2 — Mini-spec

Write the answers into `docs/stories/spec-intake-<slug>.md` (the
`docs/templates/spec-intake.md` shape, trimmed): summary, selection screen
table, processing rules, output layout, data sources, acceptance criteria.
Show it to the user briefly.

## Step 3 — Run the pipeline

Continue exactly as the `spec-to-abap` skill from its **Phase 1 step 3**
(record intake) onward: analysis (skip or shrink sap-analyst if the mini-
spec is fully grounded already), planning, APPROVAL GATE, author+push,
review gate, validation ladder, handoff. All gates apply — especially the
explicit approval keyword before any `sap_write_program`.
