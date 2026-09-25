* Ghi 1 dòng log gọi API vào ZCTD_T_API_LOG.
* Ghi và COMMIT qua kết nối DB phụ nên không ảnh hưởng LUW của request,
* và log vẫn được lưu kể cả khi API trả lỗi. Không bao giờ ném lỗi ra ngoài.

  CONSTANTS lc_connection TYPE dbcon_name VALUE 'R/3*ZCTD_API_LOG'.
  DATA ls_log TYPE zctd_t_api_log.

  CLEAR: ev_subrc, ev_message.
  ls_log = is_log.
  ls_log-mandt = sy-mandt.
  IF ls_log-corr_id IS INITIAL.
    TRY.
        ls_log-corr_id = to_lower( cl_system_uuid=>create_uuid_c36_static( ) ).
      CATCH cx_uuid_error.
    ENDTRY.
  ENDIF.
  IF ls_log-call_date IS INITIAL.
    ls_log-call_date = sy-datum.
    ls_log-call_time = sy-uzeit.
  ENDIF.
  IF ls_log-call_tstmp IS INITIAL.
    GET TIME STAMP FIELD ls_log-call_tstmp.
  ENDIF.
  IF ls_log-call_user IS INITIAL.
    ls_log-call_user = sy-uname.
  ENDIF.

  TRY.
      INSERT zctd_t_api_log CONNECTION (lc_connection) FROM ls_log.
      ev_subrc = sy-subrc.
      IF ev_subrc = 0.
        COMMIT CONNECTION (lc_connection).
        ev_message = |Đã ghi log { ls_log-corr_id }.|.
      ELSE.
        ROLLBACK CONNECTION (lc_connection).
        ev_message = |Log { ls_log-corr_id } lúc { ls_log-call_date DATE = USER } { ls_log-call_time TIME = USER } đã tồn tại.|.
      ENDIF.
    CATCH cx_root INTO DATA(lx_error).
      ev_subrc   = 8.
      ev_message = |Không ghi được log gọi API: { lx_error->get_text( ) }|.
  ENDTRY.
