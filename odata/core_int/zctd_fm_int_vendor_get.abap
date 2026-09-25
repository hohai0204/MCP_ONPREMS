* Đọc nhà cung cấp cho OData ZCTD_CORE_INT_SRV (VendorSet).
* Lọc (IT_FILTER, tùy chọn): Supplier, Name1, SearchTerm, Country,
* AccountGroup, TaxNumber1, VATNumber, CreatedOn (YYYYMMDD),
* PostingBlock, DeletionFlag.
* Sắp xếp số nhà cung cấp giảm dần. IV_TOP = 0 -> 100, tối đa 1000.
* Địa chỉ / điện thoại / e-mail lấy từ địa chỉ chuẩn (ADRC, ADR6);
* Business Partner + nhóm BP lấy qua liên kết CVI.

  DATA: lr_lifnr TYPE RANGE OF lfa1-lifnr,
        lr_name1 TYPE RANGE OF lfa1-name1,
        lr_sortl TYPE RANGE OF lfa1-sortl,
        lr_land1 TYPE RANGE OF lfa1-land1,
        lr_ktokk TYPE RANGE OF lfa1-ktokk,
        lr_stcd1 TYPE RANGE OF lfa1-stcd1,
        lr_stceg TYPE RANGE OF lfa1-stceg,
        lr_erdat TYPE RANGE OF lfa1-erdat,
        lr_sperr TYPE RANGE OF lfa1-sperr,
        lr_loevm TYPE RANGE OF lfa1-loevm,
        lv_top   TYPE i.

  CLEAR: ev_total, et_return.
  REFRESH et_vendor.

  PERFORM check_filter USING it_filter[]
    `SUPPLIER,NAME1,SEARCHTERM,COUNTRY,ACCOUNTGROUP,TAXNUMBER1,VATNUMBER,CREATEDON,POSTINGBLOCK,DELETIONFLAG`
    `Danh sách nhà cung cấp`
    CHANGING et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  PERFORM filter_range USING it_filter[] `SUPPLIER`     `ALPHA` CHANGING lr_lifnr.
  PERFORM filter_range USING it_filter[] `NAME1`        ``      CHANGING lr_name1.
  PERFORM filter_range USING it_filter[] `SEARCHTERM`   `UPPER` CHANGING lr_sortl.
  PERFORM filter_range USING it_filter[] `COUNTRY`      `UPPER` CHANGING lr_land1.
  PERFORM filter_range USING it_filter[] `ACCOUNTGROUP` `UPPER` CHANGING lr_ktokk.
  PERFORM filter_range USING it_filter[] `TAXNUMBER1`   ``      CHANGING lr_stcd1.
  PERFORM filter_range USING it_filter[] `VATNUMBER`    ``      CHANGING lr_stceg.
  PERFORM filter_range USING it_filter[] `CREATEDON`    ``      CHANGING lr_erdat.
  PERFORM filter_range USING it_filter[] `POSTINGBLOCK` `UPPER` CHANGING lr_sperr.
  PERFORM filter_range USING it_filter[] `DELETIONFLAG` `UPPER` CHANGING lr_loevm.
  PERFORM get_top USING iv_top CHANGING lv_top.

  SELECT COUNT(*) FROM lfa1
    WHERE lifnr IN @lr_lifnr AND name1 IN @lr_name1 AND sortl IN @lr_sortl
      AND land1 IN @lr_land1 AND ktokk IN @lr_ktokk AND stcd1 IN @lr_stcd1
      AND stceg IN @lr_stceg AND erdat IN @lr_erdat AND sperr IN @lr_sperr
      AND loevm IN @lr_loevm
    INTO @ev_total.

  SELECT lifnr, ktokk, name1, name2, sortl, stras, ort01, pstlz, regio, land1,
         spras, telf1, stcd1, stceg, sperr, sperm, loevm, erdat, ernam, adrnr
    FROM lfa1
    WHERE lifnr IN @lr_lifnr AND name1 IN @lr_name1 AND sortl IN @lr_sortl
      AND land1 IN @lr_land1 AND ktokk IN @lr_ktokk AND stcd1 IN @lr_stcd1
      AND stceg IN @lr_stceg AND erdat IN @lr_erdat AND sperr IN @lr_sperr
      AND loevm IN @lr_loevm
    ORDER BY lifnr DESCENDING
    INTO TABLE @DATA(lt_lfa1)
    UP TO @lv_top ROWS
    OFFSET @iv_skip.
  IF lt_lfa1 IS INITIAL.
    APPEND VALUE #( type = 'S' message = |Không có nhà cung cấp nào thỏa điều kiện.| ) TO et_return.
    RETURN.
  ENDIF.

  PERFORM vendor_details USING lt_lfa1 CHANGING et_vendor[].
  APPEND VALUE #( type = 'S'
                  message = |Tìm thấy { ev_total } nhà cung cấp, trả về { lines( et_vendor ) }.| ) TO et_return.
