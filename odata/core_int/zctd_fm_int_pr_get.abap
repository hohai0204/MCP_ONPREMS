* Đọc yêu cầu mua hàng (Purchase Requisition, EBAN) cho OData
* ZCTD_CORE_INT_SRV (PurchaseReqSet / PurchaseReqItemSet).
* Lọc (IT_FILTER, tùy chọn): PRNumber, PRType, Plant, PurchasingGroup,
* PurchasingOrg, Material, CreatedOn / RequestDate (YYYYMMDD),
* ReleaseIndicator, Requisitioner, TrackingNo.
* Điều kiện lọc áp trên dòng PR; PR thỏa khi có ít nhất 1 dòng thỏa,
* và trả về đầy đủ các dòng của PR đó.
* Phân trang theo số PR giảm dần. IV_TOP = 0 -> 100 PR, tối đa 1000.
* IV_WITH_ITEMS = space: chỉ trả header.
* Header lấy loại PR / người tạo / ngày / release từ dòng đầu tiên;
* tổng giá trị chỉ cộng các dòng chưa xóa.

  DATA: lr_banfn TYPE RANGE OF eban-banfn,
        lr_bsart TYPE RANGE OF eban-bsart,
        lr_werks TYPE RANGE OF eban-werks,
        lr_ekgrp TYPE RANGE OF eban-ekgrp,
        lr_ekorg TYPE RANGE OF eban-ekorg,
        lr_matnr TYPE RANGE OF eban-matnr,
        lr_erdat TYPE RANGE OF eban-erdat,
        lr_badat TYPE RANGE OF eban-badat,
        lr_frgkz TYPE RANGE OF eban-frgkz,
        lr_afnam TYPE RANGE OF eban-afnam,
        lr_bednr TYPE RANGE OF eban-bednr,
        lv_top   TYPE i.

  CLEAR: ev_total, et_return.
  REFRESH: et_header, et_item.

  PERFORM check_filter USING it_filter[]
    `PRNUMBER,PRTYPE,PLANT,PURCHASINGGROUP,PURCHASINGORG,MATERIAL,CREATEDON,REQUESTDATE,RELEASEINDICATOR,REQUISITIONER,TRACKINGNO`
    `Danh sách yêu cầu mua hàng`
    CHANGING et_return.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  PERFORM filter_range USING it_filter[] `PRNUMBER`         `ALPHA` CHANGING lr_banfn.
  PERFORM filter_range USING it_filter[] `PRTYPE`           `UPPER` CHANGING lr_bsart.
  PERFORM filter_range USING it_filter[] `PLANT`            `UPPER` CHANGING lr_werks.
  PERFORM filter_range USING it_filter[] `PURCHASINGGROUP`  `UPPER` CHANGING lr_ekgrp.
  PERFORM filter_range USING it_filter[] `PURCHASINGORG`    `UPPER` CHANGING lr_ekorg.
  PERFORM filter_range USING it_filter[] `MATERIAL`         `MATN1` CHANGING lr_matnr.
  PERFORM filter_range USING it_filter[] `CREATEDON`        ``      CHANGING lr_erdat.
  PERFORM filter_range USING it_filter[] `REQUESTDATE`      ``      CHANGING lr_badat.
  PERFORM filter_range USING it_filter[] `RELEASEINDICATOR` `UPPER` CHANGING lr_frgkz.
  PERFORM filter_range USING it_filter[] `REQUISITIONER`    `UPPER` CHANGING lr_afnam.
  PERFORM filter_range USING it_filter[] `TRACKINGNO`       `UPPER` CHANGING lr_bednr.
  PERFORM get_top USING iv_top CHANGING lv_top.

  SELECT COUNT( DISTINCT banfn ) FROM eban
    WHERE banfn IN @lr_banfn AND bsart IN @lr_bsart AND werks IN @lr_werks
      AND ekgrp IN @lr_ekgrp AND ekorg IN @lr_ekorg AND matnr IN @lr_matnr
      AND erdat IN @lr_erdat AND badat IN @lr_badat AND frgkz IN @lr_frgkz
      AND afnam IN @lr_afnam AND bednr IN @lr_bednr
    INTO @ev_total.

  SELECT DISTINCT banfn FROM eban
    WHERE banfn IN @lr_banfn AND bsart IN @lr_bsart AND werks IN @lr_werks
      AND ekgrp IN @lr_ekgrp AND ekorg IN @lr_ekorg AND matnr IN @lr_matnr
      AND erdat IN @lr_erdat AND badat IN @lr_badat AND frgkz IN @lr_frgkz
      AND afnam IN @lr_afnam AND bednr IN @lr_bednr
    ORDER BY banfn DESCENDING
    INTO TABLE @DATA(lt_banfn)
    UP TO @lv_top ROWS
    OFFSET @iv_skip.
  IF lt_banfn IS INITIAL.
    APPEND VALUE #( type = 'S' message = |Không có yêu cầu mua hàng nào thỏa điều kiện.| ) TO et_return.
    RETURN.
  ENDIF.

  PERFORM pr_details USING lt_banfn iv_with_items CHANGING et_header[] et_item[].
  APPEND VALUE #( type = 'S'
                  message = |Tìm thấy { ev_total } yêu cầu mua hàng, trả về { lines( et_header ) }.| ) TO et_return.
