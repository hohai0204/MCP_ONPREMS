"""MCP-RFC bridge server for SAP ABAP development.

Exposes SAP repository read (and optionally write) operations to an MCP client
such as Claude Code, talking to the SAP system over RFC — which means it works
on RFC-only / SAProuter systems and classic ECC / R/3, without ADT/HTTP.

Run:  python server.py         (stdio transport, for Claude Code / MCP clients)
"""
from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from sap import tools
from sap.connection import SapConnectionError

mcp = FastMCP("sap-rfc-bridge")


def _safe(fn, *args, **kwargs) -> dict:
    """Run a tool, converting connection errors into a structured result so the
    MCP client sees a clean message instead of a stack trace."""
    try:
        result = fn(*args, **kwargs)
        return result if isinstance(result, dict) else {"result": result}
    except SapConnectionError as exc:
        return {"error": str(exc)}
    except Exception as exc:  # last-resort guard
        return {"error": f"Unexpected error: {exc}"}


@mcp.tool()
def sap_ping() -> dict:
    """Test the SAP RFC connection and return system information (SID, host,
    kernel, release). Use this first to confirm connectivity."""
    return _safe(tools.ping)


@mcp.tool()
def sap_read_table(
    table: str,
    fields: list[str] | None = None,
    where: list[str] | None = None,
    max_rows: int = 100,
) -> dict:
    """Read rows from a transparent SAP table via RFC_READ_TABLE.

    Args:
        table: Table name, e.g. 'T000' or 'TADIR'.
        fields: Optional list of column names to select (fewer = safer for the
            512-byte RFC_READ_TABLE row limit).
        where: Optional list of ABAP WHERE clauses, e.g. ["MANDT = '100'"].
        max_rows: Maximum rows to return.
    """
    return _safe(tools.read_table, table, fields, where, max_rows)


@mcp.tool()
def sap_read_program(program: str, state: str = "A") -> dict:
    """Read the source code of an ABAP program/report by name.

    state: "A" active version (default), "I" inactive version (saved but not yet
    activated), "latest" inactive if present else active."""
    return _safe(tools.read_program, program, state)


@mcp.tool()
def sap_read_function_module(function_name: str) -> dict:
    """Read a function module's source code and interface (parameters,
    exceptions)."""
    return _safe(tools.read_function_module, function_name)


@mcp.tool()
def sap_read_class(class_name: str, state: str = "A") -> dict:
    """Read an ABAP class/interface source code by name.

    Returns the stitched full source plus a per-section index (public/protected/
    private definitions, local classes, one section per method).

    Args:
        class_name: Class or interface name, e.g. ZCL_FOO.
        state: 'A' for the active version (default), 'I' for inactive.
    """
    return _safe(tools.read_class, class_name, state)


@mcp.tool()
def sap_search_objects(
    obj_type: str | None = None,
    name_pattern: str = "",
    max_rows: int = 50,
) -> dict:
    """Search repository objects in TADIR.

    Args:
        obj_type: R3TR object type, e.g. PROG, CLAS, FUGR, TABL, DDLS.
        name_pattern: ABAP LIKE pattern, e.g. 'Z%' for custom objects.
        max_rows: Maximum rows to return.
    """
    return _safe(tools.search_objects, obj_type, name_pattern, max_rows)


@mcp.tool()
def sap_read_method(class_name: str, method: str, state: str = "A") -> dict:
    """Read ONE method's source from an ABAP class — much cheaper than the
    whole class. Also returns the list of all method names."""
    return _safe(tools.read_method, class_name, method, state)


@mcp.tool()
def sap_class_api(class_name: str, with_dependencies: bool = False) -> dict:
    """Get a class's public API (definition/public section) WITHOUT method
    implementations — a compressed view for understanding interfaces. With
    with_dependencies=true, appends the public APIs of referenced Z/Y classes."""
    return _safe(tools.class_api, class_name, with_dependencies)


@mcp.tool()
def sap_dead_code(package: str, max_classes: int = 20) -> dict:
    """Scan a package for potentially unused methods via the where-used index.
    Classifies each method live/internal/dead. Dynamic calls are invisible to
    the index, so 'dead' = review candidate."""
    return _safe(tools.dead_code, package, max_classes)


@mcp.tool()
def sap_ddic_info(name: str) -> dict:
    """Describe a DDIC table or structure: fields with types, lengths, key
    flags, data elements, and texts."""
    return _safe(tools.ddic_info, name)


@mcp.tool()
def sap_list_dumps(days: int = 7, max_rows: int = 50) -> dict:
    """List recent ABAP runtime errors (ST22 short dumps): date, time, user,
    host, and runtime-error name. Useful to see what is crashing."""
    return _safe(tools.list_dumps, days, max_rows)


@mcp.tool()
def sap_list_transports(
    user: str | None = None,
    status: str | None = None,
    max_rows: int = 50,
) -> dict:
    """List transport requests (E070). Filter by owner and/or status
    ('D' modifiable, 'R' released)."""
    return _safe(tools.list_transports, user, status, max_rows)


@mcp.tool()
def sap_read_transport(trkorr: str, max_rows: int = 200) -> dict:
    """Read one transport request: header plus contained objects."""
    return _safe(tools.read_transport, trkorr, max_rows)


@mcp.tool()
def sap_where_used(name: str, max_rows: int = 100) -> dict:
    """Find includes that reference a global type/class/method (where-used via
    the WBCROSSGT index). OTYPE: TY=type/class, ME=method, DA=data."""
    return _safe(tools.where_used, name, max_rows)


@mcp.tool()
def sap_read_screen(program: str, dynpro: str) -> dict:
    """Read a Dynpro (screen) definition: header, containers, fields, and flow
    logic. Requires the ZMCP_ADT_DISPATCH helper FM installed on the system."""
    return _safe(tools.read_screen, program, dynpro)


@mcp.tool()
def sap_read_gui_status(program: str, language: str = "") -> dict:
    """Read a program's GUI status / CUA: menus, toolbars, function keys.
    Requires the ZMCP_ADT_DISPATCH helper FM installed on the system."""
    return _safe(tools.read_gui_status, program, language)


@mcp.tool()
def sap_adt_dispatch(action: str, params: dict | None = None) -> dict:
    """Call the ZMCP_ADT_DISPATCH helper FM directly with any action.

    Read actions (always allowed): DYNPRO_READ, CUA_FETCH, SYNTAX_CHECK,
    READ_DDLS, TEXTPOOL_READ, RUN_UNIT_TESTS, ATC_CHECK.
    Write actions (need SAP_ALLOW_WRITE=true): DYNPRO_INSERT, DYNPRO_DELETE,
    CUA_WRITE, CUA_DELETE, ACTIVATE, TEXTPOOL_WRITE.
    params is the JSON payload, e.g. {"program": "ZPROG", "dynpro": "0100"}."""
    return _safe(tools.adt_dispatch, action, params)


@mcp.tool()
def sap_syntax_check(source: str, program: str = "") -> dict:
    """Syntax-check ABAP source WITHOUT saving. Returns {ok:true} or the first
    error with message/line/word. `program` is an existing report used as
    context (defaults to a standard one)."""
    return _safe(tools.syntax_check, source, program)


@mcp.tool()
def sap_read_cds(name: str, state: str = "A") -> dict:
    """Read a CDS view / DDL source by name. state 'A'=active, 'I'=inactive."""
    return _safe(tools.read_cds, name, state)


@mcp.tool()
def sap_textpool_read(program: str, language: str = "") -> dict:
    """Read a program's text elements (text symbols/selection texts/titles) via
    the dedicated ZMCP_ADT_TEXTPOOL FM."""
    return _safe(tools.textpool_read, program, language)


@mcp.tool()
def sap_run_unit_tests(class_name: str) -> dict:
    """Run ABAP Unit tests for a class and return failures. Read-only (executes
    tests, changes no repository objects)."""
    return _safe(tools.run_unit_tests, class_name)


@mcp.tool()
def sap_run_atc(object_type: str, object_name: str, variant: str = "DEFAULT") -> dict:
    """Run an ATC (ABAP Test Cockpit) check for an object. Requires the ABAP
    FORM atc_check to be implemented on the system (ships as a stub)."""
    return _safe(tools.run_atc, object_type, object_name, variant)


@mcp.tool()
def sap_activate(objects: list[dict]) -> dict:
    """Activate inactive repository objects. Requires SAP_ALLOW_WRITE=true.
    objects: list of {"type": <LIMU>, "name": <obj>}, e.g.
    [{"type":"REPS","name":"ZTEST"}]. Types: REPS, CLAS, FUGR, DYNP, DDLS…"""
    return _safe(tools.activate, objects)


@mcp.tool()
def sap_textpool_write(
    program: str,
    textpool: list[dict],
    language: str = "",
    active: bool = False,
) -> dict:
    """Write a program's text elements via ZMCP_ADT_TEXTPOOL. Requires
    SAP_ALLOW_WRITE=true. Defaults to WRITE_INACTIVE (staged; publishes when the
    program is activated); set active=true to write as active immediately.
    textpool: list of {"ID","KEY","ENTRY","LENGTH"} rows."""
    return _safe(tools.textpool_write, program, textpool, language, active)


@mcp.tool()
def sap_write_program(
    program: str, source: str, create: bool = False, title: str = ""
) -> dict:
    """Create or update an ABAP program's source.

    Disabled unless SAP_ALLOW_WRITE=true. Intended for DEV systems only.

    Args:
        program: Program name (custom objects should start with Z/Y).
        source: Full ABAP source code.
        create: True = new program in $TMP, saved INACTIVE (call sap_activate
            next). False = update an existing program: the source is
            syntax-checked, then written ACTIVE (there is no safe inactive save
            for existing programs on S4D).
        title: Program title for a new program (defaults to the program name).
    """
    return _safe(tools.write_program, program, source, create, title)


@mcp.tool()
def sap_run_rfc(function_name: str, params: dict | None = None) -> dict:
    """Advanced: call an arbitrary remote-enabled function module.

    Disabled unless SAP_ALLOW_WRITE=true, because arbitrary FMs may change data.
    Exception: FMs listed in SAP_RFC_READONLY_ALLOW may be called on a read-only
    profile (that list must only contain FMs that never change data).
    """
    return _safe(tools.run_rfc, function_name, params)


@mcp.tool()
def sap_write_ddic(
    kind: str,
    name: str,
    payload: dict,
    devclass: str = "",
    transport: str = "",
    update: bool = False,
) -> dict:
    """Create or update a DDIC object (staged INACTIVE) via the user-installed
    ZMCP_ADT_DDIC_* FMs. Disabled unless SAP_ALLOW_WRITE=true.

    Args:
        kind: TABL (tables/structures), DTEL (data element), DOMA (domain).
        name: Object name (Z/Y namespace).
        payload: DDIC content, uppercase field names:
            TABL {"dd02v": {...}, "dd03p": [...]} (structure: TABCLASS=INTTAB),
            DTEL {"dd04v": {...}}, DOMA {"dd01v": {...}, "dd07v": [...]}.
        devclass: Target package; empty/$TMP = local object.
        transport: Transport request for non-$TMP packages.
        update: False to create, True to update an existing object.

    Activate afterwards with sap_activate_ddic.
    """
    return _safe(tools.ddic_write, kind, name, payload, devclass, transport, update)


@mcp.tool()
def sap_delete_ddic(kind: str, name: str, transport: str = "") -> dict:
    """Delete a DDIC object (TABL/DTEL/DOMA). Disabled unless
    SAP_ALLOW_WRITE=true. Deletion is destructive - confirm before use."""
    return _safe(tools.ddic_delete, kind, name, transport)


@mcp.tool()
def sap_activate_ddic(kind: str, name: str) -> dict:
    """Activate an inactive DDIC object staged by sap_write_ddic
    (TABL/DTEL/DOMA). Disabled unless SAP_ALLOW_WRITE=true."""
    return _safe(tools.ddic_activate, kind, name)


if __name__ == "__main__":
    mcp.run()  # stdio transport
