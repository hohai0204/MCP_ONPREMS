* Chọn danh sách PO cho OData ZCTD_PO_INFO_SRV (POHeaderSet có/không lọc).
* Điều kiện (RSDSSELOPT, tùy chọn): số PO, loại PO, NCC, ngày chứng từ
* (YYYYMMDD), số HĐ tham chiếu (ZTB_CONT_HEADER-ZCONT / EKKO-ZZHOPDONG),
* mã dự án dạng hiển thị (ZTB_CONT_HEADER-PSPID).
* Chỉ đơn mua hàng (EKKO-BSTYP = F), sắp xếp số PO giảm dần.
* IV_TOP = 0 -> 100 PO; tối đa 1000. EV_TOTAL = tổng số PO thỏa điều kiện.
* IV_MIN_ITEMS > 1: chỉ lấy PO có ít nhất N dòng chưa xóa (EKPO-LOEKZ trống).

  CONSTANTS: lc_default_top TYPE i VALUE 100,
             lc_max_top     TYPE i VALUE 1000.

  DATA: lr_ebeln TYPE RANGE OF ebeln,
        lr_bsart TYPE RANGE OF bsart,
        lr_lifnr TYPE RANGE OF lifnr,
        lr_bedat TYPE RANGE OF bedat,
        lr_zcont TYPE RANGE OF ztb_cont_header-zcont,
        lr_pspid TYPE RANGE OF ztb_cont_header-pspid,
        lr_sub   TYPE RANGE OF ebeln,
        lv_top   TYPE i.

  CLEAR: ev_total, et_return.
  REFRESH et_po.

  " số PO / NCC: bổ sung số 0 đầu (trừ khi dùng mẫu *)
  LOOP AT it_ponumber INTO DATA(ls_opt).
    APPEND VALUE #( sign = ls_opt-sign option = ls_opt-option
                    low  = COND #( WHEN ls_opt-option = 'CP' OR ls_opt-option = 'NP' THEN ls_opt-low ELSE |{ ls_opt-low ALPHA = IN }| )
                    high = COND #( WHEN ls_opt-high IS INITIAL THEN '' ELSE |{ ls_opt-high ALPHA = IN }| ) ) TO lr_ebeln.
  ENDLOOP.
  LOOP AT it_vendor INTO ls_opt.
    APPEND VALUE #( sign = ls_opt-sign option = ls_opt-option
                    low  = COND #( WHEN ls_opt-option = 'CP' OR ls_opt-option = 'NP' THEN ls_opt-low ELSE |{ ls_opt-low ALPHA = IN }| )
                    high = COND #( WHEN ls_opt-high IS INITIAL THEN '' ELSE |{ ls_opt-high ALPHA = IN }| ) ) TO lr_lifnr.
  ENDLOOP.
  lr_bsart = VALUE #( FOR o IN it_potype ( sign = o-sign option = o-option low = o-low high = o-high ) ).
  lr_bedat = VALUE #( FOR o IN it_docdate ( sign = o-sign option = o-option low = o-low high = o-high ) ).
  lr_zcont = VALUE #( FOR o IN it_contract ( sign = o-sign option = o-option low = o-low high = o-high ) ).
  " mã dự án: dạng hiển thị -> nội bộ
  LOOP AT it_project INTO ls_opt.
    APPEND VALUE #( sign = ls_opt-sign option = ls_opt-option ) TO lr_pspid ASSIGNING FIELD-SYMBOL(<ls_pspid>).
    IF ls_opt-option = 'CP' OR ls_opt-option = 'NP'.
      <ls_pspid>-low = ls_opt-low.
    ELSE.
      CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
        EXPORTING
          input  = ls_opt-low
        IMPORTING
          output = <ls_pspid>-low.
      IF ls_opt-high IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
          EXPORTING
            input  = ls_opt-high
          IMPORTING
            output = <ls_pspid>-high.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " lọc theo hợp đồng ZCONT (số HĐ tham chiếu / dự án) -> danh sách PO
  IF lr_zcont IS NOT INITIAL OR lr_pspid IS NOT INITIAL.
    SELECT ebeln, elban FROM ztb_cont_header
      WHERE zcont IN @lr_zcont AND pspid IN @lr_pspid
      INTO TABLE @DATA(lt_cont).
    lr_sub = VALUE #( FOR c IN lt_cont ( sign = 'I' option = 'EQ'
                                         low = COND #( WHEN c-elban IS NOT INITIAL THEN c-elban ELSE c-ebeln ) ) ).
    IF lr_zcont IS NOT INITIAL AND lr_pspid IS INITIAL.
      SELECT ebeln FROM ekko WHERE zzhopdong IN @lr_zcont AND bstyp = 'F'
        INTO TABLE @DATA(lt_ekko_cont).
      lr_sub = VALUE #( BASE lr_sub FOR k IN lt_ekko_cont ( sign = 'I' option = 'EQ' low = k-ebeln ) ).
    ENDIF.
    SORT lr_sub BY low.
    DELETE ADJACENT DUPLICATES FROM lr_sub COMPARING low.
    IF lr_sub IS INITIAL.
      APPEND VALUE #( type = 'S' message = |Không có đơn mua hàng nào thỏa điều kiện.| ) TO et_return.
      RETURN.
    ENDIF.
  ENDIF.

  lv_top = COND #( WHEN iv_top <= 0 THEN lc_default_top
                   WHEN iv_top > lc_max_top THEN lc_max_top
                   ELSE iv_top ).

  SELECT COUNT(*) FROM ekko
    WHERE ebeln IN @lr_ebeln AND ebeln IN @lr_sub
      AND bsart IN @lr_bsart AND lifnr IN @lr_lifnr AND bedat IN @lr_bedat
      AND bstyp = 'F'
      AND ( @iv_min_items <= 1
            OR ebeln IN ( SELECT ebeln FROM ekpo WHERE loekz = @space
                          GROUP BY ebeln HAVING COUNT(*) >= @iv_min_items ) )
    INTO @ev_total.

  SELECT ebeln FROM ekko
    WHERE ebeln IN @lr_ebeln AND ebeln IN @lr_sub
      AND bsart IN @lr_bsart AND lifnr IN @lr_lifnr AND bedat IN @lr_bedat
      AND bstyp = 'F'
      AND ( @iv_min_items <= 1
            OR ebeln IN ( SELECT ebeln FROM ekpo WHERE loekz = @space
                          GROUP BY ebeln HAVING COUNT(*) >= @iv_min_items ) )
    ORDER BY ebeln DESCENDING
    INTO CORRESPONDING FIELDS OF TABLE @et_po
    UP TO @lv_top ROWS
    OFFSET @iv_skip.

  APPEND VALUE #( type = 'S'
                  message = |Tìm thấy { ev_total } đơn mua hàng, trả về { lines( et_po ) }.| ) TO et_return.
