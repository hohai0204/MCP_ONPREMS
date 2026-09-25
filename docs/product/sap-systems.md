# SAP Systems and Profiles

## Profile model

One MCP server instance per system profile. `mcp/sap/config.py` loads base
`mcp/.env` (shared policy, no credentials) then `mcp/profiles/<name>.env`
(credentials + per-system overrides, gitignored). setup.ps1 registers each
profile as MCP server `sap-<name>`.

## Known systems

| Profile | System | Role | Write policy | Verified |
| --- | --- | --- | --- | --- |
| `s4d-360` | S/4HANA S4D (kernel 781, release 755, HANA), host <sap-app-host> (sysnr 01), client 360, via SAProuter <saprouter-host>:3299 (giá trị thật: mcp/profiles/*.env) | Development (read) | `SAP_ALLOW_WRITE=false` — reads only | sap_ping verified live 2026-09-21 |
| `s4d-100` | Same S4D system as `s4d-360`, client 100, via same SAProuter | Development (write) | `SAP_ALLOW_WRITE=true` — designated write target; allowlisted as `sap-s4d-100` in `scripts/hooks/guard-sap-writes.ps1` (Windows) / `scripts/hooks/guard_sap_writes.py` (macOS/Linux)` | sap_ping verified live 2026-09-21 |

Add a row here whenever a new `profiles/<name>.env` is created. QA/PROD
profiles must keep `SAP_ALLOW_WRITE=false`.

## Safety policy (applies to every profile)

- **Read-only FM allowlist (`SAP_RFC_READONLY_ALLOW`)**: `sap_run_rfc` is a
  write-class tool, so a read-only profile (`s4d-360`) refuses it by default.
  A profile may list FMs (comma-separated, `*` wildcards) that it is allowed to
  call anyway, in its own gitignored `mcp/profiles/<name>.env`. Rules: default
  empty; list only FMs that never change data (a gateway test FM with a POST
  mode does not qualify); the FM deny list still wins; the bridge enforces it
  server-side and the write-guard hooks read the same key (`sap_run_rfc` only -
  every other write tool stays blocked on read-only servers). This replaces
  opening `SAP_ALLOW_WRITE` in-process for read-only tests on client 360.

- **Client-side write guard (hook)**: `.claude/settings.json` runs
  `scripts/hooks/guard-sap-writes.ps1` (Windows) / `scripts/hooks/guard_sap_writes.py` (macOS/Linux)` before every SAP write tool call and
  blocks any MCP server not in the script's `$WritableServers` allowlist
  (currently `sap-s4d-360`). When adding a QA/PROD profile, writes are blocked
  by default — do NOT add those servers to the allowlist.
- **Dependency risk**: pyrfc is archived upstream (SAP-archive/PyRFC);
  pinned vendored wheel, contingency in
  `docs/decisions/0009-pyrfc-archived-risk.md`. Keep pyrfc imports confined
  to `mcp/sap/connection.py`.

- `SAP_ALLOW_WRITE` — master write gate; off = read-only bridge.
- `SAP_TABLE_BLOCKLIST` — sensitive-table read block (defaults: USR02, PA0*,
  SECSTORE*, ... see `mcp/sap/tools.py`).
- `SAP_FM_DENYLIST` — FMs blocked in `sap_run_rfc` even with writes on
  (arbitrary ABAP, OS exec, raw SQL, mass delete, user admin).
- `SAP_ALLOWED_PACKAGES` — package whitelist for object creation; otherwise
  objects go to `$TMP`.

## Bridge prerequisites on a target system

To use the full toolset on a new system, install (SE37/SE80, group
`ZMCP_ADT_UTILS`, all remote-enabled — guide in `abap/README.md`):

1. `ZMCP_ADT_DISPATCH` — from `abap/zmcp_adt_dispatch.abap`.
2. `ZMCP_ADT_TEXTPOOL` — from `abap/zmcp_adt_textpool.abap` (flag
   Remote-Enabled).
3. `ZMCP_ADT_DDIC_TABL` / `_DTEL` / `_DOMA` / `_ACTIVATE` — from
   `abap/zmcp_adt_ddic_*.abap`; enable `sap_write_ddic` /
   `sap_delete_ddic` / `sap_activate_ddic` (DDIC objects over RFC).
   Not yet installed on DS4 as of 2026-07-19.

Without them, only the standard-FM tools work (read table/program/FM/class,
search, transports, dumps, where-used).

Known issue on DS4: the installed dispatcher's `cua_fetch`/`cua_write` declare
`TYPE TABLE OF rsmpe_tit` but need `rsmpe_titt` → CX_SY_DYN_CALL_ILLEGAL_TYPE.
Fix in SE80; the repo copy in `abap/` is already correct.

Known issue on S4D (both `s4d-360` and `s4d-100` — client-independent):
`ZMCP_ADT_DISPATCH` and `ZMCP_ADT_TEXTPOOL` are not installed (`sap_read_function_module`
-> FUNCTION_NOT_FOUND), so all dispatcher-based tools (syntax check, activate,
CDS read, textpool, dynpro/CUA) are unavailable — see `abap/README.md` to
install. Separately, and more fundamentally: `RPY_PROGRAM_UPDATE` (used by
`sap_write_program` to push ABAP source) is **not remote-enabled** on this
system (verified live 2026-09-22, `CALL_FUNCTION_NOT_REMOTE`, rc=3) — so
`sap_write_program` cannot succeed here at all, independent of the dispatcher
gap. Until a remote-enabled path exists (e.g. wrapping the write inside
`ZMCP_ADT_DISPATCH` once installed, the way `BAPI_PRICES_CONDITIONS` is
called locally by report code), deliver corrected/new ABAP source to the user
for manual paste into SE38/SE80 instead of calling `sap_write_program`.
