# S001 Design

## DDIC FMs (separate FMs, not dispatcher actions)

Kept as standalone FMs matching the superclaude originals: less rework of
proven code, and mirrors the existing precedent (`ZMCP_ADT_TEXTPOOL` is
also a standalone FM). Protocol per FM: IV_ACTION/IV_NAME/IV_DEVCLASS/
IV_TRANSPORT/IV_PAYLOAD_JSON → EV_SUBRC(i)/EV_MESSAGE/EV_RESULT(JSON).

Flow (CREATE/UPDATE): RS_CORR_INSERT (TADIR/package, non-$TMP only) →
DDIF_*_PUT (staged inactive) → TR_RECORD_OBJ_CHANGE_TO_REQ (transport) →
WB_TREE_ACTUALIZE (SE80 cache). Activation separated into
ZMCP_ADT_DDIC_ACTIVATE (DDIF_*_ACTIVATE) so the inactive-first discipline
matches the program pipeline. DELETE via RS_DD_DELETE_OBJ.

Header pseudo-signatures from the source repo were converted to standard
`FUNCTION name.` + `*"` interface comment blocks — the originals would not
compile pasted into SE37 (caught by abaplint parser).

## ATC via Code Inspector engine

CL_SATC_API_* signatures vary by release; the CL_CI_* API
(objectset → global check variant → transient inspection → run 'L' →
plain_list → delete) is release-stable and proven by abapGit's integration.
Variant = GLOBAL SCI check variant, default DEFAULT.
[Unverified on DS4 — validated only by offline lint; SE80 syntax check on
paste is the real gate.]

## Python layer

- `_check_devclass_allowed()` — package whitelist for explicit-package DDIC
  writes (programs derive their package; DDIC carries it as a parameter).
- All three tools `_require_write()`-gated; hook + settings matcher extended
  with sap_write_ddic|sap_delete_ddic|sap_activate_ddic.
