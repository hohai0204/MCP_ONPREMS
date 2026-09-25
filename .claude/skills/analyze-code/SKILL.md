---
name: analyze-code
description: Analyze an ABAP program, class, or function module from the live SAP system - structure, data flow, tables touched, callers, risks. Read-only, no intake needed. Triggers - "analyze this program", "what does ZXXX do", "explain this ABAP", "phân tích code", "phân tích chương trình", "chương trình này làm gì".
---

# Analyze Code

Read-only analysis of a live SAP object. No harness intake (answer/explain
class per `docs/FEATURE_INTAKE.md`). Deliverable: a clear explanation, not a
fix — if the user then wants changes, that goes through intake.

## Steps

1. **Locate** — if the object type is unclear, `sap_search_objects` on the
   name. Programs → `sap_read_program`; classes → `sap_read_class` (or
   `sap_class_api` for the public contract, `sap_read_method` for one
   method); FMs → `sap_read_function_module`; CDS → `sap_read_cds`.
2. **Structure** — map the main program + includes (read includes the main
   program pulls in), or class sections/methods. Identify the pattern
   (classic report / OOP report per `docs/sap-knowledge/abap-patterns.md` /
   module pool / FM group).
3. **Data** — list DB tables read/written (SELECT/MODIFY/UPDATE/INSERT/
   DELETE statements); for the important ones pull `sap_ddic_info` to
   explain what the data is. Note authority checks (or their absence).
4. **UI** — if the program has screens: `sap_read_screen`,
   `sap_read_gui_status`, `sap_textpool_read` for titles/labels.
5. **Context** — `sap_where_used` on the object (and on key FMs it calls)
   to show who depends on it. For a package-wide question,
   `sap_dead_code` can flag unused methods.
6. **Deep review (optional)** — if the user asked "is this code good/safe",
   delegate to the `sap-code-reviewer` agent and merge its findings.

## Output

- **Purpose** (1-3 sentences, business language first).
- **Structure**: includes/methods and their roles.
- **Data touched**: table → purpose → read/write.
- **Callers/impact**: where-used summary.
- **Risks & smells**: concrete, with line references; label inferences
  [Inference].

For functional/module context questions that arise (what process uses this
table...), consult the `sap-module-consultant` agent rather than guessing.
For unfamiliar language constructs found in the source, query the
`sap-abap-docs` MCP server (official ABAP Keyword Documentation) rather
than interpreting from memory.
