"""Cầu nối cục bộ Postman -> SAP Gateway qua RFC (khi máy không có đường HTTP tới SAP).

    python scripts/gw_local_proxy.py            # nghe http://127.0.0.1:8765

Postman: http://localhost:8765/sap/opu/odata/sap/ZCTD_PO_INFO_SRV/POJsonSet('4100032903')/$value?sap-client=360

- GET cho mọi client; POST chỉ cho sap-client=100 (profile ghi) - ở 360 bị chặn
  vì sẽ tạo dữ liệu thật. Chỉ nghe trên 127.0.0.1.
- sap-client=100 -> profile s4d-100; sap-client=360 -> profile s4d-360 (profile read-only:
  cổng ghi chỉ mở trong tiến trình này để gọi FM đọc ZCTD_FM_GW_TEST, file profile không đổi).
- Request chạy bằng user RFC của profile (không dùng Basic Auth của Postman).
- Dùng FM ZCTD_FM_GW_TEST ($TMP) = Gateway client nội bộ (/IWFND/GW_CLIENT).
"""
from __future__ import annotations

import os
import subprocess
import sys
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qsl, urlencode

HOST, PORT = "127.0.0.1", 8765
MCP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mcp")
PROFILES = {"100": "s4d-100", "360": "s4d-360"}

WORKER = r'''
import sys, json, os
profile, uri, method = sys.argv[1], sys.argv[2], sys.argv[3]
body = sys.stdin.buffer.read().decode("utf-8")
sys.argv = ["x", "--profile", profile]
sys.path.insert(0, os.environ["GW_MCP_DIR"])
from sap import tools
os.environ["SAP_ALLOW_WRITE"] = "true"   # để gọi FM ZCTD_FM_GW_TEST (POST chỉ được phép ở client 100)
r = tools.run_rfc("ZCTD_FM_GW_TEST", {"IV_URI": uri, "IV_METHOD": method, "IV_BODY": body})
out = {k: r.get(k) for k in ("EV_STATUS_CODE", "EV_STATUS_TEXT", "EV_CONTENT_TYPE", "EV_BODY", "EV_ERROR")}
sys.stdout.buffer.write(json.dumps(out, ensure_ascii=False).encode("utf-8"))
'''


def call_gateway(profile: str, uri: str, method: str = "GET", body: str = "") -> dict:
    env = dict(os.environ, GW_MCP_DIR=os.path.abspath(MCP_DIR), PYTHONIOENCODING="utf-8")
    p = subprocess.run([sys.executable, "-c", WORKER, profile, uri, method],
                       input=body.encode("utf-8"), capture_output=True, env=env, timeout=120)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode("utf-8", "replace")[-1500:])
    return json.loads(p.stdout.decode("utf-8"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._forward("GET")

    def do_POST(self):
        self._forward("POST")

    def _forward(self, method: str):
        parts = urlsplit(self.path)
        query = parse_qsl(parts.query, keep_blank_values=True)
        client = next((v for k, v in query if k.lower() == "sap-client"), "100")
        profile = PROFILES.get(client)
        if not profile:
            return self._send(400, "text/plain; charset=utf-8", f"sap-client {client} chưa cấu hình (dùng 100 hoặc 360)")
        if method != "GET" and client != "100":
            return self._send(405, "text/plain; charset=utf-8", "POST chỉ được phép với sap-client=100")
        body = ""
        if method != "GET":
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode("utf-8")
        rest = [(k, v) for k, v in query if k.lower() != "sap-client"]
        uri = parts.path + ("?" + urlencode(rest, safe="$'(),=") if rest else "")
        try:
            r = call_gateway(profile, uri, method, body)
        except Exception as exc:  # lỗi RFC / kết nối
            return self._send(502, "text/plain; charset=utf-8", f"Lỗi gọi SAP qua RFC: {exc}")
        body = r.get("EV_BODY") or r.get("EV_ERROR") or ""
        self._send(int(r.get("EV_STATUS_CODE") or 502), r.get("EV_CONTENT_TYPE") or "text/plain; charset=utf-8", body)
        print(f"{client} {method} {uri} -> {r.get('EV_STATUS_CODE')}", flush=True)

    def _refuse(self):
        self._send(405, "text/plain; charset=utf-8", "Cầu nối chỉ hỗ trợ GET và POST")

    do_PUT = do_PATCH = do_DELETE = do_MERGE = _refuse

    def _send(self, code: int, ctype: str, body: str):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"Gateway proxy: http://localhost:{PORT}/sap/opu/odata/sap/<SERVICE>/...?sap-client=100|360  (Ctrl+C để dừng)")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
