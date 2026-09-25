#!/usr/bin/env python3
"""guard_sap_writes.py - Claude Code PreToolUse hook (cross-platform).

Second defense layer alongside SAP_ALLOW_WRITE: hard-blocks SAP write tools for
any MCP server (= SAP profile) not explicitly allowlisted. Registered in
.claude/settings.json. Exit 2 = block the tool call.

Replaces guard-sap-writes.ps1 (PowerShell-only, silently did nothing on macOS).

When adding a QA/PROD profile (mcp/profiles/<name>.env -> server sap-<name>),
writes stay blocked unless the server is added here.
"""
import fnmatch
import json
import re
import sys
from pathlib import Path

WRITABLE_SERVERS = ["sap-s4d-100"]

WRITE_TOOLS = (
    "sap_write_program|sap_activate|sap_run_rfc|sap_adt_dispatch|"
    "sap_textpool_write|sap_write_ddic|sap_delete_ddic|sap_activate_ddic|sap_move_objects"
)


def readonly_allowlist(server: str) -> list[str]:
    """SAP_RFC_READONLY_ALLOW from mcp/.env then mcp/profiles/<name>.env (the
    profile wins), the same files the bridge loads. Empty when unset."""
    mcp = Path(__file__).resolve().parents[2] / "mcp"
    profile = server[4:] if server.startswith("sap-") else server
    value = ""
    for env_file in (mcp / ".env", mcp / "profiles" / f"{profile}.env"):
        try:
            for line in env_file.read_text(encoding="utf-8").splitlines():
                key, sep, val = line.partition("=")
                if sep and key.strip() == "SAP_RFC_READONLY_ALLOW":
                    value = val.strip().strip("'\"")
        except OSError:
            continue
    return [p.strip().upper() for p in value.split(",") if p.strip()]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        tool = str(payload.get("tool_name", ""))
    except Exception:
        return 0  # unparseable input: do not block (server-side gate still applies)

    m = re.match(rf"^mcp__(.+)__({WRITE_TOOLS})$", tool)
    if m and m.group(1) not in WRITABLE_SERVERS:
        # sap_run_rfc on a read-only server is fine for FMs the profile lists in
        # SAP_RFC_READONLY_ALLOW (the bridge enforces the same list server-side).
        if m.group(2) == "sap_run_rfc":
            fm = str((payload.get("tool_input") or {}).get("function_name", "")).upper()
            if fm and any(fnmatch.fnmatch(fm, p) for p in readonly_allowlist(m.group(1))):
                return 0
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
