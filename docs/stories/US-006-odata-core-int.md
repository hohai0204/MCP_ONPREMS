# US-006 OData ZCTD_CORE_INT_SRV – luồng tích hợp CTD Core

## Status

changed

## Lane

normal

## Product Contract

Một OData V2 service chung cho các tích hợp của CTD Core, mỗi đối tượng là entity
set riêng (OData chuẩn, response `d/results`). Mọi lần gọi ghi log vào
`ZCTD_T_API_LOG` và trả header `correlation-id`.

- Vendor: `GET /VendorSet` (lọc Supplier, Name1, SearchTerm, Country, AccountGroup,
  TaxNumber1, VATNumber, CreatedOn, PostingBlock, DeletionFlag; `$top/$skip/$inlinecount`),
  `GET /VendorSet('<Supplier>')`, `POST /VendorSet[?TestRun=X]` (tạo BP role FLVN00 +
  nhà cung cấp qua `ZCTD_FM_CREATE_BP`, bắt buộc Name1 + Country; message ở header `sap-message`).
- Purchase Requisition (EBAN): `GET /PurchaseReqSet` (lọc PRNumber, PRType, Plant,
  PurchasingGroup, PurchasingOrg, Material, CreatedOn, RequestDate, ReleaseIndicator,
  Requisitioner, TrackingNo), `GET /PurchaseReqSet('<PR>')`, `$expand=Items`,
  `/PurchaseReqSet('<PR>')/Items`, `GET /PurchaseReqItemSet(PRNumber=,Item=)`.
- Quy tắc PR (mới, không chép từ chương trình khác): lọc áp trên dòng, PR thỏa khi có ≥1
  dòng thỏa và trả đủ các dòng; header lấy từ dòng đầu; TotalValue chỉ cộng dòng chưa xóa;
  số tiền đổi sang số thực theo số lẻ tiền tệ (VND ×100); đơn vị/vật tư/WBS dạng hiển thị.
- Ngày dạng chuỗi `YYYYMMDD` (cùng quy ước ZCTD_PO_INFO_SRV).
- Ngoài `$filter`, mọi GET danh sách nhận tham số URL tùy biến làm điều kiện lọc (`?Plant=1100&Material=A,B`, `*` = mẫu) – bắt buộc cho field của dòng khi đọc `PurchaseReqSet` (OData không cho `$filter` theo property không có trong entity).

## Mở rộng cho đối tượng mới

1. Thêm entity vào `odata/core_int/build_edmx.py` → `ZCTD_FM_SEGW_UPDATE` với `IV_TRANSPORT`.
2. Structure `ZCTD_S_INT_<OBJ>` (`odata/abap/zctd_core_int_ddic.py`) + FM
   `ZCTD_FM_INT_<OBJ>_GET` trong FG `ZCTD_FG_CORE_INT`, cùng interface
   `IV_TOP / IV_SKIP / IT_FILTER (ZCTD_S_INT_FILTER) → EV_TOTAL / ET_RETURN + TABLES dữ liệu`;
   form dùng chung `check_filter` / `filter_range` / `get_top` / `currency_factor` (F01).
3. Local class `lcl_<obj>` + redefine `<SET>_GET_ENTITY(SET)` trong DPC_EXT theo mẫu
   `lcl_vendor` (log qua `lcl_api`), ghi bằng `ZCTD_FM_CLASS_REDEFINE` với `IV_TRANSPORT`.

## Objects (package ZCTD_CORE)

| Object | Vai trò |
| --- | --- |
| SEGW `ZCTD_CORE_INT` (IWPR), `ZCL_ZCTD_CORE_INT_MPC(_EXT)` / `_DPC(_EXT)`, IWMO `ZCTD_CORE_INT_MDL`, IWSV/IWSG `ZCTD_CORE_INT_SRV`, IWOM, SICF | service |
| FG `ZCTD_FG_CORE_INT`: `ZCTD_FM_INT_VENDOR_GET`, `ZCTD_FM_INT_PR_GET` (RFC), include F01 (chung) / F02 (vendor) / F03 (PR) | đọc dữ liệu |
| `ZCTD_S_INT_FILTER`, `ZCTD_S_INT_VENDOR`, `ZCTD_S_INT_PR_HDR`, `ZCTD_S_INT_PR_ITM` | structure |
| `ZCTD_FM_CREATE_BP` (FG ZCTD_FG_CORE, có sẵn) | tạo vendor |
| TR | workbench `S4DK907434` (task `S4DK907435`); customizing `S4DK907436` (`/IWFND/C_MGDEAM` gán system alias client 100) |

Source: `odata/core_int/`, `odata/ZCTD_CORE_INT.edmx`, `odata/ZCTD_CORE_INT.postman_collection.json`.

## Evidence

- 2026-09-25: FM đọc test với dữ liệu thật client 360: vendor không lọc 18.115, Supplier/Country/Name CP/CreatedOn BT/skip đúng, lọc Email → báo chưa hỗ trợ; PR không lọc 14.238, PRNumber/header-only đúng, PR 3100003115 giá 52.727,27 nội bộ → 5.272.727 VND.
- SEGW headless vào package thật: helper FM (FG ZCTD_FG_PO_INFO, $TMP) thêm `IV_TRANSPORT` (SEGW_BUILD/UPDATE, CLASS_REDEFINE) và `IV_TRANSPORT(_CUST)` (GW_ACTIVATE); đăng ký trước TADIR+TR cho IWPR/CLAS×4/IWMO/IWSV (TR_TADIR_INTERFACE + TR_RECORD_OBJ_CHANGE_TO_REQ) – nếu không generator bật dynpro SAPLSTRD 0300. Generate OK, service kích hoạt client 100, `$metadata` 200.
- Test OData client 100 (GW client): VendorSet top/inlinecount 200, key 200, key không tồn tại 404, filter Country 200, filter Email 400, PurchaseReqSet/expand/ItemSet 200 (client 100 không có PR), PR không tồn tại 404, POST TestRun 201 ("Test run OK - nothing saved"), POST thiếu Country 400. Mọi lần gọi có dòng log (URL, request JSON, status, thời gian).
- `ZCTD_FM_GW_TEST` thêm `IV_METHOD`/`IV_BODY` (POST có CSRF); `scripts/gw_local_proxy.py` hỗ trợ POST (chỉ client 100).
- 2026-09-25: gán system alias LOCAL cho `ZCTD_CORE_INT_SRV_0001` ở client 360 (user yêu cầu) bằng `ZCTD_FM_GW_ACTIVATE` (bổ sung: service đã active mà client chưa có alias thì gọi `/IWFND/CL_COF_FACADE=>ASSIGN_SYS_ALIAS_TO_SRV`); client 360 không ghi TR. Test 360 dữ liệu thật: VendorSet count 18.115, key, substringof (URL mã hóa) 1.092; PR $expand, /Items có $top/$skip, ItemSet $filter Plant, tham số URL Material (nhiều giá trị), tham số không hỗ trợ → 400.
- Chưa làm (cần xác nhận): POST tạo vendor thật (chưa chạy để tránh tạo BP rác).
