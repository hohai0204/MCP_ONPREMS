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
        ev_message = lcl_msg=>get( iv_no = '100' iv_v1 = |{ ls_log-corr_id }| )-message.
      ELSE.
        ROLLBACK CONNECTION (lc_connection).
        ev_message = lcl_msg=>get( iv_no = '101' iv_v1 = |{ ls_log-corr_id }| iv_v2 = |{ ls_log-call_date DATE = USER }|
                                   iv_v3 = |{ ls_log-call_time TIME = USER }| )-message.
      ENDIF.
    CATCH cx_root INTO DATA(lx_error).
      ev_subrc   = 8.
      ev_message = lcl_msg=>get( iv_no = '102' iv_v1 = lx_error->get_text( ) )-message.
  ENDTRY.
