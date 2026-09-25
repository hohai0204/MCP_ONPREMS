* Update module (V1) của ZCTD_FM_CREATE_CONT - ghi dữ liệu hợp đồng ZCONT
* trong CÙNG LUW cập nhật với BAPI_PO_CREATE1:
*   EKKO số hợp đồng / phụ lục / loại TK ngân hàng (dự phòng - BAPI đã ghi
*   qua EXTENSIONIN), text header PO, ZTB_CONT_HEADER / ZTB_CONT_ITEM /
*   ZTB_CONT_HEADER1 / ZTB_COND_ITEM.
* Gọi IN UPDATE TASK trước BAPI_TRANSACTION_COMMIT. Lỗi ghi bảng hợp đồng
* -> MESSAGE type A -> SAP hủy toàn bộ LUW cập nhật, kể cả đơn mua hàng
* (xem SM13), không còn trường hợp có PO mà thiếu hợp đồng.

  TYPES: BEGIN OF lty_text,
           tdid TYPE thead-tdid,
           text TYPE char255,
         END OF lty_text.
  DATA lt_text TYPE STANDARD TABLE OF lty_text WITH EMPTY KEY.

  " PO do BAPI tạo đã được ghi trước trong cùng LUW (module V1 chạy theo thứ tự gọi)
  UPDATE ekko SET zzhopdong = @is_header-zcont,
                  zzphuluc  = @is_header-zcont_an,
                  zzbvtyp   = @is_header-zzbvtyp
    WHERE ebeln = @is_header-ebeln.

  lt_text = VALUE #( ( tdid = 'F01' text = is_header-zekkof01 )
                     ( tdid = 'F02' text = is_header-zekkof02 )
                     ( tdid = 'F03' text = is_header-zekkof03 )
                     ( tdid = 'F04' text = is_header-zekkof04 )
                     ( tdid = 'F05' text = is_header-zekkof05 )
                     ( tdid = 'F06' text = is_header-zekkof06 )
                     ( tdid = 'F98' text = is_header-zekkof07 )
                     ( tdid = 'F99' text = is_header-zekkof08 ) ).
  DATA(lv_tdname) = CONV thead-tdname( is_header-ebeln ).
  LOOP AT lt_text INTO DATA(ls_text) WHERE text IS NOT INITIAL.
    CALL FUNCTION 'ZCORE_FM_SAVE_TEXT'
      EXPORTING
        i_tdid     = ls_text-tdid
        i_tdobject = 'EKKO'
        i_tname    = lv_tdname
        i_text     = ls_text-text.
  ENDLOOP.

  MODIFY ztb_cont_header FROM is_header.
  IF sy-subrc <> 0.
    MESSAGE a060(zmc_ctd) WITH is_header-ebeln.
  ENDIF.
  IF it_item[] IS NOT INITIAL.
    MODIFY ztb_cont_item FROM TABLE it_item.
    IF sy-subrc <> 0.
      MESSAGE a061(zmc_ctd) WITH is_header-ebeln.
    ENDIF.
  ENDIF.
  IF it_partner[] IS NOT INITIAL.
    MODIFY ztb_cont_header1 FROM TABLE it_partner.
    IF sy-subrc <> 0.
      MESSAGE a062(zmc_ctd) WITH is_header-ebeln.
    ENDIF.
  ENDIF.
  IF it_cond[] IS NOT INITIAL.
    MODIFY ztb_cond_item FROM TABLE it_cond.
    IF sy-subrc <> 0.
      MESSAGE a063(zmc_ctd) WITH is_header-ebeln.
    ENDIF.
  ENDIF.
