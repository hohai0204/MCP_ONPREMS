*@LOCALS_IMP
*----------------------------------------------------------------------*
* Luồng tích hợp CTD Core - OData ZCTD_CORE_INT_SRV
*   lcl_api    : dùng chung - log mọi lần gọi vào ZCTD_T_API_LOG, trả
*                header correlation-id, chuyển $filter + tham số URL -> ZCTD_S_INT_FILTER,
*                báo lỗi nghiệp vụ
*   lcl_vendor : nhà cung cấp (ZCTD_FM_INT_VENDOR_GET, ZCTD_FM_CREATE_BP)
*   lcl_purreq : yêu cầu mua hàng (ZCTD_FM_INT_PR_GET)
* Thêm đối tượng mới:
*   1. entity trong odata/core_int/build_edmx.py -> ZCTD_FM_SEGW_UPDATE (có TR)
*   2. structure ZCTD_S_INT_<OBJ> + FM ZCTD_FM_INT_<OBJ>_GET trong FG
*      ZCTD_FG_CORE_INT (cùng interface IV_TOP/IV_SKIP/IT_FILTER)
*   3. local class lcl_<obj> theo mẫu lcl_vendor + redefine
*      <SET>_GET_ENTITY / _GET_ENTITYSET theo mẫu bên dưới
*----------------------------------------------------------------------*
CLASS lcl_api DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES ty_t_filter TYPE STANDARD TABLE OF zctd_s_int_filter WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING io_runtime TYPE REF TO /iwbep/if_mgw_conv_srv_runtime
                ir_request TYPE REF TO /iwbep/if_mgw_core_srv_runtime=>ty_s_mgw_request_context
                iv_object  TYPE csequence
                iv_method  TYPE csequence DEFAULT `GET`
                iv_body    TYPE string OPTIONAL.
    "! ghi log thành công, is_data = dữ liệu trả về
    METHODS success
      IMPORTING is_data    TYPE any
                iv_message TYPE string DEFAULT `Success`
                iv_http    TYPE csequence DEFAULT '200'.
    "! ghi log lỗi nghiệp vụ
    METHODS failure
      IMPORTING ix_error TYPE REF TO /iwbep/cx_mgw_busi_exception.
    "! $filter (select options) + tham số URL tùy biến (vd ?Plant=2100&Material=A,B)
    "! -> điều kiện lọc cho FM ZCTD_FM_INT_*_GET. Tham số URL dùng cho field không
    "! nằm trong entity (vd field của dòng PR khi đọc PurchaseReqSet).
    CLASS-METHODS filters
      IMPORTING it_select        TYPE /iwbep/t_mgw_select_option
                iv_filter_string TYPE string OPTIONAL
                ir_request       TYPE REF TO /iwbep/if_mgw_core_srv_runtime=>ty_s_mgw_request_context OPTIONAL
      RETURNING VALUE(rt_filter) TYPE ty_t_filter
      RAISING   /iwbep/cx_mgw_busi_exception.
    "! lỗi (E/A) trong ET_RETURN của FM -> HTTP 400
    CLASS-METHODS check_return
      IMPORTING it_return TYPE bapiret2_t
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS raise_error
      IMPORTING iv_message   TYPE string
                iv_not_found TYPE abap_bool DEFAULT abap_false
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS key_value
      IMPORTING it_key_tab      TYPE /iwbep/t_mgw_name_value_pair
                iv_name         TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.
  PRIVATE SECTION.
    DATA: mv_corr_id TYPE string,
          mv_date    TYPE d,
          mv_time    TYPE t,
          mv_tstmp   TYPE timestampl,
          mv_t0      TYPE i,
          mv_object  TYPE string,
          mv_method  TYPE string,
          mv_url     TYPE string,
          mv_request TYPE string.
    METHODS write
      IMPORTING iv_status   TYPE string
                iv_message  TYPE string
                iv_http     TYPE csequence
                iv_response TYPE string.
    CLASS-METHODS json_value
      IMPORTING iv_name        TYPE csequence
                iv_value       TYPE csequence
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.

CLASS lcl_api IMPLEMENTATION.
  METHOD constructor.
    DATA: lt_keys   TYPE string_table,
          lt_params TYPE string_table,
          lt_query  TYPE string_table.

    mv_date   = sy-datum.
    mv_time   = sy-uzeit.
    GET TIME STAMP FIELD mv_tstmp.
    GET RUN TIME FIELD mv_t0.
    mv_object = iv_object.
    mv_method = iv_method.
    TRY.
        mv_corr_id = to_lower( cl_system_uuid=>create_uuid_c36_static( ) ).
      CATCH cx_uuid_error.
    ENDTRY.

    IF ir_request IS BOUND.
      LOOP AT ir_request->key_tab INTO DATA(ls_key).
        APPEND |{ ls_key-name }='{ ls_key-value }'| TO lt_keys.
      ENDLOOP.
      LOOP AT ir_request->t_uri_query_parameter INTO DATA(ls_param).
        APPEND |{ ls_param-name }={ ls_param-value }| TO lt_query.
        APPEND json_value( iv_name = ls_param-name iv_value = ls_param-value ) TO lt_params.
      ENDLOOP.
      mv_url = |/sap/opu/odata/sap/{ ir_request->technical_request-service_name }/{ iv_object }|.
      IF lt_keys IS NOT INITIAL.
        mv_url = |{ mv_url }({ concat_lines_of( table = lt_keys sep = `,` ) })|.
      ENDIF.
      IF lt_query IS NOT INITIAL.
        mv_url = |{ mv_url }?{ concat_lines_of( table = lt_query sep = `&` ) }|.
      ENDIF.
      mv_request = |\{{ json_value( iv_name = `method` iv_value = iv_method ) },|
                && |{ json_value( iv_name = `entitySet` iv_value = iv_object ) },|
                && |{ json_value( iv_name = `keys` iv_value = concat_lines_of( table = lt_keys sep = `,` ) ) },|
                && |{ json_value( iv_name = `filter` iv_value = ir_request->technical_request-filter_string ) },|
                && |"parameters":\{{ concat_lines_of( table = lt_params sep = `,` ) }\},|
                && |"body":{ COND #( WHEN iv_body IS INITIAL THEN `null` ELSE iv_body ) }\}|.
    ENDIF.

    TRY.
        io_runtime->set_header( VALUE #( name = 'correlation-id' value = mv_corr_id ) ).
      CATCH cx_root ##CATCH_ALL.
    ENDTRY.
  ENDMETHOD.

  METHOD success.
    DATA lv_response TYPE string.

    TRY.
        lv_response = /ui2/cl_json=>serialize( data        = is_data
                                               compress    = abap_true
                                               pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
      CATCH cx_root ##CATCH_ALL.
    ENDTRY.
    write( iv_status = `S` iv_message = iv_message iv_http = iv_http iv_response = lv_response ).
  ENDMETHOD.

  METHOD failure.
    DATA(lv_message) = COND string( WHEN ix_error->message_unlimited IS NOT INITIAL
                                    THEN ix_error->message_unlimited ELSE ix_error->get_text( ) ).
    write( iv_status   = `E`
           iv_message  = lv_message
           iv_http     = COND string( WHEN ix_error->http_status_code IS INITIAL THEN `400`
                                      ELSE |{ ix_error->http_status_code }| )
           iv_response = |\{{ json_value( iv_name = `error` iv_value = lv_message ) }\}| ).
  ENDMETHOD.

  METHOD write.
    DATA lv_t1 TYPE i.

    GET RUN TIME FIELD lv_t1.
    TRY.
        CALL FUNCTION 'ZCTD_FM_API_LOG_WRITE'
          EXPORTING
            is_log = VALUE zctd_t_api_log( corr_id     = mv_corr_id
                                           call_date   = mv_date
                                           call_time   = mv_time
                                           call_tstmp  = mv_tstmp
                                           object_type = mv_object
                                           http_method = mv_method
                                           api_url     = mv_url
                                           duration_ms = ( lv_t1 - mv_t0 ) / 1000
                                           call_user   = sy-uname
                                           http_status = iv_http
                                           resp_status = iv_status
                                           message     = iv_message
                                           request     = mv_request
                                           response    = iv_response ).
      CATCH cx_root ##CATCH_ALL.
        " lỗi ghi log không được làm hỏng response của API
    ENDTRY.
  ENDMETHOD.

  METHOD filters.
    IF it_select IS INITIAL AND iv_filter_string IS NOT INITIAL.
      raise_error( |Biểu thức lọc chưa được hỗ trợ: { iv_filter_string }. Hãy dùng eq, ne, gt, ge, lt, le, substringof, startswith, nối bằng and.| ).
    ENDIF.
    LOOP AT it_select INTO DATA(ls_select).
      LOOP AT ls_select-select_options INTO DATA(ls_option).
        APPEND VALUE #( property = ls_select-property sign = ls_option-sign option = ls_option-option
                        low = ls_option-low high = ls_option-high ) TO rt_filter.
      ENDLOOP.
    ENDLOOP.

    CHECK ir_request IS BOUND.
    DATA lt_values TYPE string_table.
    LOOP AT ir_request->t_uri_query_parameter INTO DATA(ls_param).
      DATA(lv_name) = to_upper( ls_param-name ).
      CHECK lv_name IS NOT INITIAL AND lv_name(1) <> '$' AND lv_name NP 'SAP-*' AND lv_name <> `TESTRUN`.
      SPLIT ls_param-value AT ',' INTO TABLE lt_values.
      LOOP AT lt_values INTO DATA(lv_value).
        lv_value = condense( lv_value ).
        CHECK lv_value IS NOT INITIAL.
        APPEND VALUE #( property = ls_param-name sign = 'I'
                        option = COND #( WHEN lv_value CA '*' THEN 'CP' ELSE 'EQ' ) low = lv_value ) TO rt_filter.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_return.
    DATA lt_text TYPE string_table.

    LOOP AT it_return INTO DATA(ls_return) WHERE type CA 'EAX'.
      APPEND CONV string( ls_return-message ) TO lt_text.
    ENDLOOP.
    IF lt_text IS NOT INITIAL.
      raise_error( concat_lines_of( table = lt_text sep = ` ` ) ).
    ENDIF.
  ENDMETHOD.

  METHOD raise_error.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid            = /iwbep/cx_mgw_busi_exception=>business_error_unlimited
        message_unlimited = iv_message
        http_status_code  = COND #( WHEN iv_not_found = abap_true
                                    THEN /iwbep/cx_mgw_busi_exception=>gcs_http_status_codes-not_found
                                    ELSE /iwbep/cx_mgw_busi_exception=>gcs_http_status_codes-bad_request ).
  ENDMETHOD.

  METHOD key_value.
    rv_value = VALUE #( it_key_tab[ name = iv_name ]-value OPTIONAL ).
  ENDMETHOD.

  METHOD json_value.
    rv_json = |"{ iv_name }":"{ escape( val = condense( CONV string( iv_value ) ) format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Nhà cung cấp
*----------------------------------------------------------------------*
CLASS lcl_vendor DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES ty_t_vendor TYPE STANDARD TABLE OF zcl_zctd_core_int_mpc=>ts_vendor WITH DEFAULT KEY.
    CLASS-METHODS get_list
      IMPORTING it_filter TYPE lcl_api=>ty_t_filter
                iv_top    TYPE i DEFAULT 0
                iv_skip   TYPE i DEFAULT 0
      EXPORTING et_vendor TYPE zcl_zctd_core_int_mpc=>tt_vendor
                ev_total  TYPE i
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS get_one
      IMPORTING iv_supplier      TYPE csequence
      RETURNING VALUE(rs_vendor) TYPE zcl_zctd_core_int_mpc=>ts_vendor
      RAISING   /iwbep/cx_mgw_busi_exception.
    "! tạo BP + nhà cung cấp bằng ZCTD_FM_CREATE_BP; iv_testrun = chỉ kiểm tra
    CLASS-METHODS create
      IMPORTING is_vendor  TYPE zcl_zctd_core_int_mpc=>ts_vendor
                iv_testrun TYPE abap_bool
      EXPORTING es_vendor  TYPE zcl_zctd_core_int_mpc=>ts_vendor
                et_return  TYPE bapiret2_t
      RAISING   /iwbep/cx_mgw_busi_exception.
ENDCLASS.

CLASS lcl_vendor IMPLEMENTATION.
  METHOD get_list.
    DATA: lt_vendor TYPE STANDARD TABLE OF zctd_s_int_vendor,
          lt_return TYPE bapiret2_t.

    DATA(lt_filter) = it_filter.
    CALL FUNCTION 'ZCTD_FM_INT_VENDOR_GET'
      EXPORTING
        iv_top    = iv_top
        iv_skip   = iv_skip
      IMPORTING
        ev_total  = ev_total
        et_return = lt_return
      TABLES
        it_filter = lt_filter
        et_vendor = lt_vendor.
    lcl_api=>check_return( lt_return ).
    et_vendor = CORRESPONDING #( lt_vendor ).
  ENDMETHOD.

  METHOD get_one.
    DATA lt_vendor TYPE ty_t_vendor.

    get_list( EXPORTING it_filter = VALUE #( ( property = 'Supplier' sign = 'I' option = 'EQ' low = iv_supplier ) )
                        iv_top    = 1
              IMPORTING et_vendor = lt_vendor ).
    IF lt_vendor IS INITIAL.
      lcl_api=>raise_error( iv_message = |Không tìm thấy nhà cung cấp { iv_supplier }.| iv_not_found = abap_true ).
    ENDIF.
    rs_vendor = lt_vendor[ 1 ].
  ENDMETHOD.

  METHOD create.
    DATA: ls_supplier TYPE zctd_s_bp_supplier,
          lv_partner  TYPE bu_partner,
          lv_lifnr    TYPE lifnr.

    CLEAR: es_vendor, et_return.
    ls_supplier = VALUE #( bu_group    = is_vendor-bpgrouping
                           name1       = is_vendor-name1
                           searchterm1 = is_vendor-searchterm
                           street      = is_vendor-street
                           city        = is_vendor-city
                           postl_cod1  = is_vendor-postalcode
                           region      = to_upper( is_vendor-region )
                           country     = to_upper( is_vendor-country )
                           telephone   = is_vendor-telephone
                           e_mail      = is_vendor-email ).
    IF is_vendor-language IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_ISOLA_INPUT'
        EXPORTING
          input            = to_upper( is_vendor-language )
        IMPORTING
          output           = ls_supplier-langu
        EXCEPTIONS
          unknown_language = 1
          OTHERS           = 2.
      IF sy-subrc <> 0.
        lcl_api=>raise_error( |Mã ngôn ngữ { is_vendor-language } không hợp lệ.| ).
      ENDIF.
    ENDIF.

    CALL FUNCTION 'ZCTD_FM_CREATE_BP'
      EXPORTING
        is_supplier = ls_supplier
        iv_testrun  = iv_testrun
      IMPORTING
        ev_partner  = lv_partner
        ev_supplier = lv_lifnr
        et_return   = et_return.
    lcl_api=>check_return( et_return ).

    IF iv_testrun = abap_true OR lv_lifnr IS INITIAL.
      es_vendor = is_vendor.
      es_vendor-businesspartner = lv_partner.
    ELSE.
      es_vendor = get_one( lv_lifnr ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Yêu cầu mua hàng (Purchase Requisition)
*----------------------------------------------------------------------*
CLASS lcl_purreq DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: ty_t_header TYPE STANDARD TABLE OF zcl_zctd_core_int_mpc=>ts_purchasereq WITH DEFAULT KEY,
           ty_t_item   TYPE STANDARD TABLE OF zcl_zctd_core_int_mpc=>ts_purchasereqitem WITH DEFAULT KEY,
           BEGIN OF ty_s_expanded.
             INCLUDE TYPE zcl_zctd_core_int_mpc=>ts_purchasereq.
    TYPES:   items TYPE ty_t_item,
           END OF ty_s_expanded,
           ty_t_expanded TYPE STANDARD TABLE OF ty_s_expanded WITH DEFAULT KEY.

    CLASS-METHODS get_list
      IMPORTING it_filter     TYPE lcl_api=>ty_t_filter
                iv_top        TYPE i DEFAULT 0
                iv_skip       TYPE i DEFAULT 0
                iv_with_items TYPE abap_bool DEFAULT abap_false
      EXPORTING et_header     TYPE zcl_zctd_core_int_mpc=>tt_purchasereq
                et_item       TYPE zcl_zctd_core_int_mpc=>tt_purchasereqitem
                ev_total      TYPE i
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS get_one
      IMPORTING iv_prnumber   TYPE csequence
                iv_with_items TYPE abap_bool DEFAULT abap_false
      EXPORTING es_header     TYPE zcl_zctd_core_int_mpc=>ts_purchasereq
                et_item       TYPE zcl_zctd_core_int_mpc=>tt_purchasereqitem
      RAISING   /iwbep/cx_mgw_busi_exception.
    "! header kèm thẻ Items ($expand=Items)
    CLASS-METHODS expand
      IMPORTING it_header          TYPE ty_t_header
                it_item            TYPE ty_t_item
      RETURNING VALUE(rt_expanded) TYPE ty_t_expanded.
ENDCLASS.

CLASS lcl_purreq IMPLEMENTATION.
  METHOD get_list.
    DATA: lt_header TYPE STANDARD TABLE OF zctd_s_int_pr_hdr,
          lt_item   TYPE STANDARD TABLE OF zctd_s_int_pr_itm,
          lt_return TYPE bapiret2_t.

    DATA(lt_filter) = it_filter.
    CALL FUNCTION 'ZCTD_FM_INT_PR_GET'
      EXPORTING
        iv_top        = iv_top
        iv_skip       = iv_skip
        iv_with_items = iv_with_items
      IMPORTING
        ev_total      = ev_total
        et_return     = lt_return
      TABLES
        it_filter     = lt_filter
        et_header     = lt_header
        et_item       = lt_item.
    lcl_api=>check_return( lt_return ).
    et_header = CORRESPONDING #( lt_header ).
    et_item   = CORRESPONDING #( lt_item ).
  ENDMETHOD.

  METHOD get_one.
    DATA lt_header TYPE ty_t_header.

    get_list( EXPORTING it_filter     = VALUE #( ( property = 'PRNumber' sign = 'I' option = 'EQ' low = iv_prnumber ) )
                        iv_top        = 1
                        iv_with_items = iv_with_items
              IMPORTING et_header     = lt_header
                        et_item       = et_item ).
    IF lt_header IS INITIAL.
      lcl_api=>raise_error( iv_message = |Không tìm thấy yêu cầu mua hàng { iv_prnumber }.| iv_not_found = abap_true ).
    ENDIF.
    es_header = lt_header[ 1 ].
  ENDMETHOD.

  METHOD expand.
    LOOP AT it_header INTO DATA(ls_header).
      APPEND CORRESPONDING #( ls_header ) TO rt_expanded ASSIGNING FIELD-SYMBOL(<ls_expanded>).
      <ls_expanded>-items = VALUE #( FOR i IN it_item WHERE ( prnumber = ls_header-prnumber ) ( i ) ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
*@END_LOCALS
METHOD vendorset_get_entityset.
* GET /VendorSet[?$filter=Country eq 'VN' and ...][&$top=..&$skip=..][&$inlinecount=allpages]
    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        lcl_vendor=>get_list( EXPORTING it_filter = lcl_api=>filters( it_select        = it_filter_select_options
                                                                      iv_filter_string = iv_filter_string
                                                                      ir_request       = mr_request_details )
                                        iv_top    = is_paging-top
                                        iv_skip   = is_paging-skip
                              IMPORTING et_vendor = et_entityset
                                        ev_total  = DATA(lv_total) ).
        IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
          es_response_context-inlinecount = lv_total.
        ENDIF.
        lo_api->success( et_entityset ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD vendorset_get_entity.
* GET /VendorSet('100023')
    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        er_entity = lcl_vendor=>get_one( lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'Supplier' ) ).
        lo_api->success( er_entity ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD vendorset_create_entity.
* POST /VendorSet[?TestRun=X]  body: Name1, Country (bắt buộc), BPGrouping, SearchTerm,
*      Street, City, PostalCode, Region, Language (ISO, vd VI/EN), Telephone, Email
* TestRun=X: chỉ kiểm tra, không lưu. Message kết quả trả ở header sap-message.
    DATA: ls_input   TYPE zcl_zctd_core_int_mpc=>ts_vendor,
          lt_return  TYPE bapiret2_t,
          lv_testrun TYPE abap_bool.

    io_data_provider->read_entry_data( IMPORTING es_data = ls_input ).
    DATA(lo_api) = NEW lcl_api( io_runtime = me
                                ir_request = mr_request_details
                                iv_object  = iv_entity_set_name
                                iv_method  = `POST`
                                iv_body    = /ui2/cl_json=>serialize( data        = ls_input
                                                                      compress    = abap_true
                                                                      pretty_name = /ui2/cl_json=>pretty_mode-camel_case ) ).
    IF mr_request_details IS BOUND.
      LOOP AT mr_request_details->t_uri_query_parameter INTO DATA(ls_param) WHERE value IS NOT INITIAL.
        IF to_upper( ls_param-name ) = `TESTRUN`.
          lv_testrun = xsdbool( to_upper( ls_param-value ) = `X` OR to_upper( ls_param-value ) = `TRUE` ).
        ENDIF.
      ENDLOOP.
    ENDIF.

    TRY.
        lcl_vendor=>create( EXPORTING is_vendor  = ls_input
                                      iv_testrun = lv_testrun
                            IMPORTING es_vendor  = er_entity
                                      et_return  = lt_return ).
        DELETE lt_return WHERE type <> 'S'.
        mo_context->get_message_container( )->add_messages_from_bapi(
          it_bapi_messages          = lt_return
          iv_add_to_response_header = abap_true ).
        lo_api->success( is_data    = er_entity
                         iv_message = COND #( WHEN lt_return IS NOT INITIAL
                                              THEN CONV string( lt_return[ lines( lt_return ) ]-message ) ELSE `Success` )
                         iv_http    = '201' ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD purchasereqset_get_entityset.
* GET /PurchaseReqSet[?$filter=PRType eq 'ZPR2' and Plant eq '2100' ...][&$top=..&$skip=..]
    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        lcl_purreq=>get_list( EXPORTING it_filter = lcl_api=>filters( it_select        = it_filter_select_options
                                                                      iv_filter_string = iv_filter_string
                                                                      ir_request       = mr_request_details )
                                        iv_top    = is_paging-top
                                        iv_skip   = is_paging-skip
                              IMPORTING et_header = et_entityset
                                        ev_total  = DATA(lv_total) ).
        IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
          es_response_context-inlinecount = lv_total.
        ENDIF.
        lo_api->success( et_entityset ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD purchasereqset_get_entity.
* GET /PurchaseReqSet('3100003115')
    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        lcl_purreq=>get_one( EXPORTING iv_prnumber = lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'PRNumber' )
                             IMPORTING es_header   = er_entity ).
        lo_api->success( er_entity ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD purchasereqitems_get_entityset.
* GET /PurchaseReqSet('3100003115')/Items  - các dòng của 1 PR
* GET /PurchaseReqItemSet?$filter=...       - dòng của các PR thỏa điều kiện (phân trang theo dòng)
    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        DATA(lv_prnumber) = lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'PRNumber' ).
        IF lv_prnumber IS NOT INITIAL.
          lcl_purreq=>get_one( EXPORTING iv_prnumber   = lv_prnumber
                                         iv_with_items = abap_true
                               IMPORTING et_item       = et_entityset ).
        ELSE.
          lcl_purreq=>get_list( EXPORTING it_filter     = lcl_api=>filters( it_select        = it_filter_select_options
                                                                            iv_filter_string = iv_filter_string
                                                                            ir_request       = mr_request_details )
                                          iv_with_items = abap_true
                                IMPORTING et_item       = et_entityset ).
        ENDIF.
        " phân trang theo dòng (cả khi đi từ PurchaseReqSet('..')/Items)
        IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
          es_response_context-inlinecount = lines( et_entityset ).
        ENDIF.
        IF is_paging-skip > 0.
          DELETE et_entityset TO is_paging-skip.
        ENDIF.
        IF is_paging-top > 0 AND lines( et_entityset ) > is_paging-top.
          DELETE et_entityset FROM is_paging-top + 1.
        ENDIF.
        lo_api->success( et_entityset ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD purchasereqitems_get_entity.
* GET /PurchaseReqItemSet(PRNumber='3100003115',Item='00010')
    DATA lt_item TYPE lcl_purreq=>ty_t_item.

    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        DATA(lv_prnumber) = lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'PRNumber' ).
        DATA(lv_item)     = CONV bnfpo( lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'Item' ) ).
        lcl_purreq=>get_one( EXPORTING iv_prnumber   = lv_prnumber
                                       iv_with_items = abap_true
                             IMPORTING et_item       = lt_item ).
        READ TABLE lt_item INTO er_entity WITH KEY item = lv_item.
        IF sy-subrc <> 0.
          lcl_api=>raise_error( iv_message   = |Yêu cầu mua hàng { lv_prnumber } không có dòng { lv_item }.|
                                iv_not_found = abap_true ).
        ENDIF.
        lo_api->success( er_entity ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD /iwbep/if_mgw_appl_srv_runtime~get_expanded_entityset.
* GET /PurchaseReqSet?$expand=Items[&$filter=...][&$top=..] - header kèm dòng, mỗi PR đọc 1 lần
    IF iv_entity_set_name <> 'PurchaseReqSet' OR it_navigation_path IS NOT INITIAL
    OR io_expand IS NOT BOUND
    OR io_expand->compare_to_tech_names( `ITEMS` ) <> /iwbep/if_mgw_odata_expand=>gcs_compare_result-match_equals.
      super->/iwbep/if_mgw_appl_srv_runtime~get_expanded_entityset(
        EXPORTING
          iv_entity_name           = iv_entity_name
          iv_entity_set_name       = iv_entity_set_name
          iv_source_name           = iv_source_name
          it_filter_select_options = it_filter_select_options
          it_order                 = it_order
          is_paging                = is_paging
          it_navigation_path       = it_navigation_path
          it_key_tab               = it_key_tab
          iv_filter_string         = iv_filter_string
          iv_search_string         = iv_search_string
          io_expand                = io_expand
          io_tech_request_context  = io_tech_request_context
        IMPORTING
          er_entityset             = er_entityset
          et_expanded_clauses      = et_expanded_clauses
          et_expanded_tech_clauses = et_expanded_tech_clauses
          es_response_context      = es_response_context ).
      RETURN.
    ENDIF.

    DATA: lt_header TYPE lcl_purreq=>ty_t_header,
          lt_item   TYPE lcl_purreq=>ty_t_item.

    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        lcl_purreq=>get_list( EXPORTING it_filter     = lcl_api=>filters( it_select        = it_filter_select_options
                                                                          iv_filter_string = iv_filter_string
                                                                          ir_request       = mr_request_details )
                                        iv_top        = is_paging-top
                                        iv_skip       = is_paging-skip
                                        iv_with_items = abap_true
                              IMPORTING et_header     = lt_header
                                        et_item       = lt_item
                                        ev_total      = DATA(lv_total) ).
        DATA(lt_expanded) = lcl_purreq=>expand( it_header = lt_header it_item = lt_item ).
        copy_data_to_ref( EXPORTING is_data = lt_expanded
                          CHANGING  cr_data = er_entityset ).
        APPEND 'ITEMS' TO et_expanded_tech_clauses.
        IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
          es_response_context-inlinecount = lv_total.
        ENDIF.
        lo_api->success( lt_expanded ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
METHOD /iwbep/if_mgw_appl_srv_runtime~get_expanded_entity.
* GET /PurchaseReqSet('3100003115')?$expand=Items
    IF iv_entity_set_name <> 'PurchaseReqSet' OR it_navigation_path IS NOT INITIAL
    OR io_expand IS NOT BOUND
    OR io_expand->compare_to_tech_names( `ITEMS` ) <> /iwbep/if_mgw_odata_expand=>gcs_compare_result-match_equals.
      super->/iwbep/if_mgw_appl_srv_runtime~get_expanded_entity(
        EXPORTING
          iv_entity_name           = iv_entity_name
          iv_entity_set_name       = iv_entity_set_name
          iv_source_name           = iv_source_name
          it_key_tab               = it_key_tab
          it_navigation_path       = it_navigation_path
          io_expand                = io_expand
          io_tech_request_context  = io_tech_request_context
        IMPORTING
          er_entity                = er_entity
          es_response_context      = es_response_context
          et_expanded_clauses      = et_expanded_clauses
          et_expanded_tech_clauses = et_expanded_tech_clauses ).
      RETURN.
    ENDIF.

    DATA: ls_header TYPE zcl_zctd_core_int_mpc=>ts_purchasereq,
          lt_item   TYPE lcl_purreq=>ty_t_item.

    DATA(lo_api) = NEW lcl_api( io_runtime = me ir_request = mr_request_details iv_object = iv_entity_set_name ).
    TRY.
        lcl_purreq=>get_one( EXPORTING iv_prnumber   = lcl_api=>key_value( it_key_tab = it_key_tab iv_name = 'PRNumber' )
                                       iv_with_items = abap_true
                             IMPORTING es_header     = ls_header
                                       et_item       = lt_item ).
        DATA(lt_expanded) = lcl_purreq=>expand( it_header = VALUE #( ( ls_header ) ) it_item = lt_item ).
        copy_data_to_ref( EXPORTING is_data = lt_expanded[ 1 ]
                          CHANGING  cr_data = er_entity ).
        APPEND 'ITEMS' TO et_expanded_tech_clauses.
        lo_api->success( lt_expanded[ 1 ] ).
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        lo_api->failure( lx_error ).
        RAISE EXCEPTION lx_error.
    ENDTRY.
ENDMETHOD.
