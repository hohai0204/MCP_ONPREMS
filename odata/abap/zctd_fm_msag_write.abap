* Tạo / cập nhật message class (như SE91) không qua màn hình.
* RPY_MESSAGE_ID_INSERT từ chối tên có "_" (SE91 chỉ cảnh báo) và bật hộp
* thoại chọn TR -> ghi TADIR + TR bằng record_object (không hộp thoại),
* rồi ghi T100A / T100T / T100 như SE91. Message đã có thì ghi đè text.
* Package thật bắt buộc IV_TRANSPORT (request).
* An toàn như SE91:
*   - chỉ message class khách hàng (tên bắt đầu bằng Z hoặc Y)
*   - quyền S_DEVELOP (OBJTYPE MSAG, 01 = tạo mới / 02 = sửa) trên package
*   - khóa message class (lock object ES_MSGID) trong lúc ghi

  DATA: lv_msgid   TYPE arbgb,
        lv_package TYPE devclass,
        lv_actvt   TYPE activ_auth,
        lt_t100    TYPE STANDARD TABLE OF t100.

  CLEAR et_return.
  lv_msgid = to_upper( iv_msgid ).
  IF lv_msgid IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Chưa nhập tên message class.| ) TO et_return.
    RETURN.
  ENDIF.
  IF lv_msgid(1) <> 'Z' AND lv_msgid(1) <> 'Y'.
    APPEND VALUE #( type = 'E' message = |Chỉ được ghi message class bắt đầu bằng Z hoặc Y ({ lv_msgid }).| ) TO et_return.
    RETURN.
  ENDIF.

  " message class đã có -> sửa trên package hiện tại của nó
  SELECT SINGLE @abap_true FROM t100a WHERE arbgb = @lv_msgid INTO @DATA(lv_exists).
  SELECT SINGLE devclass FROM tadir
    WHERE pgmid = 'R3TR' AND object = 'MSAG' AND obj_name = @lv_msgid
    INTO @lv_package.
  IF lv_package IS INITIAL.
    lv_package = iv_package.
  ENDIF.
  IF lv_package <> '$TMP' AND iv_transport IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Package { lv_package } cần số TR để lưu message class.| ) TO et_return.
    RETURN.
  ENDIF.

  lv_actvt = COND #( WHEN lv_exists = abap_true THEN '02' ELSE '01' ).
  AUTHORITY-CHECK OBJECT 'S_DEVELOP'
    ID 'DEVCLASS' FIELD lv_package
    ID 'OBJTYPE'  FIELD 'MSAG'
    ID 'OBJNAME'  FIELD lv_msgid
    ID 'P_GROUP'  DUMMY
    ID 'ACTVT'    FIELD lv_actvt.
  IF sy-subrc <> 0.
    APPEND VALUE #( type = 'E'
                    message = |Người dùng { sy-uname } không có quyền { COND string( WHEN lv_actvt = '01' THEN `tạo` ELSE `sửa` ) } message class { lv_msgid } (package { lv_package }).| )
      TO et_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'ENQUEUE_ES_MSGID'
    EXPORTING
      arbgb          = lv_msgid
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    APPEND VALUE #( type = 'E'
                    message = COND #( WHEN sy-subrc = 1
                                      THEN |Message class { lv_msgid } đang được { sy-msgv1 } chỉnh sửa, thử lại sau.|
                                      ELSE |Không khóa được message class { lv_msgid } để ghi.| ) )
      TO et_return.
    RETURN.
  ENDIF.

  PERFORM record_object USING 'MSAG' lv_msgid lv_package iv_transport CHANGING et_return.
  IF NOT line_exists( et_return[ type = 'E' ] ).
    IF lv_exists = abap_false.
      INSERT t100a FROM @( VALUE #( arbgb = lv_msgid masterlang = iv_langu stext = iv_title
                                    lastuser = sy-uname ldate = sy-datum ltime = sy-uzeit ) ).
    ELSE.
      UPDATE t100a SET lastuser = @sy-uname, ldate = @sy-datum, ltime = @sy-uzeit
        WHERE arbgb = @lv_msgid.
    ENDIF.
    IF iv_title IS NOT INITIAL.
      MODIFY t100t FROM @( VALUE #( sprsl = iv_langu arbgb = lv_msgid stext = iv_title ) ).
    ENDIF.

    lt_t100 = VALUE #( FOR m IN it_t100 ( sprsl = iv_langu arbgb = lv_msgid msgnr = m-msgnr text = m-text ) ).
    MODIFY t100 FROM TABLE lt_t100.
    COMMIT WORK AND WAIT.

    APPEND VALUE #( type = 'S'
                    message = |Đã ghi message class { lv_msgid } ({ lines( lt_t100 ) } message).| ) TO et_return.
  ENDIF.

  CALL FUNCTION 'DEQUEUE_ES_MSGID'
    EXPORTING
      arbgb = lv_msgid.
