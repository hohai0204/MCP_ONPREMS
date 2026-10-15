"""MCP-RFC bridge server for SAP ABAP development.

Exposes SAP repository read (and optionally write) operations to an MCP client
such as Claude Code, talking to the SAP system over RFC — which means it works
on RFC-only / SAProuter systems and classic ECC / R/3, without ADT/HTTP.

Run:  python server.py         (stdio transport, for Claude Code / MCP clients)
"""
from __future__ import annotations

import json
import os

from mcp.server.fastmcp import FastMCP

from sap import ops, tools
from sap.connection import SapConnectionError

mcp = FastMCP("sap-rfc-bridge")


# Output cap: Claude Code drops the connection when a tool result (or several
# parallel ones) gets huge, so every result is trimmed to SAP_MAX_OUTPUT_BYTES
# (default 200 KB; 0 disables). Lists are cut, long strings shortened.
def _max_output_bytes() -> int:
    try:
        return int((os.getenv("SAP_MAX_OUTPUT_BYTES") or "").strip() or 200_000)
    except ValueError:
        return 200_000


def _size(obj) -> int:
    return len(json.dumps(obj, ensure_ascii=False, default=str).encode("utf-8"))


def _shrink(obj, ratio: float):
    if isinstance(obj, list):
        keep = max(1, int(len(obj) * ratio))
        return [_shrink(x, ratio) for x in obj[:keep]]
    if isinstance(obj, dict):
        return {k: _shrink(v, ratio) for k, v in obj.items()}
    if isinstance(obj, str) and len(obj) > 400:
        return obj[: max(200, int(len(obj) * ratio))]
    return obj


def _cap(result: dict) -> dict:
    limit = _max_output_bytes()
    if limit <= 0:
        return result
    size = _size(result)
    if size <= limit:
        return result
    ratio = limit / size * 0.8
    out = _shrink(result, ratio)
    for _ in range(8):
        if _size(out) <= limit:
            break
        ratio *= 0.6
        out = _shrink(result, ratio)
    # keep paging honest: resume right after the last row actually returned
    if isinstance(out.get("rows"), list) and "offset" in out:
        out["row_count"] = len(out["rows"])
        out["has_more"] = True
        out["next_offset"] = out["offset"] + len(out["rows"])
    out["_truncated"] = {
        "original_bytes": size,
        "limit_bytes": limit,
        "hint": "Output cut. Narrow with fields/where/max_rows, or page with offset.",
    }
    return out


def _audit(fn, args, kwargs, outcome: str) -> None:
    """Append one JSON line per tool call to logs/audit.jsonl (git-ignored).
    Large or sensitive arguments (source, body, payload) are reduced to their
    length. Never raises: auditing must not break a tool call."""
    try:
        from datetime import datetime
        from pathlib import Path
        from sap.connection import get_client

        def _brief(v):
            if isinstance(v, str):
                return v if len(v) <= 200 else f"<{len(v)} chars>"
            if isinstance(v, (dict, list)):
                t = json.dumps(v, ensure_ascii=False, default=str)
                return v if len(t) <= 200 else f"<{type(v).__name__} {len(t)} chars>"
            return v

        cfg = get_client().config
        rec = {
            "ts": datetime.now().isoformat(timespec="seconds"),
            "tool": fn.__name__,
            "client": cfg.conn_params.get("client"),
            "user": cfg.conn_params.get("user"),
            "write_enabled": cfg.allow_write,
            "args": [_brief(a) for a in args],
            "kwargs": {k: _brief(v) for k, v in kwargs.items()},
            "outcome": outcome[:200],
        }
        d = Path(__file__).resolve().parent.parent / "logs"
        d.mkdir(exist_ok=True)
        with open(d / "audit.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass


def _safe(fn, *args, **kwargs) -> dict:
    """Run a tool, converting connection errors into a structured result so the
    MCP client sees a clean message instead of a stack trace. Results are
    capped to SAP_MAX_OUTPUT_BYTES. Every call is written to logs/audit.jsonl."""
    try:
        result = fn(*args, **kwargs)
        _audit(fn, args, kwargs, "ok")
        return _cap(result if isinstance(result, dict) else {"result": result})
    except SapConnectionError as exc:
        _audit(fn, args, kwargs, f"error: {exc}")
        return {"error": str(exc)}
    except Exception as exc:  # last-resort guard
        _audit(fn, args, kwargs, f"unexpected: {exc}")
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
    offset: int = 0,
) -> dict:
    """Read rows from a transparent SAP table via RFC_READ_TABLE.

    Args:
        table: Table name, e.g. 'T000' or 'TADIR'.
        fields: Optional list of column names to select (fewer = safer for the
            512-byte RFC_READ_TABLE row limit).
        where: Optional list of ABAP WHERE clauses, e.g. ["MANDT = '100'"].
        max_rows: Maximum rows to return (capped by SAP_MAX_ROWS, default 500).
        offset: Rows to skip, for paging. Use `next_offset` from the previous
            result when `has_more` is true.
    """
    return _safe(tools.read_table, table, fields, where, max_rows, offset)


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
def sap_read_dump(
    date: str | None = None,
    time: str | None = None,
    user: str | None = None,
    client: str | None = None,
    host: str | None = None,
    days: int = 7,
    context_lines: int = 5,
    with_text: bool = True,
) -> dict:
    """Detail of one ST22 runtime error (pair with sap_list_dumps).

    No filters = newest dump of the last `days` days. Narrow with date
    (YYYYMMDD), time (HHMMSS), user, client (MANDT of the dump), host.
    Returns runtime error, program/include/line, SY-fields, error texts and the
    source around the failing line (context_lines each side).
    """
    return _safe(tools.read_dump, date, time, user, client, host, days,
                 context_lines, with_text)


@mcp.tool()
def sap_read_applog(
    log_object: str | None = None,
    subobject: str | None = None,
    user: str | None = None,
    extnumber: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    max_logs: int = 10,
    with_messages: bool = True,
    max_messages: int = 100,
) -> dict:
    """Read application log entries (SLG1), newest first, with message texts.

    Filter by log_object/subobject, user, extnumber, date_from/date_to
    (YYYYMMDD; default last 7 days). Set with_messages=False for headers only.
    """
    return _safe(tools.read_applog, log_object, subobject, user, extnumber,
                 date_from, date_to, max_logs, with_messages, max_messages)


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
def sap_move_objects(objects: list[dict], package: str, transport: str) -> dict:
    """Move repository objects (e.g. classes/SEGW objects sitting in $TMP) to a
    real package and record them in a transport, with no dialogs. Requires
    SAP_ALLOW_WRITE=true. Does not release or import anything.
    objects: list of {"type": <R3TR type>, "name": <obj>}, e.g.
    [{"type":"CLAS","name":"ZCL_FOO_DPC"},{"type":"IWSV","name":"ZFOO_SRV"}].
    IWMO/IWSV names carry a padded version suffix - a unique prefix is enough.
    package: target package (not $TMP). transport: modifiable request or task."""
    return _safe(tools.move_objects, objects, package, transport)


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
        create: True = new program in $TMP that already holds the source; call
            sap_activate next to finish it (title, generation, drops the
            leftover inactive entry). False = update an existing program: the
            source is syntax-checked, then written ACTIVE and takes effect at
            once (there is no safe inactive save for existing programs on S4D).
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
def sap_gateway_call(
    uri: str,
    method: str = "GET",
    body: str | None = None,
    headers: dict | None = None,
) -> dict:
    """Call an OData/Gateway service like transaction /IWFND/GW_CLIENT, over RFC
    (no HTTP route to SAP needed; runs as the profile's RFC user/client).

    uri: path + query, e.g. "/sap/opu/odata/sap/ZCTD_PO_INFO_SRV/POJsonSet('4100032903')/$value".
         Must start with /sap/opu/odata/ or /sap/api/.
    method: GET (default, always allowed) or POST/PUT/PATCH/MERGE/DELETE
         (need SAP_ALLOW_WRITE=true; CSRF token is fetched automatically).
    body: request body (JSON) for non-GET.
    headers: extra request headers, e.g. {"X-Correlation-Id": "abc"}.
    Requires ZCTD_FM_GW_TEST installed on the target system.
    """
    return _safe(tools.gateway_call, uri, method, body, headers)


@mcp.tool()
def sap_gateway_errors(
    minutes: int = 60,
    user: str | None = None,
    service: str | None = None,
    uri_part: str | None = None,
    min_status: int = 0,
    opid: str | None = None,
    max_rows: int = 20,
    with_context: bool = False,
) -> dict:
    """Gateway error log (/IWFND/ERROR_LOG), newest first, with a summary by
    service/status/error text. Use it right after a 4xx/5xx from an OData call.

    minutes: look-back window (default 60). service/uri_part take '%'
    wildcards. min_status=400 keeps only failures. opid returns every entry of
    one failed request (the id shown in the error response).
    Requires ZMCP_ADT_GWLOG (abap/zmcp_adt_gwlog.abap).
    """
    return _safe(tools.gateway_errors, minutes, user, service, uri_part,
                 min_status, opid, max_rows, with_context)


@mcp.tool()
def sap_gateway_admin(
    action: str = "status",
    service: str | None = None,
    version: str = "0001",
) -> dict:
    """Gateway service administration.

    action=status: registered services (/IWFND/MAINT_SERVICE view) with model
      ids and last change; `service` accepts '%' wildcards. Read only.
    action=clear_cache: clear the metadata cache of one service so changed
      entity sets/fields show up (/IWFND/CACHE_CLEANUP + /IWBEP/CACHE_CLEANUP).
      Disabled unless SAP_ALLOW_WRITE=true (or both cleanup FMs are on
      SAP_RFC_READONLY_ALLOW). The cache is system-wide, not per client.
    """
    return _safe(tools.gateway_admin, action, service, version)


@mcp.tool()
def sap_health() -> dict:
    """Check which helper function modules (ZMCP_ADT_*, ZCTD_FM_GW_TEST, the
    standard cleanup/enqueue FMs) exist on the connected system and which
    tool each one enables. Run it first when a tool reports a missing FM."""
    return _safe(ops.health)


@mcp.tool()
def sap_read_jobs(
    name: str | None = None,
    user: str | None = None,
    status: str | None = None,
    days: int = 2,
    max_rows: int = 50,
) -> dict:
    """Background jobs (SM37 list from TBTCO), newest first. name takes '%'
    wildcards; status: S scheduled, P released, R running, F finished,
    A aborted. days = how far back by scheduled start (default 2)."""
    return _safe(ops.read_jobs, name, user, status, days, max_rows)


@mcp.tool()
def sap_read_locks(
    user: str | None = None,
    table: str | None = None,
    argument: str | None = None,
    max_rows: int = 100,
) -> dict:
    """Enqueue locks (SM12) of the connected client. Filter by lock owner,
    table (lock object table) or lock argument prefix."""
    return _safe(ops.read_locks, user, table, argument, max_rows)


@mcp.tool()
def sap_create_transport(
    description: str,
    owner: str | None = None,
    category: str = "K",
) -> dict:
    """Create a transport request (category K workbench, W customizing).
    Disabled unless SAP_ALLOW_WRITE=true. Release and import remain human."""
    return _safe(ops.create_transport, description, owner, category)


@mcp.tool()
def sap_transport_check(trkorr: str, max_objects: int = 200) -> dict:
    """Read-only pre-release check of a request: empty request, objects in a
    local ($) package, objects that also sit in another open request."""
    return _safe(ops.transport_check, trkorr, max_objects)


@mcp.tool()
def sap_read_message_class(
    msgclass: str,
    lang: str | None = None,
    max_rows: int = 500,
) -> dict:
    """Messages of a message class (SE91 / T100) with their texts."""
    return _safe(ops.read_message_class, msgclass, lang, max_rows)


@mcp.tool()
def sap_join_read(
    left: dict,
    right: dict,
    on: dict,
    how: str = "inner",
    max_rows: int = 200,
) -> dict:
    """Join two tables (client-side; RFC_READ_TABLE has no JOIN).

    left/right: {table, fields?, where?}. on: {left_field: right_field}.
    how: inner or left. The right table is read only for the key values found
    on the left, so make the left side selective. The sensitive-table
    blocklist applies to both sides.
    """
    return _safe(ops.join_read, left, right, on, how, max_rows)


@mcp.tool()
def sap_user_auth(user: str, object: str, max_rows: int = 200) -> dict:
    """Authorization values a user HAS for one authorization object, grouped
    by authorization (e.g. user HAIHT, object S_DEVELOP). Use to explain a
    'no authorization' error."""
    return _safe(ops.user_auth, user, object, max_rows)


@mcp.tool()
def sap_write_function_module(
    name: str,
    source: str,
    create: bool = False,
    function_group: str | None = None,
    short_text: str = "",
    remote: bool = True,
    imports: list[dict] | None = None,
    exports: list[dict] | None = None,
    changing: list[dict] | None = None,
    exceptions: list[str] | None = None,
    transport: str = "",
) -> dict:
    """Write a function module. Requires SAP_ALLOW_WRITE=true; honours
    SAP_ALLOWED_PACKAGES. The whole function group is syntax-checked with the
    new source first (one syntax error breaks every FM of the group).

    create=False: replace the source of an existing FM (full text incl.
      FUNCTION ... ENDFUNCTION, interface unchanged); returns `backup`.
    create=True: new FM in an existing function group. `source` is the
      body only. Interface: imports/exports/changing = [{name, type,
      optional?, default?, by_reference?}], exceptions = [names],
      remote=True for RFC. `transport` is required unless the group is local.
      A group that fails its check after creation gets the FM deleted again.
    """
    return _safe(ops.write_function_module, name, source, create, function_group,
                 short_text, remote, imports, exports, changing, exceptions,
                 transport)


@mcp.tool()
def sap_delete_function_module(name: str) -> dict:
    """Delete one function module written by mistake. Only Z/Y modules in a
    LOCAL package ($TMP...) and never the bridge's own FMs; transportable
    objects must be deleted in SE37. Returns the deleted source as `backup`.
    Requires SAP_ALLOW_WRITE=true and ZMCP_ADT_FMDELETE
    (abap/zmcp_adt_fmdelete.abap). Destructive: confirm before use."""
    return _safe(ops.delete_function_module, name)


@mcp.tool()
def sap_gateway_test(
    cases: list[dict],
    stop_on_fail: bool = False,
    diagnose: bool = True,
) -> dict:
    """Run a batch of OData test cases and report pass/fail per case.

    case: {name, uri, method="GET", body, headers, expect_status (int or list,
    default any 2xx), expect_contains, expect_json: [{path:"d.results.0.Matnr",
    equals|contains|min|max|count_min|exists}], save: {var: "d.Key"}}.
    `{{var}}` in later cases is replaced by a saved value, so POST -> GET
    chains work. Non-GET cases need SAP_ALLOW_WRITE=true. With diagnose=True a
    failed 4xx/5xx case attaches the newest Gateway error-log entries.
    """
    return _safe(tools.gateway_test, cases, stop_on_fail, diagnose)


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
