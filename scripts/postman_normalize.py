"""Chuẩn hóa Postman collection (v2.1): URL chỉ có "raw" -> đủ host/path/query
để mọi bản Postman hiển thị URL + tab Params sau khi import.

    python scripts/postman_normalize.py odata/*.postman_collection.json
"""
import json
import sys
import uuid


def split_url(raw: str) -> dict:
    path_part, _, query = raw.partition("?")
    host, _, path = path_part.partition("/")          # host = "{{baseUrl}}"
    url = {"raw": raw, "host": [host], "path": [p for p in path.split("/") if p]}
    if query:
        url["query"] = [{"key": k, "value": v} for k, _, v in (q.partition("=") for q in query.split("&"))]
    return url


def walk(items):
    for item in items:
        if "item" in item:
            walk(item["item"])
        req = item.get("request")
        if not req:
            continue
        url = req.get("url")
        raw = url if isinstance(url, str) else (url or {}).get("raw", "")
        req["url"] = split_url(raw)
        desc = req.get("description")
        if isinstance(desc, str) and not desc:
            req.pop("description")


for path in sys.argv[1:]:
    data = json.load(open(path, encoding="utf-8"))
    data["info"].setdefault("_postman_id", str(uuid.uuid4()))
    walk(data["item"])
    json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("normalized", path)
