FUNCTION zmcp_adt_msag.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PARAMS) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  I
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RESULT) TYPE  STRING
*"----------------------------------------------------------------------
* ZMCP_ADT_MSAG - add / change / delete messages of an EXISTING message
* class (SE91 / table T100) over RFC. RPY_MESSAGE_ID_INSERT only creates new
* classes and the delete / change FMs are not remote-enabled, hence this
* wrapper. Deliberately narrow:
*   - class name must start with Z or Y and must already exist (T100A)
*   - S_DEVELOP change authorization on the class
*   - class in a transportable package -> a request is required; it is
*     recorded with RS_CORR_INSERT (object R3TR MSAG), same as SE91
*   - number 000-999, text up to 73 characters
* IV_PARAMS (JSON):
*   { "action":"UPSERT" | "DELETE", "class":"ZMC_CTD", "language":"E",
*     "transport":"S4DK907429",
*     "messages":[ {"number":"560","text":"..."} ] }
*   DELETE ignores "text".
* EV_RESULT (JSON): { "class", "package", "language", "action", "count" }
*----------------------------------------------------------------------

  TYPES: BEGIN OF ty_msg,
           number TYPE string,
           text   TYPE string,
         END OF ty_msg.

  DATA: BEGIN OF ls_in,
          action    TYPE string,
          class     TYPE string,
          language  TYPE string,
          transport TYPE string,
          messages  TYPE STANDARD TABLE OF ty_msg WITH DEFAULT KEY,
        END OF ls_in.
  DATA: lv_class  TYPE t100-arbgb,
        lv_lang   TYPE t100-sprsl,
        lv_pkg    TYPE tadir-devclass,
        lv_trkorr TYPE e070-trkorr,
        lv_dummy  TYPE t100a-arbgb,
        lv_msgnr  TYPE t100-msgnr,
        lv_num    TYPE string,
        lv_count  TYPE i,
        ls_t100   TYPE t100,
        lt_t100   TYPE STANDARD TABLE OF t100 WITH DEFAULT KEY,
        lv_ret_dev  TYPE tadir-devclass,
        lv_ret_korr TYPE e070-trkorr,
        lv_ret_ord  TYPE e070-trkorr,
        lv_ret_auth TYPE sy-uname.

  CLEAR: ev_subrc, ev_message, ev_result.

  TRY.
      /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                                 CHANGING  data = ls_in ).
    CATCH cx_root INTO DATA(lx_json).
      ev_subrc   = 4.
      ev_message = |Bad IV_PARAMS JSON: { lx_json->get_text( ) }|.
      RETURN.
  ENDTRY.

  ls_in-action = to_upper( condense( ls_in-action ) ).
  IF ls_in-action <> 'UPSERT' AND ls_in-action <> 'DELETE'.
    ev_subrc   = 4.
    ev_message = |Unknown action "{ ls_in-action }". Use UPSERT or DELETE.|.
    RETURN.
  ENDIF.

  lv_class = to_upper( condense( ls_in-class ) ).
  IF lv_class IS INITIAL.
    ev_subrc   = 4.
    ev_message = 'No message class given'.
    RETURN.
  ENDIF.
  IF lv_class(1) <> 'Z' AND lv_class(1) <> 'Y'.
    ev_subrc   = 4.
    ev_message = 'Only customer message classes (Z/Y) can be changed here'.
    RETURN.
  ENDIF.
  IF ls_in-messages IS INITIAL.
    ev_subrc   = 4.
    ev_message = 'No messages given'.
    RETURN.
  ENDIF.

  lv_lang = COND #( WHEN ls_in-language IS INITIAL THEN 'E' ELSE to_upper( condense( ls_in-language ) ) ).

  SELECT SINGLE arbgb FROM t100a WHERE arbgb = @lv_class INTO @lv_dummy.
  IF sy-subrc <> 0.
    ev_subrc   = 4.
    ev_message = |Message class { lv_class } does not exist (create it in SE91 first)|.
    RETURN.
  ENDIF.

  SELECT SINGLE devclass FROM tadir
    WHERE pgmid = 'R3TR' AND object = 'MSAG' AND obj_name = @lv_class
    INTO @lv_pkg.
  IF sy-subrc <> 0.
    ev_subrc   = 4.
    ev_message = |Message class { lv_class } has no repository entry|.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_DEVELOP'
    ID 'DEVCLASS' FIELD lv_pkg
    ID 'OBJTYPE'  FIELD 'MSAG'
    ID 'OBJNAME'  FIELD lv_class
    ID 'P_GROUP'  DUMMY
    ID 'ACTVT'    FIELD '02'.
  IF sy-subrc <> 0.
    ev_subrc   = 4.
    ev_message = |No S_DEVELOP change authorization for message class { lv_class }|.
    RETURN.
  ENDIF.

  " validate every message before touching anything
  LOOP AT ls_in-messages INTO DATA(ls_msg).
    lv_num = condense( ls_msg-number ).
    IF lv_num IS INITIAL OR strlen( lv_num ) > 3 OR lv_num CN '0123456789'.
      ev_subrc   = 4.
      ev_message = |Message number "{ ls_msg-number }" is not 000-999|.
      RETURN.
    ENDIF.
    lv_msgnr = |{ lv_num ALPHA = IN }|.
    IF ls_in-action = 'UPSERT'.
      IF ls_msg-text IS INITIAL.
        ev_subrc   = 4.
        ev_message = |Message { lv_msgnr }: text is empty|.
        RETURN.
      ENDIF.
      IF strlen( ls_msg-text ) > 73.
        ev_subrc   = 4.
        ev_message = |Message { lv_msgnr }: text longer than 73 characters ({ strlen( ls_msg-text ) })|.
        RETURN.
      ENDIF.
    ENDIF.
    CLEAR ls_t100.
    ls_t100-sprsl = lv_lang.
    ls_t100-arbgb = lv_class.
    ls_t100-msgnr = lv_msgnr.
    ls_t100-text  = ls_msg-text.
    APPEND ls_t100 TO lt_t100.
  ENDLOOP.

  " transportable package: record the class in the request (as SE91 does)
  IF lv_pkg(1) <> '$'.
    lv_trkorr = ls_in-transport.
    IF lv_trkorr IS INITIAL.
      ev_subrc   = 4.
      ev_message = |Message class { lv_class } is in package { lv_pkg }: a transport request is required|.
      RETURN.
    ENDIF.
    CALL FUNCTION 'RS_CORR_INSERT'
      EXPORTING
        object                   = lv_class
        object_class             = 'MSAG'
        mode                     = 'I'
        global_lock              = 'X'
        devclass                 = lv_pkg
        korrnum                  = lv_trkorr
        use_korrnum_immediatedly = 'X'
        master_language          = sy-langu
        suppress_dialog          = 'X'
      IMPORTING
        devclass                 = lv_ret_dev
        korrnum                  = lv_ret_korr
        ordernum                 = lv_ret_ord
        author                   = lv_ret_auth
      EXCEPTIONS
        cancelled                = 1
        permission_failure       = 2
        unknown_objectclass      = 3
        OTHERS                   = 4.
    IF sy-subrc <> 0.
      ev_subrc   = 8.
      ev_message = |RS_CORR_INSERT failed for { lv_class } (sy-subrc={ sy-subrc } msgno={ sy-msgno } { sy-msgv1 } { sy-msgv2 } { sy-msgv3 } { sy-msgv4 })|.
      RETURN.
    ENDIF.
  ENDIF.

  IF ls_in-action = 'UPSERT'.
    MODIFY t100 FROM TABLE lt_t100.
  ELSE.
    DELETE t100 FROM TABLE lt_t100.
  ENDIF.
  IF sy-subrc <> 0 AND ls_in-action = 'UPSERT'.
    ROLLBACK WORK.
    ev_subrc   = 8.
    ev_message = |Database update of T100 failed (sy-subrc={ sy-subrc })|.
    RETURN.
  ENDIF.
  COMMIT WORK.

  lv_count = lines( lt_t100 ).
  ev_subrc   = 0.
  ev_message = |{ ls_in-action } { lv_count } message(s) in { lv_class } ({ lv_lang })|.
  ev_result  = |\{"class":"{ lv_class }","package":"{ lv_pkg }","language":"{ lv_lang }",| &&
               |"action":"{ ls_in-action }","count":{ lv_count }\}|.

ENDFUNCTION.
