* Đọc log gọi API (ZCTD_T_API_LOG) - mới nhất trước.
* Lọc theo correlationId, ngày gọi, loại object, người gọi; mặc định 50 dòng.
* Trả dạng JSON (mảng) vì bảng có cột STRING - không truyền qua TABLES được.

  DATA: lt_corr TYPE RANGE OF zctd_t_api_log-corr_id,
        lt_date TYPE RANGE OF zctd_t_api_log-call_date,
        lt_obj  TYPE RANGE OF zctd_t_api_log-object_type,
        lt_user TYPE RANGE OF zctd_t_api_log-call_user,
        lt_log  TYPE STANDARD TABLE OF zctd_t_api_log WITH DEFAULT KEY.

  CLEAR: ev_json, ev_count.
  IF iv_corr_id IS NOT INITIAL.
    lt_corr = VALUE #( ( sign = 'I' option = 'EQ' low = to_lower( iv_corr_id ) ) ).
  ENDIF.
  IF iv_date_from IS NOT INITIAL OR iv_date_to IS NOT INITIAL.
    lt_date = VALUE #( ( sign = 'I' option = 'BT'
                         low  = iv_date_from
                         high = COND #( WHEN iv_date_to IS INITIAL THEN '99991231' ELSE iv_date_to ) ) ).
  ENDIF.
  IF iv_object_type IS NOT INITIAL.
    lt_obj = VALUE #( ( sign = 'I' option = 'EQ' low = iv_object_type ) ).
  ENDIF.
  IF iv_user IS NOT INITIAL.
    lt_user = VALUE #( ( sign = 'I' option = 'EQ' low = to_upper( iv_user ) ) ).
  ENDIF.

  SELECT * FROM zctd_t_api_log
    WHERE corr_id     IN @lt_corr
      AND call_date   IN @lt_date
      AND object_type IN @lt_obj
      AND call_user   IN @lt_user
    ORDER BY call_tstmp DESCENDING
    INTO TABLE @lt_log
    UP TO @( COND i( WHEN iv_max_rows > 0 THEN iv_max_rows ELSE 50 ) ) ROWS.

  ev_count = lines( lt_log ).
  ev_json  = /ui2/cl_json=>serialize( data = lt_log pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
