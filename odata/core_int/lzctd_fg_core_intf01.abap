*----------------------------------------------------------------------*
***INCLUDE LZCTD_FG_CORE_INTF01.
* Form dùng chung cho các FM ZCTD_FM_INT_*_GET
*----------------------------------------------------------------------*

* Báo lỗi nếu có điều kiện lọc theo field không hỗ trợ.
* iv_allowed: danh sách property viết hoa, cách nhau bằng dấu phẩy.
FORM check_filter USING    it_filter  TYPE ty_t_filter
                           iv_allowed TYPE string
                           iv_object  TYPE string
                  CHANGING ct_return  TYPE bapiret2_t.
  DATA lt_allowed TYPE string_table.

  SPLIT iv_allowed AT ',' INTO TABLE lt_allowed.
  LOOP AT it_filter INTO DATA(ls_filter).
    DATA(lv_property) = to_upper( condense( CONV string( ls_filter-property ) ) ).
    IF NOT line_exists( lt_allowed[ table_line = lv_property ] ).
      APPEND VALUE #( type    = 'E'
                      message = |{ iv_object } chưa hỗ trợ lọc theo { ls_filter-property }.| )
        TO ct_return.
    ENDIF.
  ENDLOOP.
ENDFORM.

* Chuyển các điều kiện lọc của một property sang range (sign/option/low/high).
* iv_conv: ALPHA = bổ sung số 0 đầu, UPPER = chữ hoa, MATN1 = mã vật tư,
*          ISOLA = mã ngôn ngữ ISO, trống = giữ nguyên.
* Mẫu CP/NP (dấu *) không chuyển đổi.
FORM filter_range USING    it_filter   TYPE ty_t_filter
                           iv_property TYPE string
                           iv_conv     TYPE string
                  CHANGING ct_range    TYPE STANDARD TABLE.
  FIELD-SYMBOLS: <ls_range> TYPE any,
                 <lv_value> TYPE any.

  LOOP AT it_filter INTO DATA(ls_filter).
    CHECK to_upper( condense( CONV string( ls_filter-property ) ) ) = iv_property.
    APPEND INITIAL LINE TO ct_range ASSIGNING <ls_range>.
    ASSIGN COMPONENT 'SIGN' OF STRUCTURE <ls_range> TO <lv_value>.
    <lv_value> = COND #( WHEN ls_filter-sign IS INITIAL THEN 'I' ELSE ls_filter-sign ).
    ASSIGN COMPONENT 'OPTION' OF STRUCTURE <ls_range> TO <lv_value>.
    <lv_value> = COND #( WHEN ls_filter-option IS INITIAL THEN 'EQ' ELSE ls_filter-option ).
    ASSIGN COMPONENT 'LOW' OF STRUCTURE <ls_range> TO <lv_value>.
    PERFORM convert_value USING ls_filter-low iv_conv ls_filter-option CHANGING <lv_value>.
    ASSIGN COMPONENT 'HIGH' OF STRUCTURE <ls_range> TO <lv_value>.
    IF ls_filter-high IS NOT INITIAL.
      PERFORM convert_value USING ls_filter-high iv_conv ls_filter-option CHANGING <lv_value>.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM convert_value USING    iv_value  TYPE csequence
                            iv_conv   TYPE string
                            iv_option TYPE csequence
                   CHANGING cv_value  TYPE any.
  DATA lv_value TYPE string.

  lv_value = condense( iv_value ).
  IF iv_option = 'CP' OR iv_option = 'NP'.
    cv_value = lv_value.
    RETURN.
  ENDIF.
  CASE iv_conv.
    WHEN 'ALPHA'.
      cv_value = |{ lv_value ALPHA = IN WIDTH = 10 }|.
    WHEN 'UPPER'.
      cv_value = to_upper( lv_value ).
    WHEN 'MATN1'.
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input        = lv_value
        IMPORTING
          output       = cv_value
        EXCEPTIONS
          length_error = 1
          OTHERS       = 2.
      IF sy-subrc <> 0.
        cv_value = to_upper( lv_value ).
      ENDIF.
    WHEN 'ISOLA'.
      CALL FUNCTION 'CONVERSION_EXIT_ISOLA_INPUT'
        EXPORTING
          input            = to_upper( lv_value )
        IMPORTING
          output           = cv_value
        EXCEPTIONS
          unknown_language = 1
          OTHERS           = 2.
      IF sy-subrc <> 0.
        cv_value = lv_value.
      ENDIF.
    WHEN OTHERS.
      cv_value = lv_value.
  ENDCASE.
ENDFORM.

* Số dòng trả về: 0 -> mặc định, vượt quá thì cắt ở mức tối đa.
FORM get_top USING    iv_top TYPE i
             CHANGING cv_top TYPE i.
  cv_top = COND #( WHEN iv_top <= 0 THEN gc_default_top
                   WHEN iv_top > gc_max_top THEN gc_max_top
                   ELSE iv_top ).
ENDFORM.

* Hệ số đổi số tiền nội bộ sang số thực theo số lẻ của tiền tệ (VND: x100).
FORM currency_factor USING    iv_waers  TYPE waers
                     CHANGING cv_factor TYPE decfloat34.
  SELECT SINGLE currdec FROM tcurx WHERE currkey = @iv_waers INTO @DATA(lv_currdec).
  IF sy-subrc <> 0.
    lv_currdec = 2.
  ENDIF.
  cv_factor = ipow( base = CONV decfloat34( 10 ) exp = 2 - lv_currdec ).
ENDFORM.
