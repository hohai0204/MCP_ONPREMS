* Đọc thông tin PO (header + item) cho OData ZCTD_PO_INFO_SRV.
* Cùng nguồn dữ liệu với ZPOST_PO (ZPG_MASTER_POST_PO_WBS, các form
* GET_DATA / PROCESS_DATA / BUILD_JSON):
*   - Header: ZTB_CONT_HEADER (+ PROJ/PRPS), EKKO; hợp đồng phụ lục thì
*     PO thực là ZTB_CONT_HEADER-ELBAN (chỉ khi phụ lục không có PO riêng)
*   - Item  : EKPO + EKKN (WBS, BOMG) + ZTB_CONT_ITEM (Brand, thiết bị ZP08)
*   - Trả tất cả dòng PO (kể cả dòng không nhận hóa đơn - ZPOST_PO bỏ các dòng này)
* Số tiền trả ra theo số thực của tiền tệ (VND nhân 100 so với giá trị
* lưu nội bộ). Thuế lấy từ điều kiện MWST của PO (PRCD_ELEMENTS).

  CONSTANTS lc_mwst TYPE kschl VALUE 'MWST'.

  DATA: lv_ebeln    TYPE ebeln,
        lv_factor   TYPE p LENGTH 8 DECIMALS 0 VALUE 100,
        lv_currdec  TYPE currdec,
        lv_tax      TYPE p LENGTH 16 DECIMALS 2,
        lv_net      TYPE p LENGTH 16 DECIMALS 2,
        lv_kposn    TYPE kposn,
        lv_date     TYPE d,
        lv_time     TYPE t,
        lv_all_del  TYPE abap_bool VALUE abap_true,
        lv_all_done TYPE abap_bool VALUE abap_true,
        ls_item     TYPE zctd_s_po_info_itm.

  CLEAR: es_header, et_return.
  REFRESH et_item.

  IF iv_ebeln IS INITIAL.
    APPEND VALUE #( type = 'E' parameter = 'IV_EBELN'
                    message = |Chưa nhập số đơn mua hàng.| ) TO et_return.
    RETURN.
  ENDIF.
  lv_ebeln = |{ iv_ebeln ALPHA = IN }|.

  " hợp đồng ZCONT; phụ lục thì PO thực là ELBAN
  SELECT SINGLE ebeln, elban, bsart, lifnr, name_org2, pspid, posid, zcont,
                zhdnd, zzgthd, tgthd, bedat
    FROM ztb_cont_header
    WHERE ebeln = @lv_ebeln
    INTO @DATA(ls_cont).
  IF ls_cont-elban IS NOT INITIAL.
    " phụ lục không có PO riêng -> dùng PO gốc; có PO riêng thì giữ đúng PO được hỏi
    SELECT SINGLE ebeln FROM ekko WHERE ebeln = @lv_ebeln INTO @DATA(lv_own_po).
    IF lv_own_po IS INITIAL.
      lv_ebeln = ls_cont-elban.
    ENDIF.
  ENDIF.

  SELECT SINGLE ebeln, bsart, lifnr, bedat, aedat, waers, wkurs, knumv,
                procstat, frggr, frgrl, lastchangedatetime, zzhopdong
    FROM ekko
    WHERE ebeln = @lv_ebeln
    INTO @DATA(ls_ekko).
  IF sy-subrc <> 0.
    APPEND VALUE #( type = 'E' parameter = 'IV_EBELN'
                    message = |Không tìm thấy đơn mua hàng { iv_ebeln ALPHA = OUT }.| ) TO et_return.
    RETURN.
  ENDIF.

  " hệ số đổi số tiền nội bộ -> số thực (VND: 0 số lẻ -> x100)
  SELECT SINGLE currdec FROM tcurx WHERE currkey = @ls_ekko-waers INTO @lv_currdec.
  IF sy-subrc <> 0.
    lv_currdec = 2.
  ENDIF.
  lv_factor = ipow( base = 10 exp = 2 - lv_currdec ).

  "--------------------------------------------------------------------
  " Item
  "--------------------------------------------------------------------
  SELECT ekpo~ebelp, ekpo~matnr, ekpo~txz01, ekpo~menge, ekpo~meins,
         ekpo~netpr, ekpo~peinh, ekpo~netwr, ekpo~loekz, ekpo~elikz,
         ekpo~retpo, ekpo~repos, ekpo~webre, ekpo~banfn, ekpo~bnfpo,
         ekpo~werks, ekpo~lgort,
         prps~posid, prps~post1,
         bomg~zbomg_code, bomg~zbomg_desc,
         cont_it~matnr_e, cont_it~meins_e, cont_it~menge_e, cont_it~brand
    FROM ekpo
    LEFT JOIN ekkn ON ekkn~ebeln = ekpo~ebeln AND ekkn~ebelp = ekpo~ebelp AND ekkn~zekkn = '01'
    LEFT JOIN prps ON prps~pspnr = ekkn~ps_psp_pnr
    LEFT JOIN ztb_bomg_header AS bomg ON bomg~zbomg_code = ekkn~ablad
    LEFT JOIN ztb_cont_item AS cont_it ON cont_it~ebeln = ekpo~ebeln AND cont_it~sttit = ekpo~ebelp
    WHERE ekpo~ebeln = @lv_ebeln
    ORDER BY ekpo~ebelp
    INTO TABLE @DATA(lt_po).

  SELECT kposn, kbetr, kwert FROM prcd_elements
    WHERE knumv = @ls_ekko-knumv AND kschl = @lc_mwst AND kinak = @space
    INTO TABLE @DATA(lt_tax).

  SELECT ebelp, MIN( eindt ) AS eindt FROM eket
    WHERE ebeln = @lv_ebeln
    GROUP BY ebelp
    INTO TABLE @DATA(lt_eket).

  LOOP AT lt_po INTO DATA(ls_po).
    CLEAR ls_item.
    ls_item-ponumber        = lv_ebeln.
    ls_item-item            = ls_po-ebelp.
    ls_item-prnumber        = ls_po-banfn.
    ls_item-pritem          = ls_po-bnfpo.
    ls_item-wbsname         = ls_po-post1.
    ls_item-bomg            = ls_po-zbomg_code.
    ls_item-bomgname        = ls_po-zbomg_desc.
    ls_item-description     = ls_po-txz01.
    ls_item-priceunit       = ls_po-peinh.
    ls_item-plant           = ls_po-werks.
    ls_item-storagelocation = ls_po-lgort.
    ls_item-deleteindicator = ls_po-loekz.
    ls_item-returnitem      = ls_po-retpo.
    ls_item-brand           = ls_po-brand.
    ls_item-unitprice       = ls_po-netpr * lv_factor.
    ls_item-amount          = ls_po-netwr * lv_factor.
    IF ls_po-retpo IS NOT INITIAL.
      ls_item-amount = - ls_item-amount.
    ENDIF.

    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
      EXPORTING
        input  = ls_po-posid
      IMPORTING
        output = ls_item-wbs.

    " hợp đồng thuê thiết bị ZP08: gửi thiết bị thay cho vật tư (như ZPOST_PO)
    IF ls_ekko-bsart = 'ZP08' AND ls_po-matnr_e IS NOT INITIAL.
      ls_po-matnr = ls_po-matnr_e.
      ls_po-meins = ls_po-meins_e.
      ls_po-menge = ls_po-menge_e.
    ENDIF.
    CALL FUNCTION 'CONVERSION_EXIT_MATN1_OUTPUT'
      EXPORTING
        input  = ls_po-matnr
      IMPORTING
        output = ls_item-material.
    CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
      EXPORTING
        input          = ls_po-meins
        language       = sy-langu
      IMPORTING
        output         = ls_item-uom
      EXCEPTIONS
        unit_not_found = 1
        OTHERS         = 2.
    IF sy-subrc <> 0.
      ls_item-uom = ls_po-meins.
    ENDIF.
    ls_item-quantity = ls_po-menge.

    lv_kposn = ls_po-ebelp.
    ls_item-vatrate = VALUE #( lt_tax[ kposn = lv_kposn ]-kbetr OPTIONAL ).
    lv_date = VALUE #( lt_eket[ ebelp = ls_po-ebelp ]-eindt OPTIONAL ).
    IF lv_date IS NOT INITIAL.
      ls_item-deliverydate = lv_date.
    ENDIF.

    " dòng đã xóa nhưng đã có nhập kho -> không cho sửa ở hệ thống nhận
    IF ls_po-loekz = 'L'.
      SELECT SINGLE mblnr FROM mseg
        WHERE ebeln = @lv_ebeln AND ebelp = @ls_po-ebelp
        INTO @DATA(lv_mblnr).
      IF lv_mblnr IS NOT INITIAL.
        ls_item-disable = 'X'.
      ENDIF.
      CLEAR lv_mblnr.
    ENDIF.

    ls_item-itemstatus = COND #( WHEN ls_po-loekz = 'L' THEN 'DELETED'
                                 WHEN ls_po-loekz = 'S' THEN 'BLOCKED'
                                 WHEN ls_po-elikz IS NOT INITIAL THEN 'CLOSED'
                                 ELSE 'OPEN' ).
    IF ls_po-loekz IS INITIAL.
      lv_all_del = abap_false.
      lv_net = lv_net + ls_item-amount.
      IF ls_po-elikz IS INITIAL.
        lv_all_done = abap_false.
      ENDIF.
      IF es_header-prnumber IS INITIAL.
        es_header-prnumber = ls_po-banfn.
      ENDIF.
      IF ls_item-deliverydate IS NOT INITIAL
      AND ( es_header-deliverydate IS INITIAL OR ls_item-deliverydate < es_header-deliverydate ).
        es_header-deliverydate = ls_item-deliverydate.
      ENDIF.
    ENDIF.
    APPEND ls_item TO et_item.
  ENDLOOP.

  "--------------------------------------------------------------------
  " Header
  "--------------------------------------------------------------------
  es_header-ponumber   = lv_ebeln.
  es_header-potype     = ls_ekko-bsart.
  es_header-vendorcode = ls_ekko-lifnr.
  es_header-vendorname = ls_cont-name_org2.
  IF es_header-vendorname IS INITIAL.
    SELECT SINGLE name_org1 FROM but000 WHERE partner = @ls_ekko-lifnr INTO @es_header-vendorname.
  ENDIF.
  IF es_header-vendorname IS INITIAL.
    SELECT SINGLE name1 FROM lfa1 WHERE lifnr = @ls_ekko-lifnr INTO @es_header-vendorname.
  ENDIF.

  " dự án / WBS hợp đồng: theo ZCONT, nếu không có thì theo WBS dòng đầu
  IF ls_cont-pspid IS INITIAL AND lt_po IS NOT INITIAL.
    SELECT SINGLE proj~pspid FROM prps
      INNER JOIN proj ON proj~pspnr = prps~psphi
      WHERE prps~posid = @( lt_po[ 1 ]-posid )
      INTO @ls_cont-pspid.
  ENDIF.
  SELECT SINGLE post1 FROM proj WHERE pspid = @ls_cont-pspid INTO @es_header-projectname.
  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
    EXPORTING
      input  = ls_cont-pspid
    IMPORTING
      output = es_header-projectcode.
  IF ls_cont-posid IS NOT INITIAL.
    CALL FUNCTION 'CONVERSION_EXIT_ABPSN_OUTPUT'
      EXPORTING
        input  = ls_cont-posid
      IMPORTING
        output = es_header-wbscode.
    SELECT SINGLE post1 FROM prps WHERE posid = @ls_cont-posid INTO @es_header-tenderpackage.
  ENDIF.

  es_header-contractno   = COND #( WHEN ls_cont-zcont IS NOT INITIAL THEN ls_cont-zcont ELSE ls_ekko-zzhopdong ).
  es_header-documentdate = COND #( WHEN ls_cont-bedat IS NOT INITIAL THEN ls_cont-bedat ELSE ls_ekko-bedat ).
  es_header-currency     = ls_ekko-waers.
  es_header-exchangerate = abs( ls_ekko-wkurs ).
  es_header-note         = ls_cont-zhdnd.

  " giá trị: theo hợp đồng ZCONT (như ZPOST_PO), không có thì theo PO
  lv_tax = REDUCE #( INIT s = CONV decfloat34( 0 ) FOR t IN lt_tax NEXT s = s + t-kwert ).
  IF ls_cont-ebeln IS NOT INITIAL AND ls_cont-zzgthd IS NOT INITIAL.
    es_header-subtotal    = ls_cont-zzgthd * lv_factor.
    es_header-totalamount = COND #( WHEN ls_cont-tgthd IS NOT INITIAL THEN ls_cont-tgthd * lv_factor
                                    ELSE ( ls_cont-zzgthd + lv_tax ) * lv_factor ).
  ELSE.
    es_header-subtotal    = lv_net.
    es_header-totalamount = lv_net + lv_tax * lv_factor.
  ENDIF.
  es_header-taxamount = es_header-totalamount - es_header-subtotal.

  " trạng thái PO / phê duyệt
  es_header-releasestatus = COND #( WHEN ls_ekko-frggr IS INITIAL THEN 'NOT_REQUIRED'
                                    WHEN ls_ekko-frgrl IS NOT INITIAL THEN 'NOT_RELEASED'
                                    ELSE 'RELEASED' ).
  es_header-status = COND #( WHEN lv_all_del = abap_true AND et_item[] IS NOT INITIAL THEN 'DELETED'
                             WHEN lv_all_done = abap_true AND et_item[] IS NOT INITIAL THEN 'CLOSED'
                             WHEN ls_ekko-procstat = '01' THEN 'IN_PREPARATION'
                             WHEN ls_ekko-procstat = '02' THEN 'ACTIVE'
                             WHEN ls_ekko-procstat = '03' OR ls_ekko-procstat = '04' THEN 'IN_RELEASE'
                             WHEN ls_ekko-procstat = '05' THEN 'RELEASED'
                             WHEN ls_ekko-procstat = '08' THEN 'REJECTED'
                             ELSE ls_ekko-procstat ).

  " thời điểm thay đổi (UTC) và phiên bản = thời điểm + số lần thay đổi
  IF ls_ekko-lastchangedatetime IS NOT INITIAL.
    CONVERT TIME STAMP ls_ekko-lastchangedatetime TIME ZONE 'UTC' INTO DATE lv_date TIME lv_time.
  ELSE.
    lv_date = ls_ekko-aedat.
    CLEAR lv_time.
  ENDIF.
  es_header-changedat = |{ lv_date(4) }-{ lv_date+4(2) }-{ lv_date+6(2) }T{ lv_time(2) }:{ lv_time+2(2) }:{ lv_time+4(2) }Z|.
  SELECT COUNT(*) FROM cdhdr
    WHERE objectclas = 'EINKBELEG' AND objectid = @lv_ebeln
    INTO @DATA(lv_changes).
  es_header-sourceversion = |{ lv_date }{ lv_time }-{ lv_changes }|.

  APPEND VALUE #( type = 'S' message_v1 = lv_ebeln
                  message = |Đã đọc đơn mua hàng { lv_ebeln ALPHA = OUT } ({ lines( et_item ) } dòng).| ) TO et_return.
