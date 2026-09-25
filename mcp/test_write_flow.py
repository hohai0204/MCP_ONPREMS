"""Live integration test: create -> read inactive -> activate -> update (active) -> refused bad update.

    .venv/bin/python mcp/test_write_flow.py --profile s4d-100

Needs a profile with SAP_ALLOW_WRITE=true (skips otherwise). Uses one fixed
fixture program in $TMP (ZMCP_T_FLOW, override with MCP_TEST_PROGRAM) - there is
no RFC delete, so once it exists only the update checks re-run.
"""
import os
import sys

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))

from sap import tools  # noqa: E402
from sap.connection import SapConnectionError, get_client  # noqa: E402

NAME = os.environ.get("MCP_TEST_PROGRAM", "ZMCP_T_FLOW").upper()
LONG = "  WRITE / 'line one two three four five six seven eight nine ten eleven twelve thirteen fourteen'."


def source(tag: str) -> str:
    return f"REPORT {NAME.lower()}.\nSTART-OF-SELECTION.\n{LONG}\n  WRITE / '{tag}'."


def states() -> list[str]:
    rows = tools.read_table("PROGDIR", ["STATE"], [f"NAME = '{NAME}'"])["rows"]
    return sorted(r["STATE"] for r in rows)


def check(label: str, cond: bool, detail: str = "") -> None:
    print(("PASS " if cond else "FAIL ") + label + (f" - {detail}" if detail and not cond else ""))
    if not cond:
        raise SystemExit(1)


def main() -> None:
    if not get_client().config.allow_write:
        print("SKIP: profile is read-only (SAP_ALLOW_WRITE is not true)")
        return

    exists = bool(tools.search_objects("PROG", NAME, 1)["rows"])
    v1 = source("v1")
    if exists:
        print("SKIP create/inactive/activate checks: fixture exists (no RFC delete); "
              "they run on a system where " + NAME + " is new")
    else:
        tools.write_program(NAME, v1, create=True, title="MCP write flow test")
        check("create saved inactive", "I" in states(), str(states()))
        check("read inactive == written (long line intact)",
              tools.read_program(NAME, state="I")["source"] == v1)
        check("latest returns inactive", tools.read_program(NAME, state="latest")["source"] == v1)
        check("syntax check", tools.syntax_check(v1, NAME)["result"]["ok"])
        tools.activate([{"type": "REPS", "name": NAME}])
        check("activate v1 -> only active version left", states() == ["A"], str(states()))
        check("read active == v1", tools.read_program(NAME)["source"] == v1)

    v2 = source("v2")
    tools.write_program(NAME, v2, create=False)
    check("update v2 is written active (syntax-checked first)",
          tools.read_program(NAME)["source"] == v2, tools.read_program(NAME)["source"][-40:])
    try:
        tools.write_program(NAME, f"REPORT {NAME.lower()}.\nSTART-OF-SELECTION.\n  THIS_IS_NOT_ABAP foo bar.", create=False)
        check("update with a syntax error is refused", False)
    except SapConnectionError as exc:
        check("update with a syntax error is refused", "Syntax check failed" in str(exc), str(exc))
    check("refused update left the active source untouched", tools.read_program(NAME)["source"] == v2)
    print("ALL PASS")


if __name__ == "__main__":
    try:
        main()
    except SapConnectionError as exc:
        print("FAIL:", exc)
        raise SystemExit(1)
