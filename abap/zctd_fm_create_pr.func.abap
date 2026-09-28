* Tạo / sửa yêu cầu mua hàng (PR) dự án loại ZPR1 bằng BAPI_PR_CREATE /
* BAPI_PR_CHANGE (quyền và kiểm tra chuẩn / tùy biến của SAP do BAPI chạy).
* IV_PREQ_NO trống -> TẠO MỚI: mỗi dòng bắt buộc vật tư, số lượng > 0, ngày
*   giao, nhà máy, WBS; gán dự án (P), TK mặc định 6211000001; dòng chưa có
*   số -> 10, 20, ...
* IV_PREQ_NO có giá trị -> SỬA PR đó (phải là ZPR1):
*   - PREQ_ITEM là dòng đã có: chỉ đổi các ô được truyền (số lượng, ngày
*     giao, giá, kho, nhóm mua, người yêu cầu, tracking no, WBS, TK...);
*     DELETE_IND = 'X' đặt cờ xóa, RESTORE_IND = 'X' bỏ cờ xóa. Dòng đã đặt hàng
*     (có PO) -> lỗi, không sửa.
*   - PREQ_ITEM trống / chưa có -> THÊM dòng mới (bắt buộc như tạo mới).
* IV_TESTRUN = 'X': chạy mọi kiểm tra + BAPI ở chế độ thử rồi hủy, không lưu.
* Lỗi bất kỳ dòng nào -> không lưu gì. Các bước nằm trong LZCTD_FG_COREF03.

  DATA: lt_item    TYPE gty_t_pr_item,
        lt_exist   TYPE gty_t_pr_exist_item,
        lt_bitem   TYPE gty_t_pr_bapi_item,
        lt_bitmx   TYPE gty_t_pr_bapi_itemx,
        lt_bacc    TYPE gty_t_pr_bapi_acc,
        lt_baccx   TYPE gty_t_pr_bapi_accx,
        lt_bapiret TYPE bapiret2_t,
        lv_banfn   TYPE banfn,
        lv_new     TYPE abap_bool.

  CLEAR: ev_preq_no, et_return.

  lt_item = it_item[].
  IF lt_item IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '120' ) type = 'E' parameter = 'IT_ITEM' ) TO et_return.
    RETURN.
  ENDIF.

  DATA(lv_change) = xsdbool( iv_preq_no IS NOT INITIAL ).
  IF lv_change = abap_true.
    lv_banfn = |{ iv_preq_no ALPHA = IN }|.
    PERFORM pr_read_existing USING lv_banfn CHANGING lt_exist et_return.
    IF et_return IS NOT INITIAL.
      RETURN.
    ENDIF.
  ENDIF.

  PERFORM pr_prepare_items USING lt_exist CHANGING lt_item.
  PERFORM pr_check_items USING lt_item lt_exist CHANGING et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  LOOP AT lt_item INTO DATA(ls_item).
    lv_new = xsdbool( NOT line_exists( lt_exist[ bnfpo = ls_item-preq_item ] ) ).
    PERFORM pr_build_item USING ls_item lv_new
                          CHANGING lt_bitem lt_bitmx lt_bacc lt_baccx.
  ENDLOOP.

  IF lv_change = abap_false.
    CALL FUNCTION 'BAPI_PR_CREATE'
      EXPORTING
        prheader   = VALUE bapimereqheader( pr_type = gc_pr_type )
        prheaderx  = VALUE bapimereqheaderx( pr_type = abap_true )
        testrun    = iv_testrun
      IMPORTING
        number     = lv_banfn
      TABLES
        return     = lt_bapiret
        pritem     = lt_bitem
        pritemx    = lt_bitmx
        praccount  = lt_bacc
        praccountx = lt_baccx.
  ELSE.
    CALL FUNCTION 'BAPI_PR_CHANGE'
      EXPORTING
        number     = lv_banfn
        testrun    = iv_testrun
      TABLES
        return     = lt_bapiret
        pritem     = lt_bitem
        pritemx    = lt_bitmx
        praccount  = lt_bacc
        praccountx = lt_baccx.
  ENDIF.

  PERFORM pr_finish USING lt_bapiret iv_testrun lv_change lv_banfn CHANGING et_return.
  IF iv_testrun IS INITIAL AND NOT line_exists( et_return[ type = 'E' ] ).
    ev_preq_no = lv_banfn.
  ENDIF.
