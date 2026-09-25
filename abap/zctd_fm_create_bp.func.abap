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
* Các bước nằm trong include LZCTD_FG_COREF02.

  DATA: lt_data    TYPE cvis_ei_extern_t,
        ls_data    TYPE cvis_ei_extern,
        lt_company TYPE gty_t_bp_company,
        lt_purch   TYPE gty_t_bp_purch,
        lv_guid    TYPE bu_partner_guid_bapi.

  CLEAR: ev_partner, ev_supplier, et_return.

  PERFORM bp_check_input USING is_supplier CHANGING et_return.
  IF et_return IS NOT INITIAL.
    RETURN.
  ENDIF.

  PERFORM bp_default_org USING it_company[] it_purchasing[] CHANGING lt_company lt_purch.

  TRY.
      lv_guid = cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      APPEND VALUE #( type = 'E' message = |Không tạo được mã định danh cho nhà cung cấp mới.| ) TO et_return.
      RETURN.
  ENDTRY.

  PERFORM bp_build_partner USING is_supplier lv_guid CHANGING ls_data.
  PERFORM bp_build_vendor  USING lt_company lt_purch CHANGING ls_data.
  APPEND ls_data TO lt_data.

  PERFORM bp_maintain USING lt_data iv_testrun lv_guid
                      CHANGING ev_partner ev_supplier et_return.
