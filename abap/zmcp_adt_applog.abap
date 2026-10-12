FUNCTION zmcp_adt_applog.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PARAMS) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  I
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RESULT) TYPE  STRING
*"----------------------------------------------------------------------
* ZMCP_ADT_APPLOG - read-only: messages of application logs (SLG1).
* Why: BALM is empty on many systems, messages live in the BALDAT
* cluster, which RFC_READ_TABLE cannot read. BAL_DB_LOAD is not
* remote-enabled, so this wrapper calls it locally.
*
* IV_PARAMS (JSON): { "lognumbers": ["00000000000000449583", ...],
*                     "max_messages": 100, "langu": "E" }
*   Pass LOGNUMBERs found via BALHDR (table read on the bridge side).
* EV_RESULT (JSON): [ { LOGNUMBER, OBJECT, SUBOBJECT, TRUNCATED, ERROR,
*                       MESSAGES: [ {TYPE,ID,NO,TEXT,V1..V4,
*                                    PROBCLASS,TIME_STMP} ] } ]
*----------------------------------------------------------------------

  TYPES: BEGIN OF ty_msg,
           type      TYPE c LENGTH 1,
           id        TYPE c LENGTH 20,
           no        TYPE c LENGTH 3,
           text      TYPE string,
           v1        TYPE string,
           v2        TYPE string,
           v3        TYPE string,
           v4        TYPE string,
           probclass TYPE c LENGTH 1,
           time_stmp TYPE string,
         END OF ty_msg.
  TYPES: BEGIN OF ty_log,
           lognumber TYPE c LENGTH 20,
           object    TYPE c LENGTH 20,
           subobject TYPE c LENGTH 20,
           truncated TYPE abap_bool,
           error     TYPE string,
           messages  TYPE STANDARD TABLE OF ty_msg WITH DEFAULT KEY,
         END OF ty_log.

  DATA: BEGIN OF ls_in,
          lognumbers   TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
          max_messages TYPE i,
          langu        TYPE string,
        END OF ls_in.
  DATA: lt_logs   TYPE STANDARD TABLE OF ty_log WITH DEFAULT KEY,
        ls_log    TYPE ty_log,
        ls_msg    TYPE ty_msg,
        ls_bal    TYPE bal_s_msg,
        lt_lognr  TYPE bal_t_logn,
        lt_logh   TYPE bal_t_logh,
        lt_msgh   TYPE bal_t_msgh,
        lv_lognr  TYPE balognr,
        lv_ln     TYPE string,
        lv_txt    TYPE c LENGTH 255,
        lv_langu  TYPE sylangu,
        lv_text   TYPE string.

  CLEAR: ev_subrc, ev_message, ev_result.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).
  IF ls_in-max_messages <= 0.
    ls_in-max_messages = 100.
  ENDIF.
  IF ls_in-max_messages > 1000.
    ls_in-max_messages = 1000.
  ENDIF.
  IF lines( ls_in-lognumbers ) = 0.
    ev_subrc = 4.
    ev_message = 'No lognumbers given'.
    RETURN.
  ENDIF.
  lv_langu = COND #( WHEN ls_in-langu IS INITIAL THEN sy-langu
                     ELSE to_upper( ls_in-langu(1) ) ).

  LOOP AT ls_in-lognumbers INTO lv_ln.
    CLEAR: ls_log, lt_lognr, lt_logh, lt_msgh.

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = lv_ln
      IMPORTING
        output = lv_lognr.
    ls_log-lognumber = lv_lognr.

    SELECT SINGLE object, subobject FROM balhdr
      WHERE lognumber = @lv_lognr
      INTO ( @ls_log-object, @ls_log-subobject ).
    IF sy-subrc <> 0.
      ls_log-error = 'Log not found'.
      APPEND ls_log TO lt_logs.
      CONTINUE.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'S_APPL_LOG'
      ID 'ALG_OBJECT' FIELD ls_log-object
      ID 'ALG_SUBOBJ' FIELD ls_log-subobject
      ID 'ACTVT'      FIELD '03'.
    IF sy-subrc <> 0.
      ls_log-error = 'No display authorization (S_APPL_LOG)'.
      APPEND ls_log TO lt_logs.
      CONTINUE.
    ENDIF.

    APPEND lv_lognr TO lt_lognr.
    CALL FUNCTION 'BAL_DB_LOAD'
      EXPORTING
        i_t_lognumber      = lt_lognr
      IMPORTING
        e_t_log_handle     = lt_logh
        e_t_msg_handle     = lt_msgh
      EXCEPTIONS
        no_logs_specified  = 1
        log_not_found      = 2
        log_already_loaded = 3
        OTHERS             = 4.
    IF sy-subrc <> 0.
      ls_log-error = |BAL_DB_LOAD failed (subrc { sy-subrc })|.
      APPEND ls_log TO lt_logs.
      CONTINUE.
    ENDIF.

    LOOP AT lt_msgh INTO DATA(ls_msgh).
      IF lines( ls_log-messages ) >= ls_in-max_messages.
        ls_log-truncated = abap_true.
        EXIT.
      ENDIF.
      CLEAR: ls_bal, lv_txt, ls_msg.
      CALL FUNCTION 'BAL_LOG_MSG_READ'
        EXPORTING
          i_s_msg_handle = ls_msgh
          i_langu        = lv_langu
        IMPORTING
          e_s_msg        = ls_bal
          e_txt_msg      = lv_txt
        EXCEPTIONS
          log_not_found  = 1
          msg_not_found  = 2
          OTHERS         = 3.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ls_msg-type      = ls_bal-msgty.
      ls_msg-id        = ls_bal-msgid.
      ls_msg-no        = ls_bal-msgno.
      ls_msg-v1        = ls_bal-msgv1.
      ls_msg-v2        = ls_bal-msgv2.
      ls_msg-v3        = ls_bal-msgv3.
      ls_msg-v4        = ls_bal-msgv4.
      ls_msg-probclass = ls_bal-probclass.
      ls_msg-time_stmp = |{ ls_bal-time_stmp }|.
      lv_text = lv_txt.
      IF lv_text IS INITIAL AND ls_bal-msgid IS NOT INITIAL.
        MESSAGE ID ls_bal-msgid TYPE 'S' NUMBER ls_bal-msgno
          WITH ls_bal-msgv1 ls_bal-msgv2 ls_bal-msgv3 ls_bal-msgv4
          INTO lv_text.
      ENDIF.
      ls_msg-text = condense( lv_text ).
      APPEND ls_msg TO ls_log-messages.
    ENDLOOP.

    " free the loaded log so the same log can be read again later in
    " this (stateful) RFC session
    LOOP AT lt_logh INTO DATA(lv_logh).
      CALL FUNCTION 'BAL_LOG_REFRESH'
        EXPORTING
          i_log_handle  = lv_logh
        EXCEPTIONS
          log_not_found = 1
          OTHERS        = 2.
    ENDLOOP.

    APPEND ls_log TO lt_logs.
  ENDLOOP.

  ev_result  = /ui2/cl_json=>serialize( data = lt_logs ).
  ev_subrc   = 0.
  ev_message = |{ lines( lt_logs ) } log(s)|.

ENDFUNCTION.
