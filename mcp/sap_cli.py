"""Call any `sap.tools` function headless, without the MCP server being bound.

Use when the MCP tools (`mcp__sap-s4d-*__*`) are not loaded in the current
Claude Code session, or for scripted multi-step work. Same code path, same
write gate (`SAP_ALLOW_WRITE` of the chosen profile) as the MCP server.

    python mcp/sap_cli.py --profile s4d-360 ping
    python mcp/sap_cli.py --profile s4d-360 read_program '{"program": "ZPG_X"}'
    python mcp/sap_cli.py --profile s4d-100 run_rfc @params.json
    python mcp/sap_cli.py --list

Arguments: a JSON object inline, or `@path` to a JSON file (avoids shell
quoting/backslash issues on Windows). Output is UTF-8 JSON on stdout; errors go
to stderr with exit code 1.
"""
from __future__ import annotations

import argparse
import inspect
import io
import json
import os
import sys
from pathlib import Path


def _parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--profile", help="profile name in mcp/profiles/<name>.env")
    p.add_argument("--list", action="store_true", help="list callable tools")
    p.add_argument("tool", nargs="?", help="function name in sap.tools")
    p.add_argument("args", nargs="?", default="{}", help="JSON object or @file.json")
    return p.parse_args()


def main() -> int:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    ns = _parse()
    if ns.profile:
        os.environ["SAP_PROFILE"] = ns.profile
    # config.py resolves the profile from argv/env at import time
    sys.argv = [sys.argv[0]]
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from sap import tools

    public = {
        n: f for n, f in inspect.getmembers(tools, inspect.isfunction)
        if not n.startswith("_") and f.__module__ == tools.__name__
    }
    if ns.list or not ns.tool:
        for n, f in sorted(public.items()):
            print(f"{n}{inspect.signature(f)}")
        return 0
    if ns.tool not in public:
        print(f"unknown tool {ns.tool!r}; use --list", file=sys.stderr)
        return 1

    raw = ns.args
    if raw.startswith("@"):
        raw = Path(raw[1:]).read_text(encoding="utf-8")
    try:
        kwargs = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"args is not valid JSON: {exc}", file=sys.stderr)
        return 1

    try:
        result = public[ns.tool](**kwargs)
    except Exception as exc:  # surface SapConnectionError etc. without traceback noise
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=1, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
