* Tạo / cập nhật message class (như SE91) không qua màn hình.
* RPY_MESSAGE_ID_INSERT từ chối tên có "_" (SE91 chỉ cảnh báo) và bật hộp
* thoại chọn TR -> ghi TADIR + TR bằng record_object (không hộp thoại),
* rồi ghi T100A / T100T / T100 như SE91. Message đã có thì ghi đè text.
* Package thật bắt buộc IV_TRANSPORT (request).

  DATA: lv_msgid TYPE arbgb,
        lt_t100  TYPE STANDARD TABLE OF t100.

  CLEAR et_return.
  lv_msgid = to_upper( iv_msgid ).
  IF lv_msgid IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Chưa nhập tên message class.| ) TO et_return.
    RETURN.
  ENDIF.
  IF iv_package <> '$TMP' AND iv_transport IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Package { iv_package } cần số TR để lưu message class.| ) TO et_return.
    RETURN.
  ENDIF.

  PERFORM record_object USING 'MSAG' lv_msgid iv_package iv_transport CHANGING et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  SELECT SINGLE @abap_true FROM t100a WHERE arbgb = @lv_msgid INTO @DATA(lv_exists).
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
