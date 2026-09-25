* Cập nhật model của SEGW project có sẵn từ EDMX rồi generate lại -
* tương đương "Import Data Model from File" (import toàn bộ) + "Generate
* Runtime Objects" trên SEGW. Class *_EXT được giữ nguyên như SEGW.
* Project trong $TMP, hoặc package thật khi có IV_TRANSPORT (request).

  DATA: lo_manager   TYPE REF TO /iwbep/if_sbdm_manager,
        lo_factory   TYPE REF TO /iwbep/if_sbdm_factory,
        lo_trans     TYPE REF TO /iwbep/cl_sbdm_transact_handlr,
        lo_project   TYPE REF TO /iwbep/if_sbdm_project,
        lo_model     TYPE REF TO /iwbep/if_sbdm_model,
        lo_importer  TYPE REF TO /iwbep/if_sb_file_importer,
        lo_fhandler  TYPE REF TO /iwbep/cl_sb_file_handler,
        lo_artifacts TYPE REF TO /iwbep/if_sb_odata_artifacts,
        lo_sync      TYPE REF TO /iwbep/cl_sbdsp_sync_ent_sets,
        lo_generator TYPE REF TO /iwbep/cl_sb_gen_generator,
        lo_strategy  TYPE REF TO /iwbep/if_sbdm_gen_strategy,
        lo_ixml      TYPE REF TO if_ixml,
        lo_sfactory  TYPE REF TO if_ixml_stream_factory,
        lo_document  TYPE REF TO if_ixml_document,
        lo_parser    TYPE REF TO if_ixml_parser,
        lo_error     TYPE REF TO cx_root,
        lt_projects  TYPE /iwbep/t_sbdm_projects,
        lt_locked    TYPE /iwbep/t_sbdm_projects,
        lt_failed    TYPE /iwbep/t_sbdm_projects,
        lt_new       TYPE /iwbep/t_sbdm_projects,
        lt_messages  TYPE /iwbep/if_sbcm_msg_object=>ty_t_object,
        lv_completed TYPE abap_bool,
        lv_project   TYPE /iwbep/sbdm_project,
        lv_package   TYPE devclass,
        lv_task      TYPE trkorr.

  CLEAR et_return.
  lv_project = to_upper( iv_project ).

  TRY.
      "--- EDMX -> iXML -> artifacts ---------------------------------------
      lo_ixml     = cl_ixml=>create( ).
      lo_sfactory = lo_ixml->create_stream_factory( ).
      lo_document = lo_ixml->create_document( ).
      lo_parser   = lo_ixml->create_parser( stream_factory = lo_sfactory
                                            istream        = lo_sfactory->create_istream_xstring( cl_abap_codepage=>convert_to( iv_edmx ) )
                                            document       = lo_document ).
      IF lo_parser->parse( ) <> 0.
        APPEND VALUE #( type = 'E' message = |Nội dung EDMX không phải XML hợp lệ.| ) TO et_return.
        RETURN.
      ENDIF.
      CREATE OBJECT lo_fhandler.
      lo_importer  = lo_fhandler->get_file_imp_instance( /iwbep/cl_sb_file_handler=>gc_command_file_import ).
      lo_artifacts = lo_importer->file_parsing( lo_document ).

      "--- mở project + khóa ----------------------------------------------
      lo_manager  = /iwbep/cl_sbdm=>get_manager( ).
      lo_factory  = /iwbep/cl_sbdm=>get_factory( ).
      lo_trans    = /iwbep/cl_sbdm_transact_handlr=>go_instance.
      lt_projects = lo_manager->find_projects( it_project_names = VALUE #( ( sign = 'I' option = 'EQ' low = lv_project ) ) ).
      IF lt_projects IS INITIAL.
        APPEND VALUE #( type = 'E' message = |Không tìm thấy SEGW project { lv_project }.| ) TO et_return.
        RETURN.
      ENDIF.
      READ TABLE lt_projects INTO lo_project INDEX 1.
      lv_package = lo_project->get_package( ).
      IF lv_package <> '$TMP' AND iv_transport IS INITIAL.
        APPEND VALUE #( type = 'E' message = |Project { lv_project } thuộc package { lv_package }, cần số TR để cập nhật.| ) TO et_return.
        RETURN.
      ENDIF.
      IF iv_transport IS NOT INITIAL.
        PERFORM tr_task USING iv_transport CHANGING lv_task.
        PERFORM record_object USING 'IWPR' lv_project lv_package iv_transport CHANGING et_return.
        IF line_exists( et_return[ type = 'E' ] ).
          RETURN.
        ENDIF.
      ENDIF.
      lo_trans->/iwbep/if_sbdm_transaction~lock_projects( EXPORTING it_projects         = lt_projects
                                                          IMPORTING et_success_projects = lt_locked
                                                                    et_failed_projects  = lt_failed
                                                                    et_new_projects     = lt_new
                                                                    et_messages         = lt_messages ).
      IF lt_failed IS NOT INITIAL.
        PERFORM sbcm_messages USING lt_messages CHANGING et_return.
        APPEND VALUE #( type = 'E' message = |Project { lv_project } đang bị khóa (có người đang mở trong SEGW?).| ) TO et_return.
        RETURN.
      ENDIF.
      lo_trans->/iwbep/if_sbdm_transaction~load_projects_deep( lt_projects ).

      "--- thay model (như CL_SB_FILE_IMPORTER~IMPORT_FILE) ----------------
      lo_model = lo_project->get_model( ).
      DATA(lt_nodes) = lo_project->/iwbep/if_sbdm_node~get_children( is_node_type = /iwbep/if_sbdm_model=>gc_node_type
                                                                     iv_node_name = lo_model->get_name( ) ).
      lo_manager->create_deletion_request( lt_nodes )->execute( ).
      lo_model = lo_factory->create_model( ).
      lo_project->insert_child( io_child = lo_model ).
      lo_fhandler->get_dm_adapter_instance( )->adapt_odata_artifacts( io_model           = lo_model
                                                                      io_odata_artifacts = lo_artifacts ).
      CREATE OBJECT lo_sync.
      lo_sync->synchronize_entity_sets( EXPORTING io_project = lo_project
                                        IMPORTING et_message = lt_messages ).
      PERFORM sbcm_messages USING lt_messages CHANGING et_return.
      lo_trans->/iwbep/if_sbdm_transaction~save( EXPORTING iv_tr       = abap_false
                                                           it_projects = lt_projects
                                                 IMPORTING et_messages = lt_messages ).
      PERFORM sbcm_messages USING lt_messages CHANGING et_return.
      COMMIT WORK AND WAIT.
      APPEND VALUE #( type = 'S' message = |Đã cập nhật model của project { lv_project }.| ) TO et_return.

      "--- generate lại -----------------------------------------------------
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
          lo_trans->/iwbep/if_sbdm_transaction~save( EXPORTING iv_tr       = abap_false
                                                               it_projects = lt_projects
                                                     IMPORTING et_messages = lt_messages ).
          COMMIT WORK AND WAIT.
          APPEND VALUE #( type = 'S' message = |Đã generate lại runtime objects cho project { lv_project }.| ) TO et_return.
        ELSE.
          APPEND VALUE #( type = 'E' message = |Generate project { lv_project } không hoàn tất.| ) TO et_return.
        ENDIF.
      ENDIF.
      lo_trans->/iwbep/if_sbdm_transaction~unlock_projects( lt_projects ).

    CATCH cx_root INTO lo_error.
      ROLLBACK WORK.
      WHILE lo_error IS BOUND.
        APPEND VALUE #( type = 'E' message = lo_error->get_text( ) ) TO et_return.
        lo_error = lo_error->previous.
      ENDWHILE.
      TRY.
          lo_trans->/iwbep/if_sbdm_transaction~unlock_projects( lt_projects ).
        CATCH cx_root.
      ENDTRY.
  ENDTRY.
