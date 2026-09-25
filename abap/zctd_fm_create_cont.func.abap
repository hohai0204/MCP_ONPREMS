FUNCTION ZCTD_FM_CREATE_CONT.
*"--------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IS_HEADER) TYPE  ZTB_CONT_HEADER
*"     VALUE(IV_ZBUDG) TYPE  ZDE_SIGNBUDG_PLAN_NO OPTIONAL
*"     VALUE(IS_VENDOR_ADDR) TYPE  ADDR1_DIA OPTIONAL
*"     VALUE(IV_TESTRUN) TYPE  XFELD DEFAULT SPACE
*"  EXPORTING
*"     VALUE(EV_EBELN) TYPE  EBELN
*"     VALUE(ES_HEADER) TYPE  ZTB_CONT_HEADER
*"     VALUE(ET_RETURN) TYPE  BAPIRET2_T
*"  TABLES
*"      IT_ITEM STRUCTURE  ZTB_CONT_ITEM
*"      IT_PARTNER STRUCTURE  ZTB_CONT_HEADER1 OPTIONAL
*"      IT_COND STRUCTURE  ZTB_COND_ITEM OPTIONAL
*"--------------------------------------------------------------------
* Tạo hợp đồng ZCONT + đơn mua hàng không qua màn hình, cùng luồng với
* chương trình ZCCM_PG_ZCONT_NEW, T-code ZCONT1 (chế độ tạo mới).
* Các bước nằm trong include LZCTD_FG_COREF01:
*   A. Kiểm tra đầu vào       (CHECK_PARAMETER/CHECK_INPUT/CHECK_AUTHORITY)
*   B. Điền giá trị mặc định  (DATA_HEADER_DISPLAY/GET_ITEM/CALCULATE_CONDITION)
*   C. Kiểm tra trước khi lưu (CHECK_PLHD_SAVE/CHECK_SAVE)
*   D. Lưu chứng từ           (POST_PO/UPDATE_PO_ZCONT/SAVE_TABLE_ZCONT)
* Mã nhập ở dạng nội bộ (NCC/vật tư có số 0 đầu, dự án/WBS không dấu).
* IT_COND: STTIT rỗng = điều kiện header (tab Condition), có STTIT =
*          điều kiện bổ sung của dòng.
* ET_RETURN: PARAMETER/ROW/FIELD chỉ ra tham số, số dòng (STTIT) và
*            trường gây lỗi.
* IV_TESTRUN = 'X': chạy toàn bộ kiểm tra + BAPI ở chế độ test, không lưu.

  DATA: ls_doc   TYPE gty_cont_doc,
        lv_ebeln TYPE ebeln.

  CLEAR: ev_ebeln, es_header, et_return.

  PERFORM cont_init USING is_header iv_zbudg is_vendor_addr
                          it_item[] it_partner[] it_cond[]
                    CHANGING ls_doc.

* A. Kiểm tra đầu vào - dừng ở lỗi đầu tiên như màn hình chọn ZCONT1
  PERFORM cont_check_selection CHANGING ls_doc et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

* B. Điền giá trị mặc định như màn hình ZCONT
  PERFORM cont_read_pricing_steps CHANGING ls_doc.
  PERFORM cont_default_header     CHANGING ls_doc.
  PERFORM cont_default_partner    CHANGING ls_doc.
  PERFORM cont_default_items      CHANGING ls_doc et_return.
  PERFORM cont_build_conditions   CHANGING ls_doc et_return.
  PERFORM cont_read_check_data    CHANGING ls_doc.

* C. Kiểm tra trước khi lưu - gom tất cả lỗi
  PERFORM cont_check_header      CHANGING ls_doc et_return.
  PERFORM cont_check_items       USING ls_doc CHANGING et_return.
  PERFORM cont_check_amount      USING ls_doc CHANGING et_return.
  PERFORM cont_check_header_cond USING ls_doc CHANGING et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

* D. Lưu chứng từ
  PERFORM cont_prepare_header CHANGING ls_doc.
  PERFORM cont_post_po USING ls_doc iv_testrun CHANGING lv_ebeln et_return.
  IF line_exists( et_return[ type = 'E' ] ) OR line_exists( et_return[ type = 'A' ] ).
    RETURN.
  ENDIF.
  IF iv_testrun = abap_true.
    es_header = ls_doc-head.
    RETURN.
  ENDIF.

  ls_doc-head-ebeln = lv_ebeln.
  PERFORM cont_update_ekko_texts USING ls_doc CHANGING et_return.
  PERFORM cont_save_tables       CHANGING ls_doc et_return.

  ev_ebeln  = lv_ebeln.
  es_header = ls_doc-head.
ENDFUNCTION.
