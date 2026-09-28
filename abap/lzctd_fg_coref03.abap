*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_COREF03.
*----------------------------------------------------------------------*
* Subroutine của ZCTD_FM_CREATE_PR - tạo / sửa yêu cầu mua hàng (PR) dự án
* loại ZPR1 bằng BAPI_PR_CREATE / BAPI_PR_CHANGE:
*   pr_read_existing  sửa: đọc PR đã có (loại, dòng, đã đặt hàng chưa)
*   pr_prepare_items  đổi mã vật tư / đơn vị sang dạng nội bộ, đánh số dòng mới
*   pr_check_items    kiểm tra từng dòng: dòng mới đủ dữ liệu bắt buộc, dòng
*                     đã đặt hàng không sửa, có thông tin để đổi
*   pr_build_item     dòng -> dữ liệu BAPI (dòng + gán dự án), chỉ ô được truyền
*   pr_finish         gom thông báo SAP, COMMIT / ROLLBACK, thông báo kết quả
*----------------------------------------------------------------------*

* Sửa: PR phải có và đúng loại ZPR1
FORM pr_read_existing USING    iv_banfn  TYPE banfn
                      CHANGING ct_exist  TYPE gty_t_pr_exist_item
                               ct_return TYPE bapiret2_t.
  CLEAR ct_exist.
  SELECT bnfpo, bsart, statu, bsmng, ebakz, loekz FROM eban
    WHERE banfn = @iv_banfn
    INTO TABLE @DATA(lt_eban).
  IF lt_eban IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '131' iv_v1 = |{ iv_banfn ALPHA = OUT }| )
                    type = 'E' parameter = 'IV_PREQ_NO' ) TO ct_return.
    RETURN.
  ENDIF.
  READ TABLE lt_eban INTO DATA(ls_first) INDEX 1.
  IF ls_first-bsart <> gc_pr_type.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '132' iv_v1 = |{ iv_banfn ALPHA = OUT }| iv_v2 = ls_first-bsart )
                    type = 'E' parameter = 'IV_PREQ_NO' ) TO ct_return.
    RETURN.
  ENDIF.
  ct_exist = CORRESPONDING #( lt_eban ).
ENDFORM.

* Mã vật tư / đơn vị -> dạng nội bộ; dòng chưa có số -> số tiếp theo (bước 10)
FORM pr_prepare_items USING    it_exist TYPE gty_t_pr_exist_item
                      CHANGING ct_item  TYPE gty_t_pr_item.
  DATA lv_last TYPE bnfpo.

  LOOP AT it_exist INTO DATA(ls_exist).
    lv_last = nmax( val1 = lv_last val2 = ls_exist-bnfpo ).
  ENDLOOP.
  LOOP AT ct_item ASSIGNING FIELD-SYMBOL(<ls_item>).
    IF <ls_item>-material IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input        = <ls_item>-material
        IMPORTING
          output       = <ls_item>-material
        EXCEPTIONS
          length_error = 1
          OTHERS       = 2.
      IF sy-subrc <> 0.
        <ls_item>-material = to_upper( <ls_item>-material ).
      ENDIF.
    ENDIF.
    IF <ls_item>-unit IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_CUNIT_INPUT'
        EXPORTING
          input          = <ls_item>-unit
          language       = sy-langu
        IMPORTING
          output         = <ls_item>-unit
        EXCEPTIONS
          unit_not_found = 1
          OTHERS         = 2.
      IF sy-subrc <> 0.
        <ls_item>-unit = to_upper( <ls_item>-unit ).
      ENDIF.
    ENDIF.
    lv_last = nmax( val1 = lv_last val2 = <ls_item>-preq_item ).
  ENDLOOP.
  LOOP AT ct_item ASSIGNING <ls_item> WHERE preq_item IS INITIAL.
    lv_last = lv_last + gc_pr_step.
    <ls_item>-preq_item = lv_last.
  ENDLOOP.
ENDFORM.

* Dòng mới: đủ vật tư, số lượng, ngày giao, nhà máy, WBS. Dòng đã có: chưa
* đặt hàng và có ít nhất một thông tin để đổi. Không vừa xóa vừa khôi phục.
FORM pr_check_items USING    it_item   TYPE gty_t_pr_item
                             it_exist  TYPE gty_t_pr_exist_item
                    CHANGING ct_return TYPE bapiret2_t.
  DATA ls_nothing TYPE zctd_s_pr_item.

  LOOP AT it_item INTO DATA(ls_item).
    DATA(lv_no) = condense( |{ ls_item-preq_item ALPHA = OUT }| ).
    IF ls_item-delete_ind = abap_true AND ls_item-restore_ind = abap_true.
      APPEND VALUE #( BASE lcl_msg=>get( iv_no = '136' iv_v1 = lv_no ) type = 'E' ) TO ct_return.
      CONTINUE.
    ENDIF.

    READ TABLE it_exist INTO DATA(ls_exist) WITH TABLE KEY bnfpo = ls_item-preq_item.
    IF sy-subrc = 0.
      IF ls_exist-statu = 'B' OR ls_exist-bsmng > 0 OR ls_exist-ebakz = abap_true.
        APPEND VALUE #( BASE lcl_msg=>get( iv_no = '133' iv_v1 = lv_no ) type = 'E' ) TO ct_return.
      ELSEIF ls_item = VALUE zctd_s_pr_item( BASE ls_nothing preq_item = ls_item-preq_item ).
        APPEND VALUE #( BASE lcl_msg=>get( iv_no = '134' iv_v1 = lv_no ) type = 'E' ) TO ct_return.
      ENDIF.
      CONTINUE.
    ENDIF.

    PERFORM pr_check_new_item USING ls_item lv_no CHANGING ct_return.
  ENDLOOP.
ENDFORM.

FORM pr_check_new_item USING    is_item   TYPE zctd_s_pr_item
                                iv_no     TYPE csequence
                       CHANGING ct_return TYPE bapiret2_t.
  IF is_item-material IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '121' iv_v1 = iv_no ) type = 'E' field = 'MATERIAL' ) TO ct_return.
  ENDIF.
  IF is_item-quantity <= 0.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '122' iv_v1 = iv_no ) type = 'E' field = 'QUANTITY' ) TO ct_return.
  ENDIF.
  IF is_item-deliv_date IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '123' iv_v1 = iv_no ) type = 'E' field = 'DELIV_DATE' ) TO ct_return.
  ENDIF.
  IF is_item-plant IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '124' iv_v1 = iv_no ) type = 'E' field = 'PLANT' ) TO ct_return.
  ENDIF.
  IF is_item-wbs_element IS INITIAL.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '125' iv_v1 = iv_no ) type = 'E' field = 'WBS_ELEMENT' ) TO ct_return.
  ENDIF.
ENDFORM.

* Một dòng -> BAPI. Chỉ ô được truyền mới đặt cờ X. Dòng mới: loại gán dự án
* (P) + tài khoản mặc định. Sửa dòng đã có: gán dự án chỉ đổi khi truyền WBS / TK.
FORM pr_build_item USING    is_item  TYPE zctd_s_pr_item
                            iv_new   TYPE abap_bool
                   CHANGING ct_bitem TYPE gty_t_pr_bapi_item
                            ct_bitmx TYPE gty_t_pr_bapi_itemx
                            ct_bacc  TYPE gty_t_pr_bapi_acc
                            ct_baccx TYPE gty_t_pr_bapi_accx.
  DATA: ls_item  TYPE bapimereqitemimp,
        ls_itemx TYPE bapimereqitemx,
        ls_acc   TYPE bapimereqaccount,
        ls_accx  TYPE bapimereqaccountx.
  " ô cùng tên giữa ZCTD_S_PR_ITEM và BAPIMEREQITEMIMP
  DATA(lt_field) = VALUE string_table( ( `MATERIAL` ) ( `SHORT_TEXT` ) ( `QUANTITY` ) ( `UNIT` )
                                       ( `DELIV_DATE` ) ( `PLANT` ) ( `STORE_LOC` ) ( `PUR_GROUP` )
                                       ( `PURCH_ORG` ) ( `PREQ_NAME` ) ( `TRACKINGNO` ) ( `PREQ_PRICE` )
                                       ( `PRICE_UNIT` ) ).

  ls_item-preq_item  = is_item-preq_item.
  ls_itemx-preq_item = is_item-preq_item.
  ls_itemx-preq_itemx = abap_true.
  IF iv_new = abap_true.
    ls_item-acctasscat  = gc_pr_acct.
    ls_itemx-acctasscat = abap_true.
  ENDIF.
  LOOP AT lt_field INTO DATA(lv_field).
    ASSIGN COMPONENT lv_field OF STRUCTURE is_item TO FIELD-SYMBOL(<lv_in>).
    CHECK sy-subrc = 0 AND <lv_in> IS NOT INITIAL.
    ASSIGN COMPONENT lv_field OF STRUCTURE ls_item TO FIELD-SYMBOL(<lv_out>).
    ASSIGN COMPONENT lv_field OF STRUCTURE ls_itemx TO FIELD-SYMBOL(<lv_flag>).
    <lv_out>  = <lv_in>.
    <lv_flag> = abap_true.
  ENDLOOP.
  IF is_item-delete_ind = abap_true.
    ls_item-delete_ind  = abap_true.
    ls_itemx-delete_ind = abap_true.
  ELSEIF is_item-restore_ind = abap_true.
    ls_item-delete_ind  = space.
    ls_itemx-delete_ind = abap_true.
  ENDIF.
  APPEND ls_item TO ct_bitem.
  APPEND ls_itemx TO ct_bitmx.

  " gán dự án (một dòng, số 01)
  CHECK iv_new = abap_true OR is_item-wbs_element IS NOT INITIAL OR is_item-gl_account IS NOT INITIAL.
  ls_acc  = VALUE #( preq_item = is_item-preq_item serial_no = '01' ).
  ls_accx = VALUE #( preq_item = is_item-preq_item serial_no = '01' preq_itemx = abap_true serial_nox = abap_true ).
  IF is_item-wbs_element IS NOT INITIAL.
    ls_acc-wbs_element  = is_item-wbs_element.
    ls_accx-wbs_element = abap_true.
  ENDIF.
  IF is_item-gl_account IS NOT INITIAL.
    ls_acc-gl_account  = |{ is_item-gl_account ALPHA = IN }|.
    ls_accx-gl_account = abap_true.
  ELSEIF iv_new = abap_true.
    ls_acc-gl_account  = gc_pr_gl_def.
    ls_accx-gl_account = abap_true.
  ENDIF.
  APPEND ls_acc TO ct_bacc.
  APPEND ls_accx TO ct_baccx.
ENDFORM.

* Kết quả BAPI: thông báo SAP giữ nguyên văn (bỏ dòng trùng); lỗi / chạy thử
* -> ROLLBACK; còn lại COMMIT và báo số PR.
FORM pr_finish USING    it_bapiret  TYPE bapiret2_t
                        iv_testrun  TYPE xfeld
                        iv_change   TYPE abap_bool
                        iv_banfn    TYPE banfn
               CHANGING ct_return   TYPE bapiret2_t.
  DATA: lt_msg     TYPE bapiret2_t,
        ls_commit  TYPE bapiret2,
        lv_has_err TYPE abap_bool.

  LOOP AT it_bapiret INTO DATA(ls_ret).
    IF NOT line_exists( lt_msg[ type = ls_ret-type id = ls_ret-id number = ls_ret-number message = ls_ret-message ] ).
      APPEND ls_ret TO lt_msg.
    ENDIF.
    IF ls_ret-type CA 'EAX'.
      lv_has_err = abap_true.
    ENDIF.
  ENDLOOP.
  APPEND LINES OF lt_msg TO ct_return.

  DATA(lv_no) = condense( |{ iv_banfn ALPHA = OUT }| ).
  IF lv_has_err = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = COND #( WHEN iv_change = abap_true THEN '127' ELSE '126' ) iv_v1 = lv_no )
                    type = 'E' ) TO ct_return.
    RETURN.
  ENDIF.
  IF iv_testrun = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '128' ) type = 'S' ) TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait   = abap_true
    IMPORTING
      return = ls_commit.
  IF ls_commit-type CA 'EA'.
    APPEND ls_commit TO ct_return.
    APPEND VALUE #( BASE lcl_msg=>get( iv_no = '135' ) type = 'E' ) TO ct_return.
    RETURN.
  ENDIF.
  APPEND VALUE #( BASE lcl_msg=>get( iv_no = COND #( WHEN iv_change = abap_true THEN '130' ELSE '129' ) iv_v1 = lv_no )
                  type = 'S' ) TO ct_return.
ENDFORM.
