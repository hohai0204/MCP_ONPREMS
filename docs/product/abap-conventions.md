# ABAP Conventions for Generated Customizations

Rules the agent follows when authoring ABAP from a spec. Extend this file as
real specs establish more conventions — do not invent rules ahead of need.

## Naming and placement

- All custom objects in the `Z` namespace. [Unverified] Team prefix scheme
  beyond `Z` (e.g. `ZFI_`, module-wise) — fill in when the user confirms.
- Bridge infrastructure objects use `ZMCP_*` (group `ZMCP_ADT_UTILS`); do not
  mix business customizations into that group.
- Target package comes from the spec/story; must be in
  `SAP_ALLOWED_PACKAGES`, else the object lands in `$TMP` (prototypes only).

## Authoring rules

- Read the live system first (`sap_ddic_info`, `sap_read_program`,
  `sap_where_used`) — never assume field names or existing logic.
- Source pushed over RFC arrives **inactive**; syntax-check before asking for
  activation.
- RFC-callable custom FMs follow the dispatcher protocol pattern:
  `IV_ACTION` + `IV_PARAMS` (JSON) → `EV_SUBRC` / `EV_MESSAGE` / `EV_RESULT`
  (JSON via `/ui2/cl_json`), remote-enabled.
- Keep the 72-char line discipline in mind for anything that round-trips
  through classic RFC FMs (`RFC_READ_TABLE` OPTIONS, RPY_* readers).
- New/changed behavior that has a testable core gets ABAP Unit test classes
  when feasible on the target release.

## Change safety

- Before modifying an existing Z-object: `sap_where_used` + read current
  source + note the transport (`sap_list_transports`).
- Never modify SAP standard objects; spec requirements that seem to need it
  become a high-risk story and an explicit decision (enhancement/BAdI first).
- Changes to `ZMCP_ADT_DISPATCH` / `ZMCP_ADT_TEXTPOOL` themselves are
  high-risk: they are the bridge everything else depends on. Update the repo
  copy in `abap/` in the same story so repo and system never drift.
