FUNCTION zmcp_adt_gwlog.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PARAMS) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  I
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RESULT) TYPE  STRING
*"----------------------------------------------------------------------
* ZMCP_ADT_GWLOG - read-only: Gateway error log (/IWFND/ERROR_LOG).
* Why: table /IWFND/SU_ERRLOG has string columns, RFC_READ_TABLE dumps
* with ASSIGN_CASTING_ILLEGAL_CAST on it, so it is read here with Open SQL.
*
* IV_PARAMS (JSON, all optional):
*   { "minutes": 60, "username": "HAIHT", "service": "ZCTC_MATERIAL%",
*     "uri_part": "MaterialSet", "min_status": 400, "opid": "<32 chars>",
*     "max_rows": 20, "with_context": false, "context_chars": 4000 }
*   minutes = look back from now (default 60). service / uri_part are
*   substring or pattern ('%' wildcard) filters.
* EV_RESULT (JSON): [ { OPID, SUBNO, TIMESTAMP, USERNAME, HTTP_STATUS,
*   SERVICE_NAME, SERVICE_VERSION, REQUEST_URI, ERROR_TEXT, T100_MSGID,
*   T100_MSGNO, T100_MSGV1..4, SOURCE_PROGRAM, SOURCE_INCLUDE,
*   SOURCE_LINE, ERROR_COMPONENT, ERROR_PACKAGE, ERROR_COUNT,
*   CONTEXT (only when with_context) } ]
*----------------------------------------------------------------------

  TYPES: BEGIN OF ty_row,
           opid            TYPE c LENGTH 32,
           subno           TYPE i,
           timestamp       TYPE string,
           username        TYPE c LENGTH 12,
           http_status     TYPE c LENGTH 3,
           service_name    TYPE c LENGTH 40,
           service_version TYPE c LENGTH 4,
           request_uri     TYPE string,
           error_text      TYPE string,
           t100_msgid      TYPE c LENGTH 20,
           t100_msgno      TYPE c LENGTH 3,
           t100_msgv1      TYPE string,
           t100_msgv2      TYPE string,
           t100_msgv3      TYPE string,
           t100_msgv4      TYPE string,
           source_program  TYPE string,
           source_include  TYPE string,
           source_line     TYPE i,
           error_component TYPE string,
           error_package   TYPE string,
           error_count     TYPE i,
           context         TYPE string,
         END OF ty_row.

  DATA: BEGIN OF ls_in,
          minutes       TYPE i,
          username      TYPE string,
          service       TYPE string,
          uri_part      TYPE string,
          min_status    TYPE i,
          opid          TYPE string,
          max_rows      TYPE i,
          with_context  TYPE abap_bool,
          context_chars TYPE i,
        END OF ls_in.
  DATA: lt_rows   TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY,
        ls_row    TYPE ty_row,
        lt_db     TYPE STANDARD TABLE OF /iwfnd/su_errlog WITH DEFAULT KEY,
        lv_now    TYPE timestampl,
        lv_from   TYPE timestampl,
        lv_where  TYPE string,
        lv_raw    TYPE xstring,
        lv_len    TYPE i,
        lv_user   TYPE string,
        lv_serv   TYPE string,
        lv_uri    TYPE string,
        lv_xml    TYPE string.

  CLEAR: ev_subrc, ev_message, ev_result.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).
  IF ls_in-minutes <= 0.
    ls_in-minutes = 60.
  ENDIF.
  IF ls_in-max_rows <= 0.
    ls_in-max_rows = 20.
  ENDIF.
  IF ls_in-max_rows > 200.
    ls_in-max_rows = 200.
  ENDIF.
  IF ls_in-context_chars <= 0.
    ls_in-context_chars = 4000.
  ENDIF.
  IF ls_in-context_chars > 50000.
    ls_in-context_chars = 50000.
  ENDIF.

  TRY.
      /iwfnd/cl_cof_util=>authority_check_config(
        iv_db_name          = /iwfnd/cl_cof_util=>co_db_name-/iwfnd/c_config
        iv_read_only_access = abap_true ).
    CATCH /iwfnd/cx_cof.
      ev_subrc   = 4.
      ev_message = 'No authorization to read the Gateway error log'.
      RETURN.
  ENDTRY.

  GET TIME STAMP FIELD lv_now.
  lv_from = cl_abap_tstmp=>subtractsecs( tstmp = lv_now
                                         secs  = ls_in-minutes * 60 ).
  lv_user = to_upper( ls_in-username ).
  lv_serv = ls_in-service.
  lv_uri  = ls_in-uri_part.
  IF lv_uri IS NOT INITIAL AND lv_uri NS '%'.
    lv_uri = |%{ lv_uri }%|.
  ENDIF.

  " dynamic WHERE, every value quoted (no injection from IV_PARAMS);
  " client handling is automatic, so no SAPCLIENT condition
  IF ls_in-opid IS NOT INITIAL.
    lv_where = |opid = { cl_abap_dyn_prg=>quote( to_upper( ls_in-opid ) ) }|.
  ELSE.
    lv_where = |timestamp >= @lv_from|.
    IF lv_user IS NOT INITIAL.
      lv_where = lv_where &&
                 | AND username = { cl_abap_dyn_prg=>quote( lv_user ) }|.
    ENDIF.
    IF lv_serv IS NOT INITIAL.
      lv_where = lv_where &&
                 | AND service_name LIKE { cl_abap_dyn_prg=>quote( lv_serv ) }|.
    ENDIF.
    IF lv_uri IS NOT INITIAL.
      lv_where = lv_where &&
                 | AND request_uri LIKE { cl_abap_dyn_prg=>quote( lv_uri ) }|.
    ENDIF.
    IF ls_in-min_status > 0.
      lv_where = lv_where &&
                 | AND http_status >= '{ ls_in-min_status WIDTH = 3 ALIGN = RIGHT PAD = '0' }'|.
    ENDIF.
  ENDIF.

  SELECT * FROM /iwfnd/su_errlog
    WHERE (lv_where)
    ORDER BY timestamp DESCENDING
    INTO TABLE @lt_db
    UP TO @ls_in-max_rows ROWS.

  LOOP AT lt_db INTO DATA(ls_db).
    CLEAR ls_row.
    ls_row-opid            = ls_db-opid.
    ls_row-subno           = ls_db-subno.
    ls_row-timestamp       = |{ ls_db-timestamp TIMESTAMP = ISO }|.
    ls_row-username        = ls_db-username.
    ls_row-http_status     = ls_db-http_status.
    ls_row-service_name    = ls_db-service_name.
    ls_row-service_version = ls_db-service_version.
    ls_row-request_uri     = ls_db-request_uri.
    ls_row-error_text      = ls_db-error_text.
    ls_row-t100_msgid      = ls_db-t100_msgid.
    ls_row-t100_msgno      = ls_db-t100_msgno.
    ls_row-t100_msgv1      = ls_db-t100_msgv1.
    ls_row-t100_msgv2      = ls_db-t100_msgv2.
    ls_row-t100_msgv3      = ls_db-t100_msgv3.
    ls_row-t100_msgv4      = ls_db-t100_msgv4.
    ls_row-source_program  = ls_db-source_program.
    ls_row-source_include  = ls_db-source_include.
    ls_row-source_line     = ls_db-source_line.
    ls_row-error_component = ls_db-error_component.
    ls_row-error_package   = ls_db-error_package.
    ls_row-error_count     = ls_db-error_count.
    IF ls_in-with_context = abap_true AND ls_db-error_context IS NOT INITIAL.
      TRY.
          " the context is stored gzip-compressed XML; plain XML as fallback
          TRY.
              cl_abap_gzip=>decompress_binary(
                EXPORTING gzip_in     = ls_db-error_context
                IMPORTING raw_out     = lv_raw
                          raw_out_len = lv_len ).
              lv_xml = cl_abap_codepage=>convert_from( lv_raw ).
            CATCH cx_root.
              lv_xml = cl_abap_codepage=>convert_from( ls_db-error_context ).
          ENDTRY.
          IF strlen( lv_xml ) > ls_in-context_chars.
            lv_xml = lv_xml(ls_in-context_chars).
          ENDIF.
          ls_row-context = lv_xml.
        CATCH cx_root.
          ls_row-context = '(context could not be decoded)'.
      ENDTRY.
    ENDIF.
    APPEND ls_row TO lt_rows.
  ENDLOOP.

  ev_result  = /ui2/cl_json=>serialize( data = lt_rows ).
  ev_subrc   = 0.
  ev_message = |{ lines( lt_rows ) } entr(ies)|.

ENDFUNCTION.
