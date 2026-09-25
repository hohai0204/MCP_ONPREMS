*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_PO_INFOF01.
*----------------------------------------------------------------------*
* Chuyển message của Service Builder (SEGW) sang BAPIRET2
FORM sbcm_messages USING    it_messages TYPE /iwbep/if_sbcm_msg_object=>ty_t_object
                   CHANGING ct_return   TYPE bapiret2_t.
  DATA lv_type TYPE symsgty.

  LOOP AT it_messages INTO DATA(lo_message).
    TRY.
        lv_type = lo_message->get_severity( ).
        APPEND VALUE #( type    = COND #( WHEN lv_type IS INITIAL THEN 'I' ELSE lv_type )
                        message = lo_message->get_text( ) ) TO ct_return.
      CATCH /iwbep/cx_sbcm_exception.
    ENDTRY.
  ENDLOOP.
ENDFORM.

* Task của user hiện tại trong TR (request). Không có task -> dùng luôn request.
FORM tr_task USING    iv_request TYPE trkorr
             CHANGING cv_task    TYPE trkorr.
  SELECT SINGLE trkorr FROM e070
    WHERE strkorr = @iv_request AND as4user = @sy-uname AND trstatus = 'D'
    INTO @cv_task.
  IF sy-subrc <> 0.
    cv_task = iv_request.
  ENDIF.
ENDFORM.

* Đăng ký trước (TADIR + TR) các object mà SEGW generator sẽ sinh ra cho
* package thật - nếu không, generator bật hộp thoại chọn package/TR
* (SAPLSTRD 0300) và dừng khi chạy qua RFC. Tên theo đề xuất chuẩn.
FORM prereg_generated USING    iv_project   TYPE csequence
                               iv_package   TYPE devclass
                               iv_transport TYPE trkorr
                      CHANGING ct_return    TYPE bapiret2_t.
  DATA lv_name TYPE string.

  CHECK iv_package <> '$TMP'.
  LOOP AT VALUE string_table( ( `_MPC` ) ( `_MPC_EXT` ) ( `_DPC` ) ( `_DPC_EXT` ) ) INTO DATA(lv_suffix).
    lv_name = |ZCL_{ iv_project }{ lv_suffix }|.
    PERFORM record_object USING 'CLAS' lv_name iv_package iv_transport CHANGING ct_return.
  ENDLOOP.
  lv_name = |{ iv_project }_MDL|.
  lv_name = |{ lv_name WIDTH = 32 }0001|.
  PERFORM record_object USING 'IWMO' lv_name iv_package iv_transport CHANGING ct_return.
  lv_name = |{ iv_project }_SRV|.
  lv_name = |{ lv_name WIDTH = 35 }0001|.
  PERFORM record_object USING 'IWSV' lv_name iv_package iv_transport CHANGING ct_return.
ENDFORM.

* Ghi object R3TR cho package thật, không hỏi hộp thoại:
* TADIR (TR_TADIR_INTERFACE) rồi ghi vào TR (TR_RECORD_OBJ_CHANGE_TO_REQ).
* Gọi lại khi object đã có trong TR thì không sao.
FORM record_object USING    iv_type      TYPE trobjtype
                            iv_name      TYPE csequence
                            iv_package   TYPE devclass
                            iv_transport TYPE trkorr
                   CHANGING ct_return    TYPE bapiret2_t.
  DATA: lv_object  TYPE tadir-obj_name,
        lv_srcsys  TYPE tadir-srcsystem,
        lt_objects TYPE tredt_objects,
        lt_tadir   TYPE scts_tadir.

  CHECK iv_package <> '$TMP'.
  lv_object = iv_name.
  lv_srcsys = sy-sysid.

  SELECT SINGLE devclass FROM tadir
    WHERE pgmid = 'R3TR' AND object = @iv_type AND obj_name = @lv_object
    INTO @DATA(lv_devclass).
  IF sy-subrc <> 0 OR lv_devclass <> iv_package.
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus       = ' '
        wi_tadir_pgmid      = 'R3TR'
        wi_tadir_object     = iv_type
        wi_tadir_obj_name   = lv_object
        wi_tadir_author     = sy-uname
        wi_tadir_devclass   = iv_package
        wi_tadir_masterlang = sy-langu
        wi_tadir_srcsystem  = lv_srcsys
      EXCEPTIONS
        OTHERS              = 1.
    IF sy-subrc <> 0.
      APPEND VALUE #( type = 'E' id = sy-msgid number = sy-msgno
                      message_v1 = sy-msgv1 message_v2 = sy-msgv2 message_v3 = sy-msgv3 message_v4 = sy-msgv4
                      message = |Không tạo được TADIR cho { iv_type } { iv_name } (package { iv_package }).| ) TO ct_return.
      RETURN.
    ENDIF.
  ENDIF.

  lt_objects = VALUE #( ( pgmid = 'R3TR' object = iv_type obj_name = lv_object
                          author = sy-uname masterlang = sy-langu devclass = iv_package operation = 'I' ) ).
  CALL FUNCTION 'TR_RECORD_OBJ_CHANGE_TO_REQ'
    EXPORTING
      iv_request = iv_transport
      it_objects = lt_objects
    IMPORTING
      et_tadir   = lt_tadir
    EXCEPTIONS
      cancel     = 1
      OTHERS     = 2.
  IF sy-subrc = 0.
    APPEND VALUE #( type = 'S' message = |Đã ghi { iv_type } { iv_name } vào TR { iv_transport } (package { iv_package }).| ) TO ct_return.
  ELSE.
    APPEND VALUE #( type = 'E' id = sy-msgid number = sy-msgno
                    message_v1 = sy-msgv1 message_v2 = sy-msgv2 message_v3 = sy-msgv3 message_v4 = sy-msgv4
                    message = |Không ghi được { iv_type } { iv_name } vào TR { iv_transport } (mã { sy-subrc }).| ) TO ct_return.
  ENDIF.
ENDFORM.
