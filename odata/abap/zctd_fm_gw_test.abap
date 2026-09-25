* Gọi thử OData service qua Gateway client nội bộ (cơ chế của
* /IWFND/GW_CLIENT, không qua mạng). Trả HTTP status + body.
* IV_METHOD mặc định GET; POST/PUT/PATCH/DELETE: IV_BODY (JSON), tự lấy
* CSRF token từ gốc service như GW client.

  DATA: lt_header TYPE /iwfnd/sutil_property_t,
        lv_method TYPE string,
        lv_body   TYPE xstring,
        lv_csrf   TYPE string.

  CLEAR: ev_status_code, ev_status_text, ev_content_type, ev_body, ev_error.
  lv_method = to_upper( COND string( WHEN iv_method IS INITIAL THEN `GET` ELSE iv_method ) ).
  lt_header = VALUE #( ( name = '~request_method'  value = lv_method )
                       ( name = '~request_uri'     value = iv_uri )
                       ( name = '~server_protocol' value = 'HTTP/1.1' ) ).
  IF lv_method <> `GET`.
    APPEND VALUE #( name = 'content-type' value = 'application/json' ) TO lt_header.
    APPEND VALUE #( name = 'accept'       value = 'application/json' ) TO lt_header.
    " gốc service (…_SRV/) để lấy CSRF token
    FIND REGEX '^(.*_SRV/)' IN iv_uri SUBMATCHES lv_csrf.
  ENDIF.

  /iwfnd/cl_sutil_client_proxy=>get_instance( )->web_request(
    EXPORTING
      it_request_header  = lt_header
      iv_request_body    = COND #( WHEN iv_body IS NOT INITIAL THEN cl_abap_codepage=>convert_to( iv_body ) )
      iv_csrf_uri        = lv_csrf
      iv_csrf_method     = COND #( WHEN lv_csrf IS NOT INITIAL THEN `GET` )
      iv_suppress_dialog = abap_true
    IMPORTING
      ev_status_code     = ev_status_code
      ev_status_text     = ev_status_text
      ev_content_type    = ev_content_type
      ev_response_body   = lv_body
      ev_error_text      = ev_error ).
  ev_body = cl_abap_codepage=>convert_from( lv_body ).
