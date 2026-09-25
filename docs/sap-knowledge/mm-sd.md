# MM/SD — Materials Management & Sales/Distribution

> [Unverified] General SAP knowledge adapted from superclaude-for-sap
> configs; not yet validated against DS4. Before relying on any entry,
> verify with `sap_ddic_info` (tables) or `sap_search_objects` /
> `sap_read_function_module` (BAPIs). Append `(verified: DS4 <date>)` as
> entries are confirmed.

## Key tables — MM

| Table | Content | S/4 note |
| --- | --- | --- |
| MARA / MAKT | Material master general / descriptions | |
| MARC / MARD | Plant / storage-location data | |
| MBEW | Material valuation | |
| EKKO / EKPO | Purchase order header / items | |
| EKET / EKBE | PO schedule lines / history | |
| EBAN | Purchase requisitions | |
| MKPF / MSEG | Material document header / items | compatibility views over **MATDOC** in S/4 |
| MATDOC | Material documents (S/4 only) | preferred read source on DS4 |
| LFA1 / LFM1 | Vendor general / purchasing org | BP model in S/4 |
| T001W / T001L | Plants / storage locations | |

## Key tables — SD

| Table | Content | S/4 note |
| --- | --- | --- |
| VBAK / VBAP | Sales order header / items | |
| VBEP / VBKD | Schedule lines / business data | |
| LIKP / LIPS | Delivery header / items | |
| VBRK / VBRP | Billing header / items | |
| VBFA | Document flow | |
| KONV | Pricing conditions (doc) | replaced by **PRCD_ELEMENTS** in S/4 |
| KNA1 / KNVV | Customer general / sales area | |
| VBUK / VBUP | Status headers/items | statuses moved into VBAK/VBAP in S/4 |

## Key BAPIs / FMs

| BAPI/FM | Purpose |
| --- | --- |
| BAPI_PO_CREATE1 / BAPI_PO_CHANGE / BAPI_PO_GETDETAIL1 | Purchase orders |
| BAPI_PR_CREATE | Purchase requisitions |
| BAPI_GOODSMVT_CREATE | Goods movements (101/201/261...) |
| BAPI_MATERIAL_SAVEDATA / BAPI_MATERIAL_GET_DETAIL | Material master |
| BAPI_SALESORDER_CREATEFROMDAT2 / _CHANGE / _GETSTATUS | Sales orders |
| BAPI_OUTB_DELIVERY_CREATE_SLS | Outbound delivery from SO |
| BAPI_BILLINGDOC_CREATEMULTIPLE | Billing documents |
| SD_SALESDOCUMENT_CREATE | Sales doc (more fields than BAPI) |
| BAPI_TRANSACTION_COMMIT | Mandatory after create/change BAPIs |

## T-codes

MM: ME21N/ME22N/ME23N (PO), ME51N (PR), MIGO (goods movement), MM01/MM02/MM03
(material), MB52 (stock), ME2M/ME2L (PO lists).
SD: VA01/VA02/VA03 (sales order), VL01N/VL02N (delivery), VF01/VF03
(billing), VA05 (order list), VOV8 (order type config).

## Common Z-enhancement spots

- MM: BAdI `ME_PROCESS_PO_CUST` (PO checks/defaults), `MB_MIGO_BADI` (MIGO
  screens), user exits EXIT_SAPMM06E_* (CMOD ZXM06U..).
- SD: USEREXIT_SAVE_DOCUMENT / USEREXIT_PRICING_* in MV45AFZZ / RV60AFZZ,
  BAdI `BADI_SD_SALES_DOC` , copy requirements (VOFM).
