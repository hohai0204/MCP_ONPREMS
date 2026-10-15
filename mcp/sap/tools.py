"""Tool implementations: each wraps one or more standard SAP function modules.

Design notes
------------
* Every function returns a plain dict/list (JSON-serialisable) so it can be
  handed straight back through MCP.
* Function modules used here are standard, remote-enabled SAP FMs. Their exact
  availability and interface can vary by release; the classic ones below are
  chosen for broad ECC / R/3 -> S/4HANA coverage but SHOULD be validated on the
  target system. [Unverified across all releases]
* Write operations go through `_require_write()` which raises unless
  SAP_ALLOW_WRITE=true, so read-only setups cannot mutate the system.
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
from datetime import date, datetime, timedelta
from typing import Any

from .connection import SapConnectionError, get_client

# ---------------------------------------------------------------------------
# sensitive-table read policy (idea borrowed from abap-mcp-adt-powerup's
# SC4SAP_POLICY): block row extraction from tables holding credentials/PII.
# Override or extend via SAP_TABLE_BLOCKLIST (comma-separated, * wildcards).
# ---------------------------------------------------------------------------
_DEFAULT_TABLE_BLOCKLIST = [
    "USR02", "USH02", "USRPWDHISTORY",          # password hashes
    "PA0*", "PB0*", "HRP*",                     # HR master data (PII)
    "SECSTORE*", "RSECTAB", "RSECACTB",         # secure storage
    "USOBAUTHINACTIVE", "UST04",                # auth data
]


def _table_blocklist() -> list[str]:
    env = (os.getenv("SAP_TABLE_BLOCKLIST") or "").strip()
    if env:
        return [p.strip().upper() for p in env.split(",") if p.strip()]
    return _DEFAULT_TABLE_BLOCKLIST


def _check_table_allowed(table: str) -> None:
    t = table.upper()
    for pat in _table_blocklist():
        if fnmatch.fnmatch(t, pat):
            raise SapConnectionError(
                f"Reading table {t} is blocked by the sensitive-table policy "
                f"(matched '{pat}'). Set SAP_TABLE_BLOCKLIST to adjust."
            )


# ---------------------------------------------------------------------------
# function-module deny list for sap_run_rfc (idea borrowed from
# zcl_mcp_rfc_http_handler's hardcoded deny list). Blocks high-risk FMs — OS
# command execution, arbitrary code, mass deletion, raw SQL, file transfer,
# task handling — even when SAP_ALLOW_WRITE is on. Override via SAP_FM_DENYLIST
# (comma-separated, * wildcards); the default list is REPLACED when set.
# ---------------------------------------------------------------------------
_DEFAULT_FM_DENYLIST = [
    "RFC_ABAP_INSTALL_AND_RUN",   # run arbitrary ABAP
    "SUBST_*", "SXPG_*",          # OS command / external program execution
    "RFC_START_PROGRAM", "RFC_REMOTE_EXEC",
    "EPS_*", "C13Z_*", "ARCHIVFILE_*", "SCMS_*",  # file / content transfer
    "DB_*", "ADBC_*", "RFC_READ_TABLE_SQL",       # raw DB / SQL access
    "TH_*",                       # kernel / work-process admin
    "RS_DELETE_*", "RSAU_*", "*_DELETE_ALL", "MASS_*",  # mass delete/change
    "BAPI_USER_CREATE*", "SUSR_*", "SU01_*",      # user administration
    "RFC_SET_REG_SERVER_PROPERTY",
]


def _fm_denylist() -> list[str]:
    env = (os.getenv("SAP_FM_DENYLIST") or "").strip()
    if env:
        return [p.strip().upper() for p in env.split(",") if p.strip()]
    return _DEFAULT_FM_DENYLIST


# ---------------------------------------------------------------------------
# read-only FM allowlist for sap_run_rfc. run_rfc is a write-class tool, so a
# read-only profile (SAP_ALLOW_WRITE=false, e.g. the client with real data)
# cannot call even harmless FMs. SAP_RFC_READONLY_ALLOW lists FMs (comma-
# separated, * wildcards) that a read-only profile may call anyway. Empty by
# default. Only list FMs that never change data; the deny list still applies.
# ---------------------------------------------------------------------------
def _rfc_readonly_allowlist() -> list[str]:
    env = (os.getenv("SAP_RFC_READONLY_ALLOW") or "").strip()
    return [p.strip().upper() for p in env.split(",") if p.strip()]


def _rfc_readonly_allowed(function_name: str) -> bool:
    fm = function_name.upper()
    return any(fnmatch.fnmatch(fm, pat) for pat in _rfc_readonly_allowlist())


def _check_fm_allowed(function_name: str) -> None:
    fm = function_name.upper()
    for pat in _fm_denylist():
        if fnmatch.fnmatch(fm, pat):
            raise SapConnectionError(
                f"Calling function module {fm} is blocked by the FM deny list "
                f"(matched '{pat}'). Adjust SAP_FM_DENYLIST if this is intended."
            )


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _require_write() -> None:
    if not get_client().config.allow_write:
        raise SapConnectionError(
            "Write operations are disabled. Set SAP_ALLOW_WRITE=true in .env to "
            "enable create/update/activate tools (use only on a DEV system)."
        )


def _lines_to_source(rows: list[dict], key: str = "LINE") -> str:
    """Join an ABAP source table (list of {LINE: '...'}) into one string."""
    return "\n".join(r.get(key, "") for r in rows)


def _source_to_lines(source: str, key: str = "LINE", width: int = 72) -> list[dict]:
    """Split a source string into the row structure most ABAP source FMs expect.

    Classic report source tables hold 72-char lines; we hard-wrap defensively.
    """
    out: list[dict] = []
    for raw in source.replace("\r\n", "\n").split("\n"):
        if len(raw) <= width:
            out.append({key: raw})
        else:
            for i in range(0, len(raw), width):
                out.append({key: raw[i : i + width]})
    return out


def _wrap_options(where_str: str, width: int = 72) -> list[dict]:
    """Split a WHERE string into RFC_READ_TABLE OPTIONS rows of <= `width` chars.

    RFC_READ_TABLE caps each OPTIONS line at 72 chars and concatenates the rows
    back together WITHOUT inserting spaces, so we break only at word boundaries
    and keep a trailing space on every line to preserve token separation.
    """
    words = [w for w in where_str.split(" ") if w != ""]
    lines: list[str] = []
    cur = ""
    for w in words:
        if not cur:
            cur = w
        elif len(cur) + 1 + len(w) + 1 <= width:  # +1 join space, +1 trailing
            cur = f"{cur} {w}"
        else:
            lines.append(cur + " ")
            cur = w
    if cur:
        lines.append(cur + " ")
    return [{"TEXT": line} for line in lines]


# ---------------------------------------------------------------------------
# connectivity
# ---------------------------------------------------------------------------
def ping() -> dict:
    """Return system info for the connected SAP system (also proves logon)."""
    client = get_client()
    res = client.call("RFC_SYSTEM_INFO")
    info = res.get("RFCSI_EXPORT", {})
    return {
        "connected": True,
        "profile": client.config.profile,
        "system_id": info.get("RFCSYSID"),
        "host": info.get("RFCHOST"),
        "database": info.get("RFCDBSYS"),
        "kernel_release": info.get("RFCKERNRL"),
        "sap_release": info.get("RFCSAPRL"),
        "ip": info.get("RFCIPADDR"),
        "connection": client.config.masked,
    }


# ---------------------------------------------------------------------------
# generic table read
# ---------------------------------------------------------------------------
def read_table(
    table: str,
    fields: list[str] | None = None,
    where: list[str] | None = None,
    max_rows: int = 100,
    offset: int = 0,
) -> dict:
    """Read a transparent table via RFC_READ_TABLE.

    `where` is a list of conditions that are AND-ed together; each may itself
    contain OR. Long clauses are auto-wrapped to satisfy the 72-char OPTIONS
    line limit.

    Note the RFC_READ_TABLE limits: total selected width <= 512 bytes and no
    deep/long fields. Good enough for Dictionary / repository metadata.
    """
    _check_table_allowed(table)
    try:
        row_cap = int((os.getenv("SAP_MAX_ROWS") or "").strip() or 500)
    except ValueError:
        row_cap = 500
    want = max(1, min(int(max_rows), row_cap)) if row_cap > 0 else max(1, int(max_rows))
    skip = max(0, int(offset or 0))
    call_kwargs: dict[str, Any] = {
        "QUERY_TABLE": table.upper(),
        "DELIMITER": "|",
        "ROWCOUNT": want + 1,  # one extra row tells us whether more exist
        "ROWSKIPS": skip,
    }
    if fields:
        call_kwargs["FIELDS"] = [{"FIELDNAME": f.upper()} for f in fields]
    if where:
        combined = " AND ".join(f"( {clause} )" for clause in where)
        call_kwargs["OPTIONS"] = _wrap_options(combined)

    res = get_client().call("RFC_READ_TABLE", **call_kwargs)
    field_defs = res.get("FIELDS", [])
    names = [f["FIELDNAME"] for f in field_defs]
    rows: list[dict] = []
    for entry in res.get("DATA", []):
        parts = entry["WA"].split("|")
        rows.append({name: (parts[i].strip() if i < len(parts) else "")
                     for i, name in enumerate(names)})
    has_more = len(rows) > want
    rows = rows[:want]
    out = {"table": table.upper(), "fields": names, "row_count": len(rows), "rows": rows,
           "offset": skip, "has_more": has_more}
    if has_more:
        out["next_offset"] = skip + want
    if want < int(max_rows):
        out["max_rows_capped_to"] = want
    return out


# ---------------------------------------------------------------------------
# repository read
# ---------------------------------------------------------------------------
def read_program(program: str, state: str = "A") -> dict:
    """Read ABAP report/program source.

    state "A" (default) = active version, "I" = inactive version (saved, not yet
    activated), "latest" = inactive if it exists, else active. Versions are read
    with ZMCP_ADT_DISPATCH READ_PROGRAM. RPY_PROGRAM_READ is only the fallback for
    "A" when the dispatcher lacks that action: it returns the caller's inactive
    version when there is one, so it is not a reliable "active" read.
    """
    st = (state or "A").upper()
    name = program.upper()

    def _dispatch(ver: str) -> list[str] | None:
        try:
            res = adt_dispatch("READ_PROGRAM", {"name": name, "state": ver})
        except SapConnectionError as exc:
            if "no version in state" in str(exc):
                return []
            return None  # dispatcher not updated: caller falls back
        return (res.get("result") or {}).get("LINES") or []

    if st in ("I", "LATEST"):
        lines = _dispatch("I")
        if lines is None:
            raise SapConnectionError(
                "ZMCP_ADT_DISPATCH has no READ_PROGRAM action - reinstall abap/zmcp_adt_dispatch.abap"
            )
        if lines or st == "I":
            return {"program": name, "state": "I", "line_count": len(lines),
                    "source": "\n".join(lines)}
    lines = _dispatch("A")
    if lines is not None:
        return {"program": name, "state": "A", "line_count": len(lines),
                "source": "\n".join(lines)}
    res = get_client().call(
        "RPY_PROGRAM_READ",
        PROGRAM_NAME=program.upper(),
        WITH_LOWERCASE="X",
        ONLY_SOURCE="X",
    )
    # Different releases populate different source tables; take the first non-empty.
    for tbl in ("SOURCE_EXTENDED", "SOURCE"):
        rows = res.get(tbl)
        if rows:
            key = "LINE" if tbl == "SOURCE_EXTENDED" else "LINE"
            return {
                "program": program.upper(),
                "line_count": len(rows),
                "source": _lines_to_source(rows, key),
            }
    return {"program": program.upper(), "line_count": 0, "source": ""}


def read_function_module(function_name: str) -> dict:
    """Read a function module's source + interface.

    Tries RPY_FUNCTIONMODULE_READ first; falls back to the _NEW variant when
    the source has lines wider than 72 chars (the classic FM aborts with
    "Source wider than 72 char"). The _NEW variant returns the source as one
    string in NEW_SOURCE instead of a line table.
    """
    client = get_client()
    fm = function_name.upper()
    try:
        res = client.call("RPY_FUNCTIONMODULE_READ", FUNCTIONNAME=fm)
        source = _lines_to_source(res.get("SOURCE", []), "LINE")
    except SapConnectionError:
        res = client.call("RPY_FUNCTIONMODULE_READ_NEW", FUNCTIONNAME=fm)
        new_src = res.get("NEW_SOURCE")
        if isinstance(new_src, list):  # table of plain-string lines
            source = "\n".join(
                x if isinstance(x, str) else next(iter(x.values()), "")
                for x in new_src
            )
        else:
            source = new_src or _lines_to_source(res.get("SOURCE", []), "LINE")
    return {
        "function": fm,
        "function_group": res.get("FUNCTION_POOL"),
        "short_text": res.get("SHORT_TEXT"),
        "remote_enabled": res.get("REMOTE_CALL") == "R",
        "source": source,
        "import_params": res.get("IMPORT_PARAMETER", []),
        "export_params": res.get("EXPORT_PARAMETER", []),
        "changing_params": res.get("CHANGING_PARAMETER", []),
        "tables_params": res.get("TABLES_PARAMETER", []),
        "exceptions": res.get("EXCEPTION_LIST", []),
    }


def search_objects(
    obj_type: str | None = None,
    name_pattern: str = "",
    max_rows: int = 50,
) -> dict:
    """Search repository objects in TADIR (dev objects catalogue).

    obj_type examples: PROG (program), FUGR (function group), CLAS (class),
    TABL (table), DDLS (CDS). name_pattern uses ABAP LIKE syntax (e.g. 'Z%').
    """
    conditions: list[str] = []
    if obj_type:
        conditions.append("PGMID = 'R3TR'")
        conditions.append(f"OBJECT = '{obj_type.upper()}'")
    if name_pattern:
        conditions.append(f"OBJ_NAME LIKE '{name_pattern.upper()}'")
    return read_table(
        "TADIR",
        fields=["PGMID", "OBJECT", "OBJ_NAME", "DEVCLASS", "AUTHOR"],
        where=conditions or None,
        max_rows=max_rows,
    )


def read_class(class_name: str, state: str = "A") -> dict:
    """Read an ABAP class/interface source via SIW_RFC_READ_CLIF_SOURCE.

    The FM returns source per include-section (public/protected/private
    definitions, local classes, and one section per method). We stitch them
    into one readable listing and also return a per-section index.

    Args:
        class_name: Class or interface name (e.g. ZCL_FOO).
        state: 'A' for active version, 'I' for inactive. Falls back A->I.
    """
    client = get_client()
    states = [state] if state else ["A", "I"]
    rows: list[dict] = []
    exc: dict = {}
    used_state = state
    for st in states:
        res = client.call(
            "SIW_RFC_READ_CLIF_SOURCE", I_CLIF=class_name.upper(), I_STATE=st
        )
        rows = res.get("E_TAB_SOURCE", []) or []
        exc = res.get("E_STR_EXCEPTION", {}) or {}
        used_state = st
        if rows:
            break

    if not rows:
        msg = exc.get("MSGSTRING") or exc.get("EXCEPTION") or "class not found or empty"
        raise SapConnectionError(f"Could not read class {class_name.upper()}: {msg}")

    seen: set = set()
    sections: list[dict] = []
    listing: list[str] = []
    for r in rows:
        include = r.get("EXTENSION", "")
        method = r.get("METHODNAME", "")
        key = (include, method)
        if key in seen:  # some sections (e.g. CU) come back duplicated
            continue
        seen.add(key)
        code = r.get("TAB_CODE", []) or []
        # TAB_CODE items are plain strings on this release, but be defensive.
        lines = [c if isinstance(c, str) else next(iter(c.values()), "") for c in code]
        sections.append(
            {"include": include, "method": method, "line_count": len(lines)}
        )
        header = f"*--- {include}" + (f" {method}" if method else "") + " ---"
        listing.append(header)
        listing.extend(lines)

    return {
        "class": class_name.upper(),
        "state": used_state,
        "section_count": len(sections),
        "sections": sections,
        "source": "\n".join(listing),
    }


# ---------------------------------------------------------------------------
# class-level analysis  (ideas ported from vibing-steampunk / vsp)
# ---------------------------------------------------------------------------
def read_method(class_name: str, method: str, state: str = "A") -> dict:
    """Read ONE method's source from a class (vsp's "method-level surgery").

    Fetches the class over RFC and returns only the requested method section —
    a fraction of the tokens of the full class. Method names are matched
    case-insensitively.
    """
    cls = read_class(class_name, state)
    wanted = method.upper()
    methods = [s["method"] for s in cls["sections"] if s["method"]]
    target = next(
        (s for s in cls["sections"] if s["method"].upper() == wanted), None
    )
    if target is None:
        raise SapConnectionError(
            f"Method {wanted} not found in {cls['class']}. "
            f"Available: {', '.join(methods) or '(none)'}"
        )
    # Slice the stitched listing: sections were emitted in order with headers.
    lines = cls["source"].splitlines()
    header = f"*--- {target['include']} {target['method']} ---"
    start = lines.index(header)
    end = start + 1
    while end < len(lines) and not lines[end].startswith("*--- "):
        end += 1
    return {
        "class": cls["class"],
        "method": target["method"],
        "state": cls["state"],
        "line_count": end - start - 1,
        "source": "\n".join(lines[start + 1 : end]),
        "all_methods": methods,
    }


def class_api(class_name: str, with_dependencies: bool = False) -> dict:
    """Return a class's public API only (vsp's "context compression").

    Extracts the definition/public section (the CU include) without method
    implementations. With `with_dependencies`, also scans it for referenced
    Z*/Y* classes (TYPE REF TO / NEW / INHERITING FROM) and appends THEIR
    public sections — a compressed context bundle for AI consumption.
    """
    cls = read_class(class_name)
    lines = cls["source"].splitlines()

    def section(listing: list[str], include: str) -> str:
        header = f"*--- {include} ---"
        if header not in listing:
            return ""
        start = listing.index(header) + 1
        end = start
        while end < len(listing) and not listing[end].startswith("*--- "):
            end += 1
        return "\n".join(listing[start:end])

    api = section(lines, "CU")
    deps: list[dict] = []
    if with_dependencies:
        pat = re.compile(
            r"(?:TYPE\s+REF\s+TO|NEW|INHERITING\s+FROM)\s+([ZY]\w+)",
            re.IGNORECASE,
        )
        seen: set = set()
        for m in pat.finditer(api):
            dep = m.group(1).upper()
            if dep in seen or dep == cls["class"]:
                continue
            seen.add(dep)
            if len(deps) >= 5:  # cap like vsp does
                break
            try:
                dep_cls = read_class(dep)
                deps.append(
                    {"class": dep, "public_api": section(dep_cls["source"].splitlines(), "CU")}
                )
            except SapConnectionError:
                continue  # referenced name isn't a readable class
    return {
        "class": cls["class"],
        "public_api": api,
        "api_line_count": len(api.splitlines()),
        "full_class_line_count": len(lines),
        "dependencies": deps,
    }


def dead_code(package: str, max_classes: int = 20) -> dict:
    """Find potentially unused methods in a package (vsp's "dead code" idea).

    For each class in the package (TADIR), lists its methods (SEOCOMPO) and
    checks the WBCROSSGT where-used index: a method is
      live      - referenced from outside its own class,
      internal  - referenced only from its own class includes,
      dead      - no references found at all.
    The WBCROSSGT index only covers compiled references — dynamic calls
    (CALL METHOD ... dynamic, RTTI) will NOT show up, so treat "dead" as a
    review candidate, not a verdict.
    """
    pkg = package.upper()
    classes = read_table(
        "TADIR",
        fields=["OBJ_NAME"],
        where=["PGMID = 'R3TR'", "OBJECT = 'CLAS'", f"DEVCLASS = '{pkg}'"],
        max_rows=max_classes,
    )
    results: list[dict] = []
    for row in classes["rows"]:
        cls = row["OBJ_NAME"]
        comps = read_table(
            "SEOCOMPO",
            fields=["CMPNAME"],
            where=[f"CLSNAME = '{cls}'", "CMPTYPE = '1'"],
            max_rows=200,
        )
        methods: list[dict] = []
        for c in comps["rows"]:
            meth = c["CMPNAME"].upper()
            refs = read_table(
                "WBCROSSGT",
                fields=["INCLUDE"],
                where=["OTYPE = 'ME'", f"NAME = '{cls}\\ME:{meth}'"],
                max_rows=50,
            )
            includes = [r_["INCLUDE"] for r_ in refs["rows"]]
            external = [i for i in includes if not i.startswith(cls)]
            status = "live" if external else ("internal" if includes else "dead")
            methods.append({"method": meth, "status": status, "ref_count": len(includes)})
        results.append(
            {
                "class": cls,
                "method_count": len(methods),
                "dead": [m["method"] for m in methods if m["status"] == "dead"],
                "internal": [m["method"] for m in methods if m["status"] == "internal"],
                "live_count": sum(1 for m in methods if m["status"] == "live"),
            }
        )
    return {
        "package": pkg,
        "classes_analyzed": len(results),
        "classes_in_package": classes["row_count"],
        "results": results,
        "note": "WBCROSSGT misses dynamic calls; 'dead' means review candidate.",
    }


# ---------------------------------------------------------------------------
# DDIC / diagnostics / transports  (read-only)
# ---------------------------------------------------------------------------
def ddic_info(name: str) -> dict:
    """Describe a DDIC table/structure via DDIF_FIELDINFO_GET: field list with
    types, lengths, and texts. Works for transparent tables and structures."""
    res = get_client().call(
        "DDIF_FIELDINFO_GET", TABNAME=name.upper(), LANGU="E"
    )
    fields = [
        {
            "field": f.get("FIELDNAME"),
            "type": f.get("DATATYPE"),
            "length": (f.get("LENG") or "").lstrip("0") or "0",
            "decimals": (f.get("DECIMALS") or "").lstrip("0") or "0",
            "key": f.get("KEYFLAG") == "X",
            "data_element": f.get("ROLLNAME"),
            "text": f.get("FIELDTEXT"),
        }
        for f in res.get("DFIES_TAB", [])
    ]
    return {"name": name.upper(), "field_count": len(fields), "fields": fields}


def list_dumps(days: int = 7, max_rows: int = 50) -> dict:
    """List recent ABAP runtime errors (ST22 dumps) via /SDF/GET_DUMP_LOG.

    Returns date, time, user, host, and the runtime-error name per dump —
    enough to spot what is failing; open ST22 for the full dump text.
    """
    today = date.today()
    res = get_client().call(
        "/SDF/GET_DUMP_LOG",
        DATE_FROM=(today - timedelta(days=int(days))).strftime("%Y%m%d"),
        DATE_TO=today.strftime("%Y%m%d"),
    )
    logs = res.get("ET_E2E_LOG", []) or []
    dumps = [
        {
            "date": x.get("E2E_DATE"),
            "time": x.get("E2E_TIME"),
            "user": x.get("E2E_USER"),
            "host": x.get("E2E_HOST"),
            "runtime_error": x.get("FIELD1"),
        }
        for x in logs[: int(max_rows)]
    ]
    return {"days": days, "total_found": len(logs), "dumps": dumps}


def list_transports(
    user: str | None = None,
    status: str | None = None,
    max_rows: int = 50,
) -> dict:
    """List transport requests from E070.

    Args:
        user: Filter by owner (AS4USER).
        status: Filter by status, e.g. 'D' (modifiable) or 'R' (released).
    """
    conditions: list[str] = []
    if user:
        conditions.append(f"AS4USER = '{user.upper()}'")
    if status:
        conditions.append(f"TRSTATUS = '{status.upper()}'")
    return read_table(
        "E070",
        fields=["TRKORR", "TRFUNCTION", "TRSTATUS", "AS4USER", "AS4DATE", "STRKORR"],
        where=conditions or None,
        max_rows=max_rows,
    )


def read_transport(trkorr: str, max_rows: int = 200) -> dict:
    """Read one transport request: header (E070) plus its object list (E071)."""
    tr = trkorr.upper()
    header = read_table(
        "E070",
        fields=["TRKORR", "TRFUNCTION", "TRSTATUS", "AS4USER", "AS4DATE", "STRKORR"],
        where=[f"TRKORR = '{tr}'"],
        max_rows=1,
    )
    objects = read_table(
        "E071",
        fields=["PGMID", "OBJECT", "OBJ_NAME", "OBJFUNC"],
        where=[f"TRKORR = '{tr}'"],
        max_rows=max_rows,
    )
    return {
        "transport": tr,
        "header": header["rows"][0] if header["rows"] else None,
        "object_count": objects["row_count"],
        "objects": objects["rows"],
    }


def where_used(name: str, max_rows: int = 100) -> dict:
    """Find includes referencing a global type/class/method via WBCROSSGT.

    OTYPE in results: TY=type/class, ME=method, DA=data, EV=event.
    Covers OO/global-type references; classic FM-call usage (CROSS) may be
    empty depending on index state.
    """
    res = read_table(
        "WBCROSSGT",
        fields=["OTYPE", "NAME", "INCLUDE"],
        where=[f"NAME LIKE '{name.upper()}%'"],
        max_rows=max_rows,
    )
    return {
        "name": name.upper(),
        "hit_count": res["row_count"],
        "references": res["rows"],
    }


# ---------------------------------------------------------------------------
# custom ZMCP_ADT_DISPATCH bridge (user-installed FM on the SAP system)
# ---------------------------------------------------------------------------
# The dispatcher (function group ZMCP_ADT_UTILS, from abap-mcp-adt-powerup)
# exposes Dynpro/GUI-Status operations that no standard RFC FM covers.
# Protocol: IV_ACTION + IV_PARAMS(JSON) -> EV_SUBRC / EV_MESSAGE / EV_RESULT(JSON).
_DISPATCH_FM = "ZMCP_ADT_DISPATCH"
_DISPATCH_READ_ACTIONS = {
    "DYNPRO_READ", "CUA_FETCH",
    "SYNTAX_CHECK", "READ_DDLS", "READ_PROGRAM",
    "RUN_UNIT_TESTS", "ATC_CHECK",
}
_DISPATCH_WRITE_ACTIONS = {
    "DYNPRO_INSERT", "DYNPRO_DELETE", "CUA_WRITE", "CUA_DELETE",
    "ACTIVATE", "MOVE_OBJECTS",
}

# Text elements have their own dedicated FM (ZMCP_ADT_TEXTPOOL), which supports
# a WRITE_INACTIVE action (stage inactive, publish on activation).
_TEXTPOOL_FM = "ZMCP_ADT_TEXTPOOL"


def adt_dispatch(action: str, params: dict | None = None) -> dict:
    """Call the user-installed ZMCP_ADT_DISPATCH function module.

    Read actions (DYNPRO_READ, CUA_FETCH) are always allowed; every other
    action — including unknown/future ones — requires SAP_ALLOW_WRITE=true.
    """
    act = (action or "").upper()
    if act not in _DISPATCH_READ_ACTIONS:
        _require_write()
    res = get_client().call(
        _DISPATCH_FM, IV_ACTION=act, IV_PARAMS=json.dumps(params or {})
    )
    subrc = res.get("EV_SUBRC", 0)
    message = res.get("EV_MESSAGE", "")
    raw = res.get("EV_RESULT", "")
    if subrc != 0:
        detail = f" | result: {raw[:1500]}" if raw and raw != '{"activated":false}' else ""
        raise SapConnectionError(
            f"{_DISPATCH_FM} action {act} failed (subrc={subrc}): {message}{detail}"
        )
    try:
        result = json.loads(raw) if raw else None
    except ValueError:
        result = raw  # not JSON; return as-is
    return {"action": act, "message": message, "result": result}


def read_screen(program: str, dynpro: str) -> dict:
    """Read a Dynpro (screen) definition: header, containers, fields, flow
    logic. Uses the ZMCP_ADT_DISPATCH -> RPY_DYNPRO_READ path."""
    return adt_dispatch(
        "DYNPRO_READ", {"program": program.upper(), "dynpro": str(dynpro)}
    )


def read_gui_status(program: str, language: str = "") -> dict:
    """Read a program's GUI status/CUA (menus, toolbars, function keys).
    Uses the ZMCP_ADT_DISPATCH -> RS_CUA_INTERNAL_FETCH path."""
    params: dict = {"program": program.upper()}
    if language:
        params["language"] = language
    return adt_dispatch("CUA_FETCH", params)


def syntax_check(source: str, program: str = "") -> dict:
    """Syntax-check ABAP source without saving it (ZMCP_ADT_DISPATCH ->
    SYNTAX-CHECK). `program` is an existing program name used as context;
    defaults to a scratch report name."""
    lines = source.replace("\r\n", "\n").split("\n")
    return adt_dispatch(
        "SYNTAX_CHECK",
        {"program": (program or "SAPMV45A").upper(), "source": lines},
    )


def activate(objects: list[dict]) -> dict:
    """Activate inactive repository objects. Requires SAP_ALLOW_WRITE=true.

    `objects` is a list of {"type": <LIMU>, "name": <obj>}, e.g.
    [{"type": "REPS", "name": "ZTEST"}]. LIMU types: REPS=report source,
    CLAS=class, FUGR/FUNC=function, DYNP=screen, CUAD=gui status, DDLS=cds.
    """
    return adt_dispatch("ACTIVATE", {"objects": objects})


def move_objects(objects: list[dict], package: str, transport: str) -> dict:
    """Move repository objects to a real package and record them in a transport,
    without dialogs. Requires SAP_ALLOW_WRITE=true (DEV systems only).

    `objects` is a list of {"type": <R3TR type>, "name": <obj>}, e.g.
    [{"type":"CLAS","name":"ZCL_FOO"},{"type":"IWSV","name":"ZFOO_SRV"}]. IWMO/IWSV
    names have a padded version suffix; a unique prefix is enough. `transport` is
    the request (or task) that must be modifiable; objects land in the caller's
    task. `package` must not be $TMP. Uses ZMCP_ADT_DISPATCH MOVE_OBJECTS.
    """
    if not (package or "").strip() or package.strip().upper() == "$TMP":
        raise SapConnectionError("move_objects needs a real target package, not $TMP.")
    if not (transport or "").strip():
        raise SapConnectionError("move_objects needs a transport request.")
    _require_write()
    _check_devclass_allowed(package)
    return adt_dispatch(
        "MOVE_OBJECTS",
        {"objects": objects, "package": package.upper(), "transport": transport.upper()},
    )


def read_cds(name: str, state: str = "A") -> dict:
    """Read CDS/DDL source from DDDDLSRC (ZMCP_ADT_DISPATCH -> READ_DDLS).
    state 'A' = active, 'I' = inactive."""
    return adt_dispatch("READ_DDLS", {"name": name.upper(), "state": state})


def _textpool_call(
    action: str,
    program: str,
    language: str = "",
    textpool: list[dict] | None = None,
) -> dict:
    """Call the dedicated ZMCP_ADT_TEXTPOOL FM. Its EV_SUBRC is a string."""
    res = get_client().call(
        _TEXTPOOL_FM,
        IV_ACTION=action,
        IV_PROGRAM=program.upper(),
        IV_LANGUAGE=language,
        IV_TEXTPOOL_JSON=json.dumps(textpool) if textpool is not None else "",
    )
    subrc = str(res.get("EV_SUBRC", "0")).strip()
    message = res.get("EV_MESSAGE", "")
    if subrc not in ("0", ""):
        raise SapConnectionError(
            f"{_TEXTPOOL_FM} {action} failed (subrc={subrc}): {message}"
        )
    raw = res.get("EV_RESULT", "")
    try:
        result = json.loads(raw) if raw else None
    except ValueError:
        result = raw
    return {
        "action": action,
        "program": program.upper(),
        "message": message,
        "result": result,
    }


def textpool_read(program: str, language: str = "") -> dict:
    """Read a program's text elements (ZMCP_ADT_TEXTPOOL -> READ TEXTPOOL).

    Result rows: {"ID","KEY","ENTRY","LENGTH"}; ID = I (text symbol),
    S (selection text), R (program title), H (list heading).
    """
    return _textpool_call("READ", program, language)


def textpool_write(
    program: str,
    textpool: list[dict],
    language: str = "",
    active: bool = False,
) -> dict:
    """Write a program's text elements. Requires SAP_ALLOW_WRITE=true.

    Defaults to WRITE_INACTIVE (staged; goes live when the program is
    activated). Set active=True to write directly as active (WRITE).
    `textpool` is a list of {"ID","KEY","ENTRY","LENGTH"} rows.
    """
    _require_write()
    action = "WRITE" if active else "WRITE_INACTIVE"
    return _textpool_call(action, program, language, textpool)


def run_unit_tests(class_name: str) -> dict:
    """Run ABAP Unit tests for a class (ZMCP_ADT_DISPATCH -> RUN_UNIT_TESTS)."""
    return adt_dispatch("RUN_UNIT_TESTS", {"class": class_name.upper()})


def run_atc(object_type: str, object_name: str, variant: str = "DEFAULT") -> dict:
    """Run an ATC check for an object (ZMCP_ADT_DISPATCH -> ATC_CHECK).

    object_type is the LIMU/R3TR type (e.g. CLAS, PROG). Note: the ABAP
    FORM atc_check ships as a stub — implement it for your release first.
    """
    return adt_dispatch(
        "ATC_CHECK",
        {
            "object_type": object_type.upper(),
            "object_name": object_name.upper(),
            "variant": variant,
        },
    )


# ---------------------------------------------------------------------------
# write / modify  (guarded)
# ---------------------------------------------------------------------------
def _check_package_allowed(program: str, create: bool) -> None:
    """Enforce the SAP_ALLOWED_PACKAGES write whitelist (vsp-style).

    Comma-separated patterns with * wildcards, e.g. "$TMP,ZPK_SANDBOX*".
    Unset = no package restriction (only SAP_ALLOW_WRITE applies). New
    programs are created in $TMP, so '$TMP' must be allowed for create.
    """
    raw = (os.getenv("SAP_ALLOWED_PACKAGES") or "").strip()
    if not raw:
        return
    patterns = [p.strip().upper() for p in raw.split(",") if p.strip()]
    if create:
        pkg = "$TMP"
    else:
        res = read_table(
            "TADIR",
            fields=["DEVCLASS"],
            where=["PGMID = 'R3TR'", "OBJECT = 'PROG'", f"OBJ_NAME = '{program.upper()}'"],
            max_rows=1,
        )
        pkg = res["rows"][0]["DEVCLASS"].upper() if res["rows"] else "$TMP"
    if not any(fnmatch.fnmatch(pkg, pat) for pat in patterns):
        raise SapConnectionError(
            f"Writing to package {pkg} is not allowed. SAP_ALLOWED_PACKAGES "
            f"permits only: {', '.join(patterns)}"
        )


def write_program(
    program: str, source: str, create: bool = False, title: str = ""
) -> dict:
    """Create or update an ABAP program's source. Requires SAP_ALLOW_WRITE=true.

    create=True: new program in $TMP that already holds the source (the source
      is stored in both the active and inactive entry). It is not finished until
      sap_activate runs: that sets the title, generates the program and drops
      the leftover inactive entry. The package dialog is suppressed (without DEVELOPMENT_CLASS/SUPPRESS_DIALOG
      RPY_PROGRAM_INSERT dies with DYNPRO_SEND_IN_BACKGROUND over RFC) and the
      source goes in SOURCE_EXTENDED: on S4D the 144-wide SOURCE table is
      silently ignored and an empty program is saved.
    create=False: the source is syntax-checked first, then written ACTIVE via
      SIW_RFC_WRITE_REPORT. RPY_PROGRAM_UPDATE is not remote-enabled and its
      dispatcher wrapper empties the active version, so there is no safe
      "save inactive" for an existing program. An old inactive version, if any,
      is left untouched - do not activate it afterwards.
    """
    _require_write()
    _check_package_allowed(program, create)
    if create:
        res = get_client().call(
            "RPY_PROGRAM_INSERT",
            PROGRAM_NAME=program.upper(),
            PROGRAM_TYPE="1",  # 1 = executable report
            TITLE_STRING=(title or program).strip()[:70],
            DEVELOPMENT_CLASS="$TMP",
            SUPPRESS_DIALOG="X",
            SAVE_INACTIVE="X",
            SOURCE_EXTENDED=_source_to_lines(source, width=255),
        )
        return {
            "program": program.upper(),
            "action": "created",
            "needs_activation": True,
            "raw": res,
        }
    try:
        check = syntax_check(source, program)
    except SapConnectionError as exc:  # the dispatcher reports a syntax error as subrc 4
        raise SapConnectionError(
            f"Syntax check failed, {program.upper()} not updated: {exc}"
        ) from exc
    if not (check.get("result") or {}).get("ok"):
        raise SapConnectionError(
            f"Syntax check failed, {program.upper()} not updated: "
            f"{check.get('message') or check.get('result')}"
        )
    name = program.upper()
    res = get_client().call(
        "SIW_RFC_WRITE_REPORT",
        I_NAME=name,
        I_OBJECT="PROG",
        I_OBJNAME=name,
        I_PROGTYPE="1",
        I_TAB_CODE=[ln for ln in source.replace("\r\n", "\n").split("\n")],
    )
    return {
        "program": name,
        "action": "updated",
        "needs_activation": False,
        "active": True,
        "raw": res,
    }


def run_rfc(function_name: str, params: dict | None = None) -> dict:
    """Escape hatch: call an arbitrary remote-enabled FM with a params dict.

    Treated as a write operation (guarded) because arbitrary FMs may change
    data, unless the FM is on SAP_RFC_READONLY_ALLOW. High-risk FMs are additionally blocked by the deny list. Use
    deliberately.
    """
    if not _rfc_readonly_allowed(function_name):
        _require_write()
    _check_fm_allowed(function_name)
    return get_client().call(function_name.upper(), **(params or {}))


# ---------------------------------------------------------------------------
# Gateway client over RFC (same mechanism as /IWFND/GW_CLIENT, no network):
# user-installed ZCTD_FM_GW_TEST (FG ZCTD_FG_PO_INFO) drives
# /IWFND/CL_SUTIL_CLIENT_PROXY inside SAP, so no HTTP route to SAP is needed.
# ---------------------------------------------------------------------------
_GW_FM = "ZCTD_FM_GW_TEST"
_GW_PATH_PREFIXES = ("/sap/opu/odata/", "/sap/api/")
_GW_BODY_LIMIT = 200_000  # chars returned to the agent


def gateway_call(
    uri: str,
    method: str = "GET",
    body: str | None = None,
    headers: dict | None = None,
) -> dict:
    """Call an OData / Gateway service through ZCTD_FM_GW_TEST.

    GET is always allowed. POST/PUT/PATCH/DELETE/MERGE require
    SAP_ALLOW_WRITE=true. Only /sap/opu/odata/ and /sap/api/ paths are accepted.
    """
    m = (method or "GET").upper()
    if m not in ("GET", "POST", "PUT", "PATCH", "MERGE", "DELETE"):
        raise SapConnectionError(f"Unsupported HTTP method: {method}")
    if m != "GET":
        _require_write()
    path = (uri or "").strip()
    if not path.lower().startswith(_GW_PATH_PREFIXES) or ".." in path:
        raise SapConnectionError(
            "uri must start with /sap/opu/odata/ or /sap/api/ (no '..'): " + path
        )
    hdr = "\n".join(f"{k}: {v}" for k, v in (headers or {}).items())
    res = get_client().call(
        _GW_FM, IV_URI=path, IV_METHOD=m, IV_BODY=body or "", IV_HEADERS=hdr
    )
    out = res.get("EV_BODY") or ""
    truncated = len(out) > _GW_BODY_LIMIT
    ctype = res.get("EV_CONTENT_TYPE") or ""
    parsed = None
    if "json" in ctype.lower() and not truncated:
        try:
            parsed = json.loads(out)
        except ValueError:
            parsed = None
    return {
        "method": m,
        "uri": path,
        "status": res.get("EV_STATUS_CODE"),
        "status_text": res.get("EV_STATUS_TEXT"),
        "content_type": ctype,
        "error": res.get("EV_ERROR") or None,
        "body": parsed if parsed is not None else out[:_GW_BODY_LIMIT],
        "truncated": truncated,
    }


# ---------------------------------------------------------------------------
# Gateway admin / error log / test runner
# ---------------------------------------------------------------------------
_GWLOG_FM = "ZMCP_ADT_GWLOG"
_GW_CACHE_FMS = ("/IWFND/SUTIL_CLEANUP_MD_CACHE", "/IWBEP/SUTIL_CLEANUP_MD_CACHE")


def gateway_errors(
    minutes: int = 60,
    user: str | None = None,
    service: str | None = None,
    uri_part: str | None = None,
    min_status: int = 0,
    opid: str | None = None,
    max_rows: int = 20,
    with_context: bool = False,
) -> dict:
    """Gateway error log (/IWFND/ERROR_LOG), newest first.

    RFC_READ_TABLE cannot read /IWFND/SU_ERRLOG (string columns), so this goes
    through ZMCP_ADT_GWLOG (abap/zmcp_adt_gwlog.abap). `service` and `uri_part`
    accept '%' wildcards; `opid` returns all entries of one failed request.
    """
    params = {"minutes": int(minutes), "max_rows": int(max_rows),
              "with_context": bool(with_context)}
    for k, v in (("username", user), ("service", service),
                 ("uri_part", uri_part), ("opid", opid)):
        if v:
            params[k] = str(v)
    if min_status:
        params["min_status"] = int(min_status)
    try:
        res = get_client().call(_GWLOG_FM, IV_PARAMS=json.dumps(params))
    except SapConnectionError as exc:
        raise SapConnectionError(
            f"{_GWLOG_FM} not usable ({str(exc)[:200]}). Install "
            "abap/zmcp_adt_gwlog.abap, see abap/README.md."
        ) from exc
    if res.get("EV_SUBRC", 0) != 0:
        raise SapConnectionError(res.get("EV_MESSAGE") or "gateway log read failed")
    rows = json.loads(res.get("EV_RESULT") or "[]")
    summary: dict[tuple, int] = {}
    for r in rows:
        key = (r.get("SERVICE_NAME"), r.get("HTTP_STATUS"), r.get("ERROR_TEXT"))
        summary[key] = summary.get(key, 0) + 1
    return {
        "minutes": int(minutes),
        "count": len(rows),
        "summary": [
            {"service": k[0], "http_status": k[1], "error_text": k[2], "entries": n}
            for k, n in sorted(summary.items(), key=lambda kv: -kv[1])
        ],
        "entries": rows,
    }


def _gw_registry(service: str | None, version: str | None) -> list[dict]:
    """Registered gateway services (/IWFND/I_MED_SRH) with their models."""
    conds = ["IS_ACTIVE = 'A'"]
    if service:
        op = "LIKE" if "%" in service else "="
        conds.append(f"SERVICE_NAME {op} {_q(service.upper())}")
    if version:
        conds.append(f"SERVICE_VERSION = {_q(str(version).zfill(4))}")
    rows = read_table(
        "/IWFND/I_MED_SRH",
        ["SRV_IDENTIFIER", "NAMESPACE", "SERVICE_NAME", "SERVICE_VERSION",
         "CHANGED_BY", "CHANGED_TIMESTMP"],
        conds, 200,
    )["rows"]
    for r in rows:
        try:
            models = read_table(
                "/IWFND/I_MED_SRG", ["MODEL_IDENTIFIER"],
                [f"SRV_IDENTIFIER = {_q(r['SRV_IDENTIFIER'])}", "IS_ACTIVE = 'A'"], 10,
            )["rows"]
        except SapConnectionError:
            models = []
        r["models"] = [m["MODEL_IDENTIFIER"] for m in models]
    return rows


def gateway_admin(
    action: str = "status",
    service: str | None = None,
    version: str = "0001",
) -> dict:
    """Gateway service administration over RFC.

    status      registered services (name, version, who/when changed, model ids);
                `service` may use '%' wildcards. Read only.
    clear_cache drop the metadata cache of one service (the /IWFND/CACHE_CLEANUP
                and /IWBEP/CACHE_CLEANUP steps). Needs SAP_ALLOW_WRITE=true
                unless both cleanup FMs are on SAP_RFC_READONLY_ALLOW.
    """
    act = (action or "status").lower()
    if act == "status":
        rows = _gw_registry(service, version if service else None)
        return {"action": "status", "count": len(rows), "services": rows}
    if act != "clear_cache":
        raise SapConnectionError("action must be 'status' or 'clear_cache'")
    if not service or "%" in service:
        raise SapConnectionError("clear_cache needs an exact service name")
    if not all(_rfc_readonly_allowed(f) for f in _GW_CACHE_FMS):
        _require_write()
    for f in _GW_CACHE_FMS:
        _check_fm_allowed(f)
    reg = _gw_registry(service, version)
    if not reg:
        raise SapConnectionError(
            f"Service {service.upper()} version {version} is not registered "
            "(see action=status; register it in /IWFND/MAINT_SERVICE)."
        )
    r = reg[0]
    ns = (r.get("NAMESPACE") or "").strip()
    ver = str(version).zfill(4)
    out: dict[str, Any] = {"action": "clear_cache", "service": r["SERVICE_NAME"],
                           "version": ver, "steps": []}
    hub = get_client().call(
        _GW_CACHE_FMS[0], IV_MODE="A", IV_NAMESPACE=ns,
        IV_EXT_SERVICE_NAME=r["SERVICE_NAME"], IV_SERVICE_VERSION=ver,
    )
    out["steps"].append({"fm": _GW_CACHE_FMS[0],
                         "error_text": (hub.get("EV_ERROR_TEXT") or "").strip() or None})
    for model in (r.get("models") or [""]):
        be = get_client().call(
            _GW_CACHE_FMS[1], IV_NAMESPACE=ns,
            IV_EXT_SERVICE_NAME=r["SERVICE_NAME"], IV_SERVICE_VERSION=ver,
            IV_MODEL_ID=model,
        )
        out["steps"].append({"fm": _GW_CACHE_FMS[1], "model": model or None,
                             "error_text": (be.get("EV_ERROR_TEXT") or "").strip() or None})
    out["ok"] = all(not st["error_text"] for st in out["steps"])
    return out


def _json_path(data: Any, path: str) -> tuple[bool, Any]:
    """Resolve 'd.results.0.Matnr' against parsed JSON. Returns (found, value)."""
    cur = data
    for part in [p for p in (path or "").split(".") if p != ""]:
        if isinstance(cur, list):
            try:
                cur = cur[int(part)]
            except (ValueError, IndexError):
                return False, None
        elif isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return False, None
    return True, cur


def _gw_check(case: dict, res: dict) -> list[str]:
    """Assertion failures for one executed case (empty list = pass)."""
    fails: list[str] = []
    status = res.get("status")
    try:
        status = int(status)
    except (TypeError, ValueError):
        pass
    exp = case.get("expect_status")
    if exp is None:
        ok = isinstance(status, int) and 200 <= status < 300
        exp_txt = "2xx"
    else:
        exp_list = exp if isinstance(exp, list) else [exp]
        ok = status in [int(e) for e in exp_list]
        exp_txt = "/".join(str(e) for e in exp_list)
    if not ok:
        fails.append(f"status {status}, expected {exp_txt}")
    body = res.get("body")
    text = body if isinstance(body, str) else json.dumps(body, ensure_ascii=False)
    needle = case.get("expect_contains")
    if needle and str(needle) not in (text or ""):
        fails.append(f"body does not contain {needle!r}")
    for a in case.get("expect_json") or []:
        found, val = _json_path(body, a.get("path", ""))
        label = a.get("path", "")
        if a.get("exists") is False:
            if found:
                fails.append(f"{label} should not exist")
            continue
        if not found:
            fails.append(f"{label} missing")
            continue
        if "equals" in a and str(val) != str(a["equals"]):
            fails.append(f"{label} = {val!r}, expected {a['equals']!r}")
        if "contains" in a and str(a["contains"]) not in str(val):
            fails.append(f"{label} = {val!r} lacks {a['contains']!r}")
        for key, test in (("min", lambda v, e: float(v) >= float(e)),
                          ("max", lambda v, e: float(v) <= float(e))):
            if key in a:
                try:
                    if not test(val, a[key]):
                        fails.append(f"{label} = {val!r}, {key} {a[key]}")
                except (TypeError, ValueError):
                    fails.append(f"{label} = {val!r} is not numeric")
        if "count_min" in a:
            n = len(val) if isinstance(val, (list, dict, str)) else -1
            if n < int(a["count_min"]):
                fails.append(f"{label} has {n} item(s), need >= {a['count_min']}")
    return fails


def _gw_subst(value: Any, env: dict[str, str]) -> Any:
    if isinstance(value, str):
        for k, v in env.items():
            value = value.replace("{{" + k + "}}", v)
        return value
    if isinstance(value, dict):
        return {k: _gw_subst(v, env) for k, v in value.items()}
    return value


def gateway_test(
    cases: list[dict],
    stop_on_fail: bool = False,
    diagnose: bool = True,
) -> dict:
    """Run a list of OData test cases and assert on the results.

    case = {name, uri, method (GET), body, headers, expect_status (int|list,
    default any 2xx), expect_contains, expect_json: [{path, equals|contains|
    min|max|count_min|exists}], save: {var: path}}. `{{var}}` in later cases is
    replaced by a saved value (chain POST -> GET). Non-GET needs SAP_ALLOW_WRITE.
    diagnose=True attaches the newest Gateway error-log entries when a case
    fails with HTTP >= 400 (needs ZMCP_ADT_GWLOG).
    """
    if not isinstance(cases, list) or not cases:
        raise SapConnectionError("cases must be a non-empty list")
    if len(cases) > 100:
        raise SapConnectionError("at most 100 cases per run")
    env: dict[str, str] = {}
    results: list[dict] = []
    started = datetime.now()
    failed_http = False
    for i, raw in enumerate(cases, 1):
        case = dict(raw)
        name = case.get("name") or f"case {i}"
        item: dict[str, Any] = {"name": name, "pass": False}
        t0 = datetime.now()
        try:
            uri = _gw_subst(case.get("uri", ""), env)
            body = _gw_subst(case.get("body"), env)
            if body is not None and not isinstance(body, str):
                body = json.dumps(body, ensure_ascii=False)
            res = gateway_call(uri, case.get("method", "GET"), body,
                               _gw_subst(case.get("headers"), env))
            item.update(method=res["method"], uri=uri, status=res["status"])
            fails = _gw_check(case, res)
            if res.get("error") and case.get("expect_status") is None:
                fails.append(f"gateway error: {res['error']}")
            for var, path in (case.get("save") or {}).items():
                found, val = _json_path(res.get("body"), path)
                if found:
                    env[var] = str(val)
                else:
                    fails.append(f"save {var}: {path} missing")
            item["pass"] = not fails
            if fails:
                item["failures"] = fails
                snippet = res.get("body")
                item["body_snippet"] = (snippet if isinstance(snippet, str)
                                        else json.dumps(snippet, ensure_ascii=False))[:400]
                try:
                    if int(res.get("status") or 0) >= 400:
                        failed_http = True
                except (TypeError, ValueError):
                    pass
        except SapConnectionError as exc:
            item["failures"] = [str(exc)[:300]]
        item["ms"] = int((datetime.now() - t0).total_seconds() * 1000)
        results.append(item)
        if stop_on_fail and not item["pass"]:
            break
    passed = sum(1 for r in results if r["pass"])
    out: dict[str, Any] = {
        "total": len(results), "passed": passed, "failed": len(results) - passed,
        "seconds": round((datetime.now() - started).total_seconds(), 1),
        "results": results,
    }
    if len(results) < len(cases):
        out["not_run"] = len(cases) - len(results)
    if diagnose and failed_http:
        try:
            out["gateway_errors"] = gateway_errors(
                minutes=15, min_status=400, max_rows=5)["entries"]
        except SapConnectionError as exc:
            out["gateway_errors_note"] = str(exc)[:200]
    return out


# ---------------------------------------------------------------------------
# ST22 dump detail + SLG1 application log (plain table reads, no custom FM)
# ---------------------------------------------------------------------------
def _q(value: str) -> str:
    """Quote a value for an ABAP WHERE literal."""
    return "'" + str(value).replace("'", "''") + "'"


def _where_options(conds: list[str]) -> list[dict]:
    return _wrap_options(" AND ".join(f"( {c} )" for c in conds))


def _parse_snap_tags(chunk: str) -> list[tuple[str, str]]:
    """Parse one SNAP.FLIST chunk: repeated <2-char tag><3-digit len><value>.
    The last value may be cut by the chunk end; keep what is there."""
    out, i = [], 0
    while i + 5 <= len(chunk):
        tag, ln = chunk[i:i + 2], chunk[i + 2:i + 5]
        if not (tag.isalnum() and ln.isdigit()):
            break
        n = int(ln)
        out.append((tag, chunk[i + 5:i + 5 + n].rstrip()))
        i += 5 + n
    return out


# SY-fields kept in SNAP; longest names first so SY-MSGV1 wins over SY-MSGV
_SY_NAMES = sorted([
    "SY-SUBRC", "SY-INDEX", "SY-TABIX", "SY-DBCNT", "SY-FDPOS", "SY-LSIND",
    "SY-PAGNO", "SY-LINNO", "SY-COLNO", "SY-PFKEY", "SY-UCOMM", "SY-MSGTY",
    "SY-MSGID", "SY-MSGNO", "SY-MSGV1", "SY-MSGV2", "SY-MSGV3", "SY-MSGV4",
    "SY-MODNO", "SY-DATUM", "SY-UZEIT", "SY-XPROG", "SY-XFORM", "SY-LILLI",
    "SY-CPAGE", "SY-LISEL", "SY-STEPL", "SY-LOOPC", "SY-DYNNR", "SY-REPID",
    "SY-CPROG", "SY-TCODE", "SY-UNAME", "SY-LANGU", "SY-MANDT", "SY-HOST",
], key=len, reverse=True)


def read_dump(
    date: str | None = None,
    time: str | None = None,
    user: str | None = None,
    client: str | None = None,
    host: str | None = None,
    days: int = 7,
    context_lines: int = 5,
    with_text: bool = True,
) -> dict:
    """Detail of one ST22 runtime error, read from table SNAP/SNAPT.

    With no filters: the newest dump of the last `days` days. date=YYYYMMDD,
    time=HHMMSS, user, client (MANDT of the dump) and host narrow the choice.
    Returns error id, program/include/line, SY-fields, user/client, the error
    texts (SNAPT) and the source around the failing line. The ABAP call stack
    lives in a compressed part of SNAP and is not decoded here.
    """
    conds = ["SEQNO = '000'"]
    if date:
        conds.append(f"DATUM = {_q(date)}")
    else:
        since = (date_cls_today() - timedelta(days=int(days))).strftime("%Y%m%d")
        conds.append(f"DATUM >= {_q(since)}")
    for col, val in (("UZEIT", time), ("UNAME", (user or "").upper() or None),
                     ("MANDT", client), ("AHOST", host)):
        if val:
            conds.append(f"{col} = {_q(val)}")
    cand = get_client().call(
        "RFC_READ_TABLE", QUERY_TABLE="SNAP", DELIMITER="|", ROWCOUNT=1000,
        FIELDS=[{"FIELDNAME": f} for f in
                ("DATUM", "UZEIT", "AHOST", "UNAME", "MANDT", "MODNO")],
        OPTIONS=_where_options(conds),
    )
    keys = []
    for e in cand.get("DATA", []):
        p = [x.strip() for x in e["WA"].split("|")]
        if len(p) >= 6:
            keys.append(dict(zip(("date", "time", "host", "user", "client", "modno"), p)))
    if not keys:
        raise SapConnectionError("No dump found for the given filters.")
    keys.sort(key=lambda k: (k["date"], k["time"]), reverse=True)
    key = keys[0]

    # all FLIST chunks of this dump; RFC_READ_TABLE trims trailing blanks of
    # the WA, so slice by field offsets and keep chunks separate.
    res = get_client().call(
        "RFC_READ_TABLE", QUERY_TABLE="SNAP", DELIMITER="", ROWCOUNT=400,
        FIELDS=[{"FIELDNAME": f} for f in ("SEQNO", "FLIST")],
        OPTIONS=_where_options([
            f"DATUM = {_q(key['date'])}", f"UZEIT = {_q(key['time'])}",
            f"AHOST = {_q(key['host'])}", f"UNAME = {_q(key['user'])}",
            f"MODNO = {_q(key['modno'])}", f"MANDT = {_q(key['client'])}",
        ]),
    )
    fd = {f["FIELDNAME"]: (int(f["OFFSET"]), int(f["LENGTH"])) for f in res["FIELDS"]}
    so, sl = fd["SEQNO"]
    fo, fl = fd["FLIST"]
    chunks = sorted(
        (e["WA"][so:so + sl], e["WA"][fo:fo + fl]) for e in res.get("DATA", [])
    )
    tags: dict[str, str] = {}
    sy: dict[str, str] = {}
    for _seq, chunk in chunks:
        for tag, val in _parse_snap_tags(chunk):
            if tag == "SY":
                name = next((n for n in _SY_NAMES if val.startswith(n)), None)
                if name:
                    sy[name] = val[len(name):].strip()
            elif tag not in tags:
                tags[tag] = val

    errid = tags.get("FC", "")
    out: dict[str, Any] = {
        "date": key["date"], "time": key["time"], "host": key["host"],
        "user": key["user"], "client": key["client"],
        "runtime_error": errid,
        "program": tags.get("AP", ""), "include": tags.get("AI", ""),
        "line": int(tags["AL"]) if tags.get("AL", "").isdigit() else None,
        "database": tags.get("ED", ""), "os": tags.get("EO", ""),
        "sy": sy, "other_dumps_matching": len(keys) - 1,
    }
    if len(keys) > 1:
        out["next_candidates"] = [
            {k: c[k] for k in ("date", "time", "user", "client")} for c in keys[1:6]
        ]

    if with_text and errid:
        lang = (get_client().config.conn_params.get("lang") or "EN")[:1].upper()
        for lg in (lang, "E", "D"):
            tr = read_table("SNAPT", ["TTYPE", "SEQNO", "TLINE"],
                            [f"ERRID = {_q(errid)}", f"LANGU = {_q(lg)}"], 300)
            if tr["rows"]:
                break
        groups: dict[str, list[str]] = {}
        for r in sorted(tr["rows"], key=lambda r: (r["TTYPE"], r["SEQNO"])):
            groups.setdefault(r["TTYPE"], []).append(r["TLINE"])
        out["texts"] = {k: "\n".join(v) for k, v in groups.items()}

    inc = out["include"] or out["program"]
    if inc and out["line"] and context_lines >= 0:
        try:
            src = read_program(inc)["source"].split("\n")
            lo = max(0, out["line"] - 1 - int(context_lines))
            hi = min(len(src), out["line"] + int(context_lines))
            out["source_context"] = [
                {"line": n + 1, "text": src[n], "dump_line": n + 1 == out["line"]}
                for n in range(lo, hi)
            ]
        except Exception as exc:  # include not readable (kernel/standard)
            out["source_context_error"] = str(exc)[:200]
    return out


def date_cls_today() -> date:
    return date.today()


_APPLOG_FM = "ZMCP_ADT_APPLOG"


def read_applog(
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
    """Application log (SLG1) read from BALHDR/BALM, newest logs first.

    Filter by log_object/subobject (SLG0 names), user, external number and date
    range (YYYYMMDD). Messages are resolved to text via T100 (&1..&4 filled).
    Defaults to the last 7 days when no date is given.
    """
    conds: list[str] = []
    if log_object:
        conds.append(f"OBJECT = {_q(log_object.upper())}")
    if subobject:
        conds.append(f"SUBOBJECT = {_q(subobject.upper())}")
    if user:
        conds.append(f"ALUSER = {_q(user.upper())}")
    if extnumber:
        conds.append(f"EXTNUMBER = {_q(extnumber)}")
    if not date_from and not date_to:
        date_from = (date.today() - timedelta(days=7)).strftime("%Y%m%d")
    if date_from:
        conds.append(f"ALDATE >= {_q(date_from)}")
    if date_to:
        conds.append(f"ALDATE <= {_q(date_to)}")
    hdr = read_table(
        "BALHDR",
        ["LOGNUMBER", "OBJECT", "SUBOBJECT", "EXTNUMBER", "ALDATE", "ALTIME",
         "ALUSER", "ALPROG", "ALTCODE", "ALMODE", "MSG_CNT_E", "MSG_CNT_A",
         "MSG_CNT_W", "MSG_CNT_I", "MSG_CNT_S"],
        conds or None, 500,
    )
    logs = sorted(hdr["rows"], key=lambda r: (r["ALDATE"], r["ALTIME"], r["LOGNUMBER"]),
                  reverse=True)
    total = len(logs)
    logs = logs[: int(max_logs)]
    result: dict[str, Any] = {"total_found": total, "logs": []}
    if not with_messages:
        result["logs"] = logs
        return result

    lang = (get_client().config.conn_params.get("lang") or "EN")[:1].upper()

    # Preferred: ZMCP_ADT_APPLOG (abap/zmcp_adt_applog.abap) reads the BALDAT
    # cluster through BAL_DB_LOAD. BALM is often empty, so plain table reads
    # miss the messages. Falls back to BALM when the FM is not installed.
    def _count(lg: dict) -> int:
        return sum(int(lg.get(k) or 0) for k in
                   ("MSG_CNT_E", "MSG_CNT_A", "MSG_CNT_W", "MSG_CNT_I", "MSG_CNT_S"))

    want = [lg["LOGNUMBER"] for lg in logs if _count(lg) > 0]
    via_fm: dict[str, dict] = {}
    fm_error = ""
    if want:
        try:
            res = get_client().call(
                _APPLOG_FM,
                IV_PARAMS=json.dumps({"lognumbers": want,
                                      "max_messages": int(max_messages),
                                      "langu": lang}),
            )
            if res.get("EV_SUBRC", 0) == 0 and res.get("EV_RESULT"):
                for item in json.loads(res["EV_RESULT"]):
                    via_fm[item["LOGNUMBER"]] = item
            else:
                fm_error = res.get("EV_MESSAGE") or "unknown error"
        except SapConnectionError as exc:
            fm_error = str(exc)[:200]
    if via_fm:
        for lg in logs:
            item = via_fm.get(lg["LOGNUMBER"])
            if item is None:
                lg["messages"] = []
                continue
            lg["messages"] = [
                {"type": m.get("TYPE"), "id": m.get("ID"), "no": m.get("NO"),
                 "text": m.get("TEXT"), "time_stmp": m.get("TIME_STMP")}
                for m in item.get("MESSAGES", [])
            ]
            if item.get("TRUNCATED"):
                lg["messages_truncated"] = True
            if item.get("ERROR"):
                lg["messages_error"] = item["ERROR"]
        result["logs"] = logs
        return result

    t100: dict[tuple[str, str], str] = {}

    def _text(msgid: str, msgno: str) -> str:
        k = (msgid, msgno)
        if k not in t100:
            try:
                r = read_table("T100", ["TEXT"],
                               [f"SPRSL = {_q(lang)}", f"ARBGB = {_q(msgid)}",
                                f"MSGNR = {_q(msgno)}"], 1)
                t100[k] = r["rows"][0]["TEXT"] if r["rows"] else ""
            except SapConnectionError:
                t100[k] = ""
        return t100[k]

    for lg in logs:
        try:
            ms = read_table(
                "BALM",
                ["MSGNUMBER", "MSGTY", "MSGID", "MSGNO", "MSGV1", "MSGV2", "MSGV3", "MSGV4"],
                [f"LOGNUMBER = {_q(lg['LOGNUMBER'])}"], int(max_messages),
            )["rows"]
        except SapConnectionError as exc:
            lg["messages_error"] = str(exc)[:200]
            continue
        msgs = []
        for m in sorted(ms, key=lambda r: r["MSGNUMBER"]):
            text = _text(m["MSGID"], m["MSGNO"]) if m["MSGID"] else ""
            vals = [m["MSGV1"], m["MSGV2"], m["MSGV3"], m["MSGV4"]]
            if text:
                for n, v in enumerate(vals, 1):
                    text = text.replace(f"&{n}", v)
                # leftover '&' placeholders take the values in order
                for v in vals:
                    text = text.replace("&", v, 1) if "&" in text else text
            else:
                text = " ".join(v for v in vals if v)
            msgs.append({"type": m["MSGTY"], "id": m["MSGID"], "no": m["MSGNO"],
                         "text": text.strip()})
        lg["messages"] = msgs
        counted = sum(int(lg.get(k) or 0) for k in
                      ("MSG_CNT_E", "MSG_CNT_A", "MSG_CNT_W", "MSG_CNT_I", "MSG_CNT_S"))
        if counted and not msgs:
            lg["messages_note"] = (
                "Header says messages exist but BALM is empty (BALDAT cluster). "
                f"Install abap/zmcp_adt_applog.abap ({_APPLOG_FM}) to read them."
                + (f" FM call failed: {fm_error}" if fm_error else "")
            )
    result["logs"] = logs
    return result


# ---------------------------------------------------------------------------
# DDIC create/update/delete via user-installed ZMCP_ADT_DDIC_* FMs
# (group ZMCP_ADT_UTILS, adapted from superclaude-for-sap, see abap/).
# Protocol: IV_ACTION/IV_NAME/IV_DEVCLASS/IV_TRANSPORT/IV_PAYLOAD_JSON
#           -> EV_SUBRC(i) / EV_MESSAGE / EV_RESULT(JSON).
# ---------------------------------------------------------------------------
_DDIC_FMS = {
    "TABL": "ZMCP_ADT_DDIC_TABL",   # tables AND structures (DD02V-TABCLASS)
    "DTEL": "ZMCP_ADT_DDIC_DTEL",
    "DOMA": "ZMCP_ADT_DDIC_DOMA",
}
_DDIC_ACTIVATE_FM = "ZMCP_ADT_DDIC_ACTIVATE"


def _check_devclass_allowed(devclass: str) -> None:
    """Apply the SAP_ALLOWED_PACKAGES whitelist to an explicit target package
    (DDIC objects carry their package as a parameter, unlike programs)."""
    raw = (os.getenv("SAP_ALLOWED_PACKAGES") or "").strip()
    if not raw:
        return
    patterns = [p.strip().upper() for p in raw.split(",") if p.strip()]
    pkg = (devclass or "$TMP").upper()
    if not any(fnmatch.fnmatch(pkg, pat) for pat in patterns):
        raise SapConnectionError(
            f"Writing to package {pkg} is not allowed. SAP_ALLOWED_PACKAGES "
            f"permits only: {', '.join(patterns)}"
        )


def _ddic_fm_for(kind: str) -> str:
    k = (kind or "").upper()
    if k not in _DDIC_FMS:
        raise SapConnectionError(
            f"Unknown DDIC kind '{kind}'. Use TABL (tables/structures), "
            f"DTEL (data elements) or DOMA (domains)."
        )
    return _DDIC_FMS[k]


def _ddic_result(fm: str, res: dict) -> dict:
    subrc = res.get("EV_SUBRC", 0)
    message = res.get("EV_MESSAGE", "")
    if subrc != 0:
        raise SapConnectionError(f"{fm} failed (subrc={subrc}): {message}")
    raw = res.get("EV_RESULT", "")
    try:
        result = json.loads(raw) if raw else None
    except ValueError:
        result = raw
    return {"message": message, "result": result}


def ddic_write(
    kind: str,
    name: str,
    payload: dict,
    devclass: str = "",
    transport: str = "",
    update: bool = False,
) -> dict:
    """Create or update a DDIC object (staged INACTIVE). Requires
    SAP_ALLOW_WRITE=true and the ZMCP_ADT_DDIC_* FMs installed.

    payload per kind (uppercase field names, see abap/ headers):
      TABL: {"dd02v": {...}, "dd03p": [{...}], "dd09v": {...}?}  (structure: TABCLASS=INTTAB;
            TRANSP writes technical settings: dd09v TABART/TABKAT/BUFALLOW,
            default APPL1/0/N for a new table, existing kept when omitted)
      DTEL: {"dd04v": {...}}
      DOMA: {"dd01v": {...}, "dd07v": [{...}]}
    Activate afterwards with ddic_activate().
    """
    _require_write()
    _check_devclass_allowed(devclass)
    fm = _ddic_fm_for(kind)
    res = get_client().call(
        fm,
        IV_ACTION="UPDATE" if update else "CREATE",
        IV_NAME=name.upper(),
        IV_DEVCLASS=devclass or "",
        IV_TRANSPORT=transport or "",
        IV_PAYLOAD_JSON=json.dumps(payload or {}),
    )
    out = _ddic_result(fm, res)
    out.update({"kind": kind.upper(), "name": name.upper(), "state": "inactive"})
    return out


def ddic_delete(kind: str, name: str, transport: str = "") -> dict:
    """Delete a DDIC object (RS_DD_DELETE_OBJ inside the FM). Guarded."""
    _require_write()
    fm = _ddic_fm_for(kind)
    res = get_client().call(
        fm,
        IV_ACTION="DELETE",
        IV_NAME=name.upper(),
        IV_DEVCLASS="",
        IV_TRANSPORT=transport or "",
        IV_PAYLOAD_JSON="",
    )
    out = _ddic_result(fm, res)
    out.update({"kind": kind.upper(), "name": name.upper()})
    return out


def ddic_activate(kind: str, name: str) -> dict:
    """Activate an inactive DDIC object staged by ddic_write(). Guarded."""
    _require_write()
    k = (kind or "").upper()
    if k not in _DDIC_FMS:
        raise SapConnectionError(
            f"Unknown DDIC kind '{kind}'. Use TABL / DTEL / DOMA."
        )
    res = get_client().call(
        _DDIC_ACTIVATE_FM, IV_TYPE=k, IV_NAME=name.upper()
    )
    out = _ddic_result(_DDIC_ACTIVATE_FM, res)
    out.update({"kind": k, "name": name.upper()})
    return out
