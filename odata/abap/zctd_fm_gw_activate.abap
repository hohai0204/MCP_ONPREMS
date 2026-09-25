* Kích hoạt OData service ở Gateway hub (= /IWFND/MAINT_SERVICE > Add
* Service) qua API chuẩn /IWFND/CL_MGW_ACTIVATION_API, kèm ICF node.
* Service đã active thì bỏ qua; luôn trả trạng thái ICF node.
* Package thật: IV_TRANSPORT (workbench: service group, ICF node) và
* IV_TRANSPORT_CUST (customizing: gán system alias) - client ghi TR tự động.

  DATA: lo_error  TYPE REF TO cx_root,
        lv_active TYPE abap_bool,
        lv_exists TYPE abap_bool,
        lv_icf_on TYPE abap_bool.

  CLEAR: ev_srg_identifier, et_return.
  TRY.
      DATA(lo_api) = /iwfnd/cl_mgw_activation_api=>get_instance( ).
      lo_api->is_active( EXPORTING iv_service_name    = iv_service_name
                                   iv_service_version = iv_service_version
                         IMPORTING ev_active          = lv_active ).
      IF lv_active = abap_true.
        ev_srg_identifier = |{ iv_service_name }_{ iv_service_version }|.
        APPEND VALUE #( type = 'I' message = |Service { iv_service_name } đã được kích hoạt từ trước.| ) TO et_return.
        " đăng ký service là chung mọi client, gán system alias thì theo từng client
        SELECT SINGLE system_alias FROM /iwfnd/c_mgdeam
          WHERE service_id = @ev_srg_identifier
          INTO @DATA(lv_alias).
        IF sy-subrc <> 0.
          /iwfnd/cl_cof_facade=>assign_sys_alias_to_srv( iv_srg_identifier  = ev_srg_identifier
                                                         iv_system_alias    = iv_system_alias
                                                         iv_is_default      = abap_true
                                                         iv_transport_cust  = iv_transport_cust ).
          COMMIT WORK AND WAIT.
          APPEND VALUE #( type = 'S'
                          message = |Đã gán system alias { iv_system_alias } cho service { iv_service_name } ở client { sy-mandt }.| )
            TO et_return.
        ELSE.
          APPEND VALUE #( type = 'I'
                          message = |Client { sy-mandt } đã có system alias { lv_alias } cho service { iv_service_name }.| )
            TO et_return.
        ENDIF.
      ELSE.
        lo_api->activate_service(
          EXPORTING
            iv_service_name         = iv_service_name
            iv_service_version      = iv_service_version
            iv_system_alias         = iv_system_alias
            iv_package              = iv_package
            iv_transport            = iv_transport
            iv_transport_cust       = iv_transport_cust
            iv_suppress_dialog      = abap_true
            iv_do_activate_icf_node = abap_true
          IMPORTING
            ev_srg_identifier       = ev_srg_identifier ).
        COMMIT WORK AND WAIT.
        APPEND VALUE #( type = 'S'
                        message = |Đã kích hoạt service { iv_service_name } ({ ev_srg_identifier }) tại Gateway, system alias { iv_system_alias }.| )
          TO et_return.
      ENDIF.

      lo_api->check_icf_node( EXPORTING iv_service_name_bep   = iv_service_name
                              IMPORTING ev_icf_node_exists    = lv_exists
                                        ev_icf_node_is_active = lv_icf_on ).
      APPEND VALUE #( type    = COND #( WHEN lv_icf_on = abap_true THEN 'S' ELSE 'W' )
                      message = COND #( WHEN lv_icf_on = abap_true THEN |ICF node của { iv_service_name } đã tồn tại và đang active.|
                                        WHEN lv_exists = abap_true THEN |ICF node của { iv_service_name } có nhưng chưa active (SICF).|
                                        ELSE |Chưa có ICF node cho { iv_service_name }.| ) ) TO et_return.
    CATCH cx_root INTO lo_error.
      ROLLBACK WORK.
      WHILE lo_error IS BOUND.
        APPEND VALUE #( type = 'E' message = lo_error->get_text( ) ) TO et_return.
        lo_error = lo_error->previous.
      ENDWHILE.
  ENDTRY.
