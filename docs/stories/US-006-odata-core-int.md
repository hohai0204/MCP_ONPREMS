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
- 2026-09-25 (vendor dùng được để mua hàng): `ZCTD_FM_CREATE_BP` viết lại bằng `CL_MD_BP_MAINTAIN` (một lần lưu, lỗi -> ROLLBACK toàn bộ): BP + địa chỉ/điện thoại/e-mail + role FLVN00 và FLVN01 + company code (LFB1) + purchasing org (LFM1). TABLES mới `IT_COMPANY` (ZCTD_S_BP_COMPANY: BUKRS, AKONT, ZTERM, ZWELS, FDGRV, REPRF) và `IT_PURCHASING` (ZCTD_S_BP_PURCH: EKORG, WAERS, ZTERM, WEBRE, KALSK); không truyền -> 1000/1000; ô trống -> mặc định theo NCC nhóm Z001 ở 360 (AKONT 3311000001, ZTERM 1045, REPRF X, VND, WEBRE X). Logic chia FORM ở LZCTD_FG_COREF02, message tiếng Việt, gộp thông báo trùng. TR S4DK907429. TestRun client 100: mặc định OK, 2 công ty + 2 tổ chức mua OK; công ty 9999 / TK 1111111111 / tổ chức mua 9999 -> lỗi đúng; OData POST /VendorSet?TestRun=X 201. Chưa tạo vendor thật.
- 2026-09-25 (đổi vendor): `ZCTD_FM_CREATE_BP` thêm `IV_SUPPLIER` (upsert) - mã NCC đã có -> cập nhật bằng CL_MD_BP_MAINTAIN task U: chỉ đổi ô được truyền (tên, từ khóa, ngôn ngữ, địa chỉ chuẩn, điện thoại/e-mail mặc định theo CONSNUMBER), công ty / tổ chức mua đã có -> U, chưa có -> I với mặc định, role FLVN00/FLVN01 thiếu -> thêm, NCC chưa có LFB1/LFM1 và không truyền -> mở 1000/1000. FORM bp_read_existing / bp_build_change (LZCTD_FG_COREF02), TR S4DK907429. OData: VendorSet updatable (SEGW_UPDATE, TR S4DK907434), `PUT /VendorSet('x')` (VENDORSET_UPDATE_ENTITY) và `POST` có Supplier -> cập nhật. Test client 100 TestRun: FM đổi tên+ĐT / thêm 2000+4000 / không truyền / mã sai -> lỗi / AKONT sai -> lỗi SAP; OData PUT 204, POST có Supplier 201, PUT mã sai 400, POST tạo mới 201, GET 200; log đủ. Proxy Postman hỗ trợ PUT (client 100). Chưa lưu thật.
- 2026-09-25 (lưu thật, client 360, theo yêu cầu): `POST /VendorSet {"Supplier":"115817"}` - TestRun 201 rồi lưu 201. Trước: role FLVN00, không LFB1/LFM1. Sau: role FLVN00+FLVN01, LFB1 1000 (AKONT 3311000001, ZTERM 1045, REPRF X), LFM1 1000 (VND, WEBRE X). Kiểm chứng BAPI_PO_CREATE1 TESTRUN (ZP01, org 1000, vật tư 1000 plant 1100): vendor EE50000135 (không LFM1) báo 06 027 "not created for purchasing organization 1000"; vendor 115817 không còn lỗi vendor (chỉ còn FI 311 thiếu commitment item của dòng mẫu). Sửa khoảng trắng thừa trong message kết quả.
- 2026-09-26 (kiểm tra trùng khi tạo): `ZCTD_S_BP_SUPPLIER` thêm `TAXNUMBER` (BPTAXNUM, TR S4DK907429); tạo mới ghi mã số thuế loại VN0 (loại vendor trong nước đang dùng ở 360) và chặn nếu trùng mã số thuế (DFKKBPTAXNUM mọi loại + LFA1-STCEG/STCD1) -> ZMC_CTD 110, hoặc trùng tên NCC khác (UPPER(BUT000-NAME_ORG1), chỉ BP là NCC) -> 111. Đổi: NCC chưa có MST -> thêm (kiểm tra trùng), đã có MST khác -> 112. API POST map TaxNumber1 (hoặc VATNumber). Test: client 100 trùng tên hoa/thường -> 111, mới + MST -> TestRun OK; client 360 TestRun: trùng MST DFKKBPTAXNUM / LFA1-STCEG -> 110, trùng tên 115817 -> 111, đổi thêm MST mới OK / trùng -> 110 / khác MST hiện có -> 112 / giống -> OK; OData POST trùng tên 400, mới + MST 201.
- 2026-09-26: tạo mới bắt buộc mã số thuế (ZMC_CTD 113, cùng 070 tên / 071 quốc gia); trùng tên -> cảnh báo W 111 vẫn tạo (không cảnh báo khi đã bị chặn vì trùng MST); trùng MST -> E 110 chặn. Đổi vendor không bắt buộc MST. OData POST thiếu MST -> 400. Postman body tạo vendor có TaxNumber1.
- 2026-09-26: định dạng mã số thuế chỉ gồm số hoặc số-số (regex ^\d+(-\d+)?$, không giới hạn độ dài, bỏ khoảng trắng hai đầu) - sai -> ZMC_CTD 114; áp dụng tạo mới và đổi. Test: 0312345671 / 0312345671-001 / có khoảng trắng hai đầu OK; 0312-345-678, ABC123, '0312 345', -123, 123-, 0312345678_1, MST-ABC -> 114.
- 2026-09-26: GET VendorSet TaxNumber1 = mã số thuế BP (DFKKBPTAXNUM, VN0), không có thì STCEG rồi STCD1; lọc TaxNumber1 tìm trên mã số thuế BP (mọi loại) + STCEG + STCD1 (FORM vendor_by_taxnumber). TaxNumber1 nới lên 20 ký tự (DE BPTAXNUM), model generate lại (TR S4DK907434). Test 360: 100013 -> 0400394655, 100014 -> 010626264; eq '0400394655' -> 1 dòng (trước 0); eq '9999999999' -> 0; startswith '04' -> 827; startswith '0' -> 12174, substringof '1' -> 13413 (không lỗi).
- 2026-09-26: Postman thêm 3 request lọc TaxNumber1 (eq, startswith, tham số URL nhiều giá trị), đã chạy thử trên 360: eq '0400394655' -> 100013; startswith '0400' -> 234; TaxNumber1=0400394655,010626264 -> 100013 + 100014. Sửa mô tả bị lặp ở request 'Tạo vendor - lưu thật'.
- 2026-09-28: CREATE_BP kiểm tra quyền trước mọi bước (tạo mới + đổi, cả TestRun): F_LFA1_GRP (nhóm TK: tạo theo TBC001 của nhóm BP, đổi theo LFA1-KTOKK), B_BUPA_RLT (FLVN00/FLVN01), F_LFA1_BUK (từng công ty), M_LFM1_EKO (từng tổ chức mua); ACTVT 01 cho phần tạo/mở thêm, 02 cho phần đã có. Thiếu quyền -> ZMC_CTD 115/116/117/118, không lưu. Không dùng CL_MD_BP_MAINTAIN=>AUTHORITY_CHECK vì nó đòi S_TCODE XK01/XK02 (360: 6 role có XK01, 68 role dùng BP) và maintain() không tự kiểm tra quyền. Test 100 (user RFC đủ quyền): tạo mới / đổi 800000 TestRun -> S 074. Dự đoán bằng FM AUTHORITY_CHECK ở 360: 9 user đang tạo/sửa NCC qua đủ 9 kiểm tra; user tạo PR (QSA*) thiếu nhóm TK / vai trò BP / tổ chức mua (chỉ có công ty 1000), 1 user QSA177 đủ. Chưa chạy thật ca thiếu quyền (cần user test không có quyền).
- 2026-09-28: theo yêu cầu, bỏ kiểm tra quyền xem ở INT_VENDOR_GET (revert b0c83c2, deploy lại TOP/F02/U01, pool Syntax OK). Test 360: VendorSet('100013') 200, tổng 18115. Message 096/097 đã ghi vào ZMC_CTD trên SAP nhưng không còn dùng. Kiểm tra quyền tạo/sửa (CREATE_BP, 115-118) vẫn giữ.
