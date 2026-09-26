* Tạo Business Partner (tổ chức) + nhà cung cấp DÙNG ĐƯỢC ĐỂ MUA HÀNG,
* một lần lưu bằng CL_MD_BP_MAINTAIN (API BP/CVI chuẩn S/4):
*   - BP: tên, từ khóa tìm kiếm, địa chỉ chuẩn, điện thoại, e-mail
*   - role FLVN00 (kế toán NCC) + FLVN01 (NCC mua hàng)
*   - company code (LFB1) theo IT_COMPANY, purchasing org (LFM1) theo IT_PURCHASING
* Không truyền IT_COMPANY / IT_PURCHASING -> công ty 1000 / tổ chức mua hàng
* 1000. Ô bỏ trống lấy giá trị phổ biến của NCC nhóm Z001: TK đối chiếu
* 3311000001, điều khoản thanh toán 1045, kiểm tra trùng hóa đơn, tiền tệ
* đặt hàng VND, kiểm tra hóa đơn theo nhập kho.
* Nhóm BP mặc định Z001 (NCC trong nước, cùng số). IV_TESTRUN = 'X': chạy
* mọi kiểm tra rồi hủy, không lưu. Lỗi bất kỳ phần nào -> không lưu gì.
* Tạo mới: bắt buộc tên, quốc gia, mã số thuế (chỉ gồm số hoặc số-số). Trùng mã số thuế (TAXNUMBER, lưu loại VN0) với BP / NCC khác -> lỗi,
* không tạo; trùng tên với NCC khác -> cảnh báo (W), vẫn tạo.
* IV_SUPPLIER = mã NCC đã có -> CẬP NHẬT thay vì tạo mới: chỉ đổi các ô được
* truyền trong IS_SUPPLIER / IT_COMPANY / IT_PURCHASING; công ty, tổ chức mua
* hàng, role FLVN00/FLVN01 chưa có thì mở thêm; NCC chưa có dữ liệu công ty
* hoặc mua hàng và không truyền gì -> tự mở 1000 / 1000.
* Các bước nằm trong include LZCTD_FG_COREF02.

  DATA: lt_data    TYPE cvis_ei_extern_t,
        ls_data    TYPE cvis_ei_extern,
        ls_exist   TYPE gty_bp_exist,
        lt_company TYPE gty_t_bp_company,
        lt_purch   TYPE gty_t_bp_purch,
        lv_guid    TYPE bu_partner_guid_bapi.

  CLEAR: ev_partner, ev_supplier, et_return.

  " đã có mã nhà cung cấp -> cập nhật
  IF iv_supplier IS NOT INITIAL.
    PERFORM bp_read_existing USING iv_supplier CHANGING ls_exist et_return.
    IF et_return IS NOT INITIAL.
      RETURN.
    ENDIF.
    PERFORM bp_build_change USING is_supplier ls_exist it_company[] it_purchasing[] CHANGING ls_data.
    PERFORM bp_change_taxnumber USING is_supplier ls_exist CHANGING ls_data et_return.
    IF et_return IS NOT INITIAL.
      RETURN.
    ENDIF.
    APPEND ls_data TO lt_data.
    PERFORM bp_maintain USING lt_data iv_testrun ls_exist-guid_c abap_true
                        CHANGING ev_partner ev_supplier et_return.
    RETURN.
  ENDIF.

  " chưa có -> tạo mới: dữ liệu bắt buộc, rồi trùng mã số thuế (lỗi) / tên (cảnh báo)
  PERFORM bp_check_input USING is_supplier CHANGING et_return.
  IF et_return IS INITIAL.
    PERFORM bp_check_duplicate USING is_supplier CHANGING et_return.
  ENDIF.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  PERFORM bp_default_org USING it_company[] it_purchasing[] CHANGING lt_company lt_purch.

  TRY.
      lv_guid = cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      APPEND VALUE #( BASE lcl_msg=>get( iv_no = '077' ) type = 'E' ) TO et_return.
      RETURN.
  ENDTRY.

  PERFORM bp_build_partner USING is_supplier lv_guid CHANGING ls_data.
  PERFORM bp_build_vendor  USING lt_company lt_purch CHANGING ls_data.
  APPEND ls_data TO lt_data.

  PERFORM bp_maintain USING lt_data iv_testrun lv_guid abap_false
                      CHANGING ev_partner ev_supplier et_return.
