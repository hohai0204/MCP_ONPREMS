---
description: Check whether the SAP MCP-RFC bridge is actually working (7 layers, read-only)
argument-hint: "[profile] [--skip-sap]"
allowed-tools: Bash(powershell.exe -NoProfile -ExecutionPolicy Bypass -File *scripts/check-mcp.ps1*), Bash(powershell.exe -NoProfile -ExecutionPolicy Bypass -File *scripts\check-mcp.ps1*), Read, Grep, Glob
---

# MCP bridge check

Answer one question: **is the MCP server working right now, and if not, which
layer broke?** Read-only — this command must not write SAP objects, edit config,
or record harness intake.

Arguments: `$ARGUMENTS` — an optional profile name (e.g. `s4d-360`) and/or
`--skip-sap` to stop before the SAP logon (offline / off-VPN).

## Step 1 — run the layered check

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts/check-mcp.ps1" -Json
```

Append `-ProfileName <name>` and/or `-SkipSap` when `$ARGUMENTS` asks for them.
Timeout: allow up to 180s — layer 6 opens a real RFC/SAProuter session.

The script covers, cheapest first:

| Layer | Verifies |
| --- | --- |
| 1 Python | interpreter found |
| 2 Python deps | `mcp`, `dotenv`, `import pyrfc` |
| 3 NW RFC SDK | `mcp/vendor/nwrfcsdk/lib/sapnwrfc.dll` + `vcruntime140.dll` |
| 4 Config | logon keys present per `mcp/profiles/*.env`, write-gate state |
| 5 MCP handshake | `initialize` + `tools/list` over stdio (real JSON-RPC) |
| 6 SAP ping | `tools/call sap_ping` through MCP |
| 7 Registration | `claude mcp list` for this project |

Layer 5 is the one that matters for "is MCP working": it starts
`mcp/server.py` exactly as Claude Code does and speaks the protocol. Layers 1-4
exist to name the cause when 5 fails.

## Step 2 — cross-check what this session actually has

The script proves the server *can* start. It does not prove *this* Claude
session loaded it. Also confirm:

- Are `mcp__sap-<profile>__*` tools available in the current session? If layer 5
  PASSed but no such tools are exposed here, the server is fine and the **client
  binding** is stale → the user must restart Claude Code (or `/mcp` reconnect).
- `.mcp.json` (checked in, project-wide) vs `claude mcp add` registrations
  (machine-local, in `~/.claude.json`) — say which one supplies each server.

If the tools ARE available, additionally call `mcp__sap-<profile>__sap_ping`
directly. That is the only check that proves the full client→server→SAP path.

## Step 3 — report

Print the layer table verbatim (PASS/WARN/FAIL + evidence), then:

```
Overall: <PASS|WARN|FAIL> — <one line>
Next action: <the single most useful fix, or "none">
```

Rules for the report:

- Evidence only. Quote the script's `detail` strings and tool output; never
  guess a cause. Label any hypothesis `[Inference]`.
- On FAIL, name the **first** failing layer as the cause — later failures are
  usually downstream of it.
- Do not fix anything. If the user then asks for a fix, that request enters the
  harness intake gate (`docs/FEATURE_INTAKE.md`).
- Common causes worth checking before speculating:
  - layer 2 pyrfc import error → missing VC++ 2015-2022 x64 (SAP Note 2573790)
  - layer 6 "hostname empty" → `SAP_ASHOST` holds a full `/H/.../S/...` route
    **and** `SAP_SAPROUTER` is also set; keep ASHOST a plain host
    ([mcp/sap/config.py:100-115](mcp/sap/config.py#L100-L115))
  - layer 6 logon rejected → credentials/client in `mcp/profiles/<name>.env`

## Scope boundary

This command stops at the bridge. For the target-system health check —
bridge Z-FMs `ZMCP_ADT_DISPATCH`/`ZMCP_ADT_TEXTPOOL`, ST22 dumps, stale
transports, write-guard hook — use the `sap-doctor` skill instead.
