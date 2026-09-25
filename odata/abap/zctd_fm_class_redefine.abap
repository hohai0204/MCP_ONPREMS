* Ghi lại class con (vd. DPC_EXT do SEGW sinh) với các method REDEFINE,
* giống cách SEGW tạo class (SEO_CLASS_CREATE_COMPLETE, OVERWRITE).
* IV_SOURCE: các khối "METHOD <tên>. ... ENDMETHOD." - mỗi khối là một
* method của lớp cha được redefine. Class trong $TMP, hoặc package thật
* khi có IV_TRANSPORT (request) - thay đổi được ghi vào TR đó.
* Các method redefine đang có mà không nằm trong IV_SOURCE sẽ bị bỏ.
* Method của interface: "METHOD /ns/if_xxx~method." (REFCLSNAME = lớp cha).
* Local helper class (CCIMP): đặt giữa 2 dòng "*@LOCALS_IMP" và "*@END_LOCALS".

  TYPES: BEGIN OF lty_block,
           name  TYPE seocpdname,
           lines TYPE rswsourcet,
         END OF lty_block.

  DATA: ls_class     TYPE vseoclass,
        ls_inherit   TYPE vseoextend,
        lt_redef     TYPE seor_redefinitions_r,
        lt_sources   TYPE seo_method_source_table,
        lt_blocks    TYPE STANDARD TABLE OF lty_block,
        lt_lines     TYPE string_table,
        lt_descr     TYPE STANDARD TABLE OF seoclasstx,
        lt_locals    TYPE rswsourcet,
        lv_in_locals TYPE abap_bool,
        lv_intf      TYPE seoclsname,
        lv_intf_mtd  TYPE seocpdname,
        lv_in_method TYPE abap_bool,
        lv_upper     TYPE string.

  FIELD-SYMBOLS <ls_block> TYPE lty_block.

  CLEAR et_return.

  SELECT SINGLE devclass FROM tadir
    WHERE pgmid = 'R3TR' AND object = 'CLAS' AND obj_name = @iv_class
    INTO @DATA(lv_devclass).
  IF lv_devclass IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Không tìm thấy class { iv_class }.| ) TO et_return.
    RETURN.
  ENDIF.
  IF lv_devclass <> '$TMP' AND iv_transport IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Class { iv_class } thuộc package { lv_devclass }, cần số TR để ghi đè.| ) TO et_return.
    RETURN.
  ENDIF.
  SELECT SINGLE * FROM seoclassdf
    WHERE clsname = @iv_class AND version = '1'
    INTO @DATA(ls_classdf).
  SELECT SINGLE refclsname FROM seometarel
    WHERE clsname = @iv_class AND version = '1' AND reltype = '2'
    INTO @DATA(lv_super).
  IF ls_classdf IS INITIAL OR lv_super IS INITIAL.
    APPEND VALUE #( type = 'E' message = |Không đọc được định nghĩa hoặc lớp cha của class { iv_class }.| ) TO et_return.
    RETURN.
  ENDIF.

  " tách IV_SOURCE thành từng method
  SPLIT iv_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
  LOOP AT lt_lines INTO DATA(lv_line).
    lv_line = replace( val = lv_line sub = cl_abap_char_utilities=>cr_lf(1) with = `` occ = 0 ).
    lv_upper = to_upper( condense( lv_line ) ).
    " phần local class (CCIMP)
    IF lv_upper = '*@LOCALS_IMP'.
      lv_in_locals = abap_true.
      CONTINUE.
    ELSEIF lv_upper = '*@END_LOCALS'.
      lv_in_locals = abap_false.
      CONTINUE.
    ELSEIF lv_in_locals = abap_true.
      APPEND lv_line TO lt_locals.
      CONTINUE.
    ENDIF.
    IF lv_in_method = abap_false AND lv_upper CP 'METHOD *'.
      APPEND INITIAL LINE TO lt_blocks ASSIGNING <ls_block>.
      <ls_block>-name = to_upper( replace( val = segment( val = lv_upper index = 2 sep = ` ` ) sub = `.` with = `` ) ).
      lv_in_method = abap_true.
    ENDIF.
    " chỉ lấy thân method - SEO tự sinh khung METHOD/ENDMETHOD
    IF lv_in_method = abap_true.
      IF lv_upper CP 'ENDMETHOD*'.
        lv_in_method = abap_false.
      ELSEIF NOT lv_upper CP 'METHOD *'.
        APPEND lv_line TO <ls_block>-lines.
      ENDIF.
    ENDIF.
  ENDLOOP.
  IF lt_blocks IS INITIAL OR lv_in_method = abap_true.
    APPEND VALUE #( type = 'E' message = |Mã nguồn không có khối METHOD ... ENDMETHOD hợp lệ.| ) TO et_return.
    RETURN.
  ENDIF.

  LOOP AT lt_blocks ASSIGNING <ls_block>.
    IF <ls_block>-name CS '~'.
      " method của interface: kiểm tra tồn tại trong interface
      SPLIT <ls_block>-name AT '~' INTO lv_intf lv_intf_mtd.
      SELECT SINGLE cmpname FROM seocompodf
        WHERE clsname = @lv_intf AND cmpname = @lv_intf_mtd
        INTO @DATA(lv_intf_cmp).
      IF sy-subrc <> 0.
        APPEND VALUE #( type = 'E' message = |Interface { lv_intf } không có method { lv_intf_mtd }.| ) TO et_return.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( clsname = iv_class refclsname = lv_super version = '1'
                      mtdname = <ls_block>-name exposure = '0' ) TO lt_redef.
      APPEND VALUE #( cpdname = <ls_block>-name redefine = abap_true source = <ls_block>-lines ) TO lt_sources.
      CONTINUE.
    ENDIF.
    SELECT SINGLE exposure FROM seocompodf
      WHERE clsname = @lv_super AND cmpname = @<ls_block>-name AND version = '1'
      INTO @DATA(lv_exposure).
    IF sy-subrc <> 0.
      " method khai báo ở tầng cao hơn: dò chuỗi kế thừa (SE24 lưu EXPOSURE = 0)
      DATA(lv_anc) = CONV seoclsname( lv_super ).
      CLEAR lv_exposure.
      DO 20 TIMES.
        SELECT SINGLE refclsname FROM seometarel
          WHERE clsname = @lv_anc AND version = '1' AND reltype = '2'
          INTO @lv_anc.
        IF sy-subrc <> 0.
          CLEAR lv_anc.
          EXIT.
        ENDIF.
        SELECT SINGLE cmpname FROM seocompodf
          WHERE clsname = @lv_anc AND cmpname = @<ls_block>-name
          INTO @DATA(lv_found).
        IF sy-subrc = 0.
          EXIT.
        ENDIF.
      ENDDO.
      IF lv_anc IS INITIAL.
        APPEND VALUE #( type = 'E' message = |Lớp cha { lv_super } và các lớp trên không có method { <ls_block>-name }.| ) TO et_return.
        CONTINUE.
      ENDIF.
    ENDIF.
    APPEND VALUE #( clsname = iv_class refclsname = lv_super version = '1'
                    mtdname = <ls_block>-name exposure = lv_exposure ) TO lt_redef.
    APPEND VALUE #( cpdname = <ls_block>-name redefine = abap_true source = <ls_block>-lines ) TO lt_sources.
  ENDLOOP.
  IF line_exists( et_return[ type = 'E' ] ).
    RETURN.
  ENDIF.

  ls_class = CORRESPONDING #( ls_classdf ).
  SELECT SINGLE descript FROM seoclasstx
    WHERE clsname = @iv_class AND langu = 'E'
    INTO @ls_class-descript.
  ls_class-langu = 'E'.
  ls_inherit = VALUE #( clsname = iv_class refclsname = lv_super version = '1' state = '1' ).
  lt_descr = VALUE #( ( clsname = iv_class langu = 'E' descript = ls_class-descript ) ).

  CALL FUNCTION 'SEO_CLASS_CREATE_COMPLETE'
    EXPORTING
      devclass        = lv_devclass
      corrnr          = iv_transport
      version         = '1'
      overwrite       = abap_true
      suppress_dialog = abap_true
      method_sources  = lt_sources
      locals_imp      = lt_locals
    TABLES
      class_descriptions = lt_descr
    CHANGING
      class           = ls_class
      inheritance     = ls_inherit
      redefinitions   = lt_redef
    EXCEPTIONS
      existing        = 1
      is_interface    = 2
      db_error        = 3
      component_error = 4
      no_access       = 5
      other           = 6
      OTHERS          = 7.
  IF sy-subrc <> 0.
    APPEND VALUE #( type = 'E' id = sy-msgid number = sy-msgno
                    message_v1 = sy-msgv1 message_v2 = sy-msgv2 message_v3 = sy-msgv3 message_v4 = sy-msgv4
                    message = |Ghi class { iv_class } thất bại (SEO_CLASS_CREATE_COMPLETE rc={ sy-subrc }).| ) TO et_return.
    RETURN.
  ENDIF.
  COMMIT WORK AND WAIT.
  APPEND VALUE #( type = 'S'
                  message = |Đã ghi class { iv_class } với { lines( lt_sources ) } method redefine{ COND #( WHEN lt_locals IS NOT INITIAL THEN ` và local class` ) }.| ) TO et_return.
