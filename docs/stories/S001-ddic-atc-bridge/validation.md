# S001 Validation

## Done (repo-side)

- abaplint PASS on all 5 ABAP sources (parser + rules) — 2026-07-19.
- `python -c "ast.parse(...)"` OK for mcp/server.py + mcp/sap/tools.py.
- Hook unit test: `mcp__sap-qa4__sap_write_ddic` → exit 2 (blocked);
  ds4 write → exit 0; read tool → exit 0.

## Pending (needs FMs installed on DS4 — human step)

1. SE80 syntax check + activation of the 6 FMs (4 new + dispatcher +
   existing textpool untouched).
2. Restart Claude Code session (new tools register), then:
   - `sap_ping` OK; `sap_write_ddic` DOMA `ZMCP_TEST_DOM`
     (CHAR10, $TMP) → saved inactive; `sap_activate_ddic` → rc 0;
     `sap_ddic_info` shows the domain; `sap_delete_ddic` cleans up.
   - Bottom-up smoke: DOMA→DTEL→TABL in $TMP, verify with sap_ddic_info,
     then delete in reverse order.
   - `sap_run_atc` on an existing Z program with variant DEFAULT →
     finding list (or a clear variant-not-found message).
3. Negative: with a QA profile (when it exists) any sap_*_ddic call must
   be blocked client-side before reaching SAP.
4. Record outcomes here + `harness-cli story update`.
