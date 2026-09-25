---
name: sap-doctor
description: SAP bridge and system health check - connectivity, bridge Z-FMs, write-gate state, recent ST22 dumps, stale transports. Use when the connection seems broken, tools error out, or the user asks for a health check. Triggers - "sap doctor", "check SAP connection", "health check", "kiểm tra kết nối SAP", "hệ thống bị lỗi", "bị dump", "ST22".
---

# SAP Doctor

Layered read-only health check of the MCP-RFC bridge and the target system.
Report each layer as PASS / WARN / FAIL with evidence, then an overall
verdict. Do not fix anything in this skill — proposed fixes go through
`docs/FEATURE_INTAKE.md` as separate work.

## Checks, in order (stop early only if layer 1 fails)

1. **Connectivity** — `sap_ping`. PASS: returns system info (expect profile
   s4d-360, S/4HANA, client 310). FAIL: report the RFC error verbatim; likely
   causes: SAProuter route, credentials in `mcp/profiles/<name>.env`,
   SDK DLLs (`mcp/vendor/nwrfcsdk`). Remind: SAP_ASHOST must be a PLAIN
   host with the route in the separate saprouter param.
2. **Bridge FMs present** — `sap_read_function_module` on
   `ZMCP_ADT_DISPATCH` and `ZMCP_ADT_TEXTPOOL`.
   - PASS: both readable and remote-enabled.
   - WARN: readable but the known bug is present — check the dispatcher
     source for `TYPE TABLE OF rsmpe_tit` in cua_fetch/cua_write forms
     (should be `rsmpe_titt`, see `docs/product/sap-systems.md`).
   - FAIL: missing → dispatcher-based tools (syntax check, activate, CDS
     read, dynpro/CUA) will not work; point to `abap/README.md` install
     guide.
3. **Dispatcher responds** — `sap_adt_dispatch` with action `DYNPRO_READ`
   on a known program is a write-safe probe only if needed; prefer
   `sap_syntax_check` on a trivial `REPORT ztest.` source: PASS = returns a
   result; FAIL = "Unknown action" (dispatcher installed but missing WHEN
   branches — repo copy in `abap/` is newer than the installed FM).
4. **Write gate state** — do NOT attempt a write. Infer from config: read
   `mcp/profiles/*.env` … SAP_ALLOW_WRITE value (Read tool, local file).
   Report writable/read-only per profile and whether that matches
   `docs/product/sap-systems.md` policy (QA/PROD must be read-only).
5. **Recent dumps** — `sap_list_dumps` (days=7). PASS: none related to our
   objects. WARN: dumps mentioning Z* objects or RFC user FPT_ABAP — list
   runtime error (FIELD1), program, date; offer to delegate root-cause to
   the `sap-debugger` agent.
6. **Stale transports** — `sap_list_transports` (status D, owner = RFC
   user). WARN when old modifiable transports hold our objects.
7. **Client tooling** — local checks (no SAP): `node --version` available
   (else abaplint step degrades to skipped), `abaplint.jsonc` +
   `scripts/lint-abap.ps1` present, write-guard hook registered in
   `.claude/settings.json` (PreToolUse → `scripts/hooks/guard-sap-writes.ps1`)
   and its `$WritableServers` allowlist matches the write policy in
   `docs/product/sap-systems.md`.

## Output format

```
SAP Doctor — <profile> — <date>
1. Connectivity      PASS  <system, release, client>
2. Bridge FMs        WARN  <detail>
3. Dispatcher        PASS  <detail>
4. Write gate        PASS  <profile: state>
5. Dumps (7d)        PASS  <count, relevant ones>
6. Transports        WARN  <list>
Overall: <one-line verdict + recommended next action>
```

Everything is evidence-based: quote tool results, never guess. If the user
then asks to fix a finding, that request enters the harness intake gate.
