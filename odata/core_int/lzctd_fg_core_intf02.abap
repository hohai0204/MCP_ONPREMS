*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_CORE_INTF02.
* Nhà cung cấp (Vendor)
*----------------------------------------------------------------------*

* Bổ sung Business Partner, địa chỉ chuẩn, e-mail cho danh sách LFA1.
FORM vendor_details USING    it_lfa1   TYPE ANY TABLE
                    CHANGING ct_vendor TYPE STANDARD TABLE.
  TYPES: BEGIN OF ty_lfa1,
           lifnr TYPE lfa1-lifnr, ktokk TYPE lfa1-ktokk, name1 TYPE lfa1-name1,
           name2 TYPE lfa1-name2, sortl TYPE lfa1-sortl, stras TYPE lfa1-stras,
           ort01 TYPE lfa1-ort01, pstlz TYPE lfa1-pstlz, regio TYPE lfa1-regio,
           land1 TYPE lfa1-land1, spras TYPE lfa1-spras, telf1 TYPE lfa1-telf1,
           stcd1 TYPE lfa1-stcd1, stceg TYPE lfa1-stceg, sperr TYPE lfa1-sperr,
           sperm TYPE lfa1-sperm, loevm TYPE lfa1-loevm, erdat TYPE lfa1-erdat,
           ernam TYPE lfa1-ernam, adrnr TYPE lfa1-adrnr,
         END OF ty_lfa1.
  DATA: lt_lfa1   TYPE STANDARD TABLE OF ty_lfa1 WITH DEFAULT KEY,
        ls_vendor TYPE zctd_s_int_vendor.

  lt_lfa1 = CORRESPONDING #( it_lfa1 ).

  SELECT v~vendor, b~partner, b~bu_group
    FROM cvi_vend_link AS v
    INNER JOIN but000 AS b ON b~partner_guid = v~partner_guid
    FOR ALL ENTRIES IN @lt_lfa1
    WHERE v~vendor = @lt_lfa1-lifnr
    INTO TABLE @DATA(lt_bp).
  SORT lt_bp BY vendor.

  DATA(lt_addr) = lt_lfa1.
  DELETE lt_addr WHERE adrnr IS INITIAL.
  IF lt_addr IS NOT INITIAL.
    SELECT addrnumber, name1, name2, sort1, street, city1, post_code1, region, tel_number
      FROM adrc
      FOR ALL ENTRIES IN @lt_addr
      WHERE addrnumber = @lt_addr-adrnr AND nation = @space
      INTO TABLE @DATA(lt_adrc).
    SORT lt_adrc BY addrnumber.
    SELECT addrnumber, smtp_addr
      FROM adr6
      FOR ALL ENTRIES IN @lt_addr
      WHERE addrnumber = @lt_addr-adrnr AND persnumber = @space AND flgdefault = @abap_true
      INTO TABLE @DATA(lt_adr6).
    SORT lt_adr6 BY addrnumber.
  ENDIF.

  LOOP AT lt_lfa1 INTO DATA(ls_lfa1).
    CLEAR ls_vendor.
    ls_vendor-supplier        = ls_lfa1-lifnr.
    ls_vendor-accountgroup    = ls_lfa1-ktokk.
    ls_vendor-name1           = ls_lfa1-name1.
    ls_vendor-name2           = ls_lfa1-name2.
    ls_vendor-searchterm      = ls_lfa1-sortl.
    ls_vendor-street          = ls_lfa1-stras.
    ls_vendor-city            = ls_lfa1-ort01.
    ls_vendor-postalcode      = ls_lfa1-pstlz.
    ls_vendor-region          = ls_lfa1-regio.
    ls_vendor-country         = ls_lfa1-land1.
    ls_vendor-telephone       = ls_lfa1-telf1.
    ls_vendor-taxnumber1      = ls_lfa1-stcd1.
    ls_vendor-vatnumber       = ls_lfa1-stceg.
    ls_vendor-postingblock    = ls_lfa1-sperr.
    ls_vendor-purchasingblock = ls_lfa1-sperm.
    ls_vendor-deletionflag    = ls_lfa1-loevm.
    ls_vendor-createdon       = ls_lfa1-erdat.
    ls_vendor-createdby       = ls_lfa1-ernam.
    IF ls_lfa1-spras IS NOT INITIAL.
      CALL FUNCTION 'CONVERSION_EXIT_ISOLA_OUTPUT'
        EXPORTING
          input  = ls_lfa1-spras
        IMPORTING
          output = ls_vendor-language.
    ENDIF.

    READ TABLE lt_bp INTO DATA(ls_bp) WITH KEY vendor = ls_lfa1-lifnr BINARY SEARCH.
    IF sy-subrc = 0.
      ls_vendor-businesspartner = ls_bp-partner.
      ls_vendor-bpgrouping      = ls_bp-bu_group.
    ENDIF.

    " địa chỉ chuẩn dài hơn LFA1 -> ưu tiên ADRC khi có giá trị
    READ TABLE lt_adrc INTO DATA(ls_adrc) WITH KEY addrnumber = ls_lfa1-adrnr BINARY SEARCH.
    IF sy-subrc = 0.
      ls_vendor-name1      = COND #( WHEN ls_adrc-name1 IS NOT INITIAL THEN ls_adrc-name1 ELSE ls_vendor-name1 ).
      ls_vendor-name2      = COND #( WHEN ls_adrc-name2 IS NOT INITIAL THEN ls_adrc-name2 ELSE ls_vendor-name2 ).
      ls_vendor-searchterm = COND #( WHEN ls_adrc-sort1 IS NOT INITIAL THEN ls_adrc-sort1 ELSE ls_vendor-searchterm ).
      ls_vendor-street     = COND #( WHEN ls_adrc-street IS NOT INITIAL THEN ls_adrc-street ELSE ls_vendor-street ).
      ls_vendor-city       = COND #( WHEN ls_adrc-city1 IS NOT INITIAL THEN ls_adrc-city1 ELSE ls_vendor-city ).
      ls_vendor-postalcode = COND #( WHEN ls_adrc-post_code1 IS NOT INITIAL THEN ls_adrc-post_code1 ELSE ls_vendor-postalcode ).
      ls_vendor-region     = COND #( WHEN ls_adrc-region IS NOT INITIAL THEN ls_adrc-region ELSE ls_vendor-region ).
      ls_vendor-telephone  = COND #( WHEN ls_adrc-tel_number IS NOT INITIAL THEN ls_adrc-tel_number ELSE ls_vendor-telephone ).
    ENDIF.
    READ TABLE lt_adr6 INTO DATA(ls_adr6) WITH KEY addrnumber = ls_lfa1-adrnr BINARY SEARCH.
    IF sy-subrc = 0.
      ls_vendor-email = ls_adr6-smtp_addr.
    ENDIF.

    APPEND ls_vendor TO ct_vendor.
  ENDLOOP.
ENDFORM.
