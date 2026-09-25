"""DDIC structures for OData ZCTD_CORE_INT_SRV (package ZCTD_CORE).

    python odata/abap/zctd_core_int_ddic.py <TR>

Field names = OData property names in upper case, so DPC_EXT can move
data with CORRESPONDING. Amounts/quantities are plain DEC (no CURR/QUAN
reference), dates are CHAR8 YYYYMMDD - same convention as ZCTD_PO_INFO_SRV.
"""
import sys

TR = sys.argv[1]
sys.argv = ['x', '--profile', 's4d-100']
sys.path.insert(0, r'D:\MCP_SAP_PRIVATE\MCP_SAP_PRIVATE\mcp')
from sap import tools  # noqa: E402

PKG = 'ZCTD_CORE'


def de(name, rollname):
    return (name, {"ROLLNAME": rollname})


def raw(name, datatype, leng, dec=0, text=''):
    return (name, {"ROLLNAME": "", "DATATYPE": datatype, "LENG": f"{leng:06d}", "DECIMALS": f"{dec:06d}",
                   "DDTEXT": text})


STRUCTS = {
    # generic filter line: every object GET FM takes TABLES IT_FILTER STRUCTURE this
    'ZCTD_S_INT_FILTER': ('CTD Core Int: filter condition', [
        raw('PROPERTY', 'CHAR', 30, text='OData property'),
        de('SIGN', 'DDSIGN'), de('OPTION', 'DDOPTION'),
        raw('LOW', 'CHAR', 255, text='Low value'), raw('HIGH', 'CHAR', 255, text='High value')]),
    'ZCTD_S_INT_VENDOR': ('CTD Core Int: Vendor', [
        de('SUPPLIER', 'LIFNR'), de('BUSINESSPARTNER', 'BU_PARTNER'), de('BPGROUPING', 'BU_GROUP'),
        de('ACCOUNTGROUP', 'KTOKK'), de('NAME1', 'BU_NAMEOR1'), de('NAME2', 'BU_NAMEOR2'),
        de('SEARCHTERM', 'BU_SORT1'), de('STREET', 'AD_STREET'), de('CITY', 'AD_CITY1'),
        de('POSTALCODE', 'AD_PSTCD1'), de('REGION', 'REGIO'), de('COUNTRY', 'LAND1_GP'),
        de('LANGUAGE', 'LAISO'), de('TELEPHONE', 'AD_TLNMBR1'), de('EMAIL', 'AD_SMTPADR'),
        de('TAXNUMBER1', 'STCD1'), de('VATNUMBER', 'STCEG'), de('POSTINGBLOCK', 'SPERB_X'),
        de('PURCHASINGBLOCK', 'SPERM_X'), de('DELETIONFLAG', 'LOEVM_X'),
        raw('CREATEDON', 'CHAR', 8, text='Created on (YYYYMMDD)'), de('CREATEDBY', 'ERNAM_RF')]),
    'ZCTD_S_INT_PR_HDR': ('CTD Core Int: Purchase Requisition header', [
        de('PRNUMBER', 'BANFN'), de('PRTYPE', 'BBSRT'), de('CREATEDBY', 'ERNAM'),
        raw('CREATEDON', 'CHAR', 8, text='Created on (YYYYMMDD)'),
        raw('REQUESTDATE', 'CHAR', 8, text='Request date (YYYYMMDD)'),
        de('REQUISITIONER', 'AFNAM'), de('TRACKINGNO', 'BEDNR'), de('RELEASESTRATEGY', 'FRGST'),
        de('RELEASEINDICATOR', 'FRGKZ'), raw('ITEMCOUNT', 'INT4', 10, text='Number of items'),
        raw('TOTALVALUE', 'DEC', 23, 2, 'Total value'), de('CURRENCY', 'WAERS')]),
    'ZCTD_S_INT_PR_ITM': ('CTD Core Int: Purchase Requisition item', [
        de('PRNUMBER', 'BANFN'), de('ITEM', 'BNFPO'), de('MATERIAL', 'MATNR'), de('SHORTTEXT', 'TXZ01'),
        de('MATERIALGROUP', 'MATKL'), de('PLANT', 'EWERK'), de('STORAGELOCATION', 'LGORT_D'),
        raw('QUANTITY', 'DEC', 13, 3, 'Quantity'), raw('UOM', 'CHAR', 3, text='Unit of measure'),
        raw('DELIVERYDATE', 'CHAR', 8, text='Delivery date (YYYYMMDD)'),
        raw('VALUATIONPRICE', 'DEC', 23, 2, 'Valuation price'), raw('PRICEUNIT', 'DEC', 5, 0, 'Price unit'),
        de('CURRENCY', 'WAERS'), raw('ITEMVALUE', 'DEC', 23, 2, 'Item value'),
        de('PURCHASINGGROUP', 'EKGRP'), de('PURCHASINGORG', 'EKORG'), de('ACCTASSIGNCATEGORY', 'KNTTP'),
        de('ITEMCATEGORY', 'PSTYP'), de('WBSELEMENT', 'PS_POSID'), de('RELEASEINDICATOR', 'FRGKZ'),
        de('PROCESSINGSTATUS', 'BANST'), de('DELETIONINDICATOR', 'ELOEK'), de('CLOSED', 'EBAKZ'),
        de('PONUMBER', 'BSTNR'), de('POITEM', 'BSTPO'), de('REQUISITIONER', 'AFNAM'), de('TRACKINGNO', 'BEDNR')]),
}

for name, (text, fields) in STRUCTS.items():
    dd03p = []
    for i, (fname, attrs) in enumerate(fields, 1):
        row = {"FIELDNAME": fname, "POSITION": f"{i:04d}", "DDLANGUAGE": "E"}
        row.update(attrs)
        dd03p.append(row)
    exists = bool(tools.read_table('DD02L', ['TABNAME'], [f"TABNAME = '{name}'"])['rows'])
    payload = {"dd02v": {"TABNAME": name, "DDLANGUAGE": "E", "TABCLASS": "INTTAB", "DDTEXT": text,
                         "MASTERLANG": "E", "EXCLASS": "1"}, "dd03p": dd03p}
    tools.ddic_write("TABL", name, payload, devclass=PKG, transport=TR, update=exists)
    try:
        rc = tools.ddic_activate("TABL", name)['result'].get('rc')
    except Exception as exc:  # rc=4 warnings are raised as errors by the bridge
        rc = f"warn/err: {exc}"
    state = tools.read_table('DD02L', ['AS4LOCAL'], [f"TABNAME = '{name}'"])['rows']
    print(f"{name:20} fields={len(dd03p):2} activate rc={rc} state={state}")
