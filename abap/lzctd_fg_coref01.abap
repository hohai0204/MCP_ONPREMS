*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_COREF01.
*----------------------------------------------------------------------*
* Subroutine của ZCTD_FM_CREATE_CONT - tạo hợp đồng ZCONT + đơn mua hàng
* theo luồng ZCCM_PG_ZCONT_NEW (ZCONT1). Tên form gốc ghi trong ngoặc.
*   0. Khởi tạo                    cont_init
*   A. Kiểm tra đầu vào            cont_check_selection, cont_chk_*
*   B. Điền giá trị mặc định       cont_default_*, cont_cond_*
*   C. Kiểm tra trước khi lưu      cont_check_*, cont_chk_item_*
*   D. Lưu chứng từ                cont_prepare_header, cont_post_po,
*                                  cont_bapi_*, cont_update_ekko_texts,
*                                  cont_save_tables
*----------------------------------------------------------------------*

*======================================================================*
* 0. Khởi tạo
*======================================================================*
FORM cont_init USING is_header      TYPE ztb_cont_header
                     iv_zbudg       TYPE zde_signbudg_plan_no
                     is_vendor_addr TYPE addr1_dia
                     it_item        TYPE gty_t_cont_item
                     it_partner     TYPE gty_t_cont_partner
                     it_cond        TYPE gty_t_cont_cond_in
               CHANGING cs_doc      TYPE gty_cont_doc.
  CLEAR cs_doc.
  cs_doc-head        = is_header.
  cs_doc-head-mandt  = sy-mandt.
  CLEAR cs_doc-head-ebeln.
  cs_doc-zbudg       = iv_zbudg.
  cs_doc-vendor_addr = is_vendor_addr.
  cs_doc-t_item      = it_item.
  cs_doc-t_partner   = it_partner.
  cs_doc-t_cond_in   = it_cond.
  DELETE cs_doc-t_item WHERE sttit IS INITIAL AND matnr IS INITIAL.

  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
    EXPORTING
      input  = cs_doc-head-pspid
    IMPORTING
      output = cs_doc-pspid_ext.
  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
    EXPORTING
      input  = cs_doc-head-posid
    IMPORTING
      output = cs_doc-posid_ext.
ENDFORM.

*======================================================================*
* A. Kiểm tra đầu vào (CHECK_PARAMETER / CHECK_INPUT / CHECK_AUTHORITY)
*    Dừng ở lỗi đầu tiên giống màn hình chọn ZCONT1.
*======================================================================*
FORM cont_check_selection CHANGING cs_doc    TYPE gty_cont_doc
                                   ct_return TYPE bapiret2_t.
  PERFORM cont_chk_required USING cs_doc CHANGING ct_return.
  CHECK NOT line_exists( ct_return[ type = 'E' ] ).
  PERFORM cont_chk_wbs_in_project USING cs_doc CHANGING ct_return.
  CHECK NOT line_exists( ct_return[ type = 'E' ] ).
  PERFORM cont_chk_vendor USING cs_doc CHANGING ct_return.
  CHECK NOT line_exists( ct_return[ type = 'E' ] ).
  PERFORM cont_chk_contract_used USING cs_doc CHANGING ct_return.
  CHECK NOT line_exists( ct_return[ type = 'E' ] ).
  PERFORM cont_chk_contract_ref USING cs_doc CHANGING ct_return.
  CHECK NOT line_exists( ct_return[ type = 'E' ] ).
  PERFORM cont_chk_authority USING cs_doc CHANGING ct_return.
ENDFORM.

FORM cont_chk_required USING is_doc TYPE gty_cont_doc
                       CHANGING ct_return TYPE bapiret2_t.
  DATA lt_missing TYPE string_table.

  IF is_doc-head-bsart IS INITIAL.
    APPEND `Loại hợp đồng` TO lt_missing.
  ENDIF.
  IF is_doc-head-pspid IS INITIAL.
    APPEND `Mã dự án` TO lt_missing.
  ENDIF.
  IF is_doc-head-posid IS INITIAL.
    APPEND `WBS hợp đồng` TO lt_missing.
  ENDIF.
  IF is_doc-head-lifnr IS INITIAL.
    APPEND `Nhà cung cấp` TO lt_missing.
  ENDIF.
  IF is_doc-head-zcont IS INITIAL.
    APPEND `Số hợp đồng tham chiếu` TO lt_missing.
  ENDIF.
  IF lt_missing IS NOT INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER'
                    message = |Thiếu thông tin bắt buộc: { concat_lines_of( table = lt_missing sep = `, ` ) }.| )
      TO ct_return.
  ENDIF.
ENDFORM.

FORM cont_chk_wbs_in_project USING is_doc TYPE gty_cont_doc
                             CHANGING ct_return TYPE bapiret2_t.
  SELECT SINGLE proj~pspid FROM prps
    INNER JOIN proj ON prps~psphi = proj~pspnr
    WHERE prps~posid = @is_doc-head-posid AND proj~pspid = @is_doc-head-pspid
    INTO @DATA(lv_pspid).
  IF lv_pspid IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'POSID'
                    message = |WBS { is_doc-posid_ext } không thuộc dự án { is_doc-pspid_ext }.| ) TO ct_return.
  ENDIF.
ENDFORM.

FORM cont_chk_vendor USING is_doc TYPE gty_cont_doc
                     CHANGING ct_return TYPE bapiret2_t.
  SELECT SINGLE lifnr FROM lfm1 WHERE lifnr = @is_doc-head-lifnr INTO @DATA(lv_lifnr).
  IF lv_lifnr IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'LIFNR'
                    message = |Nhà cung cấp { is_doc-head-lifnr ALPHA = OUT } không tồn tại hoặc chưa có dữ liệu mua hàng.| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Thầu phụ ZP05/06/07: số HĐ tham chiếu chỉ được dùng cho một đơn mua hàng gốc
FORM cont_chk_contract_used USING is_doc TYPE gty_cont_doc
                            CHANGING ct_return TYPE bapiret2_t.
  CHECK is_doc-head-bsart = 'ZP05' OR is_doc-head-bsart = 'ZP06' OR is_doc-head-bsart = 'ZP07'.

  SELECT SINGLE ztb_cont_header~ebeln, ztb_cont_header~zstatus_por FROM ztb_cont_header
    INNER JOIN ztb_cont_item ON ztb_cont_header~ebeln = ztb_cont_item~ebeln
    INNER JOIN ekko ON ekko~ebeln = ztb_cont_header~ebeln
    WHERE ztb_cont_header~zcont = @is_doc-head-zcont
      AND ztb_cont_header~lifnr = @is_doc-head-lifnr
      AND ztb_cont_header~posid = @is_doc-head-posid
      AND ztb_cont_header~bsart IN ( 'ZP05', 'ZP06', 'ZP07' )
      AND ztb_cont_item~loekz IS INITIAL
    INTO @DATA(ls_po_lock).
  IF ls_po_lock-ebeln IS NOT INITIAL AND ls_po_lock-zstatus_por = 'lock'.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZCONT'
                    message = |Hợp đồng { ls_po_lock-ebeln } của số HĐ tham chiếu { is_doc-head-zcont } đang bị khóa bởi eConstruction.| )
      TO ct_return.
    RETURN.
  ENDIF.

  SELECT SINGLE ztb_cont_header~ebeln FROM ztb_cont_header
    INNER JOIN ztb_cont_item ON ztb_cont_item~ebeln = ztb_cont_header~ebeln
    WHERE ztb_cont_header~zcont EQ @is_doc-head-zcont
      AND ztb_cont_item~loekz IS INITIAL
      AND ztb_cont_header~bsart IN ( 'ZP05', 'ZP06', 'ZP07' )
    INTO @DATA(lv_ebeln).
  IF lv_ebeln IS NOT INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZCONT'
                    message = |Số HĐ tham chiếu { is_doc-head-zcont } đã được dùng cho đơn mua hàng { lv_ebeln }. Hãy tạo phụ lục trên ZCONT.| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Số HĐ tham chiếu phải có trên DMS cho NCC / dự án / WBS (GET_CONTRACT_REF)
FORM cont_chk_contract_ref USING is_doc TYPE gty_cont_doc
                           CHANGING ct_return TYPE bapiret2_t.
  TYPES: BEGIN OF lty_dms_plhd,
           soplhd     TYPE zde_dms_plhd_en,
           maduan     TYPE zde_dms_maduan_en,
           posid      TYPE zde_posid,
           vendorcode TYPE lifnr,
           pccode     TYPE zdd_dms_pccode,
           bsart      TYPE ztb_dms_plhd-bsart,
           ztodoi     TYPE zdd_dms_todoi,
         END OF lty_dms_plhd.
  DATA: lt_plhd  TYPE STANDARD TABLE OF lty_dms_plhd,
        lt_nt    TYPE STANDARD TABLE OF lty_dms_plhd,
        lr_lifn2 TYPE RANGE OF lifn2.

  " người nhận thanh toán (RS) của NCC - dạng có và không có số 0 đầu
  SELECT lifn2 FROM wyt3
    WHERE lifnr = @is_doc-head-lifnr AND ekorg = '1000' AND parvw = 'RS'
    INTO TABLE @DATA(lt_lifn2).
  LOOP AT lt_lifn2 INTO DATA(ls_lifn2).
    APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_lifn2-lifn2 ) TO lr_lifn2.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = |{ ls_lifn2-lifn2 ALPHA = OUT }| ) TO lr_lifn2.
  ENDLOOP.
  DATA(lv_lifnr_like) = CONV char12( |%{ is_doc-head-lifnr ALPHA = OUT }| ).

  SELECT soplhd, maduan, posid, vendorcode, pccode, bsart, ztodoi
    FROM ztb_dms_plhd
    WHERE ztodoi IS INITIAL
      AND soplhd IS NOT INITIAL
      AND bsart <> 'LOA'
      AND vendorcode LIKE @lv_lifnr_like
  UNION DISTINCT
  SELECT soplhd, maduan, posid, vendorcode, pccode, bsart, ztodoi
    FROM ztb_dms_plhd
    WHERE ztodoi LIKE @lv_lifnr_like
      AND soplhd IS NOT INITIAL
      AND bsart <> 'LOA'
      AND vendorcode IN @lr_lifn2
    INTO CORRESPONDING FIELDS OF TABLE @lt_plhd.

  DELETE lt_plhd WHERE soplhd CP '*PL*'.
  " HĐ nguyên tắc (NT) / PC code 00D dùng chung nhiều dự án
  lt_nt = lt_plhd.
  DELETE lt_nt WHERE bsart <> 'NT' AND pccode NP '*00D*' AND pccode IS NOT INITIAL.
  SELECT SINGLE prctr FROM proj WHERE pspid = @is_doc-head-pspid INTO @DATA(lv_prctr).
  DELETE lt_nt WHERE bsart = 'NT' AND pccode IS NOT INITIAL AND pccode NP '*00D*' AND pccode <> lv_prctr.
  DELETE lt_nt WHERE bsart = 'NT' AND posid <> is_doc-head-posid AND posid IS NOT INITIAL.
  " HĐ theo dự án / WBS
  DELETE lt_plhd WHERE maduan <> is_doc-pspid_ext AND maduan IS NOT INITIAL.
  DELETE lt_plhd WHERE posid <> is_doc-head-posid AND posid IS NOT INITIAL.
  APPEND LINES OF lt_nt TO lt_plhd.

  IF NOT line_exists( lt_plhd[ soplhd = is_doc-head-zcont ] ).
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZCONT'
                    message = |Số HĐ tham chiếu { is_doc-head-zcont } không có trên DMS cho nhà cung cấp { is_doc-head-lifnr ALPHA = OUT }, dự án { is_doc-pspid_ext }, WBS { is_doc-posid_ext }.| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Quyền theo Profit center của dự án - đối tượng ZAU_PRCTR (SET_BUTTON)
FORM cont_chk_authority USING is_doc TYPE gty_cont_doc
                        CHANGING ct_return TYPE bapiret2_t.
  DATA: lt_usvalues TYPE STANDARD TABLE OF usvalues,
        lr_prctr    TYPE RANGE OF prctr.

  CALL FUNCTION 'EFG_USER_AUTH_FOR_OBJ_GET'
    EXPORTING
      x_client       = sy-mandt
      x_uname        = sy-uname
      x_object       = 'ZAU_PRCTR'
    TABLES
      yt_usvalues    = lt_usvalues
    EXCEPTIONS
      user_not_found = 1
      not_authorized = 2
      internal_error = 3
      OTHERS         = 4.
  IF sy-subrc = 0.
    LOOP AT lt_usvalues INTO DATA(ls_value) WHERE field = 'PRCTR'.
      IF ls_value-bis IS NOT INITIAL.
        APPEND VALUE #( sign = 'I' option = 'BT' low = ls_value-von high = ls_value-bis ) TO lr_prctr.
      ELSEIF ls_value-von = '*'.
        APPEND VALUE #( sign = 'I' option = 'CP' low = ls_value-von ) TO lr_prctr.
      ELSE.
        APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_value-von ) TO lr_prctr.
      ENDIF.
    ENDLOOP.
  ENDIF.

  SELECT SINGLE pspid FROM proj
    WHERE pspid = @is_doc-head-pspid AND prctr IN @lr_prctr
    INTO @DATA(lv_pspid).
  IF lv_pspid IS INITIAL.
    SELECT SINGLE proj~pspid FROM proj
      INNER JOIN prps ON prps~psphi = proj~pspnr
      WHERE prps~posid = @is_doc-head-posid AND proj~prctr IN @lr_prctr
      INTO @lv_pspid.
  ENDIF.
  IF lv_pspid IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'PSPID'
                    message = |Người dùng { sy-uname } không có quyền tạo hợp đồng cho dự án { is_doc-pspid_ext }.| )
      TO ct_return.
  ENDIF.
ENDFORM.

*======================================================================*
* B. Điền giá trị mặc định (DATA_HEADER_DISPLAY / GET_ITEM /
*    CALCULATE_CONDITION)
*======================================================================*
* Bước tổng của thủ tục giá: bước 1 = Contract Amount, bước 2 = Total
FORM cont_read_pricing_steps CHANGING cs_doc TYPE gty_cont_doc.
  SELECT stunr, vtext FROM t683t
    WHERE vtext IS NOT INITIAL AND spras = @sy-langu
      AND kvewe = 'A' AND kappl = 'M' AND kalsm = 'ZRM000'
    ORDER BY stunr
    INTO CORRESPONDING FIELDS OF TABLE @cs_doc-t_step.
  cs_doc-step     = VALUE #( cs_doc-t_step[ 1 ]-stunr OPTIONAL ).
  cs_doc-step_tax = VALUE #( cs_doc-t_step[ 2 ]-stunr OPTIONAL ).
ENDFORM.

FORM cont_default_header CHANGING cs_doc TYPE gty_cont_doc.
  DATA ls_profile TYPE zcore_st_profile.

  " BOMG lấy theo BOQ đã duyệt kế hoạch ngân sách (KHNS)?
  SELECT SINGLE ztb_over_item~posid FROM ztb_over_item
    INNER JOIN ztb_khns_header AS khns ON khns~version_pr = ztb_over_item~zverbu
                                      AND khns~posid = ztb_over_item~posid
                                      AND khns~status = 'A'
    WHERE ztb_over_item~pspid = @cs_doc-head-pspid AND ztb_over_item~posid = @cs_doc-head-posid
    INTO @DATA(lv_boq_posid).
  cs_doc-check_bomp = xsdbool( lv_boq_posid IS NOT INITIAL ).

  IF cs_doc-head-bsart = 'ZP05' OR cs_doc-head-bsart = 'ZP06' OR cs_doc-head-bsart = 'ZP07'.
    IF cs_doc-head-zipr IS INITIAL.
      cs_doc-head-zipr = 100.
    ENDIF.
  ENDIF.

  " dữ liệu tổ chức lấy theo dự án
  IF cs_doc-head-bukrs IS INITIAL.
    SELECT SINGLE vbukr FROM proj WHERE pspid = @cs_doc-head-pspid INTO @cs_doc-head-bukrs.
    IF cs_doc-head-ekorg IS INITIAL.
      cs_doc-head-ekorg = cs_doc-head-bukrs.
    ENDIF.
  ENDIF.
  IF cs_doc-head-werks IS INITIAL.
    SELECT SINGLE werks, zsloc FROM proj WHERE pspid = @cs_doc-head-pspid
      INTO ( @cs_doc-head-werks, @cs_doc-head-lgort ).
  ENDIF.
  IF cs_doc-head-ekgrp IS INITIAL.
    cs_doc-head-ekgrp = '104'.
  ENDIF.
  IF cs_doc-head-bedat IS INITIAL.
    cs_doc-head-bedat = sy-datum.
  ENDIF.
  IF cs_doc-head-zstatus IS INITIAL.
    cs_doc-head-zstatus = 'O'.
  ENDIF.

  " tên NCC, nhóm BP
  CALL FUNCTION 'ZCORE_FM_GET_PROFILE_BP'
    EXPORTING
      i_number = cs_doc-head-lifnr
      i_kind   = 'K'
    IMPORTING
      profile  = ls_profile.
  cs_doc-head-name_org2 = ls_profile-e_name.
  IF cs_doc-head-name_org2 IS INITIAL.
    SELECT SINGLE name_org1 FROM but000 WHERE partner = @cs_doc-head-lifnr INTO @cs_doc-head-name_org2.
  ENDIF.
  SELECT SINGLE bu_group FROM but000 WHERE partner = @cs_doc-head-lifnr INTO @cs_doc-bu_group.

  PERFORM cont_default_currency CHANGING cs_doc.
  PERFORM cont_default_pay_term CHANGING cs_doc.

  SELECT SINGLE post1 FROM prps WHERE posid = @cs_doc-head-posid INTO @cs_doc-head-posid1.
  SELECT SINGLE post1 FROM proj WHERE pspid = @cs_doc-head-pspid INTO @cs_doc-head-txz01.

  " loại tài khoản ngân hàng đối tác: theo lần duyệt DMS mới nhất
  IF cs_doc-head-zzbvtyp IS INITIAL.
    SELECT zzbvtyp, ztime, ngayduyet FROM ztb_dms_plhd
      WHERE zhdg = @cs_doc-head-zcont AND soplhd IS NOT INITIAL
      INTO TABLE @DATA(lt_zzbvtyp).
    SORT lt_zzbvtyp BY ngayduyet DESCENDING ztime DESCENDING.
    cs_doc-head-zzbvtyp = VALUE #( lt_zzbvtyp[ 1 ]-zzbvtyp OPTIONAL ).
  ENDIF.
ENDFORM.

* Tiền tệ: theo HĐ tham chiếu trên DMS, sau đó theo NCC; tỷ giá M sang VND
FORM cont_default_currency CHANGING cs_doc TYPE gty_cont_doc.
  IF cs_doc-head-cuky IS INITIAL.
    SELECT SINGLE waers FROM lfm1
      WHERE lifnr = @cs_doc-head-lifnr AND ekorg = @cs_doc-head-ekorg
      INTO @cs_doc-head-cuky.
  ENDIF.
  SELECT SINGLE zdvt FROM ztb_dms_plhd
    WHERE soplhd = @cs_doc-head-zcont AND maduan = @cs_doc-pspid_ext
    INTO @DATA(lv_zdvt).
  IF lv_zdvt IS NOT INITIAL.
    cs_doc-head-cuky = lv_zdvt.
  ENDIF.
  IF cs_doc-head-cuky IS INITIAL.
    SELECT SINGLE waers FROM lfm1 WHERE lifnr = @cs_doc-head-lifnr INTO @cs_doc-head-cuky.
  ENDIF.

  CHECK cs_doc-head-wkurs IS INITIAL.
  IF cs_doc-head-cuky = 'VND'.
    cs_doc-head-wkurs = 1.
  ELSE.
    " GDATU là ngày đảo ngược -> giá trị nhỏ nhất là ngày gần nhất
    SELECT gdatu, ukurs FROM tcurr
      WHERE kurst = 'M' AND tcurr = 'VND' AND fcurr = @cs_doc-head-cuky
      ORDER BY gdatu
      INTO TABLE @DATA(lt_tcurr).
    cs_doc-head-wkurs = VALUE #( lt_tcurr[ 1 ]-ukurs OPTIONAL ).
  ENDIF.
ENDFORM.

* Điều khoản thanh toán: số ngày trên DMS, nếu không có thì theo NCC
FORM cont_default_pay_term CHANGING cs_doc TYPE gty_cont_doc.
  CHECK cs_doc-head-zterm IS INITIAL.

  SELECT SINGLE amount FROM ztb_dms_plhd_ps
    WHERE zno = '2' AND soplhd = @cs_doc-head-zcont
    INTO @DATA(lv_days).
  DATA(lv_ztag) = CONV dztage( CONV int4( lv_days ) ).
  IF lv_ztag IS NOT INITIAL.
    SELECT SINGLE t052~zterm FROM t052
      INNER JOIN t052u ON t052~zterm = t052u~zterm AND t052u~spras = @sy-langu
      WHERE t052~ztag1 = @lv_ztag AND t052u~text1 IS NOT INITIAL
      INTO @cs_doc-head-zterm.
  ENDIF.
  IF cs_doc-head-zterm IS INITIAL.
    SELECT SINGLE zterm FROM lfm1
      WHERE lifnr = @cs_doc-head-lifnr AND ekorg = @cs_doc-head-ekorg
      INTO @cs_doc-head-zterm.
  ENDIF.
ENDFORM.

* Tab Partner: nếu không truyền thì lấy theo chức năng đối tác của NCC,
* RS/LF thay bằng NCC / tổ đội trên lần duyệt DMS mới nhất
FORM cont_default_partner CHANGING cs_doc TYPE gty_cont_doc.
  IF cs_doc-t_partner IS INITIAL.
    SELECT wyt3~parvw, tpart~vtext, wyt3~lifn2, lfa1~name1
      FROM wyt3
      INNER JOIN tpart ON wyt3~parvw = tpart~parvw AND tpart~spras = 'E'
      INNER JOIN lfa1 ON lfa1~lifnr = wyt3~lifn2
      WHERE wyt3~lifnr = @cs_doc-head-lifnr AND wyt3~ekorg = @cs_doc-head-ekorg
        AND wyt3~parza < '002'
      ORDER BY wyt3~parvw
      INTO TABLE @DATA(lt_wyt3).
    cs_doc-t_partner = VALUE #( FOR ls_wyt3 IN lt_wyt3
                                ( parvw = ls_wyt3-parvw vtext = ls_wyt3-vtext
                                  lifnr = ls_wyt3-lifn2 name  = ls_wyt3-name1 ) ).

    SELECT ztodoi, vendorcode, ztime, ngayduyet FROM ztb_dms_plhd
      WHERE zhdg = @cs_doc-head-zcont
      INTO TABLE @DATA(lt_dms).
    SORT lt_dms BY ngayduyet DESCENDING ztime DESCENDING.
    READ TABLE lt_dms INTO DATA(ls_dms) INDEX 1.
    IF sy-subrc = 0.
      DATA(lv_vendor) = CONV lifnr( |{ ls_dms-vendorcode ALPHA = IN }| ).
      DATA(lv_todoi)  = CONV lifnr( |{ ls_dms-ztodoi ALPHA = IN }| ).
      SELECT SINGLE name1 FROM lfa1 WHERE lifnr = @lv_vendor INTO @DATA(lv_vendor_name).
      SELECT SINGLE name1 FROM lfa1 WHERE lifnr = @lv_todoi INTO @DATA(lv_todoi_name).
      LOOP AT cs_doc-t_partner ASSIGNING FIELD-SYMBOL(<ls_partner>).
        CASE <ls_partner>-parvw.
          WHEN 'RS'.
            <ls_partner>-lifnr = lv_vendor.
            <ls_partner>-name  = lv_vendor_name.
          WHEN 'LF'.
            IF lv_todoi IS NOT INITIAL.
              <ls_partner>-lifnr = lv_todoi.
              <ls_partner>-name  = lv_todoi_name.
            ELSE.
              <ls_partner>-lifnr = lv_vendor.
              <ls_partner>-name  = lv_vendor_name.
            ENDIF.
        ENDCASE.
      ENDLOOP.
    ENDIF.
  ENDIF.

  DELETE cs_doc-t_partner WHERE parvw IS INITIAL.
  LOOP AT cs_doc-t_partner ASSIGNING <ls_partner>.
    <ls_partner>-mandt = sy-mandt.
    <ls_partner>-sttpn = sy-tabix.
    <ls_partner>-bsart = cs_doc-head-bsart.
  ENDLOOP.
ENDFORM.

* Tab Item Overview (GET_ITEM)
FORM cont_default_items CHANGING cs_doc    TYPE gty_cont_doc
                                 ct_return TYPE bapiret2_t.
  SORT cs_doc-t_item BY sttit.
  DATA(lv_last_no) = VALUE zde_no( cs_doc-t_item[ lines( cs_doc-t_item ) ]-sttit OPTIONAL ).

  LOOP AT cs_doc-t_item ASSIGNING FIELD-SYMBOL(<ls_item>).
    IF <ls_item>-sttit IS INITIAL.
      lv_last_no = lv_last_no + 10.
      <ls_item>-sttit = lv_last_no.
    ENDIF.
    PERFORM cont_default_item USING cs_doc CHANGING <ls_item> ct_return.
  ENDLOOP.
ENDFORM.

FORM cont_default_item USING    is_doc    TYPE gty_cont_doc
                       CHANGING cs_item   TYPE ztb_cont_item
                                ct_return TYPE bapiret2_t.
  DATA lv_menge TYPE menge_d.

  cs_item-mandt = sy-mandt.
  CLEAR: cs_item-ebeln, cs_item-elban, cs_item-posnr.
  IF cs_item-peinh IS INITIAL.
    cs_item-peinh = 1.
  ENDIF.

  " dữ liệu vật tư
  SELECT SINGLE meins, matkl, extwg FROM mara WHERE matnr = @cs_item-matnr INTO @DATA(ls_mara).
  IF cs_item-meins IS INITIAL.
    cs_item-meins = ls_mara-meins.
  ENDIF.
  IF cs_item-matkl IS INITIAL.
    cs_item-matkl = ls_mara-matkl.
  ENDIF.
  IF cs_item-extwg IS INITIAL.
    cs_item-extwg = ls_mara-extwg.
  ENDIF.
  IF cs_item-txz01 IS INITIAL OR cs_item-txz01_1 IS INITIAL.
    SELECT SINGLE maktx FROM makt WHERE matnr = @cs_item-matnr AND spras = @sy-langu INTO @DATA(lv_maktx).
    IF cs_item-txz01 IS INITIAL.
      cs_item-txz01 = lv_maktx.
    ENDIF.
    IF cs_item-txz01_1 IS INITIAL.
      cs_item-txz01_1 = lv_maktx.
    ENDIF.
  ENDIF.

  " quy đổi đơn vị: đơn vị đặt hàng / đơn vị giá / đơn vị cơ sở
  IF cs_item-bprme_po IS INITIAL.
    cs_item-bprme_po = cs_item-meins.
  ENDIF.
  cs_item-lmei2   = ls_mara-meins.
  cs_item-meins_1 = ls_mara-meins.
  cs_item-mein2   = cs_item-meins.
  cs_item-mein3   = cs_item-meins.
  IF cs_item-mein3 = cs_item-lmei2.
    cs_item-umren = 1.
    cs_item-umrez = 1.
  ELSE.
    SELECT SINGLE umren, umrez FROM marm WHERE matnr = @cs_item-matnr AND meinh = @cs_item-mein3
      INTO ( @cs_item-umren, @cs_item-umrez ).
  ENDIF.
  lv_menge = cs_item-menge.
  CALL FUNCTION 'MD_CONVERT_MATERIAL_UNIT'
    EXPORTING
      i_matnr              = cs_item-matnr
      i_in_me              = cs_item-meins
      i_out_me             = cs_item-meins_1
      i_menge              = lv_menge
    IMPORTING
      e_menge              = lv_menge
    EXCEPTIONS
      error_in_application = 1
      error                = 2
      OTHERS               = 3.
  IF sy-subrc = 0.
    cs_item-lagmg = lv_menge.
  ENDIF.
  IF cs_item-lmei2 = cs_item-bprme_po AND cs_item-lmei2 = cs_item-meins.
    cs_item-bpumn = 1.
    cs_item-bpumz = 1.
  ELSEIF cs_item-bpumn IS INITIAL OR cs_item-bpumz IS INITIAL.
    CALL FUNCTION 'ME_CONVERSION_BPRME'
      EXPORTING
        i_matnr             = cs_item-matnr
        i_mein1             = cs_item-mein2
        i_mein2             = cs_item-bprme_po
        i_meins             = cs_item-lmei2
      IMPORTING
        kumne               = cs_item-bpumn
        kumza               = cs_item-bpumz
      EXCEPTIONS
        error_in_conversion = 1
        no_success          = 2
        OTHERS              = 3.
    IF sy-subrc <> 0.
      CLEAR: cs_item-bpumn, cs_item-bpumz.
    ENDIF.
  ENDIF.
  TRY.
      cs_item-mgame = cs_item-menge * cs_item-bpumz / cs_item-bpumn.
    CATCH cx_sy_arithmetic_error.
      cs_item-mgame = cs_item-menge.
  ENDTRY.

  " tài khoản, nhận hàng / hóa đơn, dung sai giao hàng
  cs_item-kokrs = 'CTC'.
  IF cs_item-knttp IS INITIAL.
    cs_item-knttp = 'P'.
  ENDIF.
  SELECT SINGLE wepos, repos, weunb FROM t163k WHERE knttp = @cs_item-knttp
    INTO ( @cs_item-wepos, @cs_item-repos, @cs_item-weunb ).
  IF cs_item-webre IS INITIAL.
    cs_item-webre = cs_item-repos.
  ENDIF.
  SELECT SINGLE t405~uebto, t405~untto, t405~uebtk FROM t405
    INNER JOIN mara ON mara~ekwsl = t405~ekwsl
    WHERE mara~matnr = @cs_item-matnr
    INTO ( @cs_item-uebto, @cs_item-untto, @cs_item-uebtk ).
  cs_item-waers = is_doc-head-cuky.
  cs_item-werks = is_doc-head-werks.
  cs_item-lgort = is_doc-head-lgort.
  IF is_doc-head-zback IS NOT INITIAL.
    cs_item-zback = 'X'.
  ENDIF.

  " thành tiền = số lượng theo đơn vị giá * đơn giá / đơn vị tính giá
  IF cs_item-zamount IS INITIAL.
    TRY.
        cs_item-zamount = cs_item-mgame * cs_item-netpr / cs_item-peinh.
      CATCH cx_sy_arithmetic_error.
        APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = cs_item-sttit field = 'NETPR'
                        message = |Dòng { CONV i( cs_item-sttit ) }: thành tiền vượt quá giới hạn cho phép, kiểm tra lại số lượng và đơn giá.| )
          TO ct_return.
    ENDTRY.
  ENDIF.
  IF is_doc-head-bsart <> 'ZP05' AND is_doc-head-bsart <> 'ZP06' AND is_doc-head-bsart <> 'ZP07'.
    cs_item-zamount1 = cs_item-zamount.
  ENDIF.
  IF cs_item-zamount1 IS INITIAL.
    cs_item-zamount1 = cs_item-zamount.
  ENDIF.

  " CSI theo BOMG, BOMP theo dự án / WBS
  SELECT SINGLE csi_code FROM ztb_bomg_header WHERE zbomg_code = @cs_item-zbomg_code
    INTO @cs_item-csi_code.
  SELECT SINGLE csi_group, csi_gdesc FROM ztb_csi WHERE csi_code = @cs_item-csi_code
    INTO ( @cs_item-csi_group, @cs_item-csi_gdesc ).
  cs_item-fipex = cs_item-csi_group.
  SELECT SINGLE ztb_bomp_header~zbomp_code FROM ztb_bomp_item
    INNER JOIN ztb_bomp_header ON ztb_bomp_item~zbomp_code = ztb_bomp_header~zbomp_code
                              AND ztb_bomp_item~pspid = ztb_bomp_header~pspid
                              AND ztb_bomp_item~posid = ztb_bomp_header~posid
    WHERE ztb_bomp_item~pspid = @is_doc-head-pspid
      AND ztb_bomp_item~posid = @is_doc-head-posid
      AND ztb_bomp_item~zbomg_code = @cs_item-zbomg_code
    INTO @cs_item-zbomp_code.
ENDFORM.

* Tab Condition (GET_ITEM + CALCULATE_CONDITION)
FORM cont_build_conditions CHANGING cs_doc    TYPE gty_cont_doc
                                    ct_return TYPE bapiret2_t.
  PERFORM cont_cond_item_price     CHANGING cs_doc.
  PERFORM cont_cond_header_input   CHANGING cs_doc ct_return.
  PERFORM cont_cond_header_value   CHANGING cs_doc.
  PERFORM cont_cond_distribute     CHANGING cs_doc.
  PERFORM cont_cond_tax            CHANGING cs_doc.
  PERFORM cont_cond_subtotals      CHANGING cs_doc.
ENDFORM.

* Thứ tự bước / tên điều kiện trong thủ tục giá ZRM000
FORM cont_cond_step_text USING    iv_kschl TYPE kschl
                         CHANGING cs_cond  TYPE zst_cond_item.
  SELECT SINGLE t683s~stunr, t683s~zaehk, t685t~vtext FROM t683s
    INNER JOIN t685t ON t685t~kschl = t683s~kschl AND t685t~spras = @sy-langu AND t685t~kappl = 'M'
    WHERE t683s~kvewe = 'A' AND t683s~kappl = 'M' AND t683s~kalsm = 'ZRM000'
      AND t683s~kschl = @iv_kschl
    INTO ( @cs_cond-stunr, @cs_cond-zaehk, @cs_cond-vtext ).
  cs_cond-kschl = iv_kschl.
ENDFORM.

* Giá gốc PBXX của từng dòng + điều kiện bổ sung của dòng; PBXX header
FORM cont_cond_item_price CHANGING cs_doc TYPE gty_cont_doc.
  DATA ls_cond TYPE zst_cond_item.

  LOOP AT cs_doc-t_item INTO DATA(ls_item) WHERE umson IS INITIAL AND loekz IS INITIAL.
    CLEAR ls_cond.
    PERFORM cont_cond_step_text USING 'PBXX' CHANGING ls_cond.
    ls_cond-sttit = ls_item-sttit.
    ls_cond-kbetr = ls_item-netpr.
    TRY.
        ls_cond-kwert = ls_item-netpr * ls_item-mgame / ls_item-peinh.
      CATCH cx_sy_arithmetic_error.
        CLEAR ls_cond-kwert.
    ENDTRY.
    IF ls_item-retpo IS NOT INITIAL.
      ls_cond-kwert = - ls_cond-kwert.
    ENDIF.
    ls_cond-waerk = ls_item-waers.
    ls_cond-koein = ls_item-waers.
    ls_cond-kpein = ls_item-peinh.
    ls_cond-kmein = ls_item-bprme_po.
    APPEND ls_cond TO cs_doc-t_cond_i.

    LOOP AT cs_doc-t_cond_in INTO DATA(ls_in) WHERE sttit = ls_item-sttit AND kschl IS NOT INITIAL
                                              AND kschl <> 'PBXX' AND kschl <> 'MWST'.
      ls_cond = CORRESPONDING #( ls_in ).
      PERFORM cont_cond_step_text USING ls_in-kschl CHANGING ls_cond.
      CLEAR ls_cond-zhead.
      ls_cond-waerk = ls_item-waers.
      ls_cond-kpein = ls_item-peinh.
      ls_cond-kmein = ls_item-bprme_po.
      APPEND ls_cond TO cs_doc-t_cond_i.
    ENDLOOP.
  ENDLOOP.

  DATA(lv_kwert) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                     FOR c IN cs_doc-t_cond_i WHERE ( kschl = 'PBXX' ) NEXT s = s + c-kwert ).
  IF lv_kwert IS NOT INITIAL.
    CLEAR ls_cond.
    PERFORM cont_cond_step_text USING 'PBXX' CHANGING ls_cond.
    ls_cond-kwert = lv_kwert.
    ls_cond-waerk = cs_doc-head-cuky.
    APPEND ls_cond TO cs_doc-t_cond_h.
  ENDIF.
ENDFORM.

* Điều kiện header nhập ở tab Condition (ZHEAD = 'X')
FORM cont_cond_header_input CHANGING cs_doc    TYPE gty_cont_doc
                                     ct_return TYPE bapiret2_t.
  DATA: ls_cond TYPE zst_cond_item,
        lv_line TYPE zde_no.

  LOOP AT cs_doc-t_cond_in INTO DATA(ls_in) WHERE sttit IS INITIAL AND kschl IS NOT INITIAL AND kschl <> 'PBXX'.
    IF ls_in-kschl = 'MWST'.
      APPEND VALUE #( type = 'E' parameter = 'IT_COND' field = 'KSCHL'
                      message = |Thuế GTGT (MWST) được tính tự động theo vật tư, không nhập ở điều kiện chung của hợp đồng.| )
        TO ct_return.
      CONTINUE.
    ENDIF.
    ls_cond = CORRESPONDING #( ls_in ).
    PERFORM cont_cond_step_text USING ls_in-kschl CHANGING ls_cond.
    lv_line = lv_line + 1.
    ls_cond-zhead       = 'X'.
    ls_cond-zcond_line  = lv_line.
    ls_cond-zcond_line1 = lv_line.
    ls_cond-waerk       = cs_doc-head-cuky.
    APPEND ls_cond TO cs_doc-t_cond_h.
  ENDLOOP.
ENDFORM.

* Giá trị điều kiện header: % trên giá trị trước nó, hoặc số tiền cố định
FORM cont_cond_header_value CHANGING cs_doc TYPE gty_cont_doc.
  SORT cs_doc-t_cond_h BY stunr zaehk zcond_line1.
  LOOP AT cs_doc-t_cond_h ASSIGNING FIELD-SYMBOL(<ls_cond>) WHERE zhead = 'X'.
    SELECT SINGLE krech, knega FROM t685a WHERE kappl = 'M' AND kschl = @<ls_cond>-kschl
      INTO @DATA(ls_t685a).
    IF ls_t685a-krech = 'A'.
      <ls_cond>-koein = '%'.
      DATA(lv_base) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                        FOR c IN cs_doc-t_cond_h
                        WHERE ( kschl IS NOT INITIAL AND ( stunr < <ls_cond>-stunr
                                OR ( stunr = <ls_cond>-stunr AND zcond_line1 < <ls_cond>-zcond_line1 ) ) )
                        NEXT s = s + c-kwert ).
      <ls_cond>-kwert = lv_base * <ls_cond>-kbetr / 100.
    ELSE.
      <ls_cond>-koein = cs_doc-head-cuky.
      IF <ls_cond>-kwert IS INITIAL.
        <ls_cond>-kwert = <ls_cond>-kbetr.
      ENDIF.
    ENDIF.
    IF ls_t685a-knega = 'X' AND <ls_cond>-kwert > 0.
      <ls_cond>-kwert = - <ls_cond>-kwert.
    ENDIF.
    CLEAR ls_t685a.
  ENDLOOP.
ENDFORM.

* Phân bổ điều kiện header xuống từng dòng theo tỷ lệ giá trị dòng;
* chênh lệch làm tròn dồn vào dòng có giá trị lớn nhất
FORM cont_cond_distribute CHANGING cs_doc TYPE gty_cont_doc.
  DATA ls_cond TYPE zst_cond_item.

  LOOP AT cs_doc-t_item INTO DATA(ls_item) WHERE umson IS INITIAL AND loekz IS INITIAL.
    LOOP AT cs_doc-t_cond_h INTO DATA(ls_head_cond) WHERE zhead = 'X' AND kschl <> 'PBXX' AND kschl <> 'MWST'.
      SELECT SINGLE kkopf FROM t685a WHERE kappl = 'M' AND kschl = @ls_head_cond-kschl INTO @DATA(lv_kkopf).
      IF lv_kkopf IS INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR lv_kkopf.
      DATA(lv_base) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                        FOR c IN cs_doc-t_cond_h
                        WHERE ( kschl IS NOT INITIAL AND ( stunr < ls_head_cond-stunr
                                OR ( stunr = ls_head_cond-stunr AND zcond_line1 < ls_head_cond-zcond_line1 ) ) )
                        NEXT s = s + c-kwert ).
      DATA(lv_item_base) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                             FOR c IN cs_doc-t_cond_i
                             WHERE ( sttit = ls_item-sttit AND kschl IS NOT INITIAL
                                     AND ( stunr < ls_head_cond-stunr
                                           OR ( stunr = ls_head_cond-stunr AND zcond_line1 < ls_head_cond-zcond_line1 ) ) )
                             NEXT s = s + c-kwert ).
      CHECK lv_base IS NOT INITIAL.
      ls_cond       = ls_head_cond.
      ls_cond-zhead = 'X'.
      ls_cond-sttit = ls_item-sttit.
      ls_cond-waerk = ls_item-waers.
      ls_cond-kpein = ls_item-peinh.
      ls_cond-kmein = ls_item-bprme_po.
      TRY.
          ls_cond-kwert = ( ls_head_cond-kwert / lv_base * lv_item_base ) / ls_item-peinh.
        CATCH cx_sy_arithmetic_error.
          CLEAR ls_cond-kwert.
      ENDTRY.
      IF ls_item-retpo IS NOT INITIAL.
        ls_cond-kwert = - ls_cond-kwert.
      ENDIF.
      APPEND ls_cond TO cs_doc-t_cond_i.
    ENDLOOP.
  ENDLOOP.

  " chênh lệch làm tròn
  LOOP AT cs_doc-t_cond_h INTO ls_head_cond WHERE zhead = 'X' AND kschl <> 'PBXX' AND kschl <> 'MWST'.
    DATA(lt_split) = cs_doc-t_cond_i.
    DELETE lt_split WHERE zhead IS INITIAL OR kschl <> ls_head_cond-kschl OR zcond_line1 <> ls_head_cond-zcond_line1.
    SORT lt_split BY kwert DESCENDING sttit DESCENDING.
    READ TABLE lt_split INTO DATA(ls_biggest) INDEX 1.
    CHECK sy-subrc = 0.
    READ TABLE cs_doc-t_cond_i ASSIGNING FIELD-SYMBOL(<ls_biggest>)
      WITH KEY sttit = ls_biggest-sttit kschl = ls_head_cond-kschl zcond_line1 = ls_head_cond-zcond_line1 zhead = 'X'.
    IF sy-subrc = 0.
      <ls_biggest>-kwert = ls_head_cond-kwert
                         - REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                             FOR c IN lt_split WHERE ( sttit <> ls_biggest-sttit ) NEXT s = s + c-kwert ).
    ENDIF.
  ENDLOOP.
ENDFORM.

* Thuế GTGT MWST theo dòng: thuế suất từ A905 (nhà máy + chỉ tiêu thuế
* của vật tư), cộng dồn lên header
FORM cont_cond_tax CHANGING cs_doc TYPE gty_cont_doc.
  DATA ls_cond TYPE zst_cond_item.

  LOOP AT cs_doc-t_item INTO DATA(ls_item) WHERE umson IS INITIAL AND loekz IS INITIAL.
    SELECT SINGLE taxim FROM mlan WHERE matnr = @ls_item-matnr AND aland = 'VN' INTO @DATA(lv_taxim).
    IF lv_taxim IS INITIAL.
      CONTINUE.
    ENDIF.
    SELECT SINGLE division( t007v~kbetr, 1000, 3 ) FROM a905
      INNER JOIN konp ON a905~knumh = konp~knumh
      INNER JOIN t007v ON t007v~mwskz = konp~mwsk1
      WHERE a905~werks = @cs_doc-head-werks AND a905~taxim = @lv_taxim AND t007v~aland = 'VN'
      INTO @DATA(lv_rate).
    CLEAR lv_taxim.
    DATA(lv_step) = cs_doc-step.
    DATA(lv_base) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                      FOR c IN cs_doc-t_cond_i
                      WHERE ( sttit = ls_item-sttit AND kschl IS NOT INITIAL AND stunr < lv_step AND stunr > '000' )
                      NEXT s = s + c-kwert ).
    CLEAR ls_cond.
    PERFORM cont_cond_step_text USING 'MWST' CHANGING ls_cond.
    ls_cond-sttit = ls_item-sttit.
    ls_cond-kbetr = lv_rate * 100.
    ls_cond-kwert = lv_base * lv_rate.
    ls_cond-waerk = ls_item-waers.
    ls_cond-koein = '%'.
    ls_cond-kpein = ls_item-peinh.
    APPEND ls_cond TO cs_doc-t_cond_i.
    CLEAR lv_rate.
  ENDLOOP.

  CHECK line_exists( cs_doc-t_cond_i[ kschl = 'MWST' ] ).
  CLEAR ls_cond.
  PERFORM cont_cond_step_text USING 'MWST' CHANGING ls_cond.
  ls_cond-kwert = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                    FOR c IN cs_doc-t_cond_i WHERE ( kschl = 'MWST' ) NEXT s = s + c-kwert ).
  ls_cond-waerk = cs_doc-head-cuky.
  ls_cond-koein = '%'.
  IF ls_cond-kwert <> 0.
    APPEND ls_cond TO cs_doc-t_cond_h.
  ENDIF.
ENDFORM.

* Dòng tổng (KSCHL rỗng) theo từng bước tổng: cho từng dòng và header
FORM cont_cond_subtotals CHANGING cs_doc TYPE gty_cont_doc.
  DATA ls_cond TYPE zst_cond_item.

  LOOP AT cs_doc-t_item INTO DATA(ls_item) WHERE umson IS INITIAL AND loekz IS INITIAL.
    LOOP AT cs_doc-t_step INTO DATA(ls_step).
      CLEAR ls_cond.
      ls_cond-sttit = ls_item-sttit.
      ls_cond-stunr = ls_step-stunr.
      ls_cond-vtext = ls_step-vtext.
      ls_cond-kpein = ls_item-peinh.
      ls_cond-kwert = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                        FOR c IN cs_doc-t_cond_i
                        WHERE ( sttit = ls_item-sttit AND kschl IS NOT INITIAL AND stunr < ls_step-stunr )
                        NEXT s = s + c-kwert ).
      TRY.
          ls_cond-kbetr = abs( ls_cond-kwert / ls_item-mgame * ls_item-peinh ).
        CATCH cx_sy_arithmetic_error.
          CLEAR ls_cond-kbetr.
      ENDTRY.
      ls_cond-waerk = cs_doc-head-cuky.
      ls_cond-koein = cs_doc-head-cuky.
      ls_cond-kmein = ls_item-bprme_po.
      APPEND ls_cond TO cs_doc-t_cond_i.
    ENDLOOP.
  ENDLOOP.

  LOOP AT cs_doc-t_step INTO ls_step.
    CLEAR ls_cond.
    ls_cond-stunr = ls_step-stunr.
    ls_cond-vtext = ls_step-vtext.
    ls_cond-kwert = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                      FOR c IN cs_doc-t_cond_h
                      WHERE ( kschl IS NOT INITIAL AND stunr < ls_step-stunr AND zdelete IS INITIAL )
                      NEXT s = s + c-kwert ).
    ls_cond-waerk = cs_doc-head-cuky.
    APPEND ls_cond TO cs_doc-t_cond_h.
  ENDLOOP.
ENDFORM.

* Dữ liệu tra cứu cho bước kiểm tra: WBS cấp 4, Brand, danh mục TVARVC
FORM cont_read_check_data CHANGING cs_doc TYPE gty_cont_doc.
  TYPES: BEGIN OF lty_objek,
           objek TYPE inob-objek,
         END OF lty_objek.
  DATA: lt_objek    TYPE STANDARD TABLE OF lty_objek,
        lt_psp_tree TYPE STANDARD TABLE OF prhi,
        lv_up       TYPE prhi-up,
        lv_posid    TYPE prps-posid.

  " WBS cấp 4 của dự án có WBS cấp 1 = WBS hợp đồng
  SELECT prps~psphi, prps~posid FROM prps
    INNER JOIN proj ON proj~pspnr = prps~psphi
    WHERE proj~pspid = @cs_doc-head-pspid AND prps~stufe = '4'
    ORDER BY prps~posid
    INTO TABLE @cs_doc-t_wbs.
  LOOP AT cs_doc-t_wbs INTO DATA(ls_wbs).
    DATA(lv_tabix) = sy-tabix.
    lv_posid = ls_wbs-posid.
    DO 3 TIMES.                           " cấp 4 -> 3 -> 2 -> 1
      CLEAR lt_psp_tree.
      CALL FUNCTION 'GET_TREE_FROM_PRHI'
        EXPORTING
          i_posid             = lv_posid
        TABLES
          psp_tree            = lt_psp_tree
        EXCEPTIONS
          input_error         = 1
          psp_hierarchy_error = 2
          psp_not_found       = 3
          OTHERS              = 4.
      lv_up = VALUE #( lt_psp_tree[ 1 ]-up OPTIONAL ).
      CLEAR lv_posid.
      SELECT SINGLE posid FROM prps WHERE pspnr = @lv_up INTO @lv_posid.
    ENDDO.
    IF lv_posid <> cs_doc-head-posid.
      DELETE cs_doc-t_wbs INDEX lv_tabix.
    ENDIF.
  ENDLOOP.

  " giá trị Brand hợp lệ (đặc tính có ATAUTH = 'BRA') của các vật tư
  lt_objek = VALUE #( FOR i IN cs_doc-t_item WHERE ( matnr IS NOT INITIAL ) ( objek = i-matnr ) ).
  IF lt_objek IS NOT INITIAL.
    SELECT klah~class, inob~objek AS matnr, ksml~imerk AS atinn, cawn~atwrt AS brand
      FROM inob
      INNER JOIN kssk ON kssk~objek = inob~cuobj AND kssk~klart = inob~klart
      INNER JOIN ksml ON ksml~clint = kssk~clint AND ksml~klart = kssk~klart
      INNER JOIN klah ON klah~clint = kssk~clint AND klah~klart = kssk~klart
      INNER JOIN cabn ON cabn~atinn = ksml~imerk AND cabn~atauth = 'BRA'
      INNER JOIN cawnt ON cawnt~atinn = cabn~atinn
      INNER JOIN cawn ON cawnt~atinn = cawn~atinn AND cawnt~atzhl = cawn~atzhl AND cawnt~adzhl = cawn~adzhl
      FOR ALL ENTRIES IN @lt_objek
      WHERE inob~objek = @lt_objek-objek
      INTO CORRESPONDING FIELDS OF TABLE @cs_doc-t_brand.
    SORT cs_doc-t_brand BY matnr brand.
  ENDIF.

  " hợp đồng thuê thiết bị ZP08: vật tư cần khai thiết bị, loại vật tư thiết bị
  IF cs_doc-head-bsart = 'ZP08'.
    SELECT sign, opti AS option, low, high FROM tvarvc WHERE name = 'ZCONT_TB'
      INTO CORRESPONDING FIELDS OF TABLE @cs_doc-r_zcont_tb.
    LOOP AT cs_doc-r_zcont_tb ASSIGNING FIELD-SYMBOL(<ls_tb>).
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input        = <ls_tb>-low
        IMPORTING
          output       = <ls_tb>-low
        EXCEPTIONS
          length_error = 1
          OTHERS       = 2.
    ENDLOOP.
    SELECT sign, opti AS option, low, high FROM tvarvc WHERE name = 'ZCONT_EQUIPMENT'
      INTO CORRESPONDING FIELDS OF TABLE @cs_doc-r_mtart_eq.
  ENDIF.
ENDFORM.

*======================================================================*
* C. Kiểm tra trước khi lưu (CHECK_PLHD_SAVE / CHECK_SAVE)
*======================================================================*
FORM cont_check_header CHANGING cs_doc    TYPE gty_cont_doc
                                ct_return TYPE bapiret2_t.
  PERFORM cont_chk_annex      USING cs_doc CHANGING ct_return.
  PERFORM cont_chk_plan_no    USING cs_doc CHANGING ct_return.
  PERFORM cont_chk_org_data   USING cs_doc CHANGING ct_return.
  PERFORM cont_chk_bank_type  USING cs_doc CHANGING ct_return.
  PERFORM cont_chk_quantity   USING cs_doc CHANGING ct_return.
ENDFORM.

* Đã có đơn mua hàng gốc thầu phụ -> phải đi luồng phụ lục (CHECK_PLHD_SAVE)
FORM cont_chk_annex USING is_doc TYPE gty_cont_doc
                    CHANGING ct_return TYPE bapiret2_t.
  CHECK is_doc-head-bsart = 'ZP05' OR is_doc-head-bsart = 'ZP06' OR is_doc-head-bsart = 'ZP07'.
  SELECT SINGLE ztb_cont_header~ebeln FROM ztb_cont_header
    INNER JOIN ztb_cont_item ON ztb_cont_header~ebeln = ztb_cont_item~ebeln
    INNER JOIN ekko ON ekko~ebeln = ztb_cont_header~ebeln
    WHERE ztb_cont_header~zcont = @is_doc-head-zcont AND ztb_cont_header~pspid = @is_doc-head-pspid
      AND ztb_cont_header~posid = @is_doc-head-posid AND ztb_cont_header~bsart IN ( 'ZP05', 'ZP06', 'ZP07' )
      AND ztb_cont_item~loekz IS INITIAL
    INTO @DATA(lv_ebeln).
  IF lv_ebeln IS NOT INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZCONT'
                    message = |Số HĐ tham chiếu { is_doc-head-zcont } đã có đơn mua hàng gốc { lv_ebeln }. Chức năng này không tạo phụ lục, hãy dùng ZCONT.| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Kế hoạch ký kết / kế hoạch ngân sách
FORM cont_chk_plan_no USING is_doc TYPE gty_cont_doc
                      CHANGING ct_return TYPE bapiret2_t.
  IF is_doc-head-zsign IS NOT INITIAL.
    SELECT SINGLE zsign FROM ztb_sbpl_header WHERE zsign = @is_doc-head-zsign INTO @DATA(lv_zsign).
    IF sy-subrc <> 0.
      APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZSIGN'
                      message = |Số kế hoạch ký kết { is_doc-head-zsign } không tồn tại.| ) TO ct_return.
    ENDIF.
  ENDIF.
  IF is_doc-zbudg IS NOT INITIAL.
    IF is_doc-head-zsign IS NOT INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IV_ZBUDG'
                      message = |Chỉ được nhập một trong hai: số kế hoạch ký kết hoặc số kế hoạch ngân sách.| ) TO ct_return.
    ENDIF.
    SELECT SINGLE zsign FROM ztb_sbpl_header WHERE zsign = @is_doc-zbudg INTO @lv_zsign.
    IF sy-subrc <> 0.
      APPEND VALUE #( type = 'E' parameter = 'IV_ZBUDG'
                      message = |Số kế hoạch ngân sách { is_doc-zbudg } không tồn tại.| ) TO ct_return.
    ENDIF.
  ENDIF.
ENDFORM.

* Tổ chức mua hàng, công ty, nhà máy, dự án, WBS hợp đồng
FORM cont_chk_org_data USING is_doc TYPE gty_cont_doc
                       CHANGING ct_return TYPE bapiret2_t.
  IF is_doc-head-ekorg IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'EKORG'
                    message = |Chưa xác định được tổ chức mua hàng, vui lòng nhập.| ) TO ct_return.
  ENDIF.
  IF is_doc-head-ekgrp IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'EKGRP'
                    message = |Chưa xác định được nhóm mua hàng, vui lòng nhập.| ) TO ct_return.
  ENDIF.
  IF is_doc-head-bukrs IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'BUKRS'
                    message = |Chưa xác định được công ty, vui lòng nhập.| ) TO ct_return.
  ELSE.
    SELECT SINGLE vbukr FROM proj WHERE pspid = @is_doc-head-pspid INTO @DATA(lv_proj_bukrs).
    IF lv_proj_bukrs <> is_doc-head-bukrs.
      APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'BUKRS'
                      message = |Dự án { is_doc-pspid_ext } không thuộc công ty { is_doc-head-bukrs }.| ) TO ct_return.
    ENDIF.
  ENDIF.

  IF is_doc-head-bsart <> 'ZP03' AND is_doc-head-bsart <> 'ZP09' AND is_doc-head-posid IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'POSID'
                    message = |Chưa nhập WBS hợp đồng.| ) TO ct_return.
  ENDIF.
  SELECT SINGLE prps~posid FROM prps
    INNER JOIN proj ON prps~psphi = proj~pspnr
    WHERE prps~stufe = 1 AND proj~pspid = @is_doc-head-pspid AND prps~posid = @is_doc-head-posid
    INTO @DATA(lv_posid_l1).
  IF lv_posid_l1 IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'POSID'
                    message = |WBS hợp đồng { is_doc-posid_ext } phải là WBS cấp 1 của dự án { is_doc-pspid_ext }.| ) TO ct_return.
  ENDIF.

  IF is_doc-head-werks IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'WERKS'
                    message = |Chưa xác định được nhà máy (dự án { is_doc-pspid_ext } chưa khai nhà máy), vui lòng nhập.| ) TO ct_return.
  ELSE.
    SELECT SINGLE bukrs FROM t001k WHERE bwkey = @is_doc-head-werks INTO @DATA(lv_plant_bukrs).
    IF lv_plant_bukrs <> is_doc-head-bukrs AND is_doc-head-bukrs IS NOT INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'WERKS'
                      message = |Nhà máy { is_doc-head-werks } không thuộc công ty { is_doc-head-bukrs }.| ) TO ct_return.
    ENDIF.
  ENDIF.
ENDFORM.

* Loại tài khoản ngân hàng đối tác, HĐ tham chiếu, địa chỉ NCC vãng lai
FORM cont_chk_bank_type USING is_doc TYPE gty_cont_doc
                        CHANGING ct_return TYPE bapiret2_t.
  IF is_doc-bu_group = 'Z007'.
    " NCC vãng lai: bắt buộc địa chỉ
    IF is_doc-vendor_addr-name1 IS INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IS_VENDOR_ADDR' field = 'NAME1'
                      message = |Nhà cung cấp { is_doc-head-lifnr ALPHA = OUT } là NCC vãng lai, cần nhập tên và địa chỉ nhà cung cấp.| )
        TO ct_return.
    ENDIF.
    RETURN.
  ENDIF.
  CHECK is_doc-bu_group IS NOT INITIAL.

  IF is_doc-head-zzbvtyp IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZZBVTYP'
                    message = |Chưa có loại tài khoản ngân hàng của đối tác (không tìm thấy trên DMS), vui lòng nhập.| ) TO ct_return.
  ELSE.
    " tài khoản của người nhận thanh toán (RS) nếu có, ngược lại của NCC
    DATA(lv_partner) = VALUE lifnr( is_doc-t_partner[ parvw = 'RS' ]-lifnr DEFAULT is_doc-head-lifnr ).
    SELECT SINGLE bkvid FROM but0bk WHERE partner = @lv_partner AND bkvid = @is_doc-head-zzbvtyp
      INTO @DATA(lv_bkvid).
    IF lv_bkvid IS INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZZBVTYP'
                      message = |Loại tài khoản ngân hàng { is_doc-head-zzbvtyp } không tồn tại hoặc đã bị lưu trữ ở đối tác { lv_partner ALPHA = OUT }.| )
        TO ct_return.
    ENDIF.
  ENDIF.

  IF is_doc-head-bsart <> 'ZP04' AND is_doc-head-zcont IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IS_HEADER' field = 'ZCONT'
                    message = |Chưa nhập số hợp đồng tham chiếu.| ) TO ct_return.
  ENDIF.
ENDFORM.

FORM cont_chk_quantity USING is_doc TYPE gty_cont_doc
                       CHANGING ct_return TYPE bapiret2_t.
  IF is_doc-t_item IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM'
                    message = |Hợp đồng chưa có dòng hàng nào.| ) TO ct_return.
    RETURN.
  ENDIF.
  TRY.
      DATA(lv_sum) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                       FOR i IN is_doc-t_item NEXT s = s + i-menge ).
      DATA(lv_sum_check) = CONV zamount( lv_sum ).
    CATCH cx_sy_arithmetic_error cx_sy_conversion_overflow.
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' field = 'MENGE'
                      message = |Tổng số lượng các dòng quá lớn.| ) TO ct_return.
  ENDTRY.
ENDFORM.

* Kiểm tra từng dòng - mỗi dòng dừng ở lỗi đầu tiên như CHECK_SAVE
FORM cont_check_items USING is_doc TYPE gty_cont_doc
                      CHANGING ct_return TYPE bapiret2_t.
  LOOP AT is_doc-t_item INTO DATA(ls_item).
    PERFORM cont_check_item USING is_doc ls_item CHANGING ct_return.
  ENDLOOP.
ENDFORM.

FORM cont_check_item USING is_doc  TYPE gty_cont_doc
                           is_item TYPE ztb_cont_item
                     CHANGING ct_return TYPE bapiret2_t.
  DATA lv_failed TYPE abap_bool.

  PERFORM cont_chk_item_brand USING is_doc is_item CHANGING ct_return lv_failed.
  CHECK lv_failed = abap_false AND is_item-loekz IS INITIAL.
  PERFORM cont_chk_item_bomg USING is_doc is_item CHANGING ct_return lv_failed.
  CHECK lv_failed = abap_false.
  PERFORM cont_chk_item_wbs USING is_doc is_item CHANGING ct_return lv_failed.
  CHECK lv_failed = abap_false.
  PERFORM cont_chk_item_material USING is_doc is_item CHANGING ct_return lv_failed.
  CHECK lv_failed = abap_false.
  PERFORM cont_chk_item_plant_unit USING is_doc is_item CHANGING ct_return.
  PERFORM cont_chk_item_equipment USING is_doc is_item CHANGING ct_return.
ENDFORM.

* Vật tư bắt buộc; Brand phải là giá trị có trong phân loại của vật tư
FORM cont_chk_item_brand USING is_doc  TYPE gty_cont_doc
                               is_item TYPE ztb_cont_item
                         CHANGING ct_return TYPE bapiret2_t
                                  cv_failed TYPE abap_bool.
  DATA lv_charact TYPE atnam.

  IF is_item-matnr IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATNR'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập vật tư.| ) TO ct_return.
    cv_failed = abap_true.
    RETURN.
  ENDIF.
  CHECK is_item-brand IS NOT INITIAL.

  READ TABLE is_doc-t_brand TRANSPORTING NO FIELDS
    WITH KEY matnr = is_item-matnr brand = is_item-brand BINARY SEARCH.
  CHECK sy-subrc <> 0.

  READ TABLE is_doc-t_brand INTO DATA(ls_brand) WITH KEY matnr = is_item-matnr BINARY SEARCH.
  IF sy-subrc = 0.
    CALL FUNCTION 'CONVERSION_EXIT_ATINN_OUTPUT'
      EXPORTING
        input  = ls_brand-atinn
      IMPORTING
        output = lv_charact.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'BRAND'
                    message = |Dòng { CONV i( is_item-sttit ) }: Brand "{ is_item-brand }" không có trong danh sách giá trị của đặc tính { lv_charact } (lớp { ls_brand-class }).| )
      TO ct_return.
  ELSE.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'BRAND'
                    message = |Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } không được khai Brand, không nhập Brand "{ is_item-brand }".| )
      TO ct_return.
  ENDIF.
  cv_failed = abap_true.
ENDFORM.

* BOMG: bắt buộc, phải có trong BOQ đã duyệt / BOMGL của dự án, chưa bị xóa
FORM cont_chk_item_bomg USING is_doc  TYPE gty_cont_doc
                              is_item TYPE ztb_cont_item
                        CHANGING ct_return TYPE bapiret2_t
                                 cv_failed TYPE abap_bool.
  DATA: lv_bomg  TYPE ztb_bomg_header-zbomg_code,
        lv_usr11 TYPE proj-usr11.

  IF is_item-zbomg_code IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZBOMG_CODE'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập mã BOMG.| ) TO ct_return.
    cv_failed = abap_true.
    RETURN.
  ENDIF.

  IF is_doc-check_bomp = abap_true.
    " dự án có BOQ đã duyệt KHNS: BOMG phải nằm trong BOQ (hoặc BOMG khấu trừ)
    SELECT SINGLE bomg~zbomg_code FROM ztb_bomg_header AS bomg
      LEFT JOIN ztb_over_item AS bomg_boq ON bomg_boq~zbomg_code = bomg~zbomg_code
                                         AND bomg_boq~pspid = @is_doc-head-pspid
                                         AND bomg_boq~posid = @is_doc-head-posid
      LEFT JOIN ztb_khns_header AS zbud ON zbud~status = 'A'
                                       AND zbud~pspid = bomg_boq~pspid
                                       AND zbud~posid = bomg_boq~posid
      INNER JOIN ztb_csig ON ztb_csig~csi_group = bomg~csi_group
      WHERE ztb_csig~ztype NOT IN ( '01', '03' )
        AND ( zbud~version_pr IS NOT INITIAL OR bomg~zdeduct IS NOT INITIAL )
        AND bomg~zbomg_code = @is_item-zbomg_code
      INTO @lv_bomg.
  ELSE.
    SELECT SINGLE usr11 FROM proj WHERE pspid = @is_doc-head-pspid INTO @lv_usr11.
    IF lv_usr11 IS NOT INITIAL.
      " dự án quản lý theo BOMGL: BOMG phải ở dòng BOMGL đã duyệt
      SELECT SINGLE bomg~zbomg_code FROM ztb_bomg_header AS bomg
        LEFT JOIN ztb_bomgl_item ON ztb_bomgl_item~zbomg_code = bomg~zbomg_code
        LEFT JOIN ztb_bomgl_header ON ztb_bomgl_header~pspid = ztb_bomgl_item~pspid
                                  AND ztb_bomgl_header~posid = ztb_bomgl_item~posid
                                  AND ztb_bomgl_header~doc_num = ztb_bomgl_item~doc_num
                                  AND ztb_bomgl_header~zversion = ztb_bomgl_item~zversion
        WHERE ( ( ztb_bomgl_header~pspid = @is_doc-head-pspid
                  AND ztb_bomgl_header~posid = @is_doc-head-posid
                  AND ztb_bomgl_item~statusitem = 'A' )
                OR bomg~zdeduct IS NOT INITIAL )
          AND bomg~zbomg_code = @is_item-zbomg_code
        INTO @lv_bomg.
    ELSE.
      SELECT SINGLE ztb_bomg_header~zbomg_code FROM ztb_bomg_header
        INNER JOIN ztb_csig ON ztb_csig~csi_group = ztb_bomg_header~csi_group
        WHERE ztb_bomg_header~zbomg_code IS NOT INITIAL
          AND ( ztb_csig~ztype NOT IN ( '01', '03' ) OR ztb_bomg_header~zdeduct IS NOT INITIAL )
          AND ztb_bomg_header~zbomg_code = @is_item-zbomg_code
        INTO @lv_bomg.
    ENDIF.
  ENDIF.

  IF lv_bomg IS INITIAL.
    IF is_doc-check_bomp = abap_true.
      SELECT SINGLE boqnu FROM ztb_over_header
        WHERE pspid = @is_doc-head-pspid AND posid = @is_doc-head-posid INTO @DATA(lv_boq).
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZBOMG_CODE'
                      message = |Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không có trong BOQ số { lv_boq } đã duyệt của WBS { is_doc-posid_ext }.| )
        TO ct_return.
    ELSEIF lv_usr11 IS NOT INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZBOMG_CODE'
                      message = |Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không có trong danh sách BOMG đã duyệt (BOMGL) của WBS { is_doc-posid_ext }.| )
        TO ct_return.
    ELSE.
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZBOMG_CODE'
                      message = |Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không tồn tại hoặc không được dùng để mua hàng.| )
        TO ct_return.
    ENDIF.
    cv_failed = abap_true.
    RETURN.
  ENDIF.

  CHECK is_item-elikz IS INITIAL.
  SELECT SINGLE zbomg_code FROM ztb_bomg_header
    INNER JOIN ztb_csig ON ztb_csig~csi_group = ztb_bomg_header~csi_group
    WHERE zbomg_code = @is_item-zbomg_code AND ztb_bomg_header~loekz IS INITIAL
    INTO @DATA(lv_bomg_active).
  IF lv_bomg_active IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZBOMG_CODE'
                    message = |Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } đã bị đánh dấu xóa.| )
      TO ct_return.
    cv_failed = abap_true.
  ENDIF.
ENDFORM.

* WBS của dòng: bắt buộc, là WBS cấp 4 thuộc WBS hợp đồng, cùng nhóm CSI
FORM cont_chk_item_wbs USING is_doc  TYPE gty_cont_doc
                             is_item TYPE ztb_cont_item
                       CHANGING ct_return TYPE bapiret2_t
                                cv_failed TYPE abap_bool.
  DATA: lv_posid    TYPE char24,
        lv_wbs_text TYPE ps_posid.

  IF is_item-posid IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'POSID'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập WBS cấp 4.| ) TO ct_return.
    cv_failed = abap_true.
    RETURN.
  ENDIF.
  CHECK is_item-elikz IS INITIAL.

  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
    EXPORTING
      input  = is_item-posid
    IMPORTING
      output = lv_wbs_text.

  IF is_doc-head-bsart <> 'ZP09'.
    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
      EXPORTING
        input  = is_item-posid
      IMPORTING
        output = lv_posid.
    IF NOT line_exists( is_doc-t_wbs[ posid = lv_posid ] ).
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'POSID'
                      message = |Dòng { CONV i( is_item-sttit ) }: WBS { lv_wbs_text } không phải WBS cấp 4 thuộc WBS hợp đồng { is_doc-posid_ext }.| )
        TO ct_return.
      cv_failed = abap_true.
      RETURN.
    ENDIF.
  ENDIF.

  SELECT SINGLE zcsi, posid_edit FROM prps WHERE posid = @is_item-posid INTO @DATA(ls_prps).
  IF ls_prps-zcsi <> is_item-csi_group.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'POSID'
                    message = |Dòng { CONV i( is_item-sttit ) }: nhóm CSI của BOMG ({ is_item-csi_group }) khác nhóm CSI của WBS { ls_prps-posid_edit } ({ ls_prps-zcsi }).| )
      TO ct_return.
    cv_failed = abap_true.
  ENDIF.
ENDFORM.

* Vật tư tồn tại, nhóm vật tư thuộc BOMG, nhà thầu phụ cho nhóm ngoài 8001
FORM cont_chk_item_material USING is_doc  TYPE gty_cont_doc
                                  is_item TYPE ztb_cont_item
                            CHANGING ct_return TYPE bapiret2_t
                                     cv_failed TYPE abap_bool.
  SELECT SINGLE matnr, extwg FROM mara WHERE matnr = @is_item-matnr INTO @DATA(ls_mara).
  IF ls_mara-matnr IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATNR'
                    message = |Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } không tồn tại hoặc chưa được kích hoạt.| )
      TO ct_return.
    cv_failed = abap_true.
    RETURN.
  ENDIF.

  IF is_item-elikz IS INITIAL.
    SELECT DISTINCT matkl FROM ztb_bomg_item WHERE zbomg_code = @is_item-zbomg_code
      INTO TABLE @DATA(lt_matkl).
    SELECT DISTINCT matkl FROM ztb_mgc WHERE publish IS NOT INITIAL APPENDING TABLE @lt_matkl.
    IF NOT line_exists( lt_matkl[ matkl = is_item-matkl ] ).
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATKL'
                      message = |Dòng { CONV i( is_item-sttit ) }: nhóm vật tư { is_item-matkl } không thuộc BOMG { is_item-zbomg_code }.| )
        TO ct_return.
      cv_failed = abap_true.
      RETURN.
    ENDIF.
  ENDIF.

  IF ls_mara-extwg = '8001'
  AND ( is_doc-head-bsart = 'ZP01' OR is_doc-head-bsart = 'ZP02' OR is_doc-head-bsart = 'ZP03'
     OR is_doc-head-bsart = 'ZP04' OR is_doc-head-bsart = 'ZP08' )
  AND ( is_item-zsub IS INITIAL OR is_item-zsubn IS INITIAL ).
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'ZSUB'
                    message = |Dòng { CONV i( is_item-sttit ) }: vật tư thuộc nhóm thuê thầu phụ, cần nhập mã và tên nhà thầu phụ.| )
      TO ct_return.
    cv_failed = abap_true.
  ENDIF.
ENDFORM.

* Vật tư có ở nhà máy, đơn vị đặt hàng hợp lệ, đơn giá
FORM cont_chk_item_plant_unit USING is_doc  TYPE gty_cont_doc
                                    is_item TYPE ztb_cont_item
                              CHANGING ct_return TYPE bapiret2_t.
  IF is_doc-head-werks IS NOT INITIAL.
    SELECT SINGLE matnr FROM marc WHERE matnr = @is_item-matnr AND werks = @is_doc-head-werks
      INTO @DATA(lv_matnr).
    IF lv_matnr IS INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATNR'
                      message = |Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } chưa được mở rộng cho nhà máy { is_doc-head-werks }.| )
        TO ct_return.
    ENDIF.
  ENDIF.

  SELECT SINGLE meins, vabme FROM mara WHERE matnr = @is_item-matnr INTO @DATA(ls_mara).
  SELECT meinh FROM marm WHERE matnr = @is_item-matnr INTO TABLE @DATA(lt_meinh).
  IF NOT line_exists( lt_meinh[ meinh = is_item-meins ] ).
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MEINS'
                    message = |Dòng { CONV i( is_item-sttit ) }: đơn vị đặt hàng { is_item-meins } chưa khai quy đổi sang đơn vị cơ sở { ls_mara-meins } của vật tư.| )
      TO ct_return.
  ELSEIF ls_mara-vabme IS INITIAL AND is_item-meins <> ls_mara-meins.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MEINS'
                    message = |Dòng { CONV i( is_item-sttit ) }: vật tư không cho phép đặt hàng theo đơn vị { is_item-meins }, hãy dùng { ls_mara-meins }.| )
      TO ct_return.
  ENDIF.

  IF is_item-netpr IS INITIAL AND is_item-umson IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'NETPR'
                    message = |Dòng { CONV i( is_item-sttit ) }: đơn giá phải lớn hơn 0 (trừ dòng hàng tặng).| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Hợp đồng thuê thiết bị ZP08: thông tin thiết bị cho vật tư trong ZCONT_TB
FORM cont_chk_item_equipment USING is_doc  TYPE gty_cont_doc
                                   is_item TYPE ztb_cont_item
                             CHANGING ct_return TYPE bapiret2_t.
  CHECK is_doc-head-bsart = 'ZP08' AND line_exists( is_doc-r_zcont_tb[ low = is_item-matnr ] ).

  IF is_item-matnr_e IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATNR_E'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập mã thiết bị thuê.| ) TO ct_return.
  ELSEIF is_item-menge_e IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MENGE_E'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập số lượng thiết bị thuê.| ) TO ct_return.
  ELSEIF is_item-meins_e IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MEINS_E'
                    message = |Dòng { CONV i( is_item-sttit ) }: chưa nhập đơn vị tính của thiết bị thuê.| ) TO ct_return.
  ENDIF.

  CHECK is_item-matnr_e IS NOT INITIAL AND is_item-elikz IS INITIAL.
  SELECT SINGLE mtart FROM mara WHERE matnr = @is_item-matnr_e AND mtart IN @is_doc-r_mtart_eq
    INTO @DATA(lv_mtart).
  IF lv_mtart IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' row = is_item-sttit field = 'MATNR_E'
                    message = |Dòng { CONV i( is_item-sttit ) }: mã { is_item-matnr_e ALPHA = OUT } không phải là thiết bị.| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Giá trị hợp đồng (cộng các đơn đã có cùng HĐ tham chiếu) không được
* vượt giá trị HĐ tham chiếu trên DMS
FORM cont_check_amount USING is_doc TYPE gty_cont_doc
                       CHANGING ct_return TYPE bapiret2_t.
  DATA: lr_ebeln       TYPE RANGE OF zde_ebeln1,
        lv_amount_post TYPE dmbtr.

  CHECK is_doc-head-bsart <> 'ZPL1' AND is_doc-head-bsart <> 'ZP09'.
  SELECT SINGLE amountwithvat FROM ztb_dms_plhd WHERE soplhd = @is_doc-head-zcont INTO @DATA(lv_dms_any).
  CHECK lv_dms_any IS NOT INITIAL.

  " giá trị HĐ tham chiếu + các phụ lục trên DMS
  SELECT SINGLE amountwithvat, zdvt FROM ztb_dms_plhd
    WHERE soplhd = @is_doc-head-zcont
      AND ( ( maduan = @is_doc-pspid_ext
              AND CASE WHEN posid IS NOT INITIAL THEN posid ELSE @is_doc-head-posid END = @is_doc-head-posid )
            OR pccode LIKE '%00D%' )
    INTO @DATA(ls_dms).
  SELECT SUM( amountwithvat ) FROM ztb_dms_plhd
    WHERE zhdg = @is_doc-head-zcont AND soplhd <> @is_doc-head-zcont
      AND maduan = @is_doc-pspid_ext
      AND CASE WHEN posid IS NOT INITIAL THEN posid ELSE @is_doc-head-posid END = @is_doc-head-posid
    INTO @DATA(lv_dms_annex).
  ls_dms-amountwithvat = ls_dms-amountwithvat + lv_dms_annex.
  IF ls_dms-zdvt = 'VND' OR ls_dms-zdvt IS INITIAL.
    ls_dms-amountwithvat = ls_dms-amountwithvat / 100.
  ENDIF.

  " giá trị đã đặt ở các đơn mua hàng khác cùng HĐ tham chiếu / dự án / WBS
  SELECT DISTINCT ebeln FROM ztb_cont_header
    WHERE zcont = @is_doc-head-zcont AND pspid = @is_doc-head-pspid AND posid = @is_doc-head-posid
    INTO TABLE @DATA(lt_ebeln).
  lr_ebeln = VALUE #( FOR ls_e IN lt_ebeln ( sign = 'I' option = 'EQ' low = ls_e-ebeln ) ).
  IF lr_ebeln IS NOT INITIAL.
    " dòng đã hoàn tất giao hàng: theo giá trị nhập kho thực tế
    SELECT SUM( wrbtr ) FROM ekbe INNER JOIN ekpo ON ekbe~ebelp = ekpo~ebelp AND ekbe~ebeln = ekpo~ebeln
      WHERE ekbe~ebeln IN @lr_ebeln AND ekbe~shkzg = 'S' AND ekpo~elikz IS NOT INITIAL
        AND ekpo~retpo IS INITIAL AND bwart IS NOT INITIAL
      INTO @DATA(lv_gr_debit).
    SELECT SUM( wrbtr ) FROM ekbe INNER JOIN ekpo ON ekbe~ebelp = ekpo~ebelp AND ekbe~ebeln = ekpo~ebeln
      WHERE ekbe~ebeln IN @lr_ebeln AND ekbe~shkzg = 'H' AND ekpo~elikz IS NOT INITIAL
        AND ekpo~retpo IS INITIAL AND bwart IS NOT INITIAL
      INTO @DATA(lv_gr_credit).
    SELECT SUM( ekbe~menge * ekpo~netpr ) FROM ekbe INNER JOIN ekpo ON ekbe~ebelp = ekpo~ebelp AND ekbe~ebeln = ekpo~ebeln
      WHERE ekbe~ebeln IN @lr_ebeln AND ekbe~shkzg = 'S' AND ekpo~elikz IS NOT INITIAL
        AND ekpo~retpo IS NOT INITIAL AND bwart IS NOT INITIAL
      INTO @DATA(lv_ret_debit).
    SELECT SUM( ekbe~menge * ekpo~netpr ) FROM ekbe INNER JOIN ekpo ON ekbe~ebelp = ekpo~ebelp AND ekbe~ebeln = ekpo~ebeln
      WHERE ekbe~ebeln IN @lr_ebeln AND ekbe~shkzg = 'H' AND ekpo~elikz IS NOT INITIAL
        AND ekpo~retpo IS NOT INITIAL AND bwart IS NOT INITIAL
      INTO @DATA(lv_ret_credit).
    " dòng chưa hoàn tất: theo giá trị đặt hàng (trừ dòng trả hàng)
    SELECT SUM( division( ( netpr * menge ), peinh, 2 ) ) FROM ekpo
      WHERE ebeln IN @lr_ebeln AND elikz IS INITIAL AND loekz IS INITIAL AND retpo IS INITIAL
      INTO @DATA(lv_open).
    SELECT SUM( division( ( netpr * menge ), peinh, 2 ) ) FROM ekpo
      WHERE ebeln IN @lr_ebeln AND elikz IS INITIAL AND loekz IS INITIAL AND retpo IS NOT INITIAL
      INTO @DATA(lv_open_ret).
    lv_amount_post = ( lv_gr_debit - lv_gr_credit ) + lv_open
                   + ( lv_ret_debit - lv_ret_credit ) - lv_open_ret.
  ENDIF.

  " giá trị hợp đồng đang tạo (dòng trả hàng làm giảm)
  DATA(lv_amount_new) = REDUCE decfloat34( INIT s = CONV decfloat34( 0 )
                          FOR i IN is_doc-t_item
                          WHERE ( loekz IS INITIAL AND elikz IS INITIAL )
                          NEXT s = COND #( WHEN i-retpo IS INITIAL THEN s + i-zamount ELSE s - i-zamount ) ).

  DATA(lv_total) = CONV decfloat34( lv_amount_post + lv_amount_new ).
  DATA(lv_limit) = CONV decfloat34( ls_dms-amountwithvat ).
  IF lv_limit < lv_total.
    APPEND VALUE #( type = 'E' parameter = 'IT_ITEM' field = 'ZAMOUNT'
                    message = |Tổng giá trị đặt hàng theo HĐ { is_doc-head-zcont } ({ lv_total NUMBER = USER } { is_doc-head-cuky }) vượt giá trị hợp đồng trên DMS ({ lv_limit NUMBER = USER }).| )
      TO ct_return.
  ENDIF.
ENDFORM.

* Điều kiện header phải được phép dùng ở cấp header
FORM cont_check_header_cond USING is_doc TYPE gty_cont_doc
                            CHANGING ct_return TYPE bapiret2_t.
  LOOP AT is_doc-t_cond_h INTO DATA(ls_cond) WHERE kschl IS NOT INITIAL AND kschl <> 'PBXX' AND kschl <> 'MWST'.
    SELECT SINGLE kkopf FROM t685a WHERE kappl = 'M' AND kschl = @ls_cond-kschl INTO @DATA(lv_kkopf).
    IF lv_kkopf IS INITIAL.
      APPEND VALUE #( type = 'E' parameter = 'IT_COND' field = 'KSCHL'
                      message = |Điều kiện giá { ls_cond-kschl } ({ ls_cond-vtext }) không được dùng làm điều kiện chung của hợp đồng.| )
        TO ct_return.
    ENDIF.
    CLEAR lv_kkopf.
  ENDLOOP.
ENDFORM.

*======================================================================*
* D. Lưu chứng từ (SAVE_DATA_PO / POST_PO / UPDATE_PO_ZCONT /
*    SAVE_TABLE_ZCONT)
*======================================================================*
FORM cont_prepare_header CHANGING cs_doc TYPE gty_cont_doc.
  IF cs_doc-head-zsign IS INITIAL.
    cs_doc-head-zsign = cs_doc-zbudg.         " số kế hoạch ngân sách
  ENDIF.
  cs_doc-head-batxt = SWITCH #( cs_doc-head-bsart
    WHEN 'ZL01' THEN 'LOA'
    WHEN 'ZC01' THEN 'Hợp đồng nguyên tắc cho 1 dự án'
    WHEN 'ZC02' THEN 'Hợp đồng nguyên tắc cho nhiều dự án'
    WHEN 'ZC03' THEN 'Hợp đồng nguyên tắc fix đơn giá'
    WHEN 'ZC04' THEN 'Hợp đồng mua bán'
    WHEN 'ZP11' THEN 'Đơn đặt hàng tổng'
    WHEN 'ZP12' THEN 'Đơn đặt hàng chi tiết'
    WHEN 'ZPL1' THEN 'Phụ lục thầu phụ'
    WHEN 'ZPL2' THEN 'Phụ lục vật tư'
    WHEN 'ZPL3' THEN 'Phụ lục chuyển đổi'
    WHEN 'ZP01' THEN 'ĐĐH mua vật tư'
    WHEN 'ZP02' THEN 'ĐĐH nhập khẩu'
    WHEN 'ZP03' THEN 'Mua TS, TB, CCDC'
    WHEN 'ZP04' THEN 'Mua DV, chi phí chung'
    WHEN 'ZP05' THEN 'Thầu phụ trọn gói'
    WHEN 'ZP06' THEN 'Thầu phụ nhân công'
    WHEN 'ZP07' THEN 'Nhà thầu chỉ định'
    WHEN 'ZP08' THEN 'Thuê thiết bị'
    WHEN 'ZP09' THEN 'ĐĐH thuê tài chính'
    WHEN 'ZP10' THEN 'ĐĐH hàng hóa'
    ELSE cs_doc-head-batxt ).

  " Contract Amount / Total Contract Amount = dòng tổng của bước 1 / 2
  cs_doc-head-zzgthd = VALUE #( cs_doc-t_cond_h[ kschl = space stunr = cs_doc-step ]-kwert OPTIONAL ).
  cs_doc-head-tgthd  = VALUE #( cs_doc-t_cond_h[ kschl = space stunr = cs_doc-step_tax ]-kwert OPTIONAL ).
  cs_doc-head-usnam = sy-uname.
  cs_doc-head-cpudt = sy-datum.
  cs_doc-head-cputm = sy-uzeit.
  CLEAR: cs_doc-head-psodt, cs_doc-head-psotm, cs_doc-head-aenam.
ENDFORM.

FORM cont_post_po USING    is_doc     TYPE gty_cont_doc
                           iv_testrun TYPE xfeld
                  CHANGING cv_ebeln   TYPE ebeln
                           ct_return  TYPE bapiret2_t.
  DATA: ls_bapi      TYPE gty_cont_bapi,
        ls_expheader TYPE bapimepoheader,
        lt_bapiret   TYPE STANDARD TABLE OF bapiret2.

  PERFORM cont_bapi_header     USING is_doc CHANGING ls_bapi.
  PERFORM cont_bapi_items      USING is_doc CHANGING ls_bapi.
  PERFORM cont_bapi_partners   USING is_doc CHANGING ls_bapi.
  PERFORM cont_bapi_conditions USING is_doc CHANGING ls_bapi.

  CALL FUNCTION 'BAPI_PO_CREATE1'
    EXPORTING
      poheader               = ls_bapi-head
      poheaderx              = ls_bapi-headx
      poaddrvendor           = ls_bapi-addrvendor
      testrun                = iv_testrun
      no_price_from_po       = 'X'
    IMPORTING
      exppurchaseorder       = cv_ebeln
      expheader              = ls_expheader
    TABLES
      return                 = lt_bapiret
      poitem                 = ls_bapi-t_item
      poitemx                = ls_bapi-t_itemx
      poschedule             = ls_bapi-t_sched
      poschedulex            = ls_bapi-t_schedx
      poaccount              = ls_bapi-t_account
      poaccountprofitsegment = ls_bapi-t_profseg
      poaccountx             = ls_bapi-t_accountx
      pocondheader           = ls_bapi-t_condh
      pocondheaderx          = ls_bapi-t_condhx
      pocond                 = ls_bapi-t_cond
      pocondx                = ls_bapi-t_condx
      extensionin            = ls_bapi-t_extin
      popartner              = ls_bapi-t_partner.

  APPEND LINES OF lt_bapiret TO ct_return.
  IF line_exists( lt_bapiret[ type = 'E' ] ) OR line_exists( lt_bapiret[ type = 'A' ] ).
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CLEAR cv_ebeln.
    APPEND VALUE #( type = 'E'
                    message = |Không tạo được đơn mua hàng, xem các thông báo của SAP ở trên để biết nguyên nhân.| )
      TO ct_return.
    RETURN.
  ENDIF.

  IF iv_testrun = abap_true.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
    CLEAR cv_ebeln.
    APPEND VALUE #( type = 'S'
                    message = |Chạy thử thành công: dữ liệu hợp lệ, chưa lưu chứng từ.| ) TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait = abap_true.
ENDFORM.

FORM cont_bapi_header USING    is_doc  TYPE gty_cont_doc
                      CHANGING cs_bapi TYPE gty_cont_bapi.
  DATA: ls_exten  TYPE bapi_te_mepoheader,
        ls_extenx TYPE bapi_te_mepoheaderx.

  cs_bapi-head = VALUE #( doc_type   = is_doc-head-bsart
                          vendor     = is_doc-head-lifnr
                          purch_org  = is_doc-head-ekorg
                          pur_group  = is_doc-head-ekgrp
                          comp_code  = is_doc-head-bukrs
                          langu      = sy-langu
                          creat_date = sy-datum
                          doc_date   = is_doc-head-bedat
                          pmnttrms   = is_doc-head-zterm
                          currency   = is_doc-head-cuky
                          exch_rate  = is_doc-head-wkurs
                          ex_rate_fx = is_doc-head-zfixrate ).
  cs_bapi-headx = VALUE #( doc_type = 'X' item_intvl = 'X' vendor = 'X' purch_org = 'X'
                           pur_group = 'X' comp_code = 'X' langu = 'X' creat_date = 'X'
                           doc_date = 'X' pmnttrms = 'X' currency = 'X' exch_rate = 'X'
                           ex_rate_fx = 'X' ).

  " trường bổ sung EKKO: số HĐ, số phụ lục, loại TK ngân hàng đối tác
  ls_exten-zzhopdong = is_doc-head-zcont.
  ls_exten-zzphuluc  = is_doc-head-zcont_an.
  ls_exten-zzbvtyp   = is_doc-head-zzbvtyp.
  APPEND VALUE #( structure = 'BAPI_TE_MEPOHEADER' valuepart1 = ls_exten
                  valuepart2 = ls_exten+240(64) ) TO cs_bapi-t_extin ##ENH_OK.
  ls_extenx-zzhopdong = 'X'.
  ls_extenx-zzphuluc  = 'X'.
  ls_extenx-zzbvtyp   = 'X'.
  APPEND VALUE #( structure = 'BAPI_TE_MEPOHEADERX' valuepart1 = ls_extenx ) TO cs_bapi-t_extin ##ENH_OK.

  " NCC vãng lai: địa chỉ trên đơn mua hàng
  CHECK is_doc-bu_group = 'Z007'.
  cs_bapi-addrvendor = VALUE #( name       = is_doc-vendor_addr-name1
                                name_2     = is_doc-vendor_addr-name2
                                name_3     = is_doc-vendor_addr-name3
                                name_4     = is_doc-vendor_addr-name4
                                street     = is_doc-vendor_addr-street
                                city       = is_doc-vendor_addr-city1
                                district   = is_doc-vendor_addr-city2
                                city_no    = is_doc-vendor_addr-city_code
                                postl_cod1 = is_doc-vendor_addr-post_code1
                                postl_cod2 = is_doc-vendor_addr-post_code2
                                postl_cod3 = is_doc-vendor_addr-post_code3
                                po_box     = is_doc-vendor_addr-po_box
                                po_box_cit = is_doc-vendor_addr-po_box_cty
                                house_no   = is_doc-vendor_addr-house_num1
                                street_no  = is_doc-vendor_addr-streetcode
                                str_suppl1 = is_doc-vendor_addr-str_suppl2
                                str_suppl2 = is_doc-vendor_addr-str_suppl3
                                location   = is_doc-vendor_addr-location
                                country    = is_doc-vendor_addr-country
                                region     = is_doc-vendor_addr-region
                                tel1_numbr = is_doc-vendor_addr-tel_number
                                tel1_ext   = is_doc-vendor_addr-tel_extens
                                fax_number = is_doc-vendor_addr-fax_number
                                fax_extens = is_doc-vendor_addr-fax_extens
                                sort1      = is_doc-vendor_addr-sort1
                                sort2      = is_doc-vendor_addr-sort2
                                langu      = is_doc-vendor_addr-langu
                                comm_type  = is_doc-vendor_addr-deflt_comm
                                formofaddr = is_doc-vendor_addr-title
                                time_zone  = is_doc-vendor_addr-time_zone
                                adr_notes  = is_doc-vendor_addr-remark
                                e_mail     = is_doc-vendor_addr-smtp_addr ).
ENDFORM.

FORM cont_bapi_items USING    is_doc  TYPE gty_cont_doc
                     CHANGING cs_bapi TYPE gty_cont_bapi.
  DATA: lv_vend_mat TYPE bapimepoitem-vend_mat,
        lv_posid    TYPE ps_posid,
        lv_prctr    TYPE prctr.

  LOOP AT is_doc-t_item INTO DATA(ls_item).
    CALL FUNCTION 'CONVERSION_EXIT_MATN1_OUTPUT'
      EXPORTING
        input  = ls_item-matnr_e
      IMPORTING
        output = lv_vend_mat.
    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
      EXPORTING
        input  = ls_item-posid
      IMPORTING
        output = lv_posid.
    CLEAR lv_prctr.
    SELECT SINGLE prctr FROM prps WHERE posid = @lv_posid INTO @lv_prctr.

    " VND không có số lẻ: giá nội bộ lưu /100 -> nhân lại khi gửi BAPI
    APPEND VALUE #( po_item       = ls_item-sttit
                    acctasscat    = ls_item-knttp
                    fund          = ls_item-geber
                    material      = ls_item-matnr
                    funds_ctr     = ls_item-fictr
                    cmmt_item     = ls_item-fipex
                    trackingno    = ls_item-brand
                    short_text    = ls_item-txz01
                    quantity      = ls_item-menge
                    po_unit       = ls_item-meins
                    orderpr_un    = ls_item-bprme_po
                    conv_num1     = ls_item-bpumz
                    conv_den1     = ls_item-bpumn
                    plant         = is_doc-head-werks
                    gl_account    = ls_item-sakto
                    stge_loc      = is_doc-head-lgort
                    net_price     = COND #( WHEN is_doc-head-cuky = 'VND' THEN ls_item-netpr * 100
                                            ELSE ls_item-netpr )
                    preq_no       = ls_item-banfn
                    preq_item     = ls_item-bnfpo
                    wbs_element   = ls_item-posid
                    over_dlv_tol  = ls_item-uebto
                    under_dlv_tol = ls_item-untto
                    unlimited_dlv = ls_item-uebtk
                    vend_mat      = lv_vend_mat
                    gr_non_val    = ls_item-weunb
                    price_unit    = ls_item-peinh
                    batch         = ls_item-charg
                    gr_ind        = ls_item-wepos
                    ir_ind        = ls_item-repos
                    final_inv     = ls_item-erekz
                    gr_basediv    = ls_item-webre
                    tax_code      = ls_item-mwskz
                    ret_item      = ls_item-retpo
                    free_item     = ls_item-umson
                    no_rounding   = 'X'
                    no_more_gr    = ls_item-elikz ) TO cs_bapi-t_item.
    APPEND VALUE #( po_item = ls_item-sttit po_itemx = 'X'
                    acctasscat = 'X' fund = 'X' material = 'X' funds_ctr = 'X' cmmt_item = 'X'
                    trackingno = 'X' short_text = 'X' quantity = 'X' po_unit = 'X' orderpr_un = 'X'
                    conv_num1 = 'X' conv_den1 = 'X' plant = 'X' gl_account = 'X' stge_loc = 'X'
                    net_price = 'X' preq_no = 'X' preq_item = 'X' wbs_element = 'X'
                    over_dlv_tol = 'X' under_dlv_tol = 'X' unlimited_dlv = 'X' vend_mat = 'X'
                    gr_non_val = 'X' price_unit = 'X' batch = 'X' gr_ind = 'X' ir_ind = 'X'
                    final_inv = 'X' gr_basediv = 'X'
                    tax_code = COND #( WHEN ls_item-mwskz IS NOT INITIAL THEN 'X' )
                    ret_item = 'X' free_item = 'X' no_rounding = 'X' no_more_gr = 'X' ) TO cs_bapi-t_itemx.

    APPEND VALUE #( po_item        = ls_item-sttit
                    quantity       = ls_item-menge
                    gl_account     = ls_item-sakto
                    fund           = ls_item-geber
                    funds_ctr      = ls_item-fictr
                    cmmt_item      = ls_item-fipex
                    cmmt_item_long = ls_item-fipex
                    co_area        = 'CTC'
                    wbs_element    = lv_posid
                    profit_ctr     = lv_prctr
                    gr_rcpt        = ls_item-zbomp_code
                    unload_pt      = ls_item-zbomg_code
                    asset_no       = COND #( WHEN ls_item-knttp = 'A' THEN ls_item-anln1 )
                    sub_number     = COND #( WHEN ls_item-knttp = 'A' THEN ls_item-anln2 ) ) TO cs_bapi-t_account.
    APPEND VALUE #( po_item = ls_item-sttit po_itemx = 'X'
                    quantity = 'X' gl_account = 'X' fund = 'X' funds_ctr = 'X' cmmt_item = 'X'
                    co_area = 'X' wbs_element = 'X' profit_ctr = 'X' gr_rcpt = 'X' unload_pt = 'X'
                    asset_no   = COND #( WHEN ls_item-knttp = 'A' THEN 'X' )
                    sub_number = COND #( WHEN ls_item-knttp = 'A' THEN 'X' ) ) TO cs_bapi-t_accountx.

    APPEND VALUE #( po_item = ls_item-sttit sched_line = 1 delivery_date = ls_item-eeind ) TO cs_bapi-t_sched.
    APPEND VALUE #( po_item = ls_item-sttit sched_line = 1 po_itemx = 'X' delivery_date = 'X' ) TO cs_bapi-t_schedx.

    APPEND VALUE #( po_item = ls_item-sttit serial_no = 1 fieldname = 'KOKRS' value = ls_item-kokrs ) TO cs_bapi-t_profseg.
    APPEND VALUE #( po_item = ls_item-sttit serial_no = 1 fieldname = 'ARTNR' value = ls_item-matnr ) TO cs_bapi-t_profseg.
    APPEND VALUE #( po_item = ls_item-sttit serial_no = 1 fieldname = 'WERKS' value = is_doc-head-werks ) TO cs_bapi-t_profseg.
    APPEND VALUE #( po_item = ls_item-sttit serial_no = 1 fieldname = 'PRCTR' value = lv_prctr ) TO cs_bapi-t_profseg.
  ENDLOOP.
ENDFORM.

FORM cont_bapi_partners USING    is_doc  TYPE gty_cont_doc
                        CHANGING cs_bapi TYPE gty_cont_bapi.
  LOOP AT is_doc-t_partner INTO DATA(ls_partner).
    APPEND INITIAL LINE TO cs_bapi-t_partner ASSIGNING FIELD-SYMBOL(<ls_partner>).
    CALL FUNCTION 'CONVERSION_EXIT_PARVW_OUTPUT'
      EXPORTING
        input  = ls_partner-parvw
      IMPORTING
        output = <ls_partner>-partnerdesc.
    <ls_partner>-buspartno = |{ ls_partner-lifnr ALPHA = IN }|.
    <ls_partner>-langu     = sy-langu.
  ENDLOOP.
ENDFORM.

FORM cont_bapi_conditions USING    is_doc  TYPE gty_cont_doc
                          CHANGING cs_bapi TYPE gty_cont_bapi.
  DATA: lv_krech TYPE krech,
        lv_matnr TYPE matnr.

  " điều kiện header nhập ở tab Condition
  LOOP AT is_doc-t_cond_h INTO DATA(ls_cond_h) WHERE zhead = 'X' AND kschl IS NOT INITIAL
                                                 AND kschl <> 'PBXX' AND kschl <> 'MWST'.
    CLEAR lv_krech.
    SELECT SINGLE krech FROM t685a WHERE kappl = 'M' AND kschl = @ls_cond_h-kschl INTO @lv_krech.
    APPEND VALUE #( cond_type  = ls_cond_h-kschl
                    calctypcon = lv_krech
                    currency   = is_doc-head-cuky
                    cond_value = COND #( WHEN is_doc-head-cuky = 'VND' AND lv_krech <> 'A' THEN ls_cond_h-kbetr * 100
                                         WHEN is_doc-head-cuky = 'VND'                  THEN ls_cond_h-kbetr * 1000
                                         ELSE ls_cond_h-kbetr )
                    change_id  = 'I' ) TO cs_bapi-t_condh.
    APPEND VALUE #( cond_type = 'X' calctypcon = 'X' currency = 'X' cond_value = 'X' change_id = 'X' )
      TO cs_bapi-t_condhx.
  ENDLOOP.

  " điều kiện dòng: PBXX (sửa), MWST, điều kiện bổ sung của dòng
  LOOP AT is_doc-t_cond_i INTO DATA(ls_cond_i) WHERE sttit IS NOT INITIAL AND kschl IS NOT INITIAL
                                                 AND zhead IS INITIAL.
    APPEND INITIAL LINE TO cs_bapi-t_cond ASSIGNING FIELD-SYMBOL(<ls_cond>).
    <ls_cond>-itm_number = ls_cond_i-sttit.
    <ls_cond>-cond_type  = ls_cond_i-kschl.
    SELECT SINGLE stunr FROM t683s
      WHERE kvewe = 'A' AND kappl = 'M' AND kalsm = 'ZRM000' AND kschl = @ls_cond_i-kschl
      INTO @<ls_cond>-cond_st_no.
    SELECT SINGLE krech FROM t685a WHERE kappl = 'M' AND kschl = @ls_cond_i-kschl
      INTO @<ls_cond>-calctypcon.
    <ls_cond>-vendor_no = ls_cond_i-lifnr.
    <ls_cond>-currency  = is_doc-head-cuky.
    IF is_doc-head-cuky = 'VND'.
      <ls_cond>-cond_value = COND #( WHEN <ls_cond>-calctypcon <> 'A' THEN ls_cond_i-kbetr * 100
                                     ELSE ls_cond_i-kbetr * 1000 ).
    ELSE.
      <ls_cond>-cond_value = COND #( WHEN <ls_cond>-calctypcon <> 'A' THEN ls_cond_i-kbetr
                                     ELSE ls_cond_i-kbetr * 10 ).
    ENDIF.
    CASE ls_cond_i-kschl.
      WHEN 'PBXX'.
        <ls_cond>-change_id = 'U'.
      WHEN 'MWST'.
        lv_matnr = VALUE #( is_doc-t_item[ sttit = ls_cond_i-sttit ]-matnr OPTIONAL ).
        SELECT SINGLE taxim FROM mlan WHERE matnr = @lv_matnr AND aland = 'VN' INTO @DATA(lv_taxim).
        <ls_cond>-change_id = COND #( WHEN lv_taxim IS NOT INITIAL THEN 'U' ELSE 'I' ).
        CLEAR lv_taxim.
      WHEN OTHERS.
        <ls_cond>-change_id = 'I'.
    ENDCASE.
    APPEND VALUE #( itm_number = ls_cond_i-sttit cond_st_no = <ls_cond>-cond_st_no cond_type = 'X'
                    calctypcon = 'X' vendor_no = 'X' currency = 'X' cond_value = 'X' change_id = 'X' )
      TO cs_bapi-t_condx.
  ENDLOOP.
ENDFORM.

* Số HĐ / số phụ lục / loại TK ngân hàng trên EKKO + text header F01..F99
FORM cont_update_ekko_texts USING    is_doc    TYPE gty_cont_doc
                            CHANGING ct_return TYPE bapiret2_t.
  TYPES: BEGIN OF lty_text,
           tdid TYPE thead-tdid,
           text TYPE char255,
         END OF lty_text.
  DATA lt_text TYPE STANDARD TABLE OF lty_text WITH EMPTY KEY.

  UPDATE ekko SET zzhopdong = @is_doc-head-zcont,
                  zzphuluc  = @is_doc-head-zcont_an,
                  zzbvtyp   = @is_doc-head-zzbvtyp
    WHERE ebeln = @is_doc-head-ebeln.
  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
  ELSE.
    ROLLBACK WORK.
    APPEND VALUE #( type = 'W'
                    message = |Đơn mua hàng { is_doc-head-ebeln } đã tạo nhưng chưa cập nhật được số hợp đồng, số phụ lục và loại tài khoản ngân hàng.| )
      TO ct_return.
  ENDIF.

  lt_text = VALUE #( ( tdid = 'F01' text = is_doc-head-zekkof01 )
                     ( tdid = 'F02' text = is_doc-head-zekkof02 )
                     ( tdid = 'F03' text = is_doc-head-zekkof03 )
                     ( tdid = 'F04' text = is_doc-head-zekkof04 )
                     ( tdid = 'F05' text = is_doc-head-zekkof05 )
                     ( tdid = 'F06' text = is_doc-head-zekkof06 )
                     ( tdid = 'F98' text = is_doc-head-zekkof07 )
                     ( tdid = 'F99' text = is_doc-head-zekkof08 ) ).
  DATA(lv_tdname) = CONV thead-tdname( is_doc-head-ebeln ).
  LOOP AT lt_text INTO DATA(ls_text).
    CALL FUNCTION 'ZCORE_FM_SAVE_TEXT'
      EXPORTING
        i_tdid     = ls_text-tdid
        i_tdobject = 'EKKO'
        i_tname    = lv_tdname
        i_text     = ls_text-text.
  ENDLOOP.
ENDFORM.

* ZTB_CONT_HEADER / ZTB_CONT_ITEM / ZTB_CONT_HEADER1 / ZTB_COND_ITEM
FORM cont_save_tables CHANGING cs_doc    TYPE gty_cont_doc
                               ct_return TYPE bapiret2_t.
  DATA: lt_cond_all TYPE gty_t_cont_cond,
        lt_cond_db  TYPE gty_t_cont_cond_in,
        lv_line     TYPE zde_no,
        lt_failed   TYPE string_table.

  LOOP AT cs_doc-t_item ASSIGNING FIELD-SYMBOL(<ls_item>).
    <ls_item>-ebeln = cs_doc-head-ebeln.
  ENDLOOP.
  DELETE cs_doc-t_item WHERE matnr IS INITIAL.
  LOOP AT cs_doc-t_partner ASSIGNING FIELD-SYMBOL(<ls_partner>).
    <ls_partner>-ebeln = cs_doc-head-ebeln.
  ENDLOOP.

  " điều kiện: header + dòng, đánh số thứ tự trong từng dòng
  lt_cond_all = cs_doc-t_cond_h.
  APPEND LINES OF cs_doc-t_cond_i TO lt_cond_all.
  lt_cond_db = CORRESPONDING #( lt_cond_all ).
  LOOP AT lt_cond_db ASSIGNING FIELD-SYMBOL(<ls_cond>).
    <ls_cond>-mandt = sy-mandt.
    <ls_cond>-ebeln = cs_doc-head-ebeln.
    READ TABLE cs_doc-t_item INTO DATA(ls_item) WITH KEY sttit = <ls_cond>-sttit.
    IF sy-subrc = 0.
      <ls_cond>-matnr = ls_item-matnr.
      <ls_cond>-txz01 = ls_item-txz01.
    ENDIF.
  ENDLOOP.
  SORT lt_cond_db BY mandt ebeln sttit.
  LOOP AT lt_cond_db ASSIGNING <ls_cond>.
    lv_line = lv_line + 1.
    <ls_cond>-zcond_line = lv_line.
    AT END OF sttit.
      lv_line = 0.
    ENDAT.
  ENDLOOP.

  MODIFY ztb_cont_header FROM cs_doc-head.
  IF sy-subrc <> 0.
    APPEND `thông tin chung` TO lt_failed.
  ENDIF.
  MODIFY ztb_cont_item FROM TABLE cs_doc-t_item.
  IF sy-subrc <> 0.
    APPEND `dòng hàng` TO lt_failed.
  ENDIF.
  IF cs_doc-t_partner IS NOT INITIAL.
    MODIFY ztb_cont_header1 FROM TABLE cs_doc-t_partner.
    IF sy-subrc <> 0.
      APPEND `đối tác` TO lt_failed.
    ENDIF.
  ENDIF.
  IF lt_cond_db IS NOT INITIAL.
    MODIFY ztb_cond_item FROM TABLE lt_cond_db.
    IF sy-subrc <> 0.
      APPEND `điều kiện giá` TO lt_failed.
    ENDIF.
  ENDIF.
  COMMIT WORK AND WAIT.

  IF lt_failed IS NOT INITIAL.
    APPEND VALUE #( type = 'E' message_v1 = cs_doc-head-ebeln
                    message = |Đơn mua hàng { cs_doc-head-ebeln } đã tạo nhưng chưa lưu được { concat_lines_of( table = lt_failed sep = `, ` ) } của hợp đồng. Vui lòng báo bộ phận IT.| )
      TO ct_return.
  ELSE.
    APPEND VALUE #( type = 'S' message_v1 = cs_doc-head-ebeln
                    message = |Đã tạo hợp đồng và đơn mua hàng { cs_doc-head-ebeln } thành công.| ) TO ct_return.
  ENDIF.
ENDFORM.
