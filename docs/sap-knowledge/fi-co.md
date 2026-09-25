# FI/CO — Financial Accounting & Controlling

> [Unverified] General SAP knowledge adapted from superclaude-for-sap
> configs; not yet validated against DS4. Before relying on any entry,
> verify with `sap_ddic_info` (tables) or `sap_search_objects` /
> `sap_read_function_module` (BAPIs). Append `(verified: DS4 <date>)` as
> entries are confirmed.

## Key tables

| Table | Content | S/4 note |
| --- | --- | --- |
| BKPF | Accounting document header | still primary |
| BSEG | Accounting document line items | in S/4 a view over ACDOCA-era model; prefer ACDOCA for reporting |
| ACDOCA | Universal Journal (S/4 only) | the reporting source of truth on DS4 |
| BSID / BSAD | Customer open / cleared items | compatibility views in S/4 |
| BSIK / BSAK | Vendor open / cleared items | compatibility views in S/4 |
| SKA1 / SKB1 | G/L account master (chart / company code) | |
| KNA1 / KNB1 | Customer master general / company code | BP model in S/4 (BUT000) |
| LFA1 / LFB1 | Vendor master general / company code | BP model in S/4 (BUT000) |
| T001 | Company codes | |
| T030 | Account determination | |
| CSKS / CSKA | Cost center master / cost elements | cost elements are G/L accounts in S/4 |
| COEP | CO line items | folded into ACDOCA in S/4 |
| AUFK | Internal orders (master) | shared with PP/PM orders |
| ANLA / ANLC | Asset master / values | FI-AA |

## Key BAPIs / FMs

| BAPI/FM | Purpose |
| --- | --- |
| BAPI_ACC_DOCUMENT_POST | Post accounting document |
| BAPI_ACC_DOCUMENT_CHECK | Validate before posting |
| BAPI_AP_ACC_GETOPENITEMS / BAPI_AR_ACC_GETOPENITEMS | Vendor / customer open items |
| BAPI_GLACCOUNT_GETDETAIL | G/L account details |
| BAPI_COSTCENTER_GETDETAIL / _GETLIST | Cost center reads |
| BAPI_TRANSACTION_COMMIT / _ROLLBACK | Mandatory after posting BAPIs |
| FI_DOCUMENT_READ | Read FI document (classic) |

## T-codes (for user instructions / testing)

FB01/FB03 (post/display document), FBL1N/FBL3N/FBL5N (vendor/G-L/customer
line items), FS00 (G/L master), F-02/F-03 (posting/clearing), KS01/KS03
(cost center), KSB1 (CO line items), OB52 (posting periods), FBZP (payment
program config).

## Common Z-enhancement spots

- Substitutions/validations (GGB0/GGB1, OBBH/OB28).
- BTE events (FIBF) for document posting side effects.
- BAdI `AC_DOCUMENT` / `FI_HEADER_SUB_1300` for document enrichment.
