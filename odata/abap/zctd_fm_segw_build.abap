* Tạo SEGW project OData V2 từ file model EDMX, không qua màn hình SEGW.
* Làm đúng trình tự của Service Builder (/IWBEP/*SBUI*):
*   1. Create Project   (LFG_SBUI_PR_MAINCI1: create_project, set_package,
*                        reserve_project_name, project type/strategy,
*                        model + service node, make_persistent)
*   2. Import Data Model from File (CL_SB_FILE_IMPORTER~IMPORT_FILE:
*                        file_parsing -> adapt_odata_artifacts; tài liệu
*                        XML dựng từ IV_EDMX thay cho gui_upload)
*   3. Save             (IF_SBDM_TRANSACTION~SAVE)
*   4. Generate Runtime Objects (CL_SB_GEN_GENERATOR, suppress dialog,
*                        tên class/model/service theo đề xuất chuẩn,
*                        package IV_PACKAGE) - tự đăng ký model/service backend
* Dừng nếu project đã tồn tại. IV_GENERATE = space: chỉ tạo + import.
* Package thật (khác $TMP) bắt buộc IV_TRANSPORT (request): project IWPR
* và class MPC/DPC được ghi vào task của user trong TR đó.

  DATA: lo_factory   TYPE REF TO /iwbep/if_sbdm_factory,
        lo_trans     TYPE REF TO /iwbep/cl_sbdm_transact_handlr,
        lo_project   TYPE REF TO /iwbep/if_sbdm_project,
        lo_model     TYPE REF TO /iwbep/if_sbdm_model,
        lo_service   TYPE REF TO /iwbep/if_sbdm_service,
        lo_importer  TYPE REF TO /iwbep/if_sb_file_importer,
        lo_fhandler  TYPE REF TO /iwbep/cl_sb_file_handler,
        lo_adapter   TYPE REF TO /iwbep/if_sb_adapter_to_dm,
        lo_artifacts TYPE REF TO /iwbep/if_sb_odata_artifacts,
        lo_sync      TYPE REF TO /iwbep/cl_sbdsp_sync_ent_sets,
        lo_generator TYPE REF TO /iwbep/cl_sb_gen_generator,
        lo_strategy  TYPE REF TO /iwbep/if_sbdm_gen_strategy,
        lo_ixml      TYPE REF TO if_ixml,
        lo_sfactory  TYPE REF TO if_ixml_stream_factory,
        lo_istream   TYPE REF TO if_ixml_istream,
        lo_parser    TYPE REF TO if_ixml_parser,
        lo_document  TYPE REF TO if_ixml_document,
        lo_error     TYPE REF TO cx_root,
        lt_projects  TYPE /iwbep/t_sbdm_projects,
        lt_messages  TYPE /iwbep/if_sbcm_msg_object=>ty_t_object,
        lv_xml       TYPE xstring,
        lv_completed TYPE abap_bool,
        lv_project   TYPE char30,
        lv_package   TYPE devclass,
        lv_task      TYPE trkorr.

  CLEAR et_return.
  lv_project = to_upper( iv_project ).
  lv_package = COND #( WHEN iv_package IS INITIAL THEN '$TMP' ELSE to_upper( iv_package ) ).

  IF lv_project IS INITIAL OR iv_edmx IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Thiếu tên project hoặc nội dung EDMX.| ) TO et_return.
    RETURN.
  ENDIF.
  IF lv_package <> '$TMP' AND iv_transport IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Package { lv_package } cần số TR để lưu project.| ) TO et_return.
    RETURN.
  ENDIF.
  IF iv_transport IS NOT INITIAL.
    PERFORM tr_task USING iv_transport CHANGING lv_task.
  ENDIF.
  SELECT SINGLE project FROM /iwbep/i_sbd_pr WHERE project = @lv_project INTO @DATA(lv_exists).
  IF sy-subrc = 0.
    APPEND VALUE #( type = 'E' message = |SEGW project { lv_project } đã tồn tại, không tạo lại.| ) TO et_return.
    RETURN.
  ENDIF.

  TRY.
      "--- 0. EDMX -> tài liệu iXML (thay cho upload file trên GUI) -----
      lv_xml = cl_abap_codepage=>convert_to( iv_edmx ).
      lo_ixml     = cl_ixml=>create( ).
      lo_sfactory = lo_ixml->create_stream_factory( ).
      lo_document = lo_ixml->create_document( ).
      lo_istream  = lo_sfactory->create_istream_xstring( lv_xml ).
      lo_parser   = lo_ixml->create_parser( stream_factory = lo_sfactory
                                            istream        = lo_istream
                                            document       = lo_document ).
      IF lo_parser->parse( ) <> 0.
        APPEND VALUE #( type = 'E' message = |Nội dung EDMX không phải XML hợp lệ.| ) TO et_return.
        RETURN.
      ENDIF.
      CREATE OBJECT lo_fhandler.
      lo_importer  = lo_fhandler->get_file_imp_instance( /iwbep/cl_sb_file_handler=>gc_command_file_import ).
      lo_artifacts = lo_importer->file_parsing( lo_document ).
      APPEND VALUE #( type = 'S' message = |Đọc model EDMX thành công.| ) TO et_return.

      "--- 1. Create Project -------------------------------------------
      lo_factory = /iwbep/cl_sbdm=>get_factory( ).
      lo_trans   = /iwbep/cl_sbdm_transact_handlr=>go_instance.
      lo_project = lo_factory->create_project( iv_project_name        = lv_project
                                               iv_project_description = iv_description ).
      lo_project->set_package( lv_package ).
      lo_trans->/iwbep/if_sbdm_transact_handlr~reserve_project_name( lo_project ).
      lo_project->set_project_type( /iwbep/if_sbdm_project=>gc_type_mpc_dpc_v2 ).
      lo_project->set_description( iv_description ).
      lo_project->set_gen_strategy( VALUE #( plugin = '/IWBEP/GEN' strat_name = '0001' ) ).
      lo_project->set_package( lv_package ).
      lo_project->set_responsible( sy-uname ).
      lo_model = lo_factory->create_model( ).
      lo_project->insert_child( io_child = lo_model ).
      lo_service = lo_factory->create_srvc( ).
      lo_project->insert_child( io_child = lo_service ).
      INSERT lo_project INTO TABLE lt_projects.
      lo_trans->/iwbep/if_sbdm_transact_handlr~make_persistent( EXPORTING it_projects = lt_projects
                                                                          iv_tr       = abap_false
                                                                IMPORTING et_messages = lt_messages ).
      PERFORM sbcm_messages USING lt_messages CHANGING et_return.
      APPEND VALUE #( type = 'S' message = |Đã tạo SEGW project { lv_project } (package { lv_package }).| ) TO et_return.

      "--- 2. Import Data Model from File -------------------------------
      lo_adapter = lo_fhandler->get_dm_adapter_instance( ).
      lo_adapter->adapt_odata_artifacts( io_model           = lo_model
                                         io_odata_artifacts = lo_artifacts ).
      CREATE OBJECT lo_sync.
      lo_sync->synchronize_entity_sets( EXPORTING io_project = lo_project
                                        IMPORTING et_message = lt_messages ).
      PERFORM sbcm_messages USING lt_messages CHANGING et_return.

      "--- 3. Save ----------------------------------------------------------
      lo_trans->/iwbep/if_sbdm_transaction~save( EXPORTING iv_tr       = abap_false
                                                           it_projects = lt_projects
                                                 IMPORTING et_messages = lt_messages ).
      PERFORM sbcm_messages USING lt_messages CHANGING et_return.
      COMMIT WORK AND WAIT.
      APPEND VALUE #( type = 'S' message = |Đã import model vào project { lv_project }.| ) TO et_return.
      PERFORM record_object USING 'IWPR' lv_project lv_package iv_transport CHANGING et_return.
      IF line_exists( et_return[ type = 'E' ] ).
        RETURN.
      ENDIF.

      "--- 4. Generate Runtime Objects --------------------------------------
      IF iv_generate = abap_true.
        CREATE OBJECT lo_generator
          EXPORTING
            is_gen_strategy      = VALUE #( plugin = '/IWBEP/GEN' name = '0001' )
            iv_gen_strat_version = '0001'.
        lo_generator->set_suppress_dialog( abap_true ).
        lo_generator->set_tr_data( VALUE #( package = lv_package transport = lv_task request = iv_transport ) ).
        PERFORM prereg_generated USING lv_project lv_package iv_transport CHANGING et_return.
        lo_strategy = lo_generator.
        lo_strategy->generate( EXPORTING io_project   = lo_project
                               IMPORTING et_message   = lt_messages
                                         ev_completed = lv_completed ).
        PERFORM sbcm_messages USING lt_messages CHANGING et_return.
        IF lv_completed = abap_true AND NOT line_exists( et_return[ type = 'E' ] ).
          lo_project->set_gen_strategy( VALUE #( plugin = '/IWBEP/GEN' strat_name = '0001' strat_version = '0001' ) ).
          lo_trans->/iwbep/if_sbdm_transaction~save( EXPORTING iv_tr       = abap_false
                                                               it_projects = lt_projects
                                                     IMPORTING et_messages = lt_messages ).
          PERFORM sbcm_messages USING lt_messages CHANGING et_return.
          COMMIT WORK AND WAIT.
          APPEND VALUE #( type = 'S' message = |Đã generate runtime objects cho project { lv_project }.| ) TO et_return.
        ELSE.
          ROLLBACK WORK.
          APPEND VALUE #( type = 'E' message = |Generate project { lv_project } không hoàn tất.| ) TO et_return.
        ENDIF.
      ENDIF.

    CATCH cx_root INTO lo_error.
      ROLLBACK WORK.
      WHILE lo_error IS BOUND.
        APPEND VALUE #( type = 'E' message = lo_error->get_text( ) ) TO et_return.
        lo_error = lo_error->previous.
      ENDWHILE.
  ENDTRY.
