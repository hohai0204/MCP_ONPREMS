FUNCTION zmcp_adt_dispatch.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_ACTION) TYPE  STRING
*"     VALUE(IV_PARAMS) TYPE  STRING
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE  I
*"     VALUE(EV_MESSAGE) TYPE  STRING
*"     VALUE(EV_RESULT) TYPE  STRING
*"----------------------------------------------------------------------
* ZMCP_ADT_DISPATCH - JSON-based dispatcher for Screen/GUI Status ops
* Called via SOAP RFC from mcp-abap-adt MCP server.
*
* Supported actions:
*   DYNPRO_INSERT  - Create screen (RPY_DYNPRO_INSERT)
*   DYNPRO_READ    - Read screen (RPY_DYNPRO_READ)
*   DYNPRO_DELETE  - Delete screen (RPY_DYNPRO_DELETE)
*   CUA_FETCH      - Read GUI status (RS_CUA_INTERNAL_FETCH)
*   CUA_WRITE      - Write GUI status (RS_CUA_INTERNAL_WRITE)
*   CUA_DELETE      - Delete GUI status (RS_CUA_DELETE)
*----------------------------------------------------------------------

  DATA: lv_json    TYPE string,
        lv_program TYPE syrepid,
        lv_dynpro  TYPE sydynnr.

* Parse common params from JSON
  DATA(lo_params) = /ui2/cl_json=>generate( json = iv_params ).

  CLEAR: ev_subrc, ev_message, ev_result.

  TRY.
      CASE iv_action.

*------ DYNPRO (Screen) operations ------
        WHEN 'DYNPRO_INSERT'.
          PERFORM dynpro_insert USING iv_params
                                CHANGING ev_subrc ev_message ev_result.

        WHEN 'DYNPRO_READ'.
          PERFORM dynpro_read USING iv_params
                              CHANGING ev_subrc ev_message ev_result.

        WHEN 'DYNPRO_DELETE'.
          PERFORM dynpro_delete USING iv_params
                                CHANGING ev_subrc ev_message ev_result.

*------ CUA (GUI Status) operations ------
        WHEN 'CUA_FETCH'.
          PERFORM cua_fetch USING iv_params
                            CHANGING ev_subrc ev_message ev_result.

        WHEN 'CUA_WRITE'.
          PERFORM cua_write USING iv_params
                            CHANGING ev_subrc ev_message ev_result.

        WHEN 'CUA_DELETE'.
          PERFORM cua_delete USING iv_params
                             CHANGING ev_subrc ev_message ev_result.

*------ Workbench operations (syntax / activate / cds / tests) ------
        WHEN 'SYNTAX_CHECK'.
          PERFORM syntax_check USING iv_params
                               CHANGING ev_subrc ev_message ev_result.

        WHEN 'ACTIVATE'.
          PERFORM activate_objs USING iv_params
                                CHANGING ev_subrc ev_message ev_result.

        WHEN 'READ_DDLS'.
          PERFORM read_ddls USING iv_params
                            CHANGING ev_subrc ev_message ev_result.

        WHEN 'RUN_UNIT_TESTS'.
          PERFORM run_unit_tests USING iv_params
                                 CHANGING ev_subrc ev_message ev_result.

        WHEN 'ATC_CHECK'.
          PERFORM atc_check USING iv_params
                            CHANGING ev_subrc ev_message ev_result.

        WHEN 'PROGRAM_WRITE'.
          PERFORM program_write USING iv_params
                                CHANGING ev_subrc ev_message ev_result.

        WHEN OTHERS.
          ev_subrc = 4.
          ev_message = |Unknown action: { iv_action }|.
      ENDCASE.

    CATCH cx_root INTO DATA(lx_root).
      ev_subrc = 8.
      ev_message = lx_root->get_text( ).
  ENDTRY.

ENDFUNCTION.


*&---------------------------------------------------------------------*
*& Form DYNPRO_INSERT
*&---------------------------------------------------------------------*
FORM dynpro_insert USING iv_params TYPE string
                   CHANGING ev_subrc TYPE i
                            ev_message TYPE string
                            ev_result TYPE string.

  TYPES: BEGIN OF ty_flow_line,
           line TYPE string,
         END OF ty_flow_line.

  DATA: ls_header     TYPE rpy_dyhead,
        lt_containers TYPE TABLE OF rpy_dycatt,
        lt_fields     TYPE TABLE OF rpy_dyfatc,
        lt_flow_src   TYPE STANDARD TABLE OF rpy_dyflow
                        WITH DEFAULT KEY,
        lt_params     TYPE abap_trans_srcbind_tab.

* Deserialize JSON to get dynpro_data
  DATA: lv_program    TYPE string,
        lv_dynpro     TYPE string,
        lv_dynpro_data TYPE string.

  " removed unused JSON pre-parse (incompatible types on this release)

DATA: BEGIN OF ls_input,
          program     TYPE string,
          dynpro      TYPE string,
          dynpro_data TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

  lv_program = to_upper( ls_input-program ).
  lv_dynpro  = ls_input-dynpro.

* Parse dynpro_data JSON into ABAP structures
  DATA: lt_flow_logic TYPE TABLE OF ty_flow_line WITH DEFAULT KEY.

  DATA: BEGIN OF ls_dynpro_full,
          header              TYPE rpy_dyhead,
          containers          TYPE TABLE OF rpy_dycatt
                                WITH DEFAULT KEY,
          fields_to_containers TYPE TABLE OF rpy_dyfatc
                                WITH DEFAULT KEY,
          flow_logic          TYPE TABLE OF ty_flow_line
                                WITH DEFAULT KEY,
        END OF ls_dynpro_full.

  /ui2/cl_json=>deserialize(
    EXPORTING json = ls_input-dynpro_data
    CHANGING  data = ls_dynpro_full ).

  ls_header = ls_dynpro_full-header.
  lt_containers = ls_dynpro_full-containers.
  lt_fields = ls_dynpro_full-fields_to_containers.

* Build flow logic source
  DATA lt_flow TYPE STANDARD TABLE OF rpy_dyflow WITH DEFAULT KEY.
  lt_flow = VALUE #(
    FOR ls_fl IN ls_dynpro_full-flow_logic
    ( line = ls_fl-line ) ).

  CALL FUNCTION 'RPY_DYNPRO_INSERT'
    EXPORTING
      header                 = ls_header
      suppress_exist_checks  = abap_true
    TABLES
      containers             = lt_containers
      fields_to_containers   = lt_fields
      flow_logic             = lt_flow
    EXCEPTIONS
      already_exists         = 1
      cancelled              = 2
      permission_error       = 3
      name_not_allowed       = 4
      not_found              = 5
      OTHERS                 = 6.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RPY_DYNPRO_INSERT failed (sy-subrc={ sy-subrc })|.
  ELSE.
    ev_message = |Screen { lv_program }/{ lv_dynpro } created|.
    ev_result = '{}'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form DYNPRO_READ
*&---------------------------------------------------------------------*
FORM dynpro_read USING iv_params TYPE string
                 CHANGING ev_subrc TYPE i
                          ev_message TYPE string
                          ev_result TYPE string.

  DATA: BEGIN OF ls_input,
          program TYPE string,
          dynpro  TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

  DATA: ls_header   TYPE rpy_dyhead,
        lt_cont     TYPE TABLE OF rpy_dycatt,
        lt_fields   TYPE TABLE OF rpy_dyfatc,
        lt_flow     TYPE STANDARD TABLE OF rpy_dyflow WITH DEFAULT KEY.

  CALL FUNCTION 'RPY_DYNPRO_READ'
    EXPORTING
      progname             = CONV syrepid(
                                to_upper( ls_input-program ) )
      dynnr                = CONV sydynnr( ls_input-dynpro )
    IMPORTING
      header               = ls_header
    TABLES
      containers           = lt_cont
      fields_to_containers = lt_fields
      flow_logic           = lt_flow
    EXCEPTIONS
      cancelled            = 1
      not_found            = 2
      permission_error     = 3
      OTHERS               = 4.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RPY_DYNPRO_READ failed (sy-subrc={ sy-subrc })|.
  ELSE.
    DATA: BEGIN OF ls_result,
            header              TYPE rpy_dyhead,
            containers          TYPE TABLE OF rpy_dycatt
                                  WITH DEFAULT KEY,
            fields_to_containers TYPE TABLE OF rpy_dyfatc
                                  WITH DEFAULT KEY,
            flow_logic          TYPE STANDARD TABLE OF rpy_dyflow
                                  WITH DEFAULT KEY,
          END OF ls_result.
    ls_result-header = ls_header.
    ls_result-containers = lt_cont.
    ls_result-fields_to_containers = lt_fields.
    ls_result-flow_logic = lt_flow.
    ev_result = /ui2/cl_json=>serialize( data = ls_result ).
    ev_message = 'OK'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form DYNPRO_DELETE
*&---------------------------------------------------------------------*
FORM dynpro_delete USING iv_params TYPE string
                   CHANGING ev_subrc TYPE i
                            ev_message TYPE string
                            ev_result TYPE string.

  DATA: BEGIN OF ls_input,
          program TYPE string,
          dynpro  TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

  CALL FUNCTION 'RPY_DYNPRO_DELETE'
    EXPORTING
      progname       = CONV syrepid( to_upper( ls_input-program ) )
      dynnr          = CONV sydynnr( ls_input-dynpro )
    EXCEPTIONS
      cancelled      = 1
      not_found      = 2
      permission_error = 3
      OTHERS         = 4.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RPY_DYNPRO_DELETE failed (sy-subrc={ sy-subrc })|.
  ELSE.
    ev_message = |{ ls_input-program }/{ ls_input-dynpro } deleted|.
    ev_result = '{}'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form CUA_FETCH
*&---------------------------------------------------------------------*
FORM cua_fetch USING iv_params TYPE string
               CHANGING ev_subrc TYPE i
                        ev_message TYPE string
                        ev_result TYPE string.

  DATA: BEGIN OF ls_input,
          program TYPE string,
          language TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

  DATA: ls_adm    TYPE rsmpe_adm,
        lt_sta    TYPE TABLE OF rsmpe_stat,
        lt_fun    TYPE TABLE OF rsmpe_funt,
        lt_men    TYPE TABLE OF rsmpe_men,
        lt_mtx    TYPE TABLE OF rsmpe_mnlt,
        lt_act    TYPE TABLE OF rsmpe_act,
        lt_but    TYPE TABLE OF rsmpe_but,
        lt_pfk    TYPE TABLE OF rsmpe_pfk,
        lt_set    TYPE TABLE OF rsmpe_staf,
        lt_doc    TYPE TABLE OF rsmpe_atrt,
        lt_tit    TYPE TABLE OF rsmpe_tit,
        lt_biv    TYPE TABLE OF rsmpe_buts.

  DATA: lv_lang TYPE sy-langu.
  IF ls_input-language IS NOT INITIAL.
    lv_lang = ls_input-language(1).
  ELSE.
    lv_lang = sy-langu.
  ENDIF.

  CALL FUNCTION 'RS_CUA_INTERNAL_FETCH'
    EXPORTING
      program         = CONV syrepid( to_upper( ls_input-program ) )
      language        = lv_lang
      state           = 'A'
    IMPORTING
      adm             = ls_adm
    TABLES
      sta             = lt_sta
      fun             = lt_fun
      men             = lt_men
      mtx             = lt_mtx
      act             = lt_act
      but             = lt_but
      pfk             = lt_pfk
      set             = lt_set
      doc             = lt_doc
      tit             = lt_tit
      biv             = lt_biv
    EXCEPTIONS
      not_found       = 1
      unknown_version = 2
      OTHERS          = 3.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RS_CUA_INTERNAL_FETCH failed (sy-subrc={ sy-subrc })|.
  ELSE.
    DATA: BEGIN OF ls_result,
            adm TYPE rsmpe_adm,
            sta TYPE TABLE OF rsmpe_stat WITH DEFAULT KEY,
            fun TYPE TABLE OF rsmpe_funt WITH DEFAULT KEY,
            men TYPE TABLE OF rsmpe_men WITH DEFAULT KEY,
            mtx TYPE TABLE OF rsmpe_mnlt WITH DEFAULT KEY,
            act TYPE TABLE OF rsmpe_act WITH DEFAULT KEY,
            but TYPE TABLE OF rsmpe_but WITH DEFAULT KEY,
            pfk TYPE TABLE OF rsmpe_pfk WITH DEFAULT KEY,
            set TYPE TABLE OF rsmpe_staf WITH DEFAULT KEY,
            doc TYPE TABLE OF rsmpe_atrt WITH DEFAULT KEY,
            tit TYPE TABLE OF rsmpe_tit WITH DEFAULT KEY,
            biv TYPE TABLE OF rsmpe_buts WITH DEFAULT KEY,
          END OF ls_result.
    ls_result-adm = ls_adm.
    ls_result-sta = lt_sta.
    ls_result-fun = lt_fun.
    ls_result-men = lt_men.
    ls_result-mtx = lt_mtx.
    ls_result-act = lt_act.
    ls_result-but = lt_but.
    ls_result-pfk = lt_pfk.
    ls_result-set = lt_set.
    ls_result-doc = lt_doc.
    ls_result-tit = lt_tit.
    ls_result-biv = lt_biv.
    ev_result = /ui2/cl_json=>serialize( data = ls_result ).
    ev_message = 'OK'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form CUA_WRITE
*&---------------------------------------------------------------------*
FORM cua_write USING iv_params TYPE string
               CHANGING ev_subrc TYPE i
                        ev_message TYPE string
                        ev_result TYPE string.

  DATA: BEGIN OF ls_input,
          program  TYPE string,
          language TYPE string,
          cua_data TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

* Deserialize CUA data from JSON
  DATA: BEGIN OF ls_cua,
          adm TYPE rsmpe_adm,
          sta TYPE TABLE OF rsmpe_stat WITH DEFAULT KEY,
          fun TYPE TABLE OF rsmpe_funt WITH DEFAULT KEY,
          men TYPE TABLE OF rsmpe_men WITH DEFAULT KEY,
          mtx TYPE TABLE OF rsmpe_mnlt WITH DEFAULT KEY,
          act TYPE TABLE OF rsmpe_act WITH DEFAULT KEY,
          but TYPE TABLE OF rsmpe_but WITH DEFAULT KEY,
          pfk TYPE TABLE OF rsmpe_pfk WITH DEFAULT KEY,
          set TYPE TABLE OF rsmpe_staf WITH DEFAULT KEY,
          doc TYPE TABLE OF rsmpe_atrt WITH DEFAULT KEY,
          tit TYPE TABLE OF rsmpe_tit WITH DEFAULT KEY,
          biv TYPE TABLE OF rsmpe_buts WITH DEFAULT KEY,
        END OF ls_cua.

  /ui2/cl_json=>deserialize(
    EXPORTING json = ls_input-cua_data
    CHANGING  data = ls_cua ).

  DATA: lv_lang TYPE sy-langu.
  IF ls_input-language IS NOT INITIAL.
    lv_lang = ls_input-language(1).
  ELSE.
    lv_lang = sy-langu.
  ENDIF.

  CALL FUNCTION 'RS_CUA_INTERNAL_WRITE'
    EXPORTING
      program   = CONV syrepid( to_upper( ls_input-program ) )
      language  = lv_lang
      adm       = ls_cua-adm
      state     = 'A'
    TABLES
      sta       = ls_cua-sta
      fun       = ls_cua-fun
      men       = ls_cua-men
      mtx       = ls_cua-mtx
      act       = ls_cua-act
      but       = ls_cua-but
      pfk       = ls_cua-pfk
      set       = ls_cua-set
      doc       = ls_cua-doc
      tit       = ls_cua-tit
      biv       = ls_cua-biv
    EXCEPTIONS
      not_found       = 1
      unknown_version = 2
      OTHERS          = 3.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RS_CUA_INTERNAL_WRITE failed (sy-subrc={ sy-subrc })|.
  ELSE.
    ev_message = |CUA written for { ls_input-program }|.
    ev_result = '{"written":true}'.
  ENDIF.

ENDFORM.


*&---------------------------------------------------------------------*
*& Form CUA_DELETE
*&---------------------------------------------------------------------*
FORM cua_delete USING iv_params TYPE string
                CHANGING ev_subrc TYPE i
                         ev_message TYPE string
                         ev_result TYPE string.

  DATA: BEGIN OF ls_input,
          program TYPE string,
          status  TYPE string,
        END OF ls_input.

  /ui2/cl_json=>deserialize(
    EXPORTING json = iv_params
    CHANGING  data = ls_input ).

  CALL FUNCTION 'RS_CUA_DELETE'
    EXPORTING
      report     = CONV syrepid( to_upper( ls_input-program ) )
    EXCEPTIONS
      not_found  = 1
      OTHERS     = 2.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    ev_message = |RS_CUA_DELETE failed (sy-subrc={ sy-subrc })|.
  ELSE.
    ev_message = |CUA deleted for { ls_input-program }|.
    ev_result = '{"deleted":true}'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM SYNTAX_CHECK   (read-only)
*&  params: { "program": "ZTEST",
*&            "source": ["REPORT ztest.", "WRITE 1."] }
*&  result: { "ok": true }  OR
*&          { "ok": false, "message": "...", "line": 12, "word": "FOO" }
*&---------------------------------------------------------------------*
FORM syntax_check USING iv_params TYPE string
                  CHANGING ev_subrc TYPE i
                           ev_message TYPE string
                           ev_result TYPE string.

  DATA: BEGIN OF ls_in,
          program TYPE string,
          source  TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
        END OF ls_in.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  DATA: lt_src  TYPE STANDARD TABLE OF string,
        lv_mess TYPE string,
        lv_lin  TYPE i,
        lv_wrd  TYPE string,
        lv_prog TYPE syrepid.

  lt_src  = ls_in-source.
  lv_prog = to_upper( ls_in-program ).

  SYNTAX-CHECK FOR lt_src
    PROGRAM lv_prog
    MESSAGE lv_mess
    LINE    lv_lin
    WORD    lv_wrd.

  ev_subrc = sy-subrc.
  IF sy-subrc = 0.
    ev_result  = '{"ok":true}'.
    ev_message = 'Syntax OK'.
  ELSE.
    DATA: BEGIN OF ls_err,
            ok      TYPE abap_bool,
            message TYPE string,
            line    TYPE i,
            word    TYPE string,
          END OF ls_err.
    ls_err-ok      = abap_false.
    ls_err-message = lv_mess.
    ls_err-line    = lv_lin.
    ls_err-word    = lv_wrd.
    ev_result  = /ui2/cl_json=>serialize( data = ls_err ).
    ev_message = lv_mess.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ACTIVATE_OBJS   (write -> gated by SAP_ALLOW_WRITE on bridge)
*&  params: { "objects": [ {"type":"REPS","name":"ZTEST"},
*&                          {"type":"CLAS","name":"ZCL_FOO"} ] }
*&  LIMU object types: REPS=report source, CLAS=class,
*&  FUGR/FUNC=function, DYNP=screen, CUAD=gui status, TABL=table,
*&  DDLS=cds ...
*&  result: { "activated": true, "count": 2 }  OR error message
*&---------------------------------------------------------------------*
FORM activate_objs USING iv_params TYPE string
                   CHANGING ev_subrc TYPE i
                            ev_message TYPE string
                            ev_result TYPE string.

  TYPES: BEGIN OF ty_obj,
           type TYPE string,
           name TYPE string,
         END OF ty_obj.

  DATA: BEGIN OF ls_in,
          objects TYPE STANDARD TABLE OF ty_obj WITH DEFAULT KEY,
        END OF ls_in.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  DATA lt_obj TYPE STANDARD TABLE OF dwinactiv.
  DATA ls_obj TYPE dwinactiv.

  LOOP AT ls_in-objects INTO DATA(ls_req).
    CLEAR ls_obj.
    ls_obj-object   = to_upper( ls_req-type ).
    ls_obj-obj_name = to_upper( ls_req-name ).
    APPEND ls_obj TO lt_obj.
  ENDLOOP.

  IF lt_obj IS INITIAL.
    ev_subrc = 4.
    ev_message = 'No objects supplied'.
    RETURN.
  ENDIF.

  CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
    TABLES
      objects                = lt_obj
    EXCEPTIONS
      cancelled              = 1
      excecution_error       = 2
      insert_into_corr_error = 3
      OTHERS                 = 4.

  ev_subrc = sy-subrc.
  IF sy-subrc = 0.
    DATA: BEGIN OF ls_ok,
            activated TYPE abap_bool,
            count     TYPE i,
          END OF ls_ok.
    ls_ok-activated = abap_true.
    ls_ok-count     = lines( lt_obj ).
    ev_result  = /ui2/cl_json=>serialize( data = ls_ok ).
    ev_message = 'Activated'.
  ELSE.
    ev_message = |Activation failed (sy-subrc={ sy-subrc })|.
    ev_result  = '{"activated":false}'.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM READ_DDLS   (read-only) - CDS / DDL source
*&  params: { "name": "ZCDS_BP", "state": "A" }
*&          (state A active / I inactive)
*&  result: { "name": "ZCDS_BP", "source": "define view ..." }
*&---------------------------------------------------------------------*
FORM read_ddls USING iv_params TYPE string
               CHANGING ev_subrc TYPE i
                        ev_message TYPE string
                        ev_result TYPE string.

  DATA: BEGIN OF ls_in,
          name  TYPE string,
          state TYPE string,
        END OF ls_in.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  DATA: lv_name  TYPE ddddlsrc-ddlname,
        lv_state TYPE ddddlsrc-as4local,
        lv_src   TYPE string.

  lv_name  = to_upper( ls_in-name ).
  lv_state = COND #( WHEN ls_in-state = 'I' THEN 'N' ELSE 'A' ).

  SELECT SINGLE source FROM ddddlsrc
    INTO @lv_src
    WHERE ddlname  = @lv_name
      AND as4local = @lv_state.

  IF sy-subrc <> 0.
    ev_subrc = 4.
    ev_message = |DDL not found: { lv_name } (state { lv_state })|.
    RETURN.
  ENDIF.

  DATA: BEGIN OF ls_out,
          name   TYPE string,
          source TYPE string,
        END OF ls_out.
  ls_out-name   = lv_name.
  ls_out-source = lv_src.
  ev_subrc  = 0.
  ev_result = /ui2/cl_json=>serialize( data = ls_out ).
  ev_message = 'OK'.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM PROGRAM_WRITE   (write -> gated by SAP_ALLOW_WRITE on bridge)
*&  params: { "program": "ZTEST", "source": ["REPORT ztest.", "..."],
*&            "create": false }
*&  Saves INACTIVE (SAVE_INACTIVE='X'); activate separately via
*&  ACTIVATE. Exists because RPY_PROGRAM_UPDATE is not remote-enabled
*&  on some systems (verified on S4D) - this dispatcher calls it
*&  locally instead, same trick as BAPI_PRICES_CONDITIONS being
*&  called locally by report code. RPY_PROGRAM_INSERT (create=true)
*&  IS remote-enabled on S4D, so "create" mainly matters for
*&  brand-new programs; update is the common case this FORM exists
*&  for.
*&  result: { "program": "ZTEST", "action": "updated" }
*&---------------------------------------------------------------------*
FORM program_write USING iv_params TYPE string
                   CHANGING ev_subrc TYPE i
                            ev_message TYPE string
                            ev_result TYPE string.

  DATA: BEGIN OF ls_in,
          program TYPE string,
          source  TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
          create  TYPE abap_bool,
        END OF ls_in.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  DATA: lt_src  TYPE STANDARD TABLE OF string,
        lv_prog TYPE syrepid.

  lt_src  = ls_in-source.
  lv_prog = to_upper( ls_in-program ).

  IF ls_in-create = abap_true.
    CALL FUNCTION 'RPY_PROGRAM_INSERT'
      EXPORTING
        program_name       = lv_prog
        save_inactive      = 'X'
        program_type       = '1'
      TABLES
        source             = lt_src
      EXCEPTIONS
        already_exists     = 1
        cancelled          = 2
        name_not_allowed   = 3
        permission_error   = 4
        OTHERS             = 5.
  ELSE.
    CALL FUNCTION 'RPY_PROGRAM_UPDATE'
      EXPORTING
        program_name       = lv_prog
        save_inactive      = 'X'
      TABLES
        source             = lt_src
      EXCEPTIONS
        cancelled          = 1
        permission_error   = 2
        not_found          = 3
        OTHERS             = 4.
  ENDIF.

  ev_subrc = sy-subrc.
  IF sy-subrc <> 0.
    DATA(lv_verb) = COND string( WHEN ls_in-create = abap_true
                                  THEN 'RPY_PROGRAM_INSERT'
                                  ELSE 'RPY_PROGRAM_UPDATE' ).
    ev_message = |{ lv_verb } failed (sy-subrc={ sy-subrc })|.
  ELSE.
    DATA: BEGIN OF ls_ok,
            program TYPE string,
            action  TYPE string,
          END OF ls_ok.
    ls_ok-program = lv_prog.
    ls_ok-action  = COND string( WHEN ls_in-create = abap_true
                                  THEN 'created' ELSE 'updated' ).
    ev_result  = /ui2/cl_json=>serialize( data = ls_ok ).
    ev_message = |Saved inactive: { lv_prog }|.
  ENDIF.

ENDFORM.

*  NOTE: Text elements are handled by the dedicated FM
*  ZMCP_ADT_TEXTPOOL (actions READ / WRITE / WRITE_INACTIVE) - just
*  flag it Remote-Enabled in SE37. The bridge calls it directly, so
*  no textpool FORM is needed here.

*&---------------------------------------------------------------------*
*& FORM RUN_UNIT_TESTS   (read-only: executes ABAP Unit, changes
*&  nothing)
*&  params: { "class": "ZCL_FOO" }
*&  result: { "class":"ZCL_FOO", "failures":[ "<alert text>", ... ],
*&            "failure_count": 0, "ok": true }
*&
*&  NOTE: CL_AUCV_TEST_RUNNER_STANDARD's API differs across releases -
*&  on S4D (verified 2026-09-22) CREATE requires I_PASSPORT and there
*&  is no GET_PROGSET_FROM_OBJECTS/RUN_FOR_PROGRAM_SET; the runner
*&  instead exposes RUN_FOR_PROGRAM_KEYS/RUN_FOR_TEST_CLASS_HANDLES.
*&  Not ported - stubbed until that API is mapped for this release.
*&---------------------------------------------------------------------*
FORM run_unit_tests USING iv_params TYPE string
                    CHANGING ev_subrc TYPE i
                             ev_message TYPE string
                             ev_result TYPE string.

  DATA: BEGIN OF ls_in,
          class TYPE string,
        END OF ls_in.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  ev_subrc = 4.
  ev_message = |RUN_UNIT_TESTS not implemented: | &&
               |CL_AUCV_TEST_RUNNER_STANDARD API on this release | &&
               |needs I_PASSPORT + program_keys/test_class_handles|.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM ATC_CHECK   (read-only: runs checks, changes nothing durable)
*&  params: { "object_type": "CLAS", "object_name": "ZCL_FOO",
*&            "variant": "DEFAULT" }
*&  result: { "findings":[ {"objtype":..,"objname":..,"test":..,
*&              "code":..,"kind":"E|W|N","line":..,"text":..} ],
*&            "finding_count": n, "variant": "..." }
*&
*&  Implementation: Code Inspector engine (CL_CI_*) - the same check
*&  engine ATC runs on, with a release-stable API (pattern proven by
*&  abapGit's code inspector integration). "variant" is an SCI
*&  GLOBAL check variant (SCI > Goto > Check Variants); DEFAULT
*&  normally exists.
*&  A transient inspection is created, run locally, read, then deleted.
*&  [Unverified on DS4 - syntax-check on paste; if CL_CI_* signatures
*&  differ on your release, adjust per SE24.]
*&---------------------------------------------------------------------*
FORM atc_check USING iv_params TYPE string
               CHANGING ev_subrc TYPE i
                        ev_message TYPE string
                        ev_result TYPE string.

  DATA: BEGIN OF ls_in,
          object_type TYPE string,
          object_name TYPE string,
          variant     TYPE string,
        END OF ls_in.

  DATA: lt_objs      TYPE scit_objs,
        ls_obj       TYPE scir_objs,
        lo_set       TYPE REF TO cl_ci_objectset,
        lo_variant   TYPE REF TO cl_ci_checkvariant,
        lo_insp      TYPE REF TO cl_ci_inspection,
        lt_list      TYPE scit_alvlist,
        lv_run_name  TYPE sci_insp,
        lv_variant   TYPE sci_chkv.

  TYPES: BEGIN OF ty_finding,
           objtype TYPE string,
           objname TYPE string,
           test    TYPE string,
           code    TYPE string,
           kind    TYPE string,
           line    TYPE i,
           text    TYPE string,
         END OF ty_finding.
  DATA: lt_findings TYPE STANDARD TABLE OF ty_finding WITH DEFAULT KEY,
        ls_finding  TYPE ty_finding.

  DATA: BEGIN OF ls_out,
          findings      LIKE lt_findings,
          finding_count TYPE i,
          variant       TYPE string,
        END OF ls_out.

  /ui2/cl_json=>deserialize( EXPORTING json = iv_params
                             CHANGING  data = ls_in ).

  IF ls_in-object_name IS INITIAL OR ls_in-object_type IS INITIAL.
    ev_subrc   = 4.
    ev_message = 'object_type and object_name are required'.
    RETURN.
  ENDIF.

  lv_variant = ls_in-variant.
  IF lv_variant IS INITIAL.
    lv_variant = 'DEFAULT'.
  ENDIF.
  lv_variant = to_upper( lv_variant ).

  " 1. object set (transient, from the single requested object)
  ls_obj-objtype = to_upper( ls_in-object_type ).
  ls_obj-objname = to_upper( ls_in-object_name ).
  APPEND ls_obj TO lt_objs.

  cl_ci_objectset=>save_from_list(
    EXPORTING p_objects = lt_objs
    RECEIVING p_ref     = lo_set ).

  " 2. global check variant
  cl_ci_checkvariant=>get_ref(
    EXPORTING
      p_user          = ''
      p_name          = lv_variant
    RECEIVING
      p_ref           = lo_variant
    EXCEPTIONS
      chkv_not_exists = 1
      missing_parameter = 2
      OTHERS          = 3 ).
  IF sy-subrc <> 0.
    ev_subrc   = sy-subrc.
    ev_message = |Check variant { lv_variant } not found (global SCI)|.
    RETURN.
  ENDIF.

  " 3. transient inspection: create -> set -> save -> run local
  lv_run_name = |ZMCP{ sy-uname(8) }|.
  cl_ci_inspection=>create(
    EXPORTING
      p_user           = sy-uname
      p_name           = lv_run_name
    RECEIVING
      p_ref            = lo_insp
    EXCEPTIONS
      locked           = 1
      error_in_enqueue = 2
      not_authorized   = 3
      OTHERS           = 4 ).
  IF sy-subrc <> 0.
    ev_subrc   = sy-subrc.
    ev_message = |cl_ci_inspection create failed (subrc={ sy-subrc })|.
    RETURN.
  ENDIF.

  lo_insp->set(
    p_chkv = lo_variant
    p_objs = lo_set ).

  lo_insp->save(
    EXCEPTIONS
      missing_information = 1
      insp_no_name        = 2
      not_enqueued        = 3
      OTHERS              = 4 ).
  IF sy-subrc <> 0.
    ev_subrc   = sy-subrc.
    ev_message = |inspection save failed (sy-subrc={ sy-subrc })|.
    RETURN.
  ENDIF.

  lo_insp->run(
    EXPORTING
      p_howtorun            = 'L'   " local, synchronous
    EXCEPTIONS
      invalid_check_version = 1
      OTHERS                = 2 ).
  IF sy-subrc <> 0.
    ev_subrc   = sy-subrc.
    ev_message = |inspection run failed (sy-subrc={ sy-subrc })|.
  ELSE.
    " 4. collect findings
    lo_insp->plain_list( IMPORTING p_list = lt_list ).

    LOOP AT lt_list ASSIGNING FIELD-SYMBOL(<ls_list>).
      CLEAR ls_finding.
      ls_finding-objtype = <ls_list>-objtype.
      ls_finding-objname = <ls_list>-objname.
      ls_finding-test    = <ls_list>-test.
      ls_finding-code    = <ls_list>-code.
      ls_finding-kind    = <ls_list>-kind.
      ls_finding-line    = <ls_list>-line.
      ls_finding-text    = <ls_list>-text.
      APPEND ls_finding TO lt_findings.
    ENDLOOP.

    ls_out-findings      = lt_findings.
    ls_out-finding_count = lines( lt_findings ).
    ls_out-variant       = lv_variant.

    ev_subrc   = 0.
    ev_message = |{ ls_out-finding_count } finding(s) ({ lv_variant })|.
    ev_result  = /ui2/cl_json=>serialize( data = ls_out ).
  ENDIF.

  " 5. cleanup transient artifacts (best effort)
  TRY.
      lo_insp->delete( EXCEPTIONS OTHERS = 1 ).
      lo_set->delete( EXCEPTIONS OTHERS = 1 ).
    CATCH cx_root.                                     "#EC NO_HANDLER
  ENDTRY.

ENDFORM.
