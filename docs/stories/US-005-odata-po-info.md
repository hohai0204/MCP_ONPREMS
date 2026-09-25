# US-005 OData ZCTD_PO_INFO_SRV – thông tin PO header/item (SEGW)

## Status

changed

## Lane

normal

## Product Contract

OData V2 service `ZCTD_PO_INFO_SRV` (SEGW project `ZCTD_PO_INFO`, $TMP, client 100)
trả thông tin PO dạng header/item tương tự JSON gửi portal của ZPOST_PO
(`ZPG_MASTER_POST_PO_WBS`). Envelope responseStatus/correlationId theo chuẩn OData
(HTTP status + error body Gateway).

- `GET /POHeaderSet?$expand=Detail` – không lọc: PO mới nhất (mặc định $top 100, tối đa 1000), header kèm thẻ Detail
- `GET /POHeaderSet?$filter=<PONumber|POType|VendorCode|DocumentDate|ContractNo|ProjectCode> ...&$expand=Detail&$top=&$skip=&$inlinecount=allpages`
- `GET /POHeaderSet('4100035733')?$expand=Detail`
- `GET /POHeaderSet('…')/Detail`, `GET /POItemSet(PONumber='…',Item='00010')`

## Objects ($TMP)

| Object | Vai trò |
| --- | --- |
| `ZCTD_S_PO_INFO_HDR` / `ZCTD_S_PO_INFO_ITM` | cấu trúc header/item |
| FG `ZCTD_FG_PO_INFO`, FM `ZCTD_FM_GET_PO_INFO` (RFC) | đọc dữ liệu (nguồn như ZPOST_PO) |
| `odata/ZCTD_PO_INFO.edmx` | model import vào SEGW |
| SEGW `ZCTD_PO_INFO` (IWPR), `ZCL_ZCTD_PO_INFO_MPC(_EXT)` / `_DPC(_EXT)`, IWMO `ZCTD_PO_INFO_MDL`, IWSV `ZCTD_PO_INFO_SRV` | service; DPC_EXT redefine 4 method GET, gọi FM |
| FM tiện ích ($TMP, FG `ZCTD_FG_PO_INFO`): `ZCTD_FM_SEGW_BUILD`, `ZCTD_FM_GW_ACTIVATE`, `ZCTD_FM_CLASS_REDEFINE`, `ZCTD_FM_GW_TEST` | tạo SEGW project từ EDMX + generate; kích hoạt Gateway; ghi DPC_EXT; gọi thử OData nội bộ |

## Mapping notes

- Subtotal/Total theo ZTB_CONT_HEADER ZZGTHD/TGTHD (như ZPOST_PO), không có HĐ ZCONT thì theo EKPO-NETWR + MWST (PRCD_ELEMENTS). Tax = Total − Subtotal. Số tiền = số thực (VND ×100 so với lưu nội bộ).
- Item: EKPO + EKKN(01) + PRPS + BOMG + ZTB_CONT_ITEM; bỏ dòng REPOS và WEBRE trống (như ZPOST_PO); ZP08 gửi thiết bị thay vật tư.
- Status từ EKKO-PROCSTAT (CLOSED/DELETED nếu mọi dòng hoàn tất/xóa); ReleaseStatus từ FRGGR/FRGRL; ChangedAt = EKKO-LASTCHANGEDATETIME (UTC); SourceVersion = thời điểm + số change document.
- Khác ZPOST_PO: EKKN/PRPS dùng LEFT JOIN (không bỏ dòng thiếu WBS), bỏ join PRPS cấp 1 theo 10 ký tự.

## Evidence

- 2026-09-23: DDIC + FG + FM tạo trên S4D/100 ($TMP, TADIR bổ sung qua SIW_RFC_WRITE_TADIR); FM đọc thử dữ liệu thật S4D/360: PO 4800003749 Subtotal 107.960.000 / Tax 10.796.000 / Total 118.756.000 (khớp ZZGTHD/TGTHD ×100), VAT 10%; PO không tồn tại → "Không tìm thấy đơn mua hàng …".

- 2026-09-24: SEGW project tạo không qua GUI bằng `ZCTD_FM_SEGW_BUILD` (theo trình tự Service Builder: create_project → file_parsing/adapt_odata_artifacts → save → CL_SB_GEN_GENERATOR suppress dialog, package $TMP): sinh MPC/MPC_EXT/DPC/DPC_EXT, đăng ký model + service backend. Frontend: `/IWFND/CL_MGW_ACTIVATION_API->ACTIVATE_SERVICE` (alias LOCAL, $TMP), ICF node active. DPC_EXT ghi bằng SEO_CLASS_CREATE_COMPLETE (4 redefinition), class pool syntax OK, không object inactive. TADIR IWPR bổ sung.
- Test end-to-end qua Gateway client nội bộ (`/IWFND/CL_SUTIL_CLIENT_PROXY`, như /IWFND/GW_CLIENT) trên client 100: `$metadata` 200; `POHeaderSet('4400000000')?$expand=Detail` 200; `$filter=PONumber eq` 200; `/Detail` 200; `POItemSet(PONumber,Item)` 200; PO không tồn tại 404 "Không tìm thấy đơn mua hàng …"; thiếu filter 400; item không tồn tại 404.
- Client 360 chưa kích hoạt frontend (cấu hình /IWFND là client-dependent); dữ liệu nghiệp vụ thật chỉ có ở 360.
- 2026-09-24 (lọc tùy chọn + Detail): FM `ZCTD_FM_FIND_PO` (RFC, lọc trên EKKO/ZTB_CONT_HEADER, phân trang DB, tổng số); DPC_EXT có local class `lcl_po` + redefine GET_EXPANDED_ENTITY/ENTITYSET (mỗi PO đọc 1 lần, Detail inline). Test 360 (FIND_PO): không lọc total 74.850; POType/Vendor/DocumentDate BT + skip/top/ContractNo/ProjectCode đúng. Test OData client 100: POHeaderSet không lọc 200; ?$expand=Detail&$inlinecount 200 (__count, Detail.results); $filter=POType eq … 200; lọc thuộc tính không hỗ trợ 400; POItemSet không lọc 200.
- Lưu ý OData V2: không có $expand=Detail thì Detail trả dạng __deferred (link) theo chuẩn.
- 2026-09-24 (JSON đúng mẫu portal): entity media `POJson` (m:HasStream) thêm vào model qua `ZCTD_FM_SEGW_UPDATE` (re-import EDMX + generate lại, *_EXT giữ nguyên). DPC_EXT redefine `GET_STREAM` + `POJSONSET_GET_ENTITY`; `lcl_po=>build_json` dựng `responseStatus/responseMessage/correlationId/data`, Detail lồng trong header, số là số, đúng thứ tự/tên field của mẫu.
  - `GET /POJsonSet('<PO>')/$value` → data object; `GET /POJsonSet('ALL')/$value[?POType=&VendorCode=&DocumentDate=&DocumentDateFrom=&DocumentDateTo=&ContractNo=&ProjectCode=&PONumber=&top=&skip=]` → data mảng (mặc định 100 PO mới nhất).
  - Test client 100: 1 PO 200 JSON đúng mẫu; ALL 200 mảng; lọc POType+DocumentDateFrom+top 200; lọc không có kết quả → data []; PO không tồn tại → responseStatus E, data null. Endpoint OData cũ vẫn 200/400 như trước.
  - Lưu ý: sau khi đổi model cần gọi $metadata (hoặc /IWFND/CACHE_CLEANUP) để Gateway hub nạp lại metadata.
- 2026-09-24 (fix 501 /POJsonSet): thêm POJSONSET_GET_ENTITYSET (feed 'ALL' + các PO, mỗi entry có media_src tới /$value); media entity cần property content type → thêm MimeType vào POJson, MPC_EXT redefine DEFINE set_as_content_type (trước đó /POJsonSet trả 500 'Invalid or no mapping to system data types found'). ZCTD_FM_CLASS_REDEFINE dò chuỗi kế thừa cho method khai báo ở lớp cao hơn (SEOREDEF theo mẫu SE24: REFCLSNAME = lớp cha trực tiếp, EXPOSURE 0). Test: /POJsonSet 200 (atom/json), /$value 200 JSON đúng mẫu, endpoint cũ 200.
- 2026-09-24: bỏ quy tắc lọc dòng REPOS/WEBRE trống (chép từ ZPOST_PO) trong ZCTD_FM_GET_PO_INFO — PO 4100032903 (360) có 1 dòng không nhận hóa đơn làm Detail rỗng; nay trả đủ dòng.
- 2026-09-24: lọc nhiều PO qua POJsonSet('ALL')/$value — hỗ trợ giá trị phân cách dấu phẩy (POType=ZP05,ZP06; PONumber=a,b); FM GET_PO_INFO chỉ chuyển sang ELBAN khi số PO không có trong EKKO (trước đó PO 4100035139 ZP01 bị thay bằng 4500007330 ZP05 làm sai kết quả lọc POType). Test 360 qua scripts/gw_local_proxy.py: ngày, loại, loại+ngày, nhiều loại, nhiều số PO, phân trang đều đúng.
- 2026-09-24: thêm lọc MinItems (PO có ≥ N dòng chưa xóa) — ZCTD_FM_FIND_PO thêm IV_MIN_ITEMS (subquery EKPO GROUP BY/HAVING, đổi interface qua SIW_RFC_WRITE_FUNC); test 360: MinItems=2/10, ZP01+MinItems=5+tháng 8, phân trang đều đúng.
- 2026-09-24: JSON POJsonSet có đủ field entity: header thêm WBSCode (sau ProjectName), Note (sau SourceVersion); Detail thêm WBSName, BOMG, BOMGName (sau WBS), Brand (sau Description). Test 360 PO 4800003749 + ALL MinItems=3. Excel ZCTD_PO_INFO_API.xlsx cập nhật.
- 2026-09-24 (log gọi API): bảng `ZCTD_T_API_LOG` ($TMP, client-dependent, APPL1, không buffer) key `MANDT + CORR_ID + CALL_DATE + CALL_TIME`; cột CALL_TSTMP (UTC, ms), OBJECT_TYPE (entity set), HTTP_METHOD, API_URL, DURATION_MS, CALL_USER, HTTP_STATUS, RESP_STATUS (S/E), MESSAGE, REQUEST (JSON: key + tham số URL + header, bỏ authorization/cookie/x-csrf-token), RESPONSE (JSON trả ra đầy đủ). FM (FG `ZCTD_FG_PO_INFO`, RFC): `ZCTD_FM_API_LOG_WRITE` (INSERT + COMMIT qua kết nối DB phụ `R/3*ZCTD_API_LOG`, không ném lỗi), `ZCTD_FM_API_LOG_READ` (lọc correlationId/ngày/object/user, trả JSON vì bảng có cột STRING). DPC_EXT: `GET_STREAM` đo thời gian, `build_json` trả thêm status/message/correlationId, `lcl_po=>write_log`. Phạm vi: chỉ `POJsonSet(...)/$value` (endpoint có correlationId).
  - Test client 100 qua GW client: PO 4400000000 → log S 13 ms; ALL POType=ZP04 top=2 → log S, parameters đúng; PO 9999999999 → log E "Không tìm thấy đơn mua hàng 9999999999."; corr_id trong log = correlationId trong response. POHeaderSet / POJsonSet (feed) vẫn 200.
- 2026-09-24 (đưa log vào package): TR `S4DK907431` "<user>/24.09.2026/Create Log API CTD Core" (task `S4DK907432`), package `ZCTD_CORE`: `R3TR TABL ZCTD_T_API_LOG` (TADIR đổi từ $TMP, ghi TR qua ddic_write UPDATE) + `R3TR FUGR ZCTD_FG_API_LOG` (FG mới) chứa `ZCTD_FM_API_LOG_WRITE` / `ZCTD_FM_API_LOG_READ` (xóa khỏi ZCTD_FG_PO_INFO, tạo lại bằng RPY_FUNCTIONMODULE_INSERT CORRNUM). Không dùng ZCTD_FG_CORE vì FG đó đang khóa trong TR chưa release S4DK907429. Ở lại $TMP: DPC_EXT/SEGW service. Test lại: POJsonSet 200, log đọc lại theo correlationId OK.
- 2026-09-24: `ZMCP_ADT_DDIC_TABL` (FG ZMCP_ADT_UTILS, TR S4DK907427/task S4DK907428) ghi luôn technical settings cho bảng TRANSP (payload `dd09v` tùy chọn; mặc định APPL1/0/không buffer cho bảng mới, giữ nguyên khi update không truyền) → gỡ FM phụ `ZCTD_FM_DDIC_TABT`. Test bảng tạm $TMP: tạo+kích hoạt không cần FM phụ, dd09v tường minh áp dụng, update không dd09v giữ nguyên, xóa sạch.
- 2026-09-24: nhãn field log tường minh — 14 data element `ZCTD_DE_API_*` (cùng domain với data element chung cũ, không đổi kiểu → không chuyển đổi dữ liệu), mô tả bảng 'CTD: API Call Log'; ghi vào TR S4DK907431, package ZCTD_CORE. Dữ liệu log cũ còn nguyên, API vẫn ghi log, FG ZCTD_FG_API_LOG syntax OK.
