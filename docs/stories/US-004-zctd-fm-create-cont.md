# US-004 FM ZCTD_FM_CREATE_CONT – tạo chứng từ ZCONT → PO không qua màn hình

## Status

changed

## Lane

normal

## Product Contract

FM `ZCTD_FM_CREATE_CONT` (FG `ZCTD_FG_CORE`, remote-enabled) tạo một hợp đồng
ZCONT + PO (BAPI_PO_CREATE1) theo đúng luồng tạo mới (T-code ZCONT1, mode `01`)
của chương trình `ZCCM_PG_ZCONT_NEW`, với các validation của chương trình:

| Bước | Form gốc | Nội dung |
| --- | --- | --- |
| A | CHECK_PARAMETER / CHECK_INPUT / CHECK_AUTHORITY | trường bắt buộc, WBS thuộc Project, vendor LFM1, lock eConstruction, Contract No.Ref ZP05–07 đã có PO, Contract No.Ref có trong DMS, quyền ZAU_PRCTR |
| B | DATA_HEADER_DISPLAY / GET_ITEM / CALCULATE_CONDITION | mặc định header (bukrs, ekorg, werks/lgort, ekgrp 104, cuky, tỷ giá, zterm, part bank type), partner từ WYT3/DMS, quy đổi ĐVT, tolerance, CSI/BOMP, điều kiện PBXX/MWST/header + subtotal |
| C | CHECK_PLHD_SAVE / CHECK_SAVE | Signing/Budget plan, org data, project–company code, WBS level 1/4, plant, bank type, brand, BOMG (BOQ/BOMGL/xóa), CSI group, vật tư/plant/nhóm VT, subcontractor 8001, equipment ZP08, ĐVT đặt hàng, net price, giá trị so với Contract No.Ref, header condition KKOPF |
| D | SAVE_DATA_PO / POST_PO / UPDATE_PO_ZCONT / SAVE_TABLE_ZCONT | BAPI_PO_CREATE1 → commit → EKKO ZZHOPDONG/ZZPHULUC/ZZBVTYP + text F01–F99 → ZTB_CONT_HEADER/ITEM/HEADER1/COND_ITEM |

## Interface

- IMPORTING `IS_HEADER` (ZTB_CONT_HEADER), `IV_ZBUDG`, `IS_VENDOR_ADDR` (ADDR1_DIA, vendor Z007), `IV_TESTRUN`
- EXPORTING `EV_EBELN`, `ES_HEADER`, `ET_RETURN` (BAPIRET2_T)
- TABLES `IT_ITEM` (ZTB_CONT_ITEM), `IT_PARTNER` (ZTB_CONT_HEADER1, rỗng = lấy mặc định), `IT_COND` (ZTB_COND_ITEM: STTIT rỗng = header condition)

## Known differences vs. dialog

- Luồng phụ lục (PLHD, POST_PO_PL) và tạo với tham chiếu (PR/Quotation/BOMP/Pricelist/copy) không nằm trong phạm vi — trả lỗi như ZCONT1.
- Vendor Z007: địa chỉ lấy từ `IS_VENDOR_ADDR` (dialog lấy từ popup), bắt buộc NAME1.
- Lỗi được gom hết vào ET_RETURN (dialog chỉ hiện 1 message cuối).
- Tab NORM/BOQ/BOMP detail (ZTB_CONT_HEADER2/COMP/BOMP/MHTG/NORM) không ghi – dialog cũng để trống ở luồng này.

## Structure (refactor 2026-09-23)

- `LZCTD_FG_COREU02` – FM chỉ điều phối các bước A–D.
- `LZCTD_FG_COREF01` (mới, đã thêm INCLUDE vào `SAPLZCTD_FG_CORE`) – 48 FORM `cont_*`.
- `LZCTD_FG_CORETOP` – kiểu `gty_cont_doc` (chứng từ đang xử lý) và `gty_cont_bapi` (tham số BAPI).
- Message viết bằng tiếng Việt nghiệp vụ; tên tham số/field kỹ thuật nằm trong `BAPIRET2-PARAMETER/FIELD`, số dòng (STTIT) trong `ROW`.
- Sửa lỗi ở bản trước: đoạn đọc thuế suất MWST từ A905 đã xóa `lv_taxim` trước khi dùng (nên thuế luôn bằng 0).
- Source trong repo: `abap/zctd_fm_create_cont.func.abap`, `abap/lzctd_fg_coref01.abap`, `abap/lzctd_fg_coretop.abap`.

## Evidence

- 2026-09-23 refactor: syntax-check bản ghép TOP+FM+F01 OK trước khi ghi; ghi qua SIW_RFC_WRITE_REPORT; SAPLZCTD_FG_CORE syntax OK, không còn object inactive, interface FM không đổi; smoke RFC trả `Thiếu thông tin bắt buộc: Mã dự án, WBS hợp đồng, Nhà cung cấp.` và `WBS P00000001 không thuộc dự án P00000001.` (PARAMETER/FIELD = IS_HEADER/POSID).

- 2026-09-23: source port syntax-check OK (ZMCP_ADT_DISPATCH SYNTAX_CHECK), FM tạo bằng RPY_FUNCTIONMODULE_INSERT → include LZCTD_FG_COREU02, FMODE R, active; SAPLZCTD_FG_CORE syntax OK. Transport: FG nằm trong task S4DK907430 / request S4DK907429.
- Smoke RFC trên S4D/100 (IV_TESTRUN='X'): thiếu trường → `Fill out all required fields…`; WBS sai → `WBS Element … is not defined in Project Definition …`.
- 2026-09-23 test run thật trên S4D/360 (IV_TESTRUN='X', cổng ghi chỉ mở trong tiến trình test):
  1. ZP01 sao chép HĐ 4100035143 (11 dòng): qua toàn bộ kiểm tra, BAPI `MMPUR_BASE 054 Performed in Test Run`, ZZGTHD=TGTHD=1.766.400 khớp HĐ gốc tạo bằng ZCONT1.
  2. ZP05 dùng số HĐ tham chiếu của 4500007223: `Số HĐ tham chiếu … đã được dùng cho đơn mua hàng 4500007223…`.
  3. BOMG sai: `Dòng 110: BOMG 99.99.9999 không có trong danh sách BOMG đã duyệt (BOMGL) của WBS CN24-24.03.`
  Sau test: không có ZTB_CONT_HEADER / EKKO mới trong ngày.
  Cảnh báo BAPI `ME 887 Error transferring ExtensionIn data for enhancement CI_EKKODB` (W) — cùng cấu trúc ExtensionIn với chương trình gốc; ZZHOPDONG/ZZPHULUC/ZZBVTYP vẫn được ghi bằng UPDATE EKKO sau commit (như UPDATE_PO_ZCONT).

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | — |
| Integration | SE37 client 360, IV_TESTRUN='X' với hợp đồng mẫu → không có E, BAPI test OK |
| E2E | ZCONT3 hiển thị hợp đồng tạo bởi FM giống tạo bằng ZCONT1 |
| Platform | — |
| Release | human-owned |

## Harness Delta

Không.
