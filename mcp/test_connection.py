"""Quick standalone connectivity check — run this BEFORE wiring up the MCP client.

    python test_connection.py

Prints system info on success, or a clear error on failure. Does not require an
MCP client; it exercises the exact same connection layer the server uses.
"""
from __future__ import annotations

import json
import sys

from sap import tools
from sap.connection import SapConnectionError


def main() -> int:
    try:
        info = tools.ping()
    except SapConnectionError as exc:
        print(f"[FAIL] {exc}")
        return 1
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] Unexpected: {exc}")
        return 1
    print("[OK] Connected to SAP:")
    print(json.dumps(info, indent=2, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
