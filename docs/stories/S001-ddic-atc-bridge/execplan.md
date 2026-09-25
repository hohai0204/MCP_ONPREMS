# S001 Execution Plan

1. [done] Fetch + adapt superclaude DDIC FM sources into `abap/` (headers:
   attribution, remote-enabled note, standard FUNCTION interface blocks,
   ASCII-only comments).
2. [done] Replace dispatcher ATC stub with CL_CI_* implementation.
3. [done] Offline lint all 5 ABAP sources — abaplint PASS.
4. [done] Python: ddic_write/ddic_delete/ddic_activate in tools.py; 3 MCP
   tools in server.py; ast.parse OK.
5. [done] Guard hook + settings matcher extended; qa4 block re-verified
   (exit 2).
6. [done] Skill create-object; docs: abap/README.md, sap-systems.md,
   spec-to-abap-workflow.md (§3 DDIC push, §4 ladder step 4b ATC),
   AGENTS.md skill list.
7. [USER] Paste FMs into DS4 (SE80/SE37) per abap/README.md; flag
   remote-enabled; activate.
8. [after 7] Live validation per validation.md; then
   `harness-cli story update --status implemented`.
