# 0009 — Accept pyrfc (archived upstream) with a documented contingency

Date: 2026-07-18
Status: accepted

## Context

The bridge depends on pyrfc 3.3.1, installed from a vendored wheel
(`mcp/vendor/pyrfc-3.3.1-cp312-cp312-win_amd64.whl`) because PyPI has no
py3.12 wheel. Upstream is **SAP-archive/PyRFC** — SAP archived the project
and it is unmaintained. Verified working against DS4 (2026-07-17). The NW
RFC SDK itself (vendored, `mcp/vendor/nwrfcsdk`) remains SAP-supported.

## Decision

Keep pyrfc 3.3.1 pinned via the vendored wheel. Do not migrate proactively.

Contingency if pyrfc breaks (Python > 3.12 upgrade, SDK update, or a
blocking bug):
1. First option: call the NW RFC SDK directly via ctypes — pattern
   demonstrated in jdsricardo/SAP-RFC-Python-without-PyRFC. Only
   `mcp/sap/connection.py` would need replacement; `tools.py` stays.
2. Alternative: adopt a maintained community fork if one has emerged.

Revisit triggers: Python version bump beyond 3.12, NW RFC SDK major update,
or new SAP guidance on RFC connectivity from Python.

## Consequences

- Python stays pinned to 3.12 on machines running the bridge until the
  contingency is exercised.
- `mcp/sap/connection.py` is the single isolation layer around pyrfc — keep
  pyrfc imports confined there so a swap stays cheap.
