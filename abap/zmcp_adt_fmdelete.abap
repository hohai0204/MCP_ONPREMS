FUNCTION zmcp_adt_fmdelete.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_PARAMS) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  I
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RESULT) TYPE  STRING
*"----------------------------------------------------------------------
* ZMCP_ADT_FMDELETE - delete ONE function module that was written by
* mistake. FUNCTION_DELETE is not remote-enabled, so this wrapper calls it
* locally. It is deliberately narrow:
*   - name must start with Z or Y
*   - the bridge's own function modules are protected
*   - the function group must be in a local package ($TMP, $...): objects
*     in transportable packages are never deleted from here
*   - S_DEVELOP delete authorization (ACTVT 06) on the function group
* IV_PARAMS (JSON): { "function": "ZMCP_ADT_TEST_FM" }
* EV_RESULT (JSON): { "function", "function_group", "package" }
*----------------------------------------------------------------------

  DATA: BEGIN OF ls_in,
          function TYPE string,
        END OF ls_in.
  DATA: lv_fm      TYPE rs38l_fnam,
        lv_pname   TYPE tfdir-pname,
        lv_fg      TYPE tadir-obj_name,
        lv_pkg     TYPE tadir-devclass,
        lv_tmp     TYPE string.

  CLEAR: ev_subrc, ev_message, ev_result.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).
  lv_fm = to_upper( condense( ls_in-function ) ).

  IF lv_fm IS INITIAL.
    ev_subrc = 4.
    ev_message = 'No function module name given'.
    RETURN.
  ENDIF.
  IF lv_fm(1) <> 'Z' AND lv_fm(1) <> 'Y'.
    ev_subrc = 4.
    ev_message = 'Only customer function modules (Z/Y) can be deleted here'.
    RETURN.
  ENDIF.
  " exact names, so test FMs named ZMCP_ADT_TEST_* stay deletable
  IF lv_fm = 'ZMCP_ADT_DISPATCH' OR lv_fm = 'ZMCP_ADT_TEXTPOOL'
     OR lv_fm = 'ZMCP_ADT_APPLOG' OR lv_fm = 'ZMCP_ADT_GWLOG'
     OR lv_fm = 'ZMCP_ADT_FMDELETE' OR lv_fm = 'ZMCP_ADT_DDIC_TABL'
     OR lv_fm = 'ZMCP_ADT_DDIC_DTEL' OR lv_fm = 'ZMCP_ADT_DDIC_DOMA'
     OR lv_fm = 'ZMCP_ADT_DDIC_ACTIVATE' OR lv_fm = 'ZCTD_FM_GW_TEST'.
    ev_subrc = 4.
    ev_message = 'This function module belongs to the MCP bridge and is protected'.
    RETURN.
  ENDIF.

  SELECT SINGLE pname FROM tfdir WHERE funcname = @lv_fm INTO @lv_pname.
  IF sy-subrc <> 0.
    ev_subrc = 4.
    ev_message = |Function module { lv_fm } does not exist|.
    RETURN.
  ENDIF.
  " main program SAPL<group>, namespaced groups keep the /NS/ part
  lv_tmp = lv_pname.
  IF lv_tmp CS 'SAPL'.
    lv_fg = lv_tmp+4.
  ELSE.
    lv_fg = lv_tmp.
  ENDIF.

  SELECT SINGLE devclass FROM tadir
    WHERE pgmid = 'R3TR' AND object = 'FUGR' AND obj_name = @lv_fg
    INTO @lv_pkg.
  IF sy-subrc <> 0 OR lv_pkg IS INITIAL OR lv_pkg(1) <> '$'.
    ev_subrc = 4.
    ev_message = |Function group { lv_fg } is not in a local package ($TMP); | &&
                 |use SE37 and a transport for transportable objects|.
    RETURN.
  ENDIF.

  AUTHORITY-CHECK OBJECT 'S_DEVELOP'
    ID 'DEVCLASS' FIELD lv_pkg
    ID 'OBJTYPE'  FIELD 'FUGR'
    ID 'OBJNAME'  FIELD lv_fg
    ID 'P_GROUP'  DUMMY
    ID 'ACTVT'    FIELD '06'.
  IF sy-subrc <> 0.
    ev_subrc = 4.
    ev_message = |No delete authorization for function group { lv_fg }|.
    RETURN.
  ENDIF.

  CALL FUNCTION 'FUNCTION_DELETE'
    EXPORTING
      funcname                 = lv_fm
      suppress_delete_longtext = abap_true
      suppress_dele_enha       = abap_true
      suppress_success_message = abap_true
    EXCEPTIONS
      error_message            = 1
      OTHERS                   = 2.
  IF sy-subrc <> 0.
    ev_subrc = 8.
    MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO ev_message.
    IF ev_message IS INITIAL.
      ev_message = |Deleting { lv_fm } failed (subrc { sy-subrc })|.
    ENDIF.
    RETURN.
  ENDIF.
  COMMIT WORK AND WAIT.

  ev_result  = |\{"function":"{ lv_fm }","function_group":"{ lv_fg }","package":"{ lv_pkg }"\}|.
  ev_subrc   = 0.
  ev_message = |Function module { lv_fm } deleted|.

ENDFUNCTION.
