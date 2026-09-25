*@LOCALS_IMP
*----------------------------------------------------------------------*
* lcl_po: chọn / đọc PO cho ZCTD_PO_INFO_SRV
*   find_po : $filter -> ZCTD_FM_FIND_PO (không lọc = PO mới nhất, $top mặc định 100)
*   read_po : ZCTD_FM_GET_PO_INFO -> header + item theo kiểu MPC
*----------------------------------------------------------------------*
CLASS lcl_po DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: ty_t_item TYPE STANDARD TABLE OF zcl_zctd_po_info_mpc=>ts_poitem WITH DEFAULT KEY,
           BEGIN OF ty_s_expanded.
             INCLUDE TYPE zcl_zctd_po_info_mpc=>ts_poheader.
    TYPES:   detail TYPE ty_t_item,
           END OF ty_s_expanded,
           ty_t_expanded TYPE STANDARD TABLE OF ty_s_expanded WITH DEFAULT KEY,
           ty_t_po       TYPE STANDARD TABLE OF ekko_key WITH DEFAULT KEY,
           ty_t_option   TYPE STANDARD TABLE OF rsdsselopt WITH DEFAULT KEY.

    CLASS-METHODS find_po
      IMPORTING it_filter        TYPE /iwbep/t_mgw_select_option
                iv_filter_string TYPE string OPTIONAL
                is_paging        TYPE /iwbep/s_mgw_paging OPTIONAL
      EXPORTING et_po            TYPE ty_t_po
                ev_total         TYPE i
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS read_po
      IMPORTING iv_ebeln  TYPE ebeln
      EXPORTING es_header TYPE zcl_zctd_po_info_mpc=>ts_poheader
                et_item   TYPE ty_t_item
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS raise_error
      IMPORTING iv_message   TYPE string
                iv_not_found TYPE abap_bool DEFAULT abap_false
      RAISING   /iwbep/cx_mgw_busi_exception.
    "! JSON theo mẫu portal: responseStatus / responseMessage / correlationId / data
    "! iv_key = số PO -> data là object; 'ALL' -> data là mảng, lọc bằng tham số URL
    CLASS-METHODS build_json
      IMPORTING iv_key     TYPE string
                it_params  TYPE /iwbep/if_mgw_core_srv_runtime=>parameter_values_t
      EXPORTING ev_json    TYPE string
                ev_status  TYPE string
                ev_message TYPE string
                ev_corr_id TYPE string.
    "! Link API đã gọi: lấy từ header ~request_uri, không có thì dựng lại từ entity set + key + tham số
    CLASS-METHODS request_url
      IMPORTING is_request    TYPE /iwbep/if_mgw_core_srv_runtime=>ty_s_mgw_request_context
                iv_entity_set TYPE string
                iv_key        TYPE string
      RETURNING VALUE(rv_url) TYPE string.
    "! Request dạng JSON: key + tham số URL + header (bỏ header xác thực/cookie)
    CLASS-METHODS request_json
      IMPORTING is_request     TYPE /iwbep/if_mgw_core_srv_runtime=>ty_s_mgw_request_context
                iv_key         TYPE string
      RETURNING VALUE(rv_json) TYPE string.
    "! Ghi log gọi API; lỗi ghi log không làm hỏng response
    CLASS-METHODS write_log
      IMPORTING is_log TYPE zctd_t_api_log.
  PRIVATE SECTION.
    CLASS-METHODS po_json
      IMPORTING iv_ebeln       TYPE ebeln
      RETURNING VALUE(rv_json) TYPE string
      RAISING   /iwbep/cx_mgw_busi_exception.
    CLASS-METHODS str
      IMPORTING iv_name        TYPE string
                iv_value       TYPE csequence
      RETURNING VALUE(rv_json) TYPE string.
    CLASS-METHODS num
      IMPORTING iv_name        TYPE string
                iv_value       TYPE decfloat34
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.

CLASS lcl_po IMPLEMENTATION.
  METHOD find_po.
    DATA: lt_ponumber TYPE ty_t_option,
          lt_potype   TYPE ty_t_option,
          lt_vendor   TYPE ty_t_option,
          lt_docdate  TYPE ty_t_option,
          lt_contract TYPE ty_t_option,
          lt_project  TYPE ty_t_option,
          lt_return   TYPE bapiret2_t.

    CLEAR: et_po, ev_total.
    IF it_filter IS INITIAL AND iv_filter_string IS NOT INITIAL.
      raise_error( |Biểu thức lọc chưa được hỗ trợ: { iv_filter_string }. Hãy lọc theo PONumber, POType, VendorCode, DocumentDate, ContractNo, ProjectCode.| ).
    ENDIF.

    LOOP AT it_filter INTO DATA(ls_filter).
      DATA(lt_option) = VALUE ty_t_option( FOR o IN ls_filter-select_options
                                           ( sign = o-sign option = o-option low = o-low high = o-high ) ).
      CASE ls_filter-property.
        WHEN 'PONumber'.
          APPEND LINES OF lt_option TO lt_ponumber.
        WHEN 'POType'.
          APPEND LINES OF lt_option TO lt_potype.
        WHEN 'VendorCode'.
          APPEND LINES OF lt_option TO lt_vendor.
        WHEN 'DocumentDate'.
          APPEND LINES OF lt_option TO lt_docdate.
        WHEN 'ContractNo'.
          APPEND LINES OF lt_option TO lt_contract.
        WHEN 'ProjectCode'.
          APPEND LINES OF lt_option TO lt_project.
        WHEN OTHERS.
          raise_error( |Không hỗ trợ lọc theo { ls_filter-property }. Có thể lọc theo: PONumber, POType, VendorCode, DocumentDate, ContractNo, ProjectCode.| ).
      ENDCASE.
    ENDLOOP.

    CALL FUNCTION 'ZCTD_FM_FIND_PO'
      EXPORTING
        iv_top      = is_paging-top
        iv_skip     = is_paging-skip
      IMPORTING
        ev_total    = ev_total
        et_return   = lt_return
      TABLES
        it_ponumber = lt_ponumber
        it_potype   = lt_potype
        it_vendor   = lt_vendor
        it_docdate  = lt_docdate
        it_contract = lt_contract
        it_project  = lt_project
        et_po       = et_po.
  ENDMETHOD.

  METHOD read_po.
    DATA: ls_header TYPE zctd_s_po_info_hdr,
          lt_item   TYPE STANDARD TABLE OF zctd_s_po_info_itm,
          lt_return TYPE bapiret2_t.

    CLEAR: es_header, et_item.
    CALL FUNCTION 'ZCTD_FM_GET_PO_INFO'
      EXPORTING
        iv_ebeln  = iv_ebeln
      IMPORTING
        es_header = ls_header
        et_return = lt_return
      TABLES
        et_item   = lt_item.
    READ TABLE lt_return INTO DATA(ls_error) WITH KEY type = 'E'.
    IF sy-subrc = 0.
      raise_error( iv_message = CONV #( ls_error-message ) iv_not_found = abap_true ).
    ENDIF.

    es_header = CORRESPONDING #( ls_header ).
    LOOP AT lt_item INTO DATA(ls_item).
      APPEND CORRESPONDING #( ls_item MAPPING return = returnitem ) TO et_item ASSIGNING FIELD-SYMBOL(<ls_item>).
      IF <ls_item>-prnumber IS INITIAL.
        CLEAR <ls_item>-pritem.
      ENDIF.
    ENDLOOP.
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
  METHOD build_json.
    DATA: lt_ponumber TYPE ty_t_option,
          lt_potype   TYPE ty_t_option,
          lt_vendor   TYPE ty_t_option,
          lt_docdate  TYPE ty_t_option,
          lt_contract TYPE ty_t_option,
          lt_project  TYPE ty_t_option,
          lt_po       TYPE ty_t_po,
          lt_return   TYPE bapiret2_t,
          lt_data     TYPE string_table,
          lv_data     TYPE string VALUE `null`,
          lv_top      TYPE i,
          lv_skip     TYPE i,
          lv_min      TYPE i,
          lv_from     TYPE string,
          lv_to       TYPE string.

    ev_status  = `S`.
    ev_message = `Success`.
    TRY.
        IF iv_key IS NOT INITIAL AND to_upper( iv_key ) <> `ALL`.
          " một PO -> data là object
          lv_data = po_json( CONV #( |{ iv_key ALPHA = IN }| ) ).
        ELSE.
          " danh sách -> data là mảng; lọc bằng tham số URL
          " tham số có thể lặp (POType=ZP05&POType=ZP06) hoặc dùng dấu phẩy (POType=ZP05,ZP06)
          DATA lt_values TYPE string_table.
          LOOP AT it_params INTO DATA(ls_param).
            SPLIT condense( CONV string( ls_param-value ) ) AT ',' INTO TABLE lt_values.
            LOOP AT lt_values INTO DATA(lv_value).
            lv_value = condense( lv_value ).
            CHECK lv_value IS NOT INITIAL.
            CASE to_upper( ls_param-name ).
              WHEN 'PONUMBER'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_value ) TO lt_ponumber.
              WHEN 'POTYPE'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = to_upper( lv_value ) ) TO lt_potype.
              WHEN 'VENDORCODE'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_value ) TO lt_vendor.
              WHEN 'DOCUMENTDATE'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_value ) TO lt_docdate.
              WHEN 'DOCUMENTDATEFROM'.
                lv_from = lv_value.
              WHEN 'DOCUMENTDATETO'.
                lv_to = lv_value.
              WHEN 'CONTRACTNO'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_value ) TO lt_contract.
              WHEN 'PROJECTCODE'.
                APPEND VALUE #( sign = 'I' option = 'EQ' low = to_upper( lv_value ) ) TO lt_project.
              WHEN 'TOP'.
                lv_top = lv_value.
              WHEN 'SKIP'.
                lv_skip = lv_value.
              WHEN 'MINITEMS'.
                lv_min = lv_value.
            ENDCASE.
            ENDLOOP.
          ENDLOOP.
          IF lv_from IS NOT INITIAL OR lv_to IS NOT INITIAL.
            APPEND VALUE #( sign = 'I' option = 'BT'
                            low  = COND #( WHEN lv_from IS INITIAL THEN `00000000` ELSE lv_from )
                            high = COND #( WHEN lv_to   IS INITIAL THEN `99991231` ELSE lv_to ) ) TO lt_docdate.
          ENDIF.

          CALL FUNCTION 'ZCTD_FM_FIND_PO'
            EXPORTING
              iv_top       = lv_top
              iv_skip      = lv_skip
              iv_min_items = lv_min
            IMPORTING
              et_return    = lt_return
            TABLES
              it_ponumber = lt_ponumber
              it_potype   = lt_potype
              it_vendor   = lt_vendor
              it_docdate  = lt_docdate
              it_contract = lt_contract
              it_project  = lt_project
              et_po       = lt_po.
          LOOP AT lt_po INTO DATA(ls_po).
            TRY.
                APPEND po_json( ls_po-ebeln ) TO lt_data.
              CATCH /iwbep/cx_mgw_busi_exception.
            ENDTRY.
          ENDLOOP.
          lv_data = |[{ concat_lines_of( table = lt_data sep = `,` ) }]|.
        ENDIF.
      CATCH /iwbep/cx_mgw_busi_exception INTO DATA(lx_error).
        ev_status  = `E`.
        ev_message = lx_error->get_text( ).
        IF lx_error->message_unlimited IS NOT INITIAL.
          ev_message = lx_error->message_unlimited.
        ENDIF.
        lv_data = `null`.
    ENDTRY.

    ev_corr_id = to_lower( cl_system_uuid=>create_uuid_c36_static( ) ).
    ev_json = |\{{ str( iv_name = `responseStatus` iv_value = ev_status ) },|
           && |{ str( iv_name = `responseMessage` iv_value = ev_message ) },|
           && |{ str( iv_name = `correlationId` iv_value = ev_corr_id ) },|
           && |"data":{ lv_data }\}|.
  ENDMETHOD.

  METHOD request_url.
    DATA lt_params TYPE string_table.

    rv_url = VALUE #( is_request-technical_request-request_header[ name = '~request_uri' ]-value OPTIONAL ).
    IF rv_url IS NOT INITIAL.
      RETURN.
    ENDIF.
    LOOP AT is_request-t_uri_query_parameter INTO DATA(ls_param).
      APPEND |{ ls_param-name }={ ls_param-value }| TO lt_params.
    ENDLOOP.
    rv_url = |/sap/opu/odata/sap/{ is_request-technical_request-service_name }/{ iv_entity_set }('{ iv_key }')/$value|.
    IF lt_params IS NOT INITIAL.
      rv_url = |{ rv_url }?{ concat_lines_of( table = lt_params sep = `&` ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD request_json.
    DATA: lt_params  TYPE string_table,
          lt_headers TYPE string_table.

    LOOP AT is_request-t_uri_query_parameter INTO DATA(ls_param).
      APPEND str( iv_name = CONV #( ls_param-name ) iv_value = ls_param-value ) TO lt_params.
    ENDLOOP.
    LOOP AT is_request-technical_request-request_header INTO DATA(ls_header).
      DATA(lv_name) = to_lower( ls_header-name ).
      CHECK lv_name IS NOT INITIAL AND lv_name(1) <> '~'
        AND lv_name <> `authorization` AND lv_name <> `cookie` AND lv_name <> `x-csrf-token`.
      APPEND str( iv_name = lv_name iv_value = ls_header-value ) TO lt_headers.
    ENDLOOP.
    rv_json = |\{"method":"GET",{ str( iv_name = `key` iv_value = iv_key ) },|
           && |"parameters":\{{ concat_lines_of( table = lt_params sep = `,` ) }\},|
           && |"headers":\{{ concat_lines_of( table = lt_headers sep = `,` ) }\}\}|.
  ENDMETHOD.

  METHOD write_log.
    TRY.
        CALL FUNCTION 'ZCTD_FM_API_LOG_WRITE'
          EXPORTING
            is_log = is_log.
      CATCH cx_root ##CATCH_ALL.
        " lỗi ghi log không được làm hỏng response của API
    ENDTRY.
  ENDMETHOD.

  METHOD po_json.
    DATA: ls_header TYPE zcl_zctd_po_info_mpc=>ts_poheader,
          lt_item   TYPE ty_t_item,
          lt_items  TYPE string_table.

    read_po( EXPORTING iv_ebeln  = iv_ebeln
             IMPORTING es_header = ls_header
                       et_item   = lt_item ).
    LOOP AT lt_item INTO DATA(ls_item).
      APPEND |\{{ str( iv_name = `PONumber` iv_value = ls_item-ponumber ) },|
          && |{ str( iv_name = `Item` iv_value = ls_item-item ) },|
          && |{ str( iv_name = `PRNumber` iv_value = ls_item-prnumber ) },|
          && |{ str( iv_name = `PRItem` iv_value = ls_item-pritem ) },|
          && |{ str( iv_name = `WBS` iv_value = ls_item-wbs ) },|
          && |{ str( iv_name = `WBSName` iv_value = ls_item-wbsname ) },|
          && |{ str( iv_name = `BOMG` iv_value = ls_item-bomg ) },|
          && |{ str( iv_name = `BOMGName` iv_value = ls_item-bomgname ) },|
          && |{ str( iv_name = `Material` iv_value = ls_item-material ) },|
          && |{ str( iv_name = `Description` iv_value = ls_item-description ) },|
          && |{ str( iv_name = `Brand` iv_value = ls_item-brand ) },|
          && |{ num( iv_name = `Quantity` iv_value = CONV #( ls_item-quantity ) ) },|
          && |{ str( iv_name = `UOM` iv_value = ls_item-uom ) },|
          && |{ num( iv_name = `UnitPrice` iv_value = CONV #( ls_item-unitprice ) ) },|
          && |{ num( iv_name = `PriceUnit` iv_value = CONV #( ls_item-priceunit ) ) },|
          && |{ num( iv_name = `Amount` iv_value = CONV #( ls_item-amount ) ) },|
          && |{ num( iv_name = `VatRate` iv_value = CONV #( ls_item-vatrate ) ) },|
          && |{ str( iv_name = `DeliveryDate` iv_value = ls_item-deliverydate ) },|
          && |{ str( iv_name = `Plant` iv_value = ls_item-plant ) },|
          && |{ str( iv_name = `StorageLocation` iv_value = ls_item-storagelocation ) },|
          && |{ str( iv_name = `DeleteIndicator` iv_value = ls_item-deleteindicator ) },|
          && |{ str( iv_name = `Return` iv_value = ls_item-return ) },|
          && |{ str( iv_name = `Disable` iv_value = ls_item-disable ) },|
          && |{ str( iv_name = `ItemStatus` iv_value = ls_item-itemstatus ) }\}| TO lt_items.
    ENDLOOP.

    rv_json = |\{{ str( iv_name = `PONumber` iv_value = ls_header-ponumber ) },|
           && |{ str( iv_name = `POType` iv_value = ls_header-potype ) },|
           && |{ str( iv_name = `VendorCode` iv_value = ls_header-vendorcode ) },|
           && |{ str( iv_name = `VendorName` iv_value = ls_header-vendorname ) },|
           && |{ str( iv_name = `ProjectCode` iv_value = ls_header-projectcode ) },|
           && |{ str( iv_name = `ProjectName` iv_value = ls_header-projectname ) },|
           && |{ str( iv_name = `WBSCode` iv_value = ls_header-wbscode ) },|
           && |{ str( iv_name = `TenderPackage` iv_value = ls_header-tenderpackage ) },|
           && |{ str( iv_name = `ContractNo` iv_value = ls_header-contractno ) },|
           && |{ str( iv_name = `PRNumber` iv_value = ls_header-prnumber ) },|
           && |{ str( iv_name = `DocumentDate` iv_value = ls_header-documentdate ) },|
           && |{ str( iv_name = `DeliveryDate` iv_value = ls_header-deliverydate ) },|
           && |{ str( iv_name = `Currency` iv_value = ls_header-currency ) },|
           && |{ num( iv_name = `ExchangeRate` iv_value = CONV #( ls_header-exchangerate ) ) },|
           && |{ num( iv_name = `Subtotal` iv_value = CONV #( ls_header-subtotal ) ) },|
           && |{ num( iv_name = `TaxAmount` iv_value = CONV #( ls_header-taxamount ) ) },|
           && |{ num( iv_name = `TotalAmount` iv_value = CONV #( ls_header-totalamount ) ) },|
           && |{ str( iv_name = `Status` iv_value = ls_header-status ) },|
           && |{ str( iv_name = `ReleaseStatus` iv_value = ls_header-releasestatus ) },|
           && |{ str( iv_name = `ChangedAt` iv_value = ls_header-changedat ) },|
           && |{ str( iv_name = `SourceVersion` iv_value = ls_header-sourceversion ) },|
           && |{ str( iv_name = `Note` iv_value = ls_header-note ) },|
           && |"Detail":[{ concat_lines_of( table = lt_items sep = `,` ) }]\}|.
  ENDMETHOD.

  METHOD str.
    rv_json = |"{ iv_name }":"{ escape( val = condense( CONV string( iv_value ) ) format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD num.
    rv_json = |"{ iv_name }":{ iv_value STYLE = SIMPLE }|.
  ENDMETHOD.
ENDCLASS.
*@END_LOCALS
METHOD poheaderset_get_entity.
* GET /POHeaderSet('4100035143')
    lcl_po=>read_po( EXPORTING iv_ebeln  = CONV #( |{ VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ) ALPHA = IN }| )
                     IMPORTING es_header = er_entity ).
ENDMETHOD.
METHOD poheaderset_get_entityset.
* GET /POHeaderSet[?$filter=...][&$top=..&$skip=..][&$inlinecount=allpages]
* Không lọc: PO mới nhất (mặc định 100). $expand=Detail xử lý ở GET_EXPANDED_ENTITYSET.
    lcl_po=>find_po( EXPORTING it_filter        = it_filter_select_options
                               iv_filter_string = iv_filter_string
                               is_paging        = is_paging
                     IMPORTING et_po            = DATA(lt_po)
                               ev_total         = DATA(lv_total) ).
    LOOP AT lt_po INTO DATA(ls_po).
      TRY.
          lcl_po=>read_po( EXPORTING iv_ebeln  = ls_po-ebeln
                           IMPORTING es_header = DATA(ls_header) ).
          APPEND ls_header TO et_entityset.
        CATCH /iwbep/cx_mgw_busi_exception.
          " PO không đọc được thì bỏ qua trong danh sách
      ENDTRY.
    ENDLOOP.
    IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
      es_response_context-inlinecount = lv_total.
    ENDIF.
ENDMETHOD.
METHOD poitemset_get_entity.
* GET /POItemSet(PONumber='4100035143',Item='00010')
    DATA lt_item TYPE lcl_po=>ty_t_item.

    DATA(lv_ebeln) = CONV ebeln( |{ VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ) ALPHA = IN }| ).
    DATA(lv_ebelp) = CONV ebelp( |{ VALUE string( it_key_tab[ name = 'Item' ]-value OPTIONAL ) ALPHA = IN }| ).
    lcl_po=>read_po( EXPORTING iv_ebeln = lv_ebeln
                     IMPORTING et_item  = lt_item ).
    READ TABLE lt_item INTO er_entity WITH KEY item = lv_ebelp.
    IF sy-subrc <> 0.
      lcl_po=>raise_error( iv_message   = |Đơn mua hàng { lv_ebeln ALPHA = OUT } không có dòng { lv_ebelp }.|
                           iv_not_found = abap_true ).
    ENDIF.
ENDMETHOD.
METHOD poitemset_get_entityset.
* GET /POHeaderSet('4100035143')/Detail  - toàn bộ dòng của PO
* GET /POItemSet[?$filter=PONumber eq '...']  - dòng của các PO được chọn
    DATA lt_item TYPE lcl_po=>ty_t_item.

    DATA(lv_key) = VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ).
    IF lv_key IS NOT INITIAL.
      lcl_po=>read_po( EXPORTING iv_ebeln = CONV #( |{ lv_key ALPHA = IN }| )
                       IMPORTING et_item  = et_entityset ).
      RETURN.
    ENDIF.

    lcl_po=>find_po( EXPORTING it_filter        = it_filter_select_options
                               iv_filter_string = iv_filter_string
                     IMPORTING et_po            = DATA(lt_po) ).
    LOOP AT lt_po INTO DATA(ls_po).
      TRY.
          lcl_po=>read_po( EXPORTING iv_ebeln = ls_po-ebeln
                           IMPORTING et_item  = lt_item ).
          APPEND LINES OF lt_item TO et_entityset.
        CATCH /iwbep/cx_mgw_busi_exception.
      ENDTRY.
    ENDLOOP.
    IF is_paging-skip > 0.
      DELETE et_entityset TO is_paging-skip.
    ENDIF.
    IF is_paging-top > 0 AND lines( et_entityset ) > is_paging-top.
      DELETE et_entityset FROM is_paging-top + 1.
    ENDIF.
ENDMETHOD.
METHOD /iwbep/if_mgw_appl_srv_runtime~get_expanded_entityset.
* GET /POHeaderSet?$expand=Detail[&$filter=...][&$top=..]
* Trả header kèm thẻ Detail (danh sách item) - mỗi PO đọc một lần.
    DATA lt_expanded TYPE lcl_po=>ty_t_expanded.

    IF iv_entity_set_name <> 'POHeaderSet' OR it_navigation_path IS NOT INITIAL
    OR io_expand IS NOT BOUND
    OR io_expand->compare_to_tech_names( `DETAIL` ) <> /iwbep/if_mgw_odata_expand=>gcs_compare_result-match_equals.
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

    lcl_po=>find_po( EXPORTING it_filter        = it_filter_select_options
                               iv_filter_string = iv_filter_string
                               is_paging        = is_paging
                     IMPORTING et_po            = DATA(lt_po)
                               ev_total         = DATA(lv_total) ).
    LOOP AT lt_po INTO DATA(ls_po).
      APPEND INITIAL LINE TO lt_expanded ASSIGNING FIELD-SYMBOL(<ls_expanded>).
      TRY.
          lcl_po=>read_po( EXPORTING iv_ebeln  = ls_po-ebeln
                           IMPORTING es_header = DATA(ls_header)
                                     et_item   = <ls_expanded>-detail ).
          MOVE-CORRESPONDING ls_header TO <ls_expanded>.
        CATCH /iwbep/cx_mgw_busi_exception.
          DELETE lt_expanded INDEX lines( lt_expanded ).
      ENDTRY.
    ENDLOOP.

    copy_data_to_ref( EXPORTING is_data = lt_expanded
                      CHANGING  cr_data = er_entityset ).
    APPEND 'DETAIL' TO et_expanded_tech_clauses.
    IF io_tech_request_context IS BOUND AND io_tech_request_context->has_inlinecount( ) = abap_true.
      es_response_context-inlinecount = lv_total.
    ENDIF.
ENDMETHOD.
METHOD /iwbep/if_mgw_appl_srv_runtime~get_expanded_entity.
* GET /POHeaderSet('4100035143')?$expand=Detail
    DATA ls_expanded TYPE lcl_po=>ty_s_expanded.

    IF iv_entity_set_name <> 'POHeaderSet' OR it_navigation_path IS NOT INITIAL
    OR io_expand IS NOT BOUND
    OR io_expand->compare_to_tech_names( `DETAIL` ) <> /iwbep/if_mgw_odata_expand=>gcs_compare_result-match_equals.
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

    lcl_po=>read_po( EXPORTING iv_ebeln  = CONV #( |{ VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ) ALPHA = IN }| )
                     IMPORTING es_header = DATA(ls_header)
                               et_item   = ls_expanded-detail ).
    MOVE-CORRESPONDING ls_header TO ls_expanded.
    copy_data_to_ref( EXPORTING is_data = ls_expanded
                      CHANGING  cr_data = er_entity ).
    APPEND 'DETAIL' TO et_expanded_tech_clauses.
ENDMETHOD.

METHOD pojsonset_get_entity.
* Entity media POJson - key là số PO (hoặc ALL); nội dung ở /$value
    er_entity-ponumber = to_upper( VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ) ).
    er_entity-mimetype = `application/json`.
ENDMETHOD.
METHOD /iwbep/if_mgw_appl_srv_runtime~get_stream.
* GET /POJsonSet('4100035733')/$value            -> data là 1 PO
* GET /POJsonSet('ALL')/$value[?POType=..&VendorCode=..&DocumentDateFrom=..&DocumentDateTo=..
*                              &ContractNo=..&ProjectCode=..&MinItems=..&top=..&skip=..] -> data là mảng
* Body: JSON đúng mẫu portal (responseStatus/responseMessage/correlationId/data).
    DATA ls_stream TYPE /iwbep/if_mgw_core_types=>ty_s_media_resource.

    IF iv_entity_set_name <> 'POJsonSet'.
      super->/iwbep/if_mgw_appl_srv_runtime~get_stream(
        EXPORTING
          iv_entity_name          = iv_entity_name
          iv_entity_set_name      = iv_entity_set_name
          iv_source_name          = iv_source_name
          it_key_tab              = it_key_tab
          it_navigation_path      = it_navigation_path
          io_tech_request_context = io_tech_request_context
        IMPORTING
          er_stream               = er_stream
          es_response_context     = es_response_context ).
      RETURN.
    ENDIF.

    DATA: lv_start   TYPE timestampl,
          lv_t0      TYPE i,
          lv_t1      TYPE i,
          lv_json    TYPE string,
          lv_status  TYPE string,
          lv_message TYPE string,
          lv_corr_id TYPE string.

    " thời điểm gọi + đo thời gian xử lý (key log: correlationId + ngày giờ gọi)
    DATA(lv_date) = sy-datum.
    DATA(lv_time) = sy-uzeit.
    GET TIME STAMP FIELD lv_start.
    GET RUN TIME FIELD lv_t0.

    DATA(lv_key) = VALUE string( it_key_tab[ name = 'PONumber' ]-value OPTIONAL ).
    lcl_po=>build_json( EXPORTING iv_key     = lv_key
                                  it_params  = mr_request_details->t_uri_query_parameter
                        IMPORTING ev_json    = lv_json
                                  ev_status  = lv_status
                                  ev_message = lv_message
                                  ev_corr_id = lv_corr_id ).
    ls_stream-mime_type = `application/json`.
    ls_stream-value     = cl_abap_codepage=>convert_to( lv_json ).
    copy_data_to_ref( EXPORTING is_data = ls_stream
                      CHANGING  cr_data = er_stream ).
    GET RUN TIME FIELD lv_t1.

    lcl_po=>write_log( VALUE #( corr_id     = lv_corr_id
                                call_date   = lv_date
                                call_time   = lv_time
                                call_tstmp  = lv_start
                                object_type = iv_entity_set_name
                                http_method = 'GET'
                                api_url     = lcl_po=>request_url( is_request    = mr_request_details->*
                                                                   iv_entity_set = iv_entity_set_name
                                                                   iv_key        = lv_key )
                                duration_ms = ( lv_t1 - lv_t0 ) / 1000
                                call_user   = sy-uname
                                http_status = '200'
                                resp_status = lv_status
                                message     = lv_message
                                request     = lcl_po=>request_json( is_request = mr_request_details->*
                                                                    iv_key     = lv_key )
                                response    = lv_json ) ).
ENDMETHOD.

METHOD pojsonset_get_entityset.
* GET /POJsonSet[?$filter=...][&$top=..] - danh sách link: 'ALL' + các PO.
* Nội dung JSON theo mẫu nằm ở /POJsonSet('<PO>')/$value hoặc /POJsonSet('ALL')/$value.
    APPEND VALUE #( ponumber = 'ALL' mimetype = `application/json` ) TO et_entityset.
    lcl_po=>find_po( EXPORTING it_filter        = it_filter_select_options
                               iv_filter_string = iv_filter_string
                               is_paging        = is_paging
                     IMPORTING et_po            = DATA(lt_po) ).
    LOOP AT lt_po INTO DATA(ls_po).
      APPEND VALUE #( ponumber = ls_po-ebeln mimetype = `application/json` ) TO et_entityset.
    ENDLOOP.
ENDMETHOD.
