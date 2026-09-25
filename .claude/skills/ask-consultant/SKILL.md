---
name: ask-consultant
description: Route SAP functional/module questions to the module consultant with live validation - which table stores X, which BAPI does Y, standard vs custom approaches, FI/CO MM/SD PP/QM/PM semantics. Triggers - "ask the consultant", "which table stores", "which BAPI", "hỏi consultant", "bảng nào chứa", "BAPI nào để", "có chuẩn SAP nào cho".
---

# Ask Consultant

Answer functional SAP questions with validated knowledge instead of memory.
Read-only; no intake.

## Steps

1. **Classify the module group** from the question: FI/CO (accounting,
   controlling, assets), MM/SD (purchasing, inventory, sales, billing,
   pricing), PP/QM/PM (production, quality, maintenance). If it spans
   groups or is unclear, say which you picked and why.
2. **Delegate to the `sap-module-consultant` agent**, passing: the module
   group, the user's question verbatim, and the instruction to load the
   matching `docs/sap-knowledge/<group>.md` file first and validate every
   cited object live (`sap_ddic_info` / `sap_search_objects` /
   `sap_read_function_module`).
3. **Relay the answer** keeping the consultant's verified/[Unverified]
   marking per item — never strip it. Answer in the user's language.
4. **Persist verifications**: if the consultant confirmed entries that the
   knowledge file marks [Unverified], append `(verified: DS4 <date>)` to
   those lines in `docs/sap-knowledge/<group>.md` (a docs-only edit — no
   intake needed; it is the update rule the file itself mandates).

## Notes

- Simple one-object questions ("what fields does BKPF have") don't need the
  agent — call `sap_ddic_info` directly and answer.
- If the question is really a build request in disguise ("BAPI nào để tạo
  PO, viết giúp tôi chương trình gọi nó"), answer the knowledge part here,
  then route the build part to the `create-program` skill (intake gate
  applies there).
