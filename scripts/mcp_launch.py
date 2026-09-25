#!/usr/bin/env python3
"""Portable launcher for the SAP MCP-RFC bridge (used by .mcp.json).

Usage: python3 scripts/mcp_launch.py [--profile] <profile> [extra server args]

Resolves everything relative to this checkout so the same .mcp.json works on
any machine: project .venv interpreter (POSIX or Windows layout), falling back
to the interpreter running this launcher. The NW RFC SDK is located by
mcp/sap/config.py (SAPNWRFC_HOME, then the per-OS bundled folder).
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "mcp" / "server.py"


def venv_python() -> str:
    for rel in (".venv/bin/python", ".venv/Scripts/python.exe"):
        cand = ROOT / rel
        if cand.is_file():
            return str(cand)
    return sys.executable


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--profile"]
    if args and not args[0].startswith("-"):
        args = ["--profile", args[0], *args[1:]]
    py = venv_python()
    os.chdir(ROOT)
    if os.name == "nt":  # execv on Windows detaches stdio; keep the pipe attached
        import subprocess
        return subprocess.call([py, str(SERVER), *args])
    os.execv(py, [py, str(SERVER), *args])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
