#!/usr/bin/env python3
"""guard_sap_writes.py - Claude Code PreToolUse hook (cross-platform).

Second defense layer alongside SAP_ALLOW_WRITE: hard-blocks SAP write tools for
any MCP server (= SAP profile) not explicitly allowlisted. Registered in
.claude/settings.json. Exit 2 = block the tool call.

Replaces guard-sap-writes.ps1 (PowerShell-only, silently did nothing on macOS).

When adding a QA/PROD profile (mcp/profiles/<name>.env -> server sap-<name>),
writes stay blocked unless the server is added here.
"""
import json
import re
import sys

WRITABLE_SERVERS = ["sap-s4d-100"]

WRITE_TOOLS = (
    "sap_write_program|sap_activate|sap_run_rfc|sap_adt_dispatch|"
    "sap_textpool_write|sap_write_ddic|sap_delete_ddic|sap_activate_ddic"
)


def main() -> int:
    try:
        tool = str(json.load(sys.stdin).get("tool_name", ""))
    except Exception:
        return 0  # unparseable input: do not block (server-side gate still applies)

    m = re.match(rf"^mcp__(.+)__({WRITE_TOOLS})$", tool)
    if m and m.group(1) not in WRITABLE_SERVERS:
        sys.stderr.write(
            f"BLOCKED by scripts/hooks/guard_sap_writes.py: '{m.group(2)}' on MCP "
            f"server '{m.group(1)}'. Only these profiles accept writes: "
            f"{', '.join(WRITABLE_SERVERS)}. QA/PROD systems are read-only by policy "
            "(docs/product/sap-systems.md); deliver source + manual install "
            "instructions instead.\n"
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
