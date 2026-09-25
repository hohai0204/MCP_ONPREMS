*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_CORE_INTF03.
* Yêu cầu mua hàng (Purchase Requisition)
*----------------------------------------------------------------------*

* Dựng header + dòng cho danh sách số PR (giữ thứ tự của it_banfn).
FORM pr_details USING    it_banfn      TYPE ANY TABLE
                         iv_with_items TYPE xfeld
                CHANGING ct_header     TYPE STANDARD TABLE
                         ct_item       TYPE STANDARD TABLE.
  TYPES: BEGIN OF ty_banfn,
           banfn TYPE eban-banfn,
         END OF ty_banfn.
  DATA: lt_banfn  TYPE STANDARD TABLE OF ty_banfn WITH DEFAULT KEY,
        ls_header TYPE zctd_s_int_pr_hdr,
        ls_item   TYPE zctd_s_int_pr_itm,
        lv_factor TYPE decfloat34,
        lv_peinh  TYPE decfloat34.

  lt_banfn = CORRESPONDING #( it_banfn ).

  SELECT e~banfn, e~bnfpo, e~bsart, e~ernam, e~erdat, e~badat, e~afnam, e~bednr,
         e~frgst, e~frgkz, e~matnr, e~txz01, e~matkl, e~werks, e~lgort, e~menge,
         e~meins, e~lfdat, e~preis, e~peinh, e~waers, e~ekgrp, e~ekorg, e~knttp,
         e~pstyp, e~statu, e~loekz, e~ebakz, e~ebeln, e~ebelp, k~ps_psp_pnr
    FROM eban AS e
    LEFT OUTER JOIN ebkn AS k ON k~banfn = e~banfn AND k~bnfpo = e~bnfpo AND k~zebkn = '01'
    FOR ALL ENTRIES IN @lt_banfn
    WHERE e~banfn = @lt_banfn-banfn
    INTO TABLE @DATA(lt_eban).
  SORT lt_eban BY banfn bnfpo.

  LOOP AT lt_banfn INTO DATA(ls_banfn).
    CLEAR ls_header.
    LOOP AT lt_eban INTO DATA(ls_eban) WHERE banfn = ls_banfn-banfn.
      IF ls_header IS INITIAL.
        ls_header-prnumber         = ls_eban-banfn.
        ls_header-prtype           = ls_eban-bsart.
        ls_header-createdby        = ls_eban-ernam.
        ls_header-createdon        = ls_eban-erdat.
        ls_header-requestdate      = ls_eban-badat.
        ls_header-requisitioner    = ls_eban-afnam.
        ls_header-trackingno       = ls_eban-bednr.
        ls_header-releasestrategy  = ls_eban-frgst.
        ls_header-releaseindicator = ls_eban-frgkz.
        ls_header-currency         = ls_eban-waers.
      ENDIF.

      CLEAR ls_item.
      PERFORM currency_factor USING ls_eban-waers CHANGING lv_factor.
      lv_peinh = COND #( WHEN ls_eban-peinh > 0 THEN ls_eban-peinh ELSE 1 ).
      ls_item-prnumber           = ls_eban-banfn.
      ls_item-item               = ls_eban-bnfpo.
      ls_item-shorttext          = ls_eban-txz01.
      ls_item-materialgroup      = ls_eban-matkl.
      ls_item-plant              = ls_eban-werks.
      ls_item-storagelocation    = ls_eban-lgort.
      ls_item-quantity           = ls_eban-menge.
      ls_item-deliverydate       = ls_eban-lfdat.
      ls_item-valuationprice     = ls_eban-preis * lv_factor.
      ls_item-priceunit          = ls_eban-peinh.
      ls_item-currency           = ls_eban-waers.
      ls_item-itemvalue          = ls_eban-menge * ls_eban-preis * lv_factor / lv_peinh.
      ls_item-purchasinggroup    = ls_eban-ekgrp.
      ls_item-purchasingorg      = ls_eban-ekorg.
      ls_item-acctassigncategory = ls_eban-knttp.
      ls_item-itemcategory       = ls_eban-pstyp.
      ls_item-releaseindicator   = ls_eban-frgkz.
      ls_item-processingstatus   = ls_eban-statu.
      ls_item-deletionindicator  = ls_eban-loekz.
      ls_item-closed             = ls_eban-ebakz.
      ls_item-ponumber           = ls_eban-ebeln.
      ls_item-poitem             = ls_eban-ebelp.
      ls_item-requisitioner      = ls_eban-afnam.
      ls_item-trackingno         = ls_eban-bednr.
      IF ls_eban-matnr IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_MATN1_OUTPUT'
          EXPORTING
            input  = ls_eban-matnr
          IMPORTING
            output = ls_item-material.
      ENDIF.
      IF ls_eban-meins IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
          EXPORTING
            input          = ls_eban-meins
            language       = sy-langu
          IMPORTING
            output         = ls_item-uom
          EXCEPTIONS
            unit_not_found = 1
            OTHERS         = 2.
        IF sy-subrc <> 0.
          ls_item-uom = ls_eban-meins.
        ENDIF.
      ENDIF.
      IF ls_eban-ps_psp_pnr IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_ABPSP_OUTPUT'
          EXPORTING
            input  = ls_eban-ps_psp_pnr
          IMPORTING
            output = ls_item-wbselement.
      ENDIF.

      ls_header-itemcount = ls_header-itemcount + 1.
      IF ls_eban-loekz IS INITIAL.
        ls_header-totalvalue = ls_header-totalvalue + ls_item-itemvalue.
      ENDIF.
      IF iv_with_items = abap_true.
        APPEND ls_item TO ct_item.
      ENDIF.
    ENDLOOP.
    IF ls_header IS NOT INITIAL.
      APPEND ls_header TO ct_header.
    ENDIF.
  ENDLOOP.
ENDFORM.
