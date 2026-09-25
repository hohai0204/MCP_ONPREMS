# guard-sap-writes.ps1 - Claude Code PreToolUse hook.
# Second defense layer alongside SAP_ALLOW_WRITE: hard-blocks SAP write
# tools for any MCP server (= SAP profile) not explicitly allowlisted.
# Registered in .claude/settings.json. Exit 2 = block the tool call.
#
# When adding a QA/PROD profile (mcp/profiles/<name>.env -> server
# sap-<name>), writes stay blocked unless the server is added here.
$WritableServers = @("sap-s4d-100")

$WriteTools = "sap_write_program|sap_activate|sap_run_rfc|sap_adt_dispatch|sap_textpool_write|sap_write_ddic|sap_delete_ddic|sap_activate_ddic"

# SAP_RFC_READONLY_ALLOW (mcp\.env, then mcp\profiles\<name>.env - the profile wins):
# FMs a read-only server may call through sap_run_rfc. Same rule as guard_sap_writes.py.
function Get-ReadonlyAllow([string]$Server) {
    $mcp = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "mcp"
    $name = $Server -replace '^sap-', ''
    $value = ""
    foreach ($f in @((Join-Path $mcp ".env"), (Join-Path (Join-Path $mcp "profiles") "$name.env"))) {
        if (Test-Path $f) {
            foreach ($line in Get-Content $f) {
                if ($line -match '^\s*SAP_RFC_READONLY_ALLOW\s*=\s*(.*)$') { $value = $Matches[1].Trim().Trim('"', "'") }
            }
        }
    }
    return @($value -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tool = [string]$payload.tool_name
} catch {
    exit 0  # unparseable input: do not block (server-side gate still applies)
}

if ($tool -match "^mcp__(.+)__($WriteTools)$") {
    $server = $matches[1]
    $writeTool = $matches[2]
    if ($WritableServers -notcontains $server) {
        if ($writeTool -eq 'sap_run_rfc') {
            $fm = ([string]$payload.tool_input.function_name).ToUpper()
            foreach ($pat in (Get-ReadonlyAllow $server)) {
                if ($fm -and $fm -like $pat) { exit 0 }
            }
        }
        [Console]::Error.WriteLine(
            "BLOCKED by scripts/hooks/guard-sap-writes.ps1: '$writeTool' on MCP server '$server'. " +
            "Only these profiles accept writes: $($WritableServers -join ', '). " +
            "QA/PROD systems are read-only by policy (docs/product/sap-systems.md); " +
            "deliver source + manual install instructions instead.")
        exit 2
    }
}
exit 0
