import sys, json
sys.argv = ['x', '--profile', 's4d-100']
sys.path.insert(0, r'D:\MCP_SAP_PRIVATE\MCP_SAP_PRIVATE\mcp')
from sap import tools

TR, PKG, TAB = 'S4DK907431', 'ZCTD_CORE', 'ZCTD_T_API_LOG'

# field, data element, domain (''=builtin STRG), short(10), medium(20), long(40), heading(55), description(60)
DEFS = [
    ('CORR_ID', 'ZCTD_DE_API_CORR_ID', 'SYSUUID_C36', 'Corr. ID', 'Correlation ID', 'Correlation ID', 'Correlation ID', 'CTD API log: Correlation ID'),
    ('CALL_DATE', 'ZCTD_DE_API_CALL_DATE', 'DATUM', 'Call Date', 'API Call Date', 'API Call Date', 'Call Date', 'CTD API log: API call date'),
    ('CALL_TIME', 'ZCTD_DE_API_CALL_TIME', 'UZEIT', 'Call Time', 'API Call Time', 'API Call Time', 'Call Time', 'CTD API log: API call time'),
    ('CALL_TSTMP', 'ZCTD_DE_API_CALL_TSTMP', 'TZNTSTMPL', 'Timestamp', 'Call Timestamp UTC', 'API Call Timestamp (UTC)', 'Call Timestamp (UTC)', 'CTD API log: API call timestamp (UTC)'),
    ('OBJECT_TYPE', 'ZCTD_DE_API_OBJECT', 'TEXT40', 'API Object', 'API Object Type', 'API Object Type (Entity Set)', 'API Object Type', 'CTD API log: API object type (entity set)'),
    ('HTTP_METHOD', 'ZCTD_DE_API_HTTP_METHOD', 'CHAR10', 'Method', 'HTTP Method', 'HTTP Method', 'HTTP Method', 'CTD API log: HTTP method'),
    ('API_URL', 'ZCTD_DE_API_URL', '', 'API URL', 'API URL', 'API Request URL', 'API URL', 'CTD API log: API request URL'),
    ('DURATION_MS', 'ZCTD_DE_API_DURATION_MS', 'INT4', 'Dur. (ms)', 'Duration (ms)', 'Processing Duration (ms)', 'Duration (ms)', 'CTD API log: processing duration in milliseconds'),
    ('CALL_USER', 'ZCTD_DE_API_CALL_USER', 'SYCHAR12', 'Call User', 'API Caller', 'User Who Called the API', 'Call User', 'CTD API log: user who called the API'),
    ('HTTP_STATUS', 'ZCTD_DE_API_HTTP_STATUS', 'CHAR3', 'HTTP Stat.', 'HTTP Status Code', 'HTTP Status Code', 'HTTP Status', 'CTD API log: HTTP status code'),
    ('RESP_STATUS', 'ZCTD_DE_API_RESP_STATUS', 'SYCHAR01', 'Resp.Stat.', 'Response Status', 'Response Status (S = Success, E = Error)', 'Resp. Status', 'CTD API log: response status (S/E)'),
    ('MESSAGE', 'ZCTD_DE_API_MESSAGE', 'TEXT220', 'Message', 'Response Message', 'Response Message', 'Response Message', 'CTD API log: response message'),
    ('REQUEST', 'ZCTD_DE_API_REQUEST', '', 'Request', 'Request Data', 'Request Data (JSON)', 'Request Data (JSON)', 'CTD API log: request data (JSON)'),
    ('RESPONSE', 'ZCTD_DE_API_RESPONSE', '', 'Response', 'Response Data', 'Response Data (JSON)', 'Response Data (JSON)', 'CTD API log: response data (JSON)'),
]


def dd04v(name, dom, s, m, l, h, text):
    assert len(s) <= 10 and len(m) <= 20 and len(l) <= 40 and len(h) <= 55 and len(text) <= 60, name
    d = {"ROLLNAME": name, "DDLANGUAGE": "E", "DTELMASTER": "E", "DDTEXT": text,
         "SCRTEXT_S": s, "SCRTEXT_M": m, "SCRTEXT_L": l, "REPTEXT": h,
         "SCRLEN1": f"{len(s):02d}" if False else "10", "SCRLEN2": "20", "SCRLEN3": "40",
         "HEADLEN": f"{max(len(h), 10):02d}"}
    if dom:
        d.update({"DOMNAME": dom, "REFKIND": "D"})
    else:
        d.update({"DATATYPE": "STRG", "LENG": "000000", "REFKIND": ""})
    return d


step = sys.argv_step if hasattr(sys, 'argv_step') else None
for field, de, dom, s, m, l, h, text in DEFS:
    exists = bool(tools.read_table('DD04L', ['ROLLNAME'], [f"ROLLNAME = '{de}'"])['rows'])
    r = tools.ddic_write("DTEL", de, {"dd04v": dd04v(de, dom, s, m, l, h, text)},
                         devclass=PKG, transport=TR, update=exists)
    try:
        a = tools.ddic_activate("DTEL", de)['result'].get('rc')
    except Exception as e:
        a = f"ERR {e}"
    st = tools.read_table('DD04L', ['AS4LOCAL'], [f"ROLLNAME = '{de}'"])['rows']
    print(f"{de:26} activate rc={a} state={st}")

# table: switch fields to the new data elements (same domains -> no DB conversion)
roll = {f: de for f, de, *_ in DEFS}
base = [("MANDT", "MANDT", "X"), ("CORR_ID", "", "X"), ("CALL_DATE", "", "X"), ("CALL_TIME", "", "X"),
        ("CALL_TSTMP", "", ""), ("OBJECT_TYPE", "", ""), ("HTTP_METHOD", "", ""), ("API_URL", "", ""),
        ("DURATION_MS", "", ""), ("CALL_USER", "", ""), ("HTTP_STATUS", "", ""), ("RESP_STATUS", "", ""),
        ("MESSAGE", "", ""), ("REQUEST", "", ""), ("RESPONSE", "", "")]
dd03p = [{"FIELDNAME": f, "POSITION": f"{i + 1:04d}", "KEYFLAG": k, "ROLLNAME": r or roll[f], "NOTNULL": k, "DDLANGUAGE": "E"}
         for i, (f, r, k) in enumerate(base)]
payload = {"dd02v": {"TABNAME": TAB, "DDLANGUAGE": "E", "TABCLASS": "TRANSP", "CLIDEP": "X",
                     "DDTEXT": "CTD: API Call Log", "CONTFLAG": "A", "MASTERLANG": "E", "EXCLASS": "1"},
           "dd03p": dd03p}
print(tools.ddic_write("TABL", TAB, payload, devclass=PKG, transport=TR, update=True)['message'])
print('activate table:', tools.ddic_activate("TABL", TAB)['result'])
print(tools.read_table('DD03L', ['FIELDNAME', 'ROLLNAME'], [f"TABNAME = '{TAB}' AND AS4LOCAL = 'A'"])['rows'])
print(tools.read_table('DD09L', ['AS4LOCAL', 'TABART', 'TABKAT', 'BUFALLOW'], [f"TABNAME = '{TAB}'"])['rows'])
print(tools.read_table('E071', ['TRKORR', 'OBJECT', 'OBJ_NAME'], [f"TRKORR = '{TR}' OR TRKORR = 'S4DK907432'"], max_rows=50)['rows'])
