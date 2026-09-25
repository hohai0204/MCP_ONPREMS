# PP/QM/PM — Production, Quality, Plant Maintenance

> [Unverified] General SAP knowledge adapted from superclaude-for-sap
> configs; not yet validated against DS4. Before relying on any entry,
> verify with `sap_ddic_info` (tables) or `sap_search_objects` /
> `sap_read_function_module` (BAPIs). Append `(verified: DS4 <date>)` as
> entries are confirmed.

## Key tables — PP

| Table | Content |
| --- | --- |
| AUFK / AFKO / AFPO | Order master / production order header / items |
| AFVC / AFVV | Order operations / quantities-dates |
| AFRU | Order confirmations |
| MAST / STKO / STPO | BOM link / header / items |
| PLKO / PLPO | Routing header / operations |
| CRHD | Work center header |
| PBIM / PBED | Independent requirements |
| RESB | Reservations / dependent requirements |

## Key tables — QM

| Table | Content |
| --- | --- |
| QALS | Inspection lots |
| QAVE | Usage decisions |
| QAMR / QASE | Characteristic results / sample results |
| QMEL | Quality notifications (shared with PM notifications) |
| QPMK | Master inspection characteristics |

## Key tables — PM

| Table | Content |
| --- | --- |
| EQUI / EQKT / EQUZ | Equipment master / texts / time segments |
| IFLOT / IFLOTX | Functional locations / texts |
| VIQMEL | Notification view (QMEL join) |
| AUFK + AFIH | Maintenance order (AUFK) + PM header (AFIH) |
| IHPA | Partners for objects |
| MPLA / MPOS | Maintenance plans / items |

## Key BAPIs / FMs

| BAPI/FM | Purpose |
| --- | --- |
| BAPI_PRODORD_CREATE / _GET_DETAIL / _RELEASE | Production orders |
| BAPI_PRODORDCONF_CREATE_TT | Time-ticket confirmations |
| BAPI_INSPLOT_GETLIST / BAPI_INSPLOT_SETSTATUS | Inspection lots |
| BAPI_INSPOPER_RECORDRESULTS | Record inspection results |
| BAPI_QUALNOT_CREATE / BAPI_ALM_NOTIF_CREATE | Quality / maintenance notifications |
| BAPI_ALM_ORDER_MAINTAIN | Create/change maintenance orders |
| BAPI_EQUI_CREATE / _GETDETAIL | Equipment |
| BAPI_TRANSACTION_COMMIT | Mandatory after create/change BAPIs |

## T-codes

PP: CO01/CO02/CO03 (production order), CO11N (confirmation), CS01/CS03 (BOM),
CA01/CA03 (routing), MD01/MD02/MD04 (MRP).
QM: QA01/QA02/QA32 (inspection lots / usage decision), QE51N (results),
QM01/QM02 (notifications).
PM: IW21/IW22/IW23 (notification), IW31/IW32/IW33 (order), IE01/IE03
(equipment), IL01/IL03 (functional location), IP41/IP10 (maintenance plans).

## Common Z-enhancement spots

- PP: BAdI `WORKORDER_UPDATE`, user exits PPCO0006/PPCO0007 (order
  check/save), CONFPP* exits for confirmations.
- QM: BAdI `QEC_USAGE_DECISION`, exit QEVA0008 (usage decision).
- PM: BAdI `IWO1_ORDER_BADI`, exits IWO10009 (order save), QQMA0014
  (notification save).
