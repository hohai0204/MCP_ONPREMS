"""Operations tools built only on standard SAP FMs / tables (no custom ABAP):
jobs, locks, transport create/check, message class read, client-side joins,
user authorizations, function-module write and a health check.
"""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from typing import Any

from .connection import SapConnectionError, get_client
from .tools import (
    _check_fm_allowed,
    _check_package_allowed,
    _q,
    _require_write,
    adt_dispatch,
    read_table,
    syntax_check,
)

# ---------------------------------------------------------------------------
# Jobs (SM37) and locks (SM12)
# ---------------------------------------------------------------------------
_JOB_STATUS = {
    "S": "scheduled", "P": "released", "Y": "ready", "R": "running",
    "F": "finished", "A": "aborted", "Z": "suspended", "X": "unknown",
}


def read_jobs(
    name: str | None = None,
    user: str | None = None,
    status: str | None = None,
    days: int = 2,
    max_rows: int = 50,
) -> dict:
    """Background jobs (TBTCO), newest first. name accepts '%' wildcards.
    status: S scheduled, P released, Y ready, R running, F finished, A aborted.
    """
    conds = []
    if name:
        op = "LIKE" if ("%" in name or "*" in name) else "="
        conds.append(f"JOBNAME {op} {_q(name.upper().replace('*', '%'))}")
    if user:
        conds.append(f"SDLUNAME = {_q(user.upper())}")
    if status:
        conds.append(f"STATUS = {_q(status.upper()[:1])}")
    since = (date.today() - timedelta(days=int(days))).strftime("%Y%m%d")
    conds.append(f"SDLSTRTDT >= {_q(since)}")
    res = read_table(
        "TBTCO",
        ["JOBNAME", "JOBCOUNT", "SDLUNAME", "STATUS", "SDLSTRTDT", "SDLSTRTTM",
         "STRTDATE", "STRTTIME", "ENDDATE", "ENDTIME"],
        conds, 500,
    )
    rows = sorted(res["rows"], key=lambda r: (r["SDLSTRTDT"], r["SDLSTRTTM"]),
                  reverse=True)
    for r in rows:
        r["STATUS_TEXT"] = _JOB_STATUS.get(r["STATUS"], r["STATUS"])
    return {"total_found": len(rows), "capped": len(rows) >= 500,
            "jobs": rows[: int(max_rows)]}


def read_locks(
    user: str | None = None,
    table: str | None = None,
    argument: str | None = None,
    max_rows: int = 100,
) -> dict:
    """Enqueue locks (SM12) via ENQUEUE_READ. Empty user = all users."""
    res = get_client().call(
        "ENQUEUE_READ",
        GCLIENT=get_client().config.conn_params.get("client", ""),
        GNAME=(table or "").upper(),
        GARG=argument or "",
        GUNAME=(user or "").upper(),
    )
    def _clean(v):
        if not isinstance(v, str):
            return v
        return "".join(c for c in v if c.isprintable() and c != "\uffff").strip()

    rows = [
        {k: _clean(r.get(k)) for k in ("GNAME", "GARG", "GMODE", "GUNAME",
                                       "GTCODE", "GTDATE", "GTTIME")}
        for r in res.get("ENQ", [])
    ]
    return {"total_found": len(rows), "locks": rows[: int(max_rows)]}


# ---------------------------------------------------------------------------
# Transports: create + pre-release check
# ---------------------------------------------------------------------------
def create_transport(description: str, owner: str | None = None,
                     category: str = "K") -> dict:
    """Create a transport request (CTS_API_CREATE_CHANGE_REQUEST).
    category: K workbench (default), W customizing. Requires SAP_ALLOW_WRITE.
    Releasing and importing stay with the human owner."""
    _require_write()
    _check_fm_allowed("CTS_API_CREATE_CHANGE_REQUEST")
    cat = (category or "K").upper()[:1]
    if cat not in ("K", "W"):
        raise SapConnectionError("category must be K (workbench) or W (customizing)")
    if not (description or "").strip():
        raise SapConnectionError("description is required")
    cfg = get_client().config.conn_params
    res = get_client().call(
        "CTS_API_CREATE_CHANGE_REQUEST",
        CATEGORY=cat,
        CLIENT=cfg.get("client", ""),
        DESCRIPTION=description.strip()[:60],
        OWNER=(owner or cfg.get("user", "")).upper(),
    )
    if (res.get("RETCODE") or "").strip() not in ("", "0", "000"):
        raise SapConnectionError(
            f"Create failed (rc {res.get('RETCODE')}): {res.get('MESSAGE')}")
    return {"request": res.get("REQUEST"), "message": res.get("MESSAGE")}


def transport_check(trkorr: str, max_objects: int = 200) -> dict:
    """Read-only pre-release check of a request: empty, objects in $TMP
    (not transportable), objects also sitting in another open request."""
    tr = trkorr.upper()
    hdr = read_table("E070", ["TRKORR", "TRFUNCTION", "TRSTATUS", "AS4USER",
                              "STRKORR"], [f"TRKORR = {_q(tr)}"], 1)["rows"]
    if not hdr:
        raise SapConnectionError(f"Request {tr} not found")
    head = hdr[0]
    # a request owns tasks; objects live in the tasks
    tasks = [r["TRKORR"] for r in read_table(
        "E070", ["TRKORR"], [f"STRKORR = {_q(tr)}"], 50)["rows"]]
    objs: list[dict] = []
    for t in [tr] + tasks:
        objs += read_table("E071", ["PGMID", "OBJECT", "OBJ_NAME"],
                           [f"TRKORR = {_q(t)}"], int(max_objects))["rows"]
    issues: list[dict] = []
    if not objs:
        issues.append({"level": "warning", "issue": "request has no objects"})
    seen: set[tuple] = set()
    for o in objs[: int(max_objects)]:
        key = (o["PGMID"], o["OBJECT"], o["OBJ_NAME"])
        if key in seen or o["PGMID"] not in ("R3TR", "LIMU"):
            continue
        seen.add(key)
        if o["PGMID"] == "R3TR":
            ta = read_table("TADIR", ["DEVCLASS"],
                            [f"PGMID = 'R3TR'", f"OBJECT = {_q(o['OBJECT'])}",
                             f"OBJ_NAME = {_q(o['OBJ_NAME'])}"], 1)["rows"]
            if ta and ta[0]["DEVCLASS"].startswith("$"):
                issues.append({"level": "error", "object": o,
                               "issue": f"local package {ta[0]['DEVCLASS']} (not transportable)"})
        other = read_table(
            "E071", ["TRKORR"],
            [f"PGMID = {_q(o['PGMID'])}", f"OBJECT = {_q(o['OBJECT'])}",
             f"OBJ_NAME = {_q(o['OBJ_NAME'])}", f"TRKORR <> {_q(tr)}"], 20)["rows"]
        mine = set(tasks) | {tr}
        for ot in sorted({r["TRKORR"] for r in other} - mine):
            h = read_table("E070", ["TRSTATUS", "AS4USER", "STRKORR"],
                           [f"TRKORR = {_q(ot)}"], 1)["rows"]
            if h and h[0]["TRSTATUS"] in ("D", "L"):
                issues.append({"level": "warning", "object": o,
                               "issue": f"also in open request {ot} ({h[0]['AS4USER']})"})
    status_txt = {"D": "modifiable", "L": "modifiable, protected", "R": "released",
                  "N": "released (import protected)"}.get(head["TRSTATUS"], head["TRSTATUS"])
    if head["TRSTATUS"] not in ("D", "L"):
        issues.append({"level": "info", "issue": f"request is {status_txt}"})
    return {"request": tr, "header": head, "status_text": status_txt,
            "tasks": tasks, "object_count": len(objs),
            "errors": sum(1 for i in issues if i["level"] == "error"),
            "warnings": sum(1 for i in issues if i["level"] == "warning"),
            "issues": issues}


# ---------------------------------------------------------------------------
# Message classes (SE91)
# ---------------------------------------------------------------------------
def read_message_class(msgclass: str, lang: str | None = None,
                       max_rows: int = 500) -> dict:
    """All messages of a message class (T100) with their texts."""
    cl = msgclass.upper()
    lg = (lang or get_client().config.conn_params.get("lang") or "EN")[:1].upper()
    msgs = read_table("T100", ["MSGNR", "TEXT"],
                      [f"ARBGB = {_q(cl)}", f"SPRSL = {_q(lg)}"], int(max_rows))["rows"]
    t100a = read_table("T100A", ["MASTERLANG", "RESPUSER"], [f"ARBGB = {_q(cl)}"], 1)["rows"]
    return {"message_class": cl, "language": lg,
            "master_lang": t100a[0]["MASTERLANG"] if t100a else None,
            "exists": bool(t100a or msgs), "count": len(msgs),
            "messages": sorted(msgs, key=lambda r: r["MSGNR"])}


# ---------------------------------------------------------------------------
# Client-side join (no custom SQL FM, table blocklist still applies)
# ---------------------------------------------------------------------------
def join_read(left: dict, right: dict, on: dict, how: str = "inner",
              max_rows: int = 200) -> dict:
    """Join two tables client-side.

    left/right: {table, fields?, where?}. on: {left_field: right_field, ...}.
    how: inner (default) or left. The right table is read only for the key
    values found on the left (chunks of 20), so keep the left side selective.
    """
    if not on:
        raise SapConnectionError("on must map left fields to right fields")
    how = (how or "inner").lower()
    if how not in ("inner", "left"):
        raise SapConnectionError("how must be inner or left")
    lf = list(dict.fromkeys((left.get("fields") or []) + list(on.keys()))) \
        if left.get("fields") else None
    rf = list(dict.fromkeys((right.get("fields") or []) + list(on.values()))) \
        if right.get("fields") else None
    lres = read_table(left["table"], lf, left.get("where"), int(max_rows))
    lrows = lres["rows"]
    keys = {tuple(r[k] for k in on) for r in lrows}
    rrows: list[dict] = []
    klist = sorted(keys)
    r_fields = list(on.values())
    for i in range(0, len(klist), 20):
        chunk = klist[i:i + 20]
        ors = " OR ".join(
            "( " + " AND ".join(f"{rfld} = {_q(v)}" for rfld, v in zip(r_fields, kv)) + " )"
            for kv in chunk)
        conds = list(right.get("where") or []) + [f"( {ors} )"]
        off = 0
        while True:
            part = read_table(right["table"], rf, conds, 500, off)
            rrows += part["rows"]
            if not part.get("has_more") or len(rrows) >= 5000:
                break
            off = part["next_offset"]
    idx: dict[tuple, list[dict]] = {}
    for r in rrows:
        idx.setdefault(tuple(r[k] for k in on.values()), []).append(r)
    out: list[dict] = []
    for l in lrows:
        matches = idx.get(tuple(l[k] for k in on), [])
        if not matches:
            if how == "left":
                out.append(dict(l))
            continue
        for m in matches:
            row = dict(l)
            for k, v in m.items():
                if k in on.values() and k in row:
                    continue  # join key already present from the left side
                row[("R_" + k) if k in row else k] = v
            out.append(row)
    return {"row_count": len(out), "left_rows": len(lrows), "right_rows": len(rrows),
            "left_has_more": bool(lres.get("has_more")), "rows": out}


# ---------------------------------------------------------------------------
# User authorizations (what a user HAS for an auth object)
# ---------------------------------------------------------------------------
def user_auth(user: str, object: str, max_rows: int = 200) -> dict:
    """Authorization values a user holds for one authorization object
    (SUSR_USER_AUTH_FOR_OBJ_GET). Answers 'why is user X not authorized'."""
    res = get_client().call(
        "SUSR_USER_AUTH_FOR_OBJ_GET", USER_NAME=user.upper(),
        SEL_OBJECT=object.upper(), NO_TRACE="X",
    )
    vals = res.get("VALUES", [])
    grouped: dict[str, dict[str, list[str]]] = {}
    for v in vals:
        auth = (v.get("AUTH") or "").strip() or "-"
        fld = (v.get("FIELD") or "").strip()
        lo, hi = (v.get("VON") or "").strip(), (v.get("BIS") or "").strip()
        grouped.setdefault(auth, {}).setdefault(fld, []).append(f"{lo}..{hi}" if hi else lo)
    return {"user": user.upper(), "object": object.upper(),
            "fully_authorized": (res.get("FULLY_AUTHORIZED") or "").strip() or None,
            "authorizations": [{"auth": a, "fields": f} for a, f in grouped.items()][: int(max_rows)]}


# ---------------------------------------------------------------------------
# Function module write (update source of an existing FM; create new FM)
# ---------------------------------------------------------------------------
def _fm_include(fm: str) -> tuple[str, str]:
    row = read_table("TFDIR", ["PNAME", "INCLUDE"], [f"FUNCNAME = {_q(fm)}"], 1)["rows"]
    if not row:
        raise SapConnectionError(f"Function module {fm} not found")
    pname, num = row[0]["PNAME"].strip(), row[0]["INCLUDE"].strip()
    fg = pname[4:] if pname.startswith("SAPL") else pname
    if "/" in fg:  # namespaced group: /NS/SAPLNAME
        ns, _, rest = fg.rpartition("/")
        fg = fg
    return fg, f"L{fg}U{num}"


def _fm_precheck(fm: str, fg: str, include: str, source: str) -> None:
    """Syntax-check the whole function group with the new source inlined.

    The group's main program SAPL<FG> is expanded (TOP + the UXX include that
    lists the FM includes) and the FM's own INCLUDE line is replaced by the new
    source, so the check sees the real group attributes (fixed-point flag,
    global types). A syntax error inside a group makes EVERY FM of the group
    fail at call time, so a failed check blocks the write.
    """
    from .tools import read_program

    def _lines(name: str) -> list[str]:
        return read_program(name).get("source", "").split("\n")

    new_lines = source.replace("\r\n", "\n").rstrip("\n").split("\n")
    inc_re = re.compile(r"^\s*INCLUDE\s+([A-Z0-9_/]+)\s*\.", re.I)
    out: list[str] = []
    found = False
    for ln in _lines("SAPL" + fg):
        m = inc_re.match(ln)
        if m and m.group(1).upper() == f"L{fg}UXX".upper():
            for l2 in _lines(m.group(1)):
                m2 = inc_re.match(l2)
                if m2 and m2.group(1).upper() == include.upper():
                    out += new_lines
                    found = True
                else:
                    out.append(l2)
        else:
            out.append(ln)
    if not found:
        raise SapConnectionError(
            f"Could not locate include {include} in SAPL{fg}; nothing written")
    try:
        r = syntax_check("\n".join(out), "SAPL" + fg)
    except SapConnectionError as exc:
        raise SapConnectionError(
            f"Syntax check failed, {fm} not written: {str(exc)[:500]}") from exc
    res = r.get("result") or {}
    if res and not res.get("ok", True):
        raise SapConnectionError(f"Syntax check failed, {fm} not written: {res}")


_FM_NAME_RE = re.compile(r"^[YZ][A-Z0-9_]{1,29}$")
_FMDELETE_FM = "ZMCP_ADT_FMDELETE"


def _fg_package(fg: str) -> str:
    ta = read_table("TADIR", ["DEVCLASS"], ["PGMID = 'R3TR'", "OBJECT = 'FUGR'",
                                            f"OBJ_NAME = {_q(fg)}"], 1)["rows"]
    if not ta:
        raise SapConnectionError(f"Function group {fg} not found")
    return ta[0]["DEVCLASS"]


def _check_pkg_whitelist(fg: str, pkg: str) -> None:
    import fnmatch
    import os
    raw = (os.getenv("SAP_ALLOWED_PACKAGES") or "").strip()
    if raw and not any(fnmatch.fnmatch(pkg.upper(), p.strip().upper())
                       for p in raw.split(",") if p.strip()):
        raise SapConnectionError(
            f"Function group {fg} is in package {pkg}; SAP_ALLOWED_PACKAGES permits {raw}")


def _body_lines(source: str) -> list[str]:
    """Body of an FM: drop FUNCTION/ENDFUNCTION and the interface comment."""
    out = []
    head = re.compile(r"^\s*FUNCTION\s+[A-Za-z0-9_/]+\s*\.\s*$", re.I)
    tail = re.compile(r"^\s*ENDFUNCTION\s*\.\s*$", re.I)
    for ln in source.replace("\r\n", "\n").rstrip("\n").split("\n"):
        if head.match(ln) or tail.match(ln) or ln.startswith('*"'):
            continue
        out.append(ln)
    return out


def _param_rows(spec: list[dict] | None, kind: str) -> list[dict]:
    rows = []
    for p in spec or []:
        name = str(p.get("name", "")).upper()
        if not re.fullmatch(r"[A-Z][A-Z0-9_]{0,29}", name):
            raise SapConnectionError(f"invalid {kind} parameter name: {p.get('name')!r}")
        typ = str(p.get("type", "")).upper()
        if not typ:
            raise SapConnectionError(f"{kind} parameter {name} needs a type")
        if kind == "export":  # RSEXP has no OPTIONAL/DEFAULT/CHANGING columns
            rows.append({
                "PARAMETER": name, "TYP": typ, "TYPES": "",
                "REFERENCE": "X" if p.get("by_reference") else "",
                "DBFIELD": "", "CLASS": "", "REF_CLASS": "",
                "LINE_OF": "", "TABLE_OF": "",
            })
            continue
        rows.append({
            "PARAMETER": name, "TYP": typ, "TYPES": "",
            "OPTIONAL": "X" if p.get("optional") else "",
            "DEFAULT": str(p.get("default", "")),
            # by value unless by_reference is true (matches VALUE(...) in the
            # interface comment of the existing ZMCP FMs)
            "REFERENCE": "X" if p.get("by_reference") else "",
            "CHANGING": "", "DBFIELD": "", "CLASS": "", "REF_CLASS": "",
            "LINE_OF": "", "TABLE_OF": "",
        })
    return rows


def _precheck_new(fm: str, fg: str, body: list[str], imports, exports, changing) -> None:
    """Syntax check of a NEW FM: the group's flattened program plus the body
    as a FORM whose parameters are declared as DATA (the interface of a new
    FM does not exist yet). The group program gives the real attributes."""
    from .tools import read_program

    def _lines(name: str) -> list[str]:
        return read_program(name).get("source", "").split("\n")

    inc_re = re.compile(r"^\s*INCLUDE\s+([A-Z0-9_/]+)\s*\.", re.I)
    out: list[str] = []
    for ln in _lines("SAPL" + fg):
        m = inc_re.match(ln)
        if m and m.group(1).upper() == f"L{fg}UXX".upper():
            out += _lines(m.group(1))
        else:
            out.append(ln)
    out.append(f"FORM zmcp_chk_{fm[-18:].lower()}.")
    for row in list(imports) + list(exports) + list(changing):
        out.append(f"  DATA {row['PARAMETER'].lower()} TYPE {row['TYP'].lower()}.")
    out += body
    out.append("ENDFORM.")
    try:
        r = syntax_check("\n".join(out), "SAPL" + fg)
    except SapConnectionError as exc:
        raise SapConnectionError(
            f"Syntax check failed, {fm} not created: {str(exc)[:500]}") from exc
    res = r.get("result") or {}
    if res and not res.get("ok", True):
        raise SapConnectionError(f"Syntax check failed, {fm} not created: {res}")


def write_function_module(
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
    """Write a function module. Requires SAP_ALLOW_WRITE.

    create=False (default): replace the source of an EXISTING FM (full text
      incl. FUNCTION ... ENDFUNCTION; interface unchanged). The whole function
      group is syntax-checked with the new source first. `backup` holds the
      previous source.
    create=True: new FM in an EXISTING function group. `source` is the body
      (FUNCTION/ENDFUNCTION/interface comment are generated). Interface via
      imports/exports/changing = [{name, type, optional?, default?,
      by_reference?}], exceptions = [names]; remote=True makes it
      RFC-enabled. A transport is required unless the group is local ($).
      If the group fails its syntax check after creation the new FM is
      deleted again.
    """
    _require_write()
    fm = name.upper()
    if not create:
        fg, include = _fm_include(fm)
        pkg = _fg_package(fg)
        _check_pkg_whitelist(fg, pkg)
        if not re.match(r"\s*FUNCTION\s+" + re.escape(fm.lower()) + r"\b",
                        source, re.I | re.M):
            raise SapConnectionError(f"source must start with FUNCTION {fm.lower()}.")
        from .tools import read_function_module
        backup = read_function_module(fm).get("source")
        _fm_precheck(fm, fg, include, source)
        get_client().call(
            "SIW_RFC_WRITE_REPORT", I_NAME=include, I_OBJECT="PROG", I_OBJNAME=include,
            I_PROGTYPE="I",
            I_TAB_CODE=source.replace("\r\n", "\n").rstrip("\n").split("\n"),
        )
        return {"function": fm, "function_group": fg, "include": include,
                "package": pkg, "written": True, "backup": backup,
                "note": "Source written active. If the group now fails to load, "
                        "restore `backup` with the same tool."}

    # ---- create ----
    if not _FM_NAME_RE.match(fm):
        raise SapConnectionError("function name must match [YZ][A-Z0-9_]{1,29}")
    if not function_group:
        raise SapConnectionError("function_group is required for create")
    fg = function_group.upper()
    if read_table("TFDIR", ["FUNCNAME"], [f"FUNCNAME = {_q(fm)}"], 1)["rows"]:
        raise SapConnectionError(f"Function module {fm} already exists")
    pkg = _fg_package(fg)
    _check_pkg_whitelist(fg, pkg)
    if not pkg.startswith("$") and not transport:
        raise SapConnectionError(
            f"Function group {fg} is in transportable package {pkg}: pass a "
            "modifiable transport request")
    imp = _param_rows(imports, "import")
    exp = _param_rows(exports, "export")
    chg = _param_rows(changing, "changing")
    body = _body_lines(source)
    if not any(l.strip() for l in body):
        raise SapConnectionError("source has no statements")
    _precheck_new(fm, fg, body, imp, exp, chg)
    res = get_client().call(
        "RPY_FUNCTIONMODULE_INSERT",
        FUNCNAME=fm, FUNCTION_POOL=fg, REMOTE_CALL="R" if remote else "",
        SHORT_TEXT=(short_text or fm)[:74], CORRNUM=transport or "",
        IMPORT_PARAMETER=imp, EXPORT_PARAMETER=exp, CHANGING_PARAMETER=chg,
        EXCEPTION_LIST=[{"EXCEPTION": str(e).upper()} for e in (exceptions or [])],
        NEW_SOURCE=body,
    )
    include = res.get("FUNCTION_INCLUDE")
    # real check of the group now that the FM exists; roll back on failure
    try:
        from .tools import read_function_module
        full = read_function_module(fm).get("source") or ""
        _fm_precheck(fm, fg, include or _fm_include(fm)[1], full)
    except SapConnectionError as exc:
        rolled = False
        try:
            delete_function_module(fm, _skip_checks=True)
            rolled = True
        except SapConnectionError:
            pass
        raise SapConnectionError(
            f"{fm} was created but the group failed its syntax check "
            f"({'rolled back' if rolled else 'ROLLBACK FAILED: delete it in SE37'}): "
            f"{str(exc)[:400]}") from exc
    return {"function": fm, "function_group": fg, "include": include,
            "package": pkg, "created": True, "remote_enabled": bool(remote)}


def delete_function_module(name: str, _skip_checks: bool = False) -> dict:
    """Delete ONE function module (e.g. one written by mistake) through
    ZMCP_ADT_FMDELETE. Only Z/Y modules in LOCAL packages, never the bridge's
    own FMs. The deleted source is returned as `backup`. Requires
    SAP_ALLOW_WRITE (abap/zmcp_adt_fmdelete.abap must be installed)."""
    _require_write()
    fm = name.upper()
    backup = None
    try:
        from .tools import read_function_module
        backup = read_function_module(fm).get("source")
    except SapConnectionError:
        pass
    try:
        res = get_client().call(_FMDELETE_FM, IV_PARAMS=json.dumps({"function": fm}))
    except SapConnectionError as exc:
        raise SapConnectionError(
            f"{_FMDELETE_FM} not usable ({str(exc)[:200]}). Install "
            "abap/zmcp_adt_fmdelete.abap, see abap/README.md.") from exc
    if res.get("EV_SUBRC", 0) != 0:
        raise SapConnectionError(res.get("EV_MESSAGE") or "delete failed")
    gone = not read_table("TFDIR", ["FUNCNAME"], [f"FUNCNAME = {_q(fm)}"], 1)["rows"]
    out = json.loads(res.get("EV_RESULT") or "{}")
    out.update({"deleted": gone, "message": res.get("EV_MESSAGE"), "backup": backup})
    return out


_MSAG_FM = "ZMCP_ADT_MSAG"


def write_message_class(class_name: str, messages: list[dict], transport: str = "",
                        language: str = "E", delete: bool = False) -> dict:
    """Add / change (or delete) messages of an EXISTING Z/Y message class (SE91)
    through ZMCP_ADT_MSAG. messages = [{"number": "560", "text": "..."}]; text
    max 73 chars, delete ignores text. Transportable class -> `transport` is
    required (recorded as R3TR MSAG, like SE91). The result is read back from
    T100 (`verified`). Requires SAP_ALLOW_WRITE and abap/zmcp_adt_msag.abap."""
    _require_write()
    name = (class_name or "").strip().upper()
    if not re.match(r"^[YZ][A-Z0-9_/]{1,19}$", name):
        raise SapConnectionError("class_name must be a Z/Y message class name")
    if not messages:
        raise SapConnectionError("messages is empty")
    rows = []
    for m in messages:
        num = str(m.get("number", "")).strip()
        if not re.fullmatch(r"\d{1,3}", num):
            raise SapConnectionError(f"message number {num!r} is not 000-999")
        rows.append({"number": num.zfill(3), "text": str(m.get("text", ""))})
    if len({r["number"] for r in rows}) != len(rows):
        raise SapConnectionError("duplicate message number in messages")
    lang = (language or "E").strip().upper()[:1] or "E"
    payload = {"action": "DELETE" if delete else "UPSERT", "class": name,
               "language": lang, "transport": (transport or "").strip().upper(),
               "messages": rows}
    try:
        res = get_client().call(_MSAG_FM, IV_PARAMS=json.dumps(payload, ensure_ascii=False))
    except SapConnectionError as exc:
        raise SapConnectionError(
            f"{_MSAG_FM} not usable ({str(exc)[:200]}). Install "
            "abap/zmcp_adt_msag.abap, see abap/README.md.") from exc
    if res.get("EV_SUBRC", 0) != 0:
        raise SapConnectionError(res.get("EV_MESSAGE") or "message write failed")
    nums = ", ".join(_q(r["number"]) for r in rows)
    back = read_table("T100", ["MSGNR", "TEXT"],
                      [f"SPRSL = {_q(lang)}", f"ARBGB = {_q(name)}", f"MSGNR IN ({nums})"],
                      len(rows))["rows"]
    got = {b["MSGNR"]: b["TEXT"] for b in back}
    if delete:
        ok = not got
    else:
        ok = all(got.get(r["number"], "").strip() == r["text"].strip() for r in rows)
    out = json.loads(res.get("EV_RESULT") or "{}")
    out.update({"message": res.get("EV_MESSAGE"), "verified": ok,
                "stored": [{"number": k, "text": v} for k, v in sorted(got.items())]})
    return out


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
_HEALTH_FMS = [
    ("ZMCP_ADT_DISPATCH", "core bridge: write/syntax/ATC/DDIC reads"),
    ("ZMCP_ADT_TEXTPOOL", "text elements"),
    ("ZMCP_ADT_APPLOG", "sap_read_applog messages"),
    ("ZMCP_ADT_GWLOG", "sap_gateway_errors"),
    ("ZMCP_ADT_FMDELETE", "sap_delete_function_module"),
    ("ZMCP_ADT_MSAG", "sap_write_message_class"),
    ("ZMCP_ADT_DDIC_TABL", "sap_write_ddic (tables)"),
    ("ZCTD_FM_GW_TEST", "sap_gateway_call / sap_gateway_test"),
    ("/IWFND/SUTIL_CLEANUP_MD_CACHE", "sap_gateway_admin clear_cache"),
    ("/IWBEP/SUTIL_CLEANUP_MD_CACHE", "sap_gateway_admin clear_cache"),
    ("CTS_API_CREATE_CHANGE_REQUEST", "sap_create_transport"),
    ("ENQUEUE_READ", "sap_read_locks"),
    ("SUSR_USER_AUTH_FOR_OBJ_GET", "sap_user_auth"),
]


def health() -> dict:
    """Which helper FMs the connected system has, and what breaks without."""
    cfg = get_client().config
    out = []
    for fm, used_by in _HEALTH_FMS:
        row = read_table("TFDIR", ["FMODE"], [f"FUNCNAME = {_q(fm)}"], 1)["rows"]
        out.append({"function": fm, "used_by": used_by,
                    "installed": bool(row),
                    "remote_enabled": bool(row and row[0]["FMODE"] == "R")})
    missing = [o for o in out if not (o["installed"] and o["remote_enabled"])]
    return {"client": cfg.conn_params.get("client"), "write_enabled": cfg.allow_write,
            "ok": not missing, "missing": [m["function"] for m in missing],
            "functions": out}
