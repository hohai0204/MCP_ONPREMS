# guard-sap-writes.ps1 - Claude Code PreToolUse hook.
# Second defense layer alongside SAP_ALLOW_WRITE: hard-blocks SAP write
# tools for any MCP server (= SAP profile) not explicitly allowlisted.
# Registered in .claude/settings.json. Exit 2 = block the tool call.
#
# When adding a QA/PROD profile (mcp/profiles/<name>.env -> server
# sap-<name>), writes stay blocked unless the server is added here.
$WritableServers = @("sap-s4d-100")

$WriteTools = "sap_write_program|sap_activate|sap_run_rfc|sap_adt_dispatch|sap_textpool_write|sap_write_ddic|sap_delete_ddic|sap_activate_ddic"

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tool = [string]$payload.tool_name
} catch {
    exit 0  # unparseable input: do not block (server-side gate still applies)
}

if ($tool -match "^mcp__(.+)__($WriteTools)$") {
    $server = $matches[1]
    if ($WritableServers -notcontains $server) {
        [Console]::Error.WriteLine(
            "BLOCKED by scripts/hooks/guard-sap-writes.ps1: '$($matches[2])' on MCP server '$server'. " +
            "Only these profiles accept writes: $($WritableServers -join ', '). " +
            "QA/PROD systems are read-only by policy (docs/product/sap-systems.md); " +
            "deliver source + manual install instructions instead.")
        exit 2
    }
}
exit 0
