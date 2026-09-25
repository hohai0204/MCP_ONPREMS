*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_COREF02.
*----------------------------------------------------------------------*
* Subroutine của ZCTD_FM_CREATE_BP - tạo BP + nhà cung cấp dùng được để
* mua hàng trong MỘT lần lưu bằng CL_MD_BP_MAINTAIN (BP/CVI chuẩn S/4):
*   bp_check_input    kiểm tra dữ liệu bắt buộc
*   bp_default_org    công ty / tổ chức mua hàng + giá trị mặc định
*   bp_build_partner  BP: dữ liệu chung, địa chỉ, liên lạc, role
*   bp_build_vendor   nhà cung cấp: company code (LFB1), purchasing (LFM1)
*   bp_maintain       gọi API, gom thông báo, COMMIT / ROLLBACK
* Chế độ đổi (IV_SUPPLIER đã có):
*   bp_read_existing  đọc BP / địa chỉ / role / công ty / tổ chức mua đã có
*   bp_build_change   chỉ đổi ô được truyền; công ty / tổ chức mua / role
*                     chưa có thì mở thêm (NCC chưa có dữ liệu mua hàng -> 1000/1000)
*----------------------------------------------------------------------*

FORM bp_check_input USING    is_supplier TYPE zctd_s_bp_supplier
                    CHANGING ct_return   TYPE bapiret2_t.
  IF is_supplier-name1 IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_SUPPLIER' field = 'NAME1'
                    message = |Chưa nhập tên nhà cung cấp.| ) TO ct_return.
  ENDIF.
  IF is_supplier-country IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_SUPPLIER' field = 'COUNTRY'
                    message = |Chưa nhập quốc gia của nhà cung cấp.| ) TO ct_return.
  ENDIF.
ENDFORM.

* Không truyền công ty / tổ chức mua hàng -> 1000 / 1000; ô trống -> mặc định
FORM bp_default_org USING    it_company TYPE gty_t_bp_company
                             it_purch   TYPE gty_t_bp_purch
                    CHANGING ct_company TYPE gty_t_bp_company
                             ct_purch   TYPE gty_t_bp_purch.
  ct_company = it_company.
  IF ct_company IS INITIAL.
    ct_company = VALUE #( ( bukrs = gc_bp_bukrs_def ) ).
  ENDIF.
  LOOP AT ct_company ASSIGNING FIELD-SYMBOL(<ls_company>).
    PERFORM bp_company_defaults CHANGING <ls_company>.
  ENDLOOP.

  ct_purch = it_purch.
  IF ct_purch IS INITIAL.
    ct_purch = VALUE #( ( ekorg = gc_bp_ekorg_def ) ).
  ENDIF.
  LOOP AT ct_purch ASSIGNING FIELD-SYMBOL(<ls_purch>).
    PERFORM bp_purch_defaults CHANGING <ls_purch>.
  ENDLOOP.
ENDFORM.

FORM bp_company_defaults CHANGING cs_company TYPE zctd_s_bp_company.
  IF cs_company-akont IS INITIAL.
    cs_company-akont = gc_bp_akont_def.
  ENDIF.
  IF cs_company-zterm IS INITIAL.
    cs_company-zterm = gc_bp_zterm_def.
  ENDIF.
  IF cs_company-reprf IS INITIAL.
    cs_company-reprf = abap_true.
  ENDIF.
  cs_company-akont = |{ cs_company-akont ALPHA = IN }|.
ENDFORM.

FORM bp_purch_defaults CHANGING cs_purch TYPE zctd_s_bp_purch.
  IF cs_purch-waers IS INITIAL.
    cs_purch-waers = gc_bp_waers_def.
  ENDIF.
  IF cs_purch-webre IS INITIAL.
    cs_purch-webre = abap_true.
  ENDIF.
ENDFORM.

FORM bp_build_partner USING    is_supplier TYPE zctd_s_bp_supplier
                               iv_guid     TYPE bu_partner_guid_bapi
                      CHANGING cs_data     TYPE cvis_ei_extern.
  DATA lv_langu TYPE spras.

  lv_langu = COND #( WHEN is_supplier-langu IS NOT INITIAL THEN is_supplier-langu ELSE sy-langu ).

  cs_data-partner-header-object_task                  = 'I'.
  cs_data-partner-header-object_instance-bpartnerguid = iv_guid.

  " dữ liệu chung: tổ chức, nhóm BP, tên, từ khóa tìm kiếm, ngôn ngữ
  cs_data-partner-central_data-common-data-bp_control-category = '2'.
  cs_data-partner-central_data-common-data-bp_control-grouping =
    COND #( WHEN is_supplier-bu_group IS NOT INITIAL THEN is_supplier-bu_group ELSE gc_bp_group_def ).
  cs_data-partner-central_data-common-data-bp_centraldata-searchterm1 =
    COND #( WHEN is_supplier-searchterm1 IS NOT INITIAL THEN is_supplier-searchterm1 ELSE is_supplier-name1 ).
  cs_data-partner-central_data-common-data-bp_centraldata-partnerlanguage = lv_langu.
  cs_data-partner-central_data-common-data-bp_organization-name1          = is_supplier-name1.
  cs_data-partner-central_data-common-datax-bp_centraldata-searchterm1     = abap_true.
  cs_data-partner-central_data-common-datax-bp_centraldata-partnerlanguage = abap_true.
  cs_data-partner-central_data-common-datax-bp_organization-name1          = abap_true.

  " role kế toán NCC (company code) + NCC mua hàng (purchasing org)
  DATA lt_roles TYPE STANDARD TABLE OF bu_role WITH EMPTY KEY.
  lt_roles = VALUE #( ( gc_bp_role_fi ) ( gc_bp_role_purch ) ).
  LOOP AT lt_roles INTO DATA(lv_role).
    APPEND VALUE #( task      = 'I'
                    data_key  = lv_role
                    data      = VALUE #( rolecategory = lv_role valid_from = sy-datum valid_to = '99991231' )
                    datax     = VALUE #( valid_from = abap_true valid_to = abap_true ) )
      TO cs_data-partner-central_data-role-roles.
  ENDLOOP.

  " địa chỉ chuẩn + điện thoại + e-mail
  APPEND INITIAL LINE TO cs_data-partner-central_data-address-addresses ASSIGNING FIELD-SYMBOL(<ls_addr>).
  <ls_addr>-task               = 'I'.
  <ls_addr>-data_key-operation = 'XXDFLT'.
  <ls_addr>-data-postal-data   = VALUE #( street     = is_supplier-street
                                          city       = is_supplier-city
                                          postl_cod1 = is_supplier-postl_cod1
                                          region     = is_supplier-region
                                          country    = is_supplier-country
                                          langu      = lv_langu ).
  <ls_addr>-data-postal-datax  = VALUE #( street = abap_true city = abap_true postl_cod1 = abap_true
                                          region = abap_true country = abap_true langu = abap_true ).
  IF is_supplier-telephone IS NOT INITIAL.
    APPEND VALUE #( contact = VALUE #( task  = 'I'
                                       data  = VALUE #( country = is_supplier-country telephone = is_supplier-telephone std_no = abap_true )
                                       datax = VALUE #( country = abap_true telephone = abap_true std_no = abap_true ) ) )
      TO <ls_addr>-data-communication-phone-phone.
  ENDIF.
  IF is_supplier-e_mail IS NOT INITIAL.
    APPEND VALUE #( contact = VALUE #( task  = 'I'
                                       data  = VALUE #( e_mail = is_supplier-e_mail std_no = abap_true )
                                       datax = VALUE #( e_mail = abap_true std_no = abap_true ) ) )
      TO <ls_addr>-data-communication-smtp-smtp.
  ENDIF.
ENDFORM.

FORM bp_build_vendor USING    it_company TYPE gty_t_bp_company
                              it_purch   TYPE gty_t_bp_purch
                     CHANGING cs_data    TYPE cvis_ei_extern.
  cs_data-ensure_create-create_vendor = abap_true.
  cs_data-vendor-header-object_task   = 'I'.

  LOOP AT it_company INTO DATA(ls_company).
    APPEND VALUE #( task     = 'I'
                    data_key = VALUE #( bukrs = ls_company-bukrs )
                    data     = VALUE #( akont = ls_company-akont zterm = ls_company-zterm zwels = ls_company-zwels
                                        fdgrv = ls_company-fdgrv reprf = ls_company-reprf )
                    datax    = VALUE #( akont = abap_true zterm = abap_true zwels = abap_true
                                        fdgrv = abap_true reprf = abap_true ) )
      TO cs_data-vendor-company_data-company.
  ENDLOOP.

  LOOP AT it_purch INTO DATA(ls_purch).
    APPEND VALUE #( task     = 'I'
                    data_key = VALUE #( ekorg = ls_purch-ekorg )
                    data     = VALUE #( waers = ls_purch-waers zterm = ls_purch-zterm
                                        webre = ls_purch-webre kalsk = ls_purch-kalsk )
                    datax    = VALUE #( waers = abap_true zterm = abap_true webre = abap_true kalsk = abap_true ) )
      TO cs_data-vendor-purchasing_data-purchasing.
  ENDLOOP.
ENDFORM.

* Lưu bằng CL_MD_BP_MAINTAIN: lỗi bất kỳ phần nào -> ROLLBACK, không lưu gì
FORM bp_maintain USING    it_data     TYPE cvis_ei_extern_t
                          iv_testrun  TYPE xfeld
                          iv_guid     TYPE bu_partner_guid_bapi
                          iv_change   TYPE abap_bool
                 CHANGING cv_partner  TYPE bu_partner
                          cv_supplier TYPE lifnr
                          ct_return   TYPE bapiret2_t.
  DATA: lt_result  TYPE bapiretm,
        ls_commit  TYPE bapiret2,
        lv_guid    TYPE bu_partner_guid,
        lv_has_err TYPE abap_bool.

  cl_md_bp_maintain=>maintain( EXPORTING i_data     = it_data
                                         i_test_run = iv_testrun
                               IMPORTING e_return   = lt_result ).
  " API trả cùng một thông báo nhiều lần -> chỉ giữ một dòng mỗi thông báo
  DATA lt_msg TYPE bapiret2_t.
  LOOP AT lt_result INTO DATA(ls_result).
    LOOP AT ls_result-object_msg INTO DATA(ls_msg).
      IF NOT line_exists( lt_msg[ type = ls_msg-type id = ls_msg-id number = ls_msg-number message = ls_msg-message ] ).
        APPEND CORRESPONDING #( ls_msg ) TO lt_msg.
      ENDIF.
      IF ls_msg-type CA 'EAX'.
        lv_has_err = abap_true.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
  APPEND LINES OF lt_msg TO ct_return.

  IF lv_has_err = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    APPEND VALUE #( type = 'E'
                    message = |Không { COND string( WHEN iv_change = abap_true THEN `cập nhật` ELSE `tạo` ) } được nhà cung cấp, xem các thông báo của SAP ở trên để biết nguyên nhân.| )
      TO ct_return.
    RETURN.
  ENDIF.
  IF iv_testrun = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    APPEND VALUE #( type = 'S'
                    message = |Chạy thử thành công: dữ liệu hợp lệ, chưa lưu nhà cung cấp.| ) TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait   = abap_true
    IMPORTING
      return = ls_commit.
  IF ls_commit-type CA 'EA'.
    APPEND ls_commit TO ct_return.
    APPEND VALUE #( type = 'E'
                    message = |Không lưu được nhà cung cấp, toàn bộ thay đổi đã được hủy.| ) TO ct_return.
    RETURN.
  ENDIF.

  " số BP theo GUID vừa tạo, số nhà cung cấp theo liên kết CVI
  lv_guid = iv_guid.
  SELECT SINGLE partner FROM but000 WHERE partner_guid = @lv_guid INTO @cv_partner.
  SELECT SINGLE vendor FROM cvi_vend_link WHERE partner_guid = @lv_guid INTO @cv_supplier.
  APPEND VALUE #( type = 'S' message_v1 = cv_partner message_v2 = cv_supplier
                  message = COND #( WHEN iv_change = abap_true
                                    THEN |Đã cập nhật nhà cung cấp { condense( |{ cv_supplier ALPHA = OUT }| ) } (BP { condense( |{ cv_partner ALPHA = OUT }| ) }).|
                                    ELSE |Đã tạo nhà cung cấp { condense( |{ cv_supplier ALPHA = OUT }| ) } (BP { condense( |{ cv_partner ALPHA = OUT }| ) }) kèm dữ liệu công ty và mua hàng.| ) )
    TO ct_return.
ENDFORM.

*======================================================================*
* Chế độ đổi nhà cung cấp đã có
*======================================================================*
FORM bp_read_existing USING    iv_supplier TYPE lifnr
                      CHANGING cs_exist    TYPE gty_bp_exist
                               ct_return   TYPE bapiret2_t.
  CLEAR cs_exist.
  cs_exist-lifnr = |{ iv_supplier ALPHA = IN }|.

  SELECT SINGLE partner_guid FROM cvi_vend_link
    WHERE vendor = @cs_exist-lifnr
    INTO @cs_exist-guid.
  IF sy-subrc <> 0.
    APPEND VALUE #( type = 'E' parameter = 'IV_SUPPLIER'
                    message = |Không tìm thấy nhà cung cấp { cs_exist-lifnr ALPHA = OUT } để cập nhật.| ) TO ct_return.
    RETURN.
  ENDIF.
  SELECT SINGLE partner FROM but000 WHERE partner_guid = @cs_exist-guid INTO @cs_exist-partner.
  cs_exist-guid_c = cs_exist-guid.

  " địa chỉ chuẩn + số thứ tự điện thoại / e-mail mặc định
  SELECT addrnumber, address_guid, xdfadr FROM but020
    WHERE partner = @cs_exist-partner
    ORDER BY xdfadr DESCENDING
    INTO TABLE @DATA(lt_addr)
    UP TO 1 ROWS.
  READ TABLE lt_addr INTO DATA(ls_addr) INDEX 1.
  IF sy-subrc = 0.
    cs_exist-addrnumber = ls_addr-addrnumber.
    cs_exist-addr_guid  = ls_addr-address_guid.
    SELECT SINGLE consnumber FROM adr2
      WHERE addrnumber = @cs_exist-addrnumber AND persnumber = @space AND flgdefault = @abap_true
      INTO @cs_exist-tel_cons.
    SELECT SINGLE consnumber FROM adr6
      WHERE addrnumber = @cs_exist-addrnumber AND persnumber = @space AND flgdefault = @abap_true
      INTO @cs_exist-smtp_cons.
  ENDIF.

  SELECT rltyp FROM but100 WHERE partner = @cs_exist-partner INTO TABLE @cs_exist-t_role.
  SELECT bukrs FROM lfb1 WHERE lifnr = @cs_exist-lifnr INTO TABLE @cs_exist-t_bukrs.
  SELECT ekorg FROM lfm1 WHERE lifnr = @cs_exist-lifnr INTO TABLE @cs_exist-t_ekorg.
ENDFORM.

* Chỉ ô được truyền mới đổi; công ty / tổ chức mua / role chưa có -> mở thêm
FORM bp_build_change USING    is_supplier TYPE zctd_s_bp_supplier
                              is_exist    TYPE gty_bp_exist
                              it_company  TYPE gty_t_bp_company
                              it_purch    TYPE gty_t_bp_purch
                     CHANGING cs_data     TYPE cvis_ei_extern.
  DATA: lt_company TYPE gty_t_bp_company,
        lt_purch   TYPE gty_t_bp_purch,
        lt_roles   TYPE STANDARD TABLE OF bu_role WITH EMPTY KEY.

  cs_data-partner-header-object_task                  = 'U'.
  cs_data-partner-header-object_instance-bpartner     = is_exist-partner.
  cs_data-partner-header-object_instance-bpartnerguid = is_exist-guid_c.

  " dữ liệu chung
  IF is_supplier-name1 IS NOT INITIAL.
    cs_data-partner-central_data-common-data-bp_organization-name1  = is_supplier-name1.
    cs_data-partner-central_data-common-datax-bp_organization-name1 = abap_true.
  ENDIF.
  IF is_supplier-searchterm1 IS NOT INITIAL.
    cs_data-partner-central_data-common-data-bp_centraldata-searchterm1  = is_supplier-searchterm1.
    cs_data-partner-central_data-common-datax-bp_centraldata-searchterm1 = abap_true.
  ENDIF.
  IF is_supplier-langu IS NOT INITIAL.
    cs_data-partner-central_data-common-data-bp_centraldata-partnerlanguage  = is_supplier-langu.
    cs_data-partner-central_data-common-datax-bp_centraldata-partnerlanguage = abap_true.
  ENDIF.

  " role còn thiếu
  lt_roles = VALUE #( ( gc_bp_role_fi ) ( gc_bp_role_purch ) ).
  LOOP AT lt_roles INTO DATA(lv_role).
    CHECK NOT line_exists( is_exist-t_role[ table_line = lv_role ] ).
    APPEND VALUE #( task     = 'I'
                    data_key = lv_role
                    data     = VALUE #( rolecategory = lv_role valid_from = sy-datum valid_to = '99991231' )
                    datax    = VALUE #( valid_from = abap_true valid_to = abap_true ) )
      TO cs_data-partner-central_data-role-roles.
  ENDLOOP.

  " địa chỉ chuẩn: chỉ đổi ô được truyền
  IF is_exist-addr_guid IS NOT INITIAL
  AND ( is_supplier-street IS NOT INITIAL OR is_supplier-city IS NOT INITIAL OR is_supplier-postl_cod1 IS NOT INITIAL
        OR is_supplier-region IS NOT INITIAL OR is_supplier-country IS NOT INITIAL
        OR is_supplier-telephone IS NOT INITIAL OR is_supplier-e_mail IS NOT INITIAL ).
    APPEND INITIAL LINE TO cs_data-partner-central_data-address-addresses ASSIGNING FIELD-SYMBOL(<ls_addr>).
    <ls_addr>-task          = 'U'.
    <ls_addr>-data_key-guid = is_exist-addr_guid.
    IF is_supplier-street IS NOT INITIAL.
      <ls_addr>-data-postal-data-street  = is_supplier-street.
      <ls_addr>-data-postal-datax-street = abap_true.
    ENDIF.
    IF is_supplier-city IS NOT INITIAL.
      <ls_addr>-data-postal-data-city  = is_supplier-city.
      <ls_addr>-data-postal-datax-city = abap_true.
    ENDIF.
    IF is_supplier-postl_cod1 IS NOT INITIAL.
      <ls_addr>-data-postal-data-postl_cod1  = is_supplier-postl_cod1.
      <ls_addr>-data-postal-datax-postl_cod1 = abap_true.
    ENDIF.
    IF is_supplier-region IS NOT INITIAL.
      <ls_addr>-data-postal-data-region  = is_supplier-region.
      <ls_addr>-data-postal-datax-region = abap_true.
    ENDIF.
    IF is_supplier-country IS NOT INITIAL.
      <ls_addr>-data-postal-data-country  = is_supplier-country.
      <ls_addr>-data-postal-datax-country = abap_true.
    ENDIF.
    IF is_supplier-telephone IS NOT INITIAL.
      APPEND VALUE #( contact = VALUE #(
                        task  = COND #( WHEN is_exist-tel_cons IS NOT INITIAL THEN 'U' ELSE 'I' )
                        data  = VALUE #( telephone = is_supplier-telephone std_no = abap_true consnumber = is_exist-tel_cons
                                         country = COND #( WHEN is_supplier-country IS NOT INITIAL THEN is_supplier-country ELSE 'VN' ) )
                        datax = VALUE #( telephone = abap_true std_no = abap_true country = abap_true
                                         updateflag = COND #( WHEN is_exist-tel_cons IS NOT INITIAL THEN 'U' ELSE 'I' ) ) ) )
        TO <ls_addr>-data-communication-phone-phone.
    ENDIF.
    IF is_supplier-e_mail IS NOT INITIAL.
      APPEND VALUE #( contact = VALUE #(
                        task  = COND #( WHEN is_exist-smtp_cons IS NOT INITIAL THEN 'U' ELSE 'I' )
                        data  = VALUE #( e_mail = is_supplier-e_mail std_no = abap_true consnumber = is_exist-smtp_cons )
                        datax = VALUE #( e_mail = abap_true std_no = abap_true
                                         updateflag = COND #( WHEN is_exist-smtp_cons IS NOT INITIAL THEN 'U' ELSE 'I' ) ) ) )
        TO <ls_addr>-data-communication-smtp-smtp.
    ENDIF.
  ENDIF.

  " nhà cung cấp: công ty / tổ chức mua đã có -> đổi ô được truyền; chưa có -> mở thêm
  cs_data-vendor-header-object_task            = 'U'.
  cs_data-vendor-header-object_instance-lifnr  = is_exist-lifnr.

  lt_company = it_company.
  IF lt_company IS INITIAL AND is_exist-t_bukrs IS INITIAL.
    lt_company = VALUE #( ( bukrs = gc_bp_bukrs_def ) ).
  ENDIF.
  LOOP AT lt_company INTO DATA(ls_company).
    IF line_exists( is_exist-t_bukrs[ table_line = ls_company-bukrs ] ).
      APPEND VALUE #( task = 'U' data_key = VALUE #( bukrs = ls_company-bukrs ) )
        TO cs_data-vendor-company_data-company ASSIGNING FIELD-SYMBOL(<ls_cc>).
      IF ls_company-akont IS NOT INITIAL.
        <ls_cc>-data-akont = |{ ls_company-akont ALPHA = IN }|. <ls_cc>-datax-akont = abap_true.
      ENDIF.
      IF ls_company-zterm IS NOT INITIAL.
        <ls_cc>-data-zterm = ls_company-zterm. <ls_cc>-datax-zterm = abap_true.
      ENDIF.
      IF ls_company-zwels IS NOT INITIAL.
        <ls_cc>-data-zwels = ls_company-zwels. <ls_cc>-datax-zwels = abap_true.
      ENDIF.
      IF ls_company-fdgrv IS NOT INITIAL.
        <ls_cc>-data-fdgrv = ls_company-fdgrv. <ls_cc>-datax-fdgrv = abap_true.
      ENDIF.
      IF ls_company-reprf IS NOT INITIAL.
        <ls_cc>-data-reprf = ls_company-reprf. <ls_cc>-datax-reprf = abap_true.
      ENDIF.
    ELSE.
      PERFORM bp_company_defaults CHANGING ls_company.
      APPEND VALUE #( task     = 'I'
                      data_key = VALUE #( bukrs = ls_company-bukrs )
                      data     = VALUE #( akont = ls_company-akont zterm = ls_company-zterm zwels = ls_company-zwels
                                          fdgrv = ls_company-fdgrv reprf = ls_company-reprf )
                      datax    = VALUE #( akont = abap_true zterm = abap_true zwels = abap_true
                                          fdgrv = abap_true reprf = abap_true ) )
        TO cs_data-vendor-company_data-company.
    ENDIF.
  ENDLOOP.

  lt_purch = it_purch.
  IF lt_purch IS INITIAL AND is_exist-t_ekorg IS INITIAL.
    lt_purch = VALUE #( ( ekorg = gc_bp_ekorg_def ) ).
  ENDIF.
  LOOP AT lt_purch INTO DATA(ls_purch).
    IF line_exists( is_exist-t_ekorg[ table_line = ls_purch-ekorg ] ).
      APPEND VALUE #( task = 'U' data_key = VALUE #( ekorg = ls_purch-ekorg ) )
        TO cs_data-vendor-purchasing_data-purchasing ASSIGNING FIELD-SYMBOL(<ls_po>).
      IF ls_purch-waers IS NOT INITIAL.
        <ls_po>-data-waers = ls_purch-waers. <ls_po>-datax-waers = abap_true.
      ENDIF.
      IF ls_purch-zterm IS NOT INITIAL.
        <ls_po>-data-zterm = ls_purch-zterm. <ls_po>-datax-zterm = abap_true.
      ENDIF.
      IF ls_purch-webre IS NOT INITIAL.
        <ls_po>-data-webre = ls_purch-webre. <ls_po>-datax-webre = abap_true.
      ENDIF.
      IF ls_purch-kalsk IS NOT INITIAL.
        <ls_po>-data-kalsk = ls_purch-kalsk. <ls_po>-datax-kalsk = abap_true.
      ENDIF.
    ELSE.
      PERFORM bp_purch_defaults CHANGING ls_purch.
      APPEND VALUE #( task     = 'I'
                      data_key = VALUE #( ekorg = ls_purch-ekorg )
                      data     = VALUE #( waers = ls_purch-waers zterm = ls_purch-zterm
                                          webre = ls_purch-webre kalsk = ls_purch-kalsk )
                      datax    = VALUE #( waers = abap_true zterm = abap_true webre = abap_true kalsk = abap_true ) )
        TO cs_data-vendor-purchasing_data-purchasing.
    ENDIF.
  ENDLOOP.
ENDFORM.
