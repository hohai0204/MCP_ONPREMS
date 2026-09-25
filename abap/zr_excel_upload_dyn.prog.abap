REPORT zr_excel_upload_dyn.

*----------------------------------------------------------------------*
* ZR_EXCEL_UPLOAD_DYN - Dynamic Excel Upload Viewer ($TMP prototype)
*----------------------------------------------------------------------*
* Upload an .xlsx file with arbitrary/unknown columns, build a dynamic
* internal table matching the file layout and display it in a read-only
* SALV. Column types are taken from config table ZTB_EXCELMAPPING when
* P_PROG/P_SHEET are supplied (row TYPE='DATATYPE', per-column code
* C=text I=integer D=date F=float P[n]=packed decimal with n decimals
* (default 2), blank=auto); columns without a code fall back to
* auto-detection (date / integer / decimal / text).
*
* Textpool (EN):
*   R   Dynamic Excel Upload Viewer
*   S   P_FILE  Excel file (.xlsx)
*   S   P_HDR   First row contains column headers
*   S   P_PROG  Mapping key PROG (ZTB_EXCELMAPPING, optional)
*   S   P_SHEET Mapping key SHEET (ZTB_EXCELMAPPING, optional)
*   I01 Select Excel file
*   I02 File could not be read
*   I03 File is not a valid .xlsx workbook
*   I04 Workbook contains no worksheets
*   I05 Worksheet contains no data rows
*   I06 Column
*   I07 Too many columns in worksheet
*   I08 Excel files (*.xlsx)
*----------------------------------------------------------------------*

PARAMETERS:
  p_file  TYPE localfile LOWER CASE OBLIGATORY,
  p_hdr   TYPE abap_bool AS CHECKBOX DEFAULT abap_true,
  p_prog  TYPE ztb_excelmapping-prog,   " optional: config-driven typing
  p_sheet TYPE ztb_excelmapping-sheet.

*----------------------------------------------------------------------*
* LCX_ERROR - single error channel for all failure paths
*----------------------------------------------------------------------*
CLASS lcx_error DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA mv_text TYPE string READ-ONLY.
    METHODS constructor IMPORTING iv_text TYPE string.
ENDCLASS.

CLASS lcx_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    mv_text = iv_text.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* LCL_EXCEL - frontend file access + raw parse (all-string columns)
*----------------------------------------------------------------------*
CLASS lcl_excel DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS choose_file
      RETURNING VALUE(rv_path) TYPE string.
    METHODS read_file
      IMPORTING iv_path        TYPE string
      RETURNING VALUE(rv_xdoc) TYPE xstring
      RAISING   lcx_error.
    METHODS get_raw_table
      IMPORTING iv_xdoc       TYPE xstring
                iv_name       TYPE string
      RETURNING VALUE(rr_raw) TYPE REF TO data
      RAISING   lcx_error.
ENDCLASS.

CLASS lcl_excel IMPLEMENTATION.

  METHOD choose_file.
    DATA: lt_files TYPE filetable,
          lv_rc    TYPE i.

    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        window_title      = CONV #( TEXT-i01 )
        file_filter       = |{ TEXT-i08 }\|*.xlsx|
        default_extension = `xlsx`
        multiselection    = abap_false
      CHANGING
        file_table        = lt_files
        rc                = lv_rc
      EXCEPTIONS
        OTHERS            = 1 ).
    IF sy-subrc = 0 AND lv_rc > 0.
      rv_path = lt_files[ 1 ]-filename.
    ENDIF.
  ENDMETHOD.

  METHOD read_file.
    DATA: lt_data TYPE solix_tab,
          lv_len  TYPE i.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename   = iv_path
        filetype   = 'BIN'
      IMPORTING
        filelength = lv_len
      CHANGING
        data_tab   = lt_data
      EXCEPTIONS
        OTHERS     = 1 ).
    IF sy-subrc <> 0 OR lv_len = 0.
      RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i02 ) ).
    ENDIF.
    rv_xdoc = cl_bcs_convert=>solix_to_xstring( it_solix = lt_data
                                                iv_size  = lv_len ).
  ENDMETHOD.

  METHOD get_raw_table.
    DATA lo_xl TYPE REF TO cl_fdt_xl_spreadsheet.

    TRY.
        " constructor raises CX_FDT_EXCEL_CORE (verified on DS4)
        lo_xl = NEW cl_fdt_xl_spreadsheet( document_name = iv_name
                                           xdocument     = iv_xdoc ).
      CATCH cx_fdt_excel_core.
        RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i03 ) ).
    ENDTRY.

    lo_xl->if_fdt_doc_spreadsheet~get_worksheet_names(
      IMPORTING worksheet_names = DATA(lt_sheets) ).
    IF lt_sheets IS INITIAL.
      RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i04 ) ).
    ENDIF.

    rr_raw = lo_xl->if_fdt_doc_spreadsheet~get_itab_from_worksheet(
               lt_sheets[ 1 ] ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* LCL_DYN_TABLE - header sanitizing, type detection, dynamic build+fill
*----------------------------------------------------------------------*
CLASS lcl_dyn_table DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_col,
        fieldname  TYPE fieldname,   " sanitized ABAP component name
        header     TYPE string,      " original Excel header (ALV label)
        kind       TYPE c LENGTH 1,  " S=str I=int N=decimal D=date F=float
        decimals   TYPE i,
        configured TYPE abap_bool,   " X = kind fixed by ZTB_EXCELMAPPING
      END OF ty_col,
      ty_cols  TYPE STANDARD TABLE OF ty_col WITH EMPTY KEY,
      ty_names TYPE STANDARD TABLE OF fieldname WITH EMPTY KEY.

    CONSTANTS c_max_cols TYPE i VALUE 300.
    CONSTANTS c_type_row TYPE ztb_excelmapping-type VALUE 'DATATYPE'.

    METHODS build
      IMPORTING ir_raw    TYPE REF TO data
                iv_header TYPE abap_bool
                iv_prog   TYPE ztb_excelmapping-prog
                iv_sheet  TYPE ztb_excelmapping-sheet
      EXPORTING er_table  TYPE REF TO data
                et_cols   TYPE ty_cols
      RAISING   lcx_error.

    " public class-methods: pure logic, unit-tested
    CLASS-METHODS sanitize_name
      IMPORTING iv_header      TYPE string
                iv_index       TYPE i
                it_used        TYPE ty_names
      RETURNING VALUE(rv_name) TYPE fieldname.
    CLASS-METHODS classify_value
      IMPORTING iv_value    TYPE string
      EXPORTING ev_kind     TYPE ty_col-kind
                ev_decimals TYPE i.
    CLASS-METHODS to_date
      IMPORTING iv_value       TYPE string
      RETURNING VALUE(rv_date) TYPE d.

  PRIVATE SECTION.
    METHODS extract_headers
      IMPORTING ir_raw         TYPE REF TO data
                iv_header      TYPE abap_bool
      RETURNING VALUE(rt_cols) TYPE ty_cols
      RAISING   lcx_error.
    METHODS apply_config_types
      IMPORTING iv_prog  TYPE ztb_excelmapping-prog
                iv_sheet TYPE ztb_excelmapping-sheet
      CHANGING  ct_cols  TYPE ty_cols.
    METHODS detect_types
      IMPORTING ir_raw    TYPE REF TO data
                iv_header TYPE abap_bool
      CHANGING  ct_cols   TYPE ty_cols.
    METHODS create_table
      IMPORTING it_cols         TYPE ty_cols
      RETURNING VALUE(rr_table) TYPE REF TO data
      RAISING   lcx_error.
    METHODS fill_rows
      IMPORTING ir_raw    TYPE REF TO data
                iv_header TYPE abap_bool
                it_cols   TYPE ty_cols
      CHANGING  cr_table  TYPE REF TO data.
ENDCLASS.

CLASS lcl_dyn_table IMPLEMENTATION.

  METHOD build.
    FIELD-SYMBOLS <lt_raw> TYPE STANDARD TABLE.

    CLEAR: er_table, et_cols.
    ASSIGN ir_raw->* TO <lt_raw>.
    IF <lt_raw> IS NOT ASSIGNED OR lines( <lt_raw> ) = 0.
      RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i05 ) ).
    ENDIF.

    et_cols = extract_headers( ir_raw = ir_raw iv_header = iv_header ).
    apply_config_types( EXPORTING iv_prog  = iv_prog
                                  iv_sheet = iv_sheet
                        CHANGING  ct_cols  = et_cols ).
    detect_types( EXPORTING ir_raw = ir_raw iv_header = iv_header
                  CHANGING  ct_cols = et_cols ).
    er_table = create_table( et_cols ).
    fill_rows( EXPORTING ir_raw    = ir_raw
                         iv_header = iv_header
                         it_cols   = et_cols
               CHANGING  cr_table  = er_table ).
  ENDMETHOD.

  METHOD extract_headers.
    FIELD-SYMBOLS <lt_raw> TYPE STANDARD TABLE.
    DATA: lt_used   TYPE ty_names,
          lv_header TYPE string.

    ASSIGN ir_raw->* TO <lt_raw>.
    DATA(lo_tab)   = CAST cl_abap_tabledescr(
                       cl_abap_typedescr=>describe_by_data(
                         <lt_raw> ) ).
    DATA(lo_line)  = CAST cl_abap_structdescr(
                       lo_tab->get_table_line_type( ) ).
    DATA(lv_ncols) = lines( lo_line->components ).
    IF lv_ncols = 0.
      RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i05 ) ).
    ENDIF.
    IF lv_ncols > c_max_cols.
      RAISE EXCEPTION NEW lcx_error( CONV #( TEXT-i07 ) ).
    ENDIF.

    ASSIGN <lt_raw>[ 1 ] TO FIELD-SYMBOL(<ls_first>).
    DO lv_ncols TIMES.
      DATA(lv_idx) = sy-index.
      CLEAR lv_header.
      IF iv_header = abap_true AND <ls_first> IS ASSIGNED.
        ASSIGN COMPONENT lv_idx OF STRUCTURE <ls_first>
          TO FIELD-SYMBOL(<lv_cell>).
        IF sy-subrc = 0.
          lv_header = condense( CONV string( <lv_cell> ) ).
        ENDIF.
      ENDIF.
      IF lv_header IS INITIAL.
        lv_header = |{ TEXT-i06 } { lv_idx }|.   " "Column n"
      ENDIF.
      DATA(lv_name) = sanitize_name( iv_header = lv_header
                                     iv_index  = lv_idx
                                     it_used   = lt_used ).
      APPEND lv_name TO lt_used.
      APPEND VALUE #( fieldname = lv_name
                      header    = lv_header
                      kind      = 'S' ) TO rt_cols.
    ENDDO.
  ENDMETHOD.

  METHOD apply_config_types.
    " Override auto-detection with per-column type codes maintained in
    " ZTB_EXCELMAPPING (row TYPE='DATATYPE'): C=text I=int D=date F=float.
    " Positional: C0001->col 1, C0002->col 2 ... blank/unknown => auto.
    IF iv_prog IS INITIAL AND iv_sheet IS INITIAL.
      RETURN.                         " no key supplied: pure auto-detect
    ENDIF.

    SELECT SINGLE * FROM ztb_excelmapping
      INTO @DATA(ls_map)
      WHERE prog  = @iv_prog
        AND sheet = @iv_sheet
        AND type  = @c_type_row.
    IF sy-subrc <> 0.
      RETURN.                         " no config row: fall back to auto
    ENDIF.

    LOOP AT ct_cols ASSIGNING FIELD-SYMBOL(<ls_col>).
      DATA(lv_comp) = |C{ sy-tabix WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
      ASSIGN COMPONENT lv_comp OF STRUCTURE ls_map
        TO FIELD-SYMBOL(<lv_code>).
      IF sy-subrc <> 0.
        CONTINUE.                     " fewer C-columns than Excel columns
      ENDIF.
      DATA(lv_code) = to_upper( condense( CONV string( <lv_code> ) ) ).
      IF lv_code IS INITIAL.
        CONTINUE.                     " blank: leave column for auto-detect
      ENDIF.
      DATA(lv_first) = substring( val = lv_code len = 1 ).
      DATA(lv_rest)  = substring( val = lv_code off = 1 ).
      IF lv_code = 'C'.
        <ls_col>-kind       = 'S'.    " text: no thousands separator
        <ls_col>-configured = abap_true.
      ELSEIF lv_code = 'I' OR lv_code = 'D' OR lv_code = 'F'.
        <ls_col>-kind       = lv_code.
        <ls_col>-configured = abap_true.
      ELSEIF lv_first = 'P'
         AND ( lv_rest IS INITIAL OR lv_rest CO '0123456789' ).
        " packed decimal (money/quantity); optional digit suffix = decimals
        <ls_col>-kind       = 'N'.
        <ls_col>-decimals   = COND i( WHEN lv_rest IS INITIAL THEN 2
                                      ELSE nmin( val1 = CONV i( lv_rest )
                                                 val2 = 14 ) ).
        <ls_col>-configured = abap_true.
      ELSE.
        " unknown code: leave column for auto-detection
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD sanitize_name.
    DATA(lv_name) = to_upper( iv_header ).
    REPLACE ALL OCCURRENCES OF REGEX '[^A-Z0-9_]' IN lv_name WITH '_'.
    IF lv_name IS INITIAL OR lv_name CO '_'.
      lv_name = |COL_{ iv_index }|.
    ELSEIF substring( val = lv_name len = 1 ) CO '0123456789'.
      lv_name = |C{ lv_name }|.
    ENDIF.
    IF strlen( lv_name ) > 30.
      lv_name = substring( val = lv_name len = 30 ).
    ENDIF.

    DATA(lv_base) = lv_name.
    DATA lv_n TYPE i VALUE 1.
    WHILE line_exists( it_used[ table_line = lv_name ] ).
      lv_n = lv_n + 1.
      DATA(lv_suffix) = |_{ lv_n }|.
      DATA(lv_maxlen) = nmin( val1 = strlen( lv_base )
                              val2 = 30 - strlen( lv_suffix ) ).
      lv_name = substring( val = lv_base len = lv_maxlen ) && lv_suffix.
    ENDWHILE.
    rv_name = lv_name.
  ENDMETHOD.

  METHOD classify_value.
    CLEAR: ev_kind, ev_decimals.
    DATA(lv_val) = condense( iv_value ).

    " CL_FDT_XL_SPREADSHEET emits date cells as ISO YYYY-MM-DD, with
    " optional " HH:MM:SS" (verified on DS4 in method
    " CONVERT_CELL_VALUE_BY_NUMFMT). D.M.YYYY / D-M-YYYY / D/M/YYYY
    " covers dates typed as text (day-first convention).
    IF matches( val = lv_val regex = '\d{4}-\d{2}-\d{2}( .*)?' )
    OR matches( val = lv_val regex = '\d{1,2}[./-]\d{1,2}[./-]\d{4}' ).
      ev_kind = 'D'.
      RETURN.
    ENDIF.
    IF matches( val = lv_val regex = '[-+]?\d{1,16}' ).
      ev_kind = 'I'.
      RETURN.
    ENDIF.
    IF matches( val = lv_val regex = '[-+]?\d{1,16}[.,]\d{1,14}' ).
      ev_kind = 'N'.
      FIND REGEX '[.,](\d+)' IN lv_val SUBMATCHES DATA(lv_frac).
      ev_decimals = nmin( val1 = strlen( lv_frac ) val2 = 14 ).
      RETURN.
    ENDIF.
    ev_kind = 'S'.
  ENDMETHOD.

  METHOD detect_types.
    FIELD-SYMBOLS <lt_raw> TYPE STANDARD TABLE.
    DATA: lv_kind TYPE ty_col-kind,
          lv_dec  TYPE i,
          lv_ck   TYPE ty_col-kind,
          lv_cd   TYPE i.

    ASSIGN ir_raw->* TO <lt_raw>.
    DATA(lv_from) = COND i( WHEN iv_header = abap_true THEN 2 ELSE 1 ).

    LOOP AT ct_cols ASSIGNING FIELD-SYMBOL(<ls_col>).
      DATA(lv_idx) = sy-tabix.
      IF <ls_col>-configured = abap_true.
        CONTINUE.                     " type fixed by ZTB_EXCELMAPPING
      ENDIF.
      CLEAR: lv_kind, lv_dec.
      LOOP AT <lt_raw> ASSIGNING FIELD-SYMBOL(<ls_raw>) FROM lv_from.
        ASSIGN COMPONENT lv_idx OF STRUCTURE <ls_raw>
          TO FIELD-SYMBOL(<lv_cell>).
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        DATA(lv_val) = condense( CONV string( <lv_cell> ) ).
        IF lv_val IS INITIAL.
          CONTINUE.                   " empty cells ignored in detection
        ENDIF.
        classify_value( EXPORTING iv_value    = lv_val
                        IMPORTING ev_kind     = lv_ck
                                  ev_decimals = lv_cd ).
        IF lv_kind IS INITIAL.
          lv_kind = lv_ck.
          lv_dec  = lv_cd.
        ELSEIF lv_kind = lv_ck.
          lv_dec = nmax( val1 = lv_dec val2 = lv_cd ).
        ELSEIF ( lv_kind = 'I' AND lv_ck = 'N' )
            OR ( lv_kind = 'N' AND lv_ck = 'I' ).
          lv_kind = 'N'.              " integers promote to decimal
          lv_dec  = nmax( val1 = lv_dec val2 = lv_cd ).
        ELSE.
          lv_kind = 'S'.              " mixed types demote to string
        ENDIF.
        IF lv_kind = 'S'.
          EXIT.
        ENDIF.
      ENDLOOP.
      <ls_col>-kind     = COND #( WHEN lv_kind IS INITIAL THEN 'S'
                                  ELSE lv_kind ).
      <ls_col>-decimals = lv_dec.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_table.
    DATA: lt_comp TYPE abap_component_tab,
          lo_elem TYPE REF TO cl_abap_datadescr.

    LOOP AT it_cols INTO DATA(ls_col).
      CASE ls_col-kind.
        WHEN 'I'.
          lo_elem = cl_abap_elemdescr=>get_p( p_length   = 16
                                              p_decimals = 0 ).
        WHEN 'N'.
          lo_elem = cl_abap_elemdescr=>get_p(
                      p_length   = 16
                      p_decimals = ls_col-decimals ).
        WHEN 'D'.
          lo_elem = cl_abap_elemdescr=>get_d( ).
        WHEN 'F'.
          lo_elem = cl_abap_elemdescr=>get_f( ).
        WHEN OTHERS.
          lo_elem = cl_abap_elemdescr=>get_string( ).
      ENDCASE.
      APPEND VALUE #( name = ls_col-fieldname
                      type = lo_elem ) TO lt_comp.
    ENDLOOP.

    TRY.
        DATA(lo_struct) = cl_abap_structdescr=>create( lt_comp ).
        DATA(lo_table)  = cl_abap_tabledescr=>create( lo_struct ).
      CATCH cx_sy_struct_creation cx_sy_table_creation
            INTO DATA(lx_rtts).
        RAISE EXCEPTION NEW lcx_error( lx_rtts->get_text( ) ).
    ENDTRY.
    CREATE DATA rr_table TYPE HANDLE lo_table.
  ENDMETHOD.

  METHOD fill_rows.
    FIELD-SYMBOLS: <lt_raw> TYPE STANDARD TABLE,
                   <lt_out> TYPE STANDARD TABLE.

    ASSIGN ir_raw->* TO <lt_raw>.
    ASSIGN cr_table->* TO <lt_out>.
    DATA(lv_from) = COND i( WHEN iv_header = abap_true THEN 2 ELSE 1 ).

    LOOP AT <lt_raw> ASSIGNING FIELD-SYMBOL(<ls_raw>) FROM lv_from.
      APPEND INITIAL LINE TO <lt_out> ASSIGNING FIELD-SYMBOL(<ls_out>).
      LOOP AT it_cols INTO DATA(ls_col).
        DATA(lv_idx) = sy-tabix.
        ASSIGN COMPONENT lv_idx OF STRUCTURE <ls_raw>
          TO FIELD-SYMBOL(<lv_src>).
        IF sy-subrc <> 0.
          CONTINUE.                 " ragged row: missing trail cells
        ENDIF.
        ASSIGN COMPONENT ls_col-fieldname OF STRUCTURE <ls_out>
          TO FIELD-SYMBOL(<lv_dst>).
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        DATA(lv_val) = condense( CONV string( <lv_src> ) ).
        IF lv_val IS INITIAL.
          CONTINUE.
        ENDIF.
        CASE ls_col-kind.
          WHEN 'S'.
            <lv_dst> = lv_val.
          WHEN 'D'.
            <lv_dst> = to_date( lv_val ).
          WHEN OTHERS.
            lv_val = replace( val = lv_val sub = ','
                              with = '.' occ = 1 ).
            TRY.
                <lv_dst> = lv_val.
              CATCH cx_sy_conversion_error.
                " residual normalization failure: cell stays initial
            ENDTRY.
        ENDCASE.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD to_date.
    DATA: lv_mn TYPE n LENGTH 2,
          lv_dn TYPE n LENGTH 2.

    DATA(lv_val) = condense( iv_value ).
    FIND REGEX '^(\d{4})-(\d{2})-(\d{2})' IN lv_val
      SUBMATCHES DATA(lv_y) DATA(lv_m) DATA(lv_d).
    IF sy-subrc = 0.
      rv_date = lv_y && lv_m && lv_d.
      RETURN.
    ENDIF.
    FIND REGEX '^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$' IN lv_val
      SUBMATCHES DATA(lv_d2) DATA(lv_m2) DATA(lv_y2).
    IF sy-subrc = 0.
      lv_mn = lv_m2.                  " numeric assign pads to 2 digits
      lv_dn = lv_d2.
      rv_date = lv_y2 && lv_mn && lv_dn.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* LCL_DATA - orchestrator, no UI
*----------------------------------------------------------------------*
CLASS lcl_data DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS get_data
      IMPORTING iv_file   TYPE string
                iv_header TYPE abap_bool
                iv_prog   TYPE ztb_excelmapping-prog
                iv_sheet  TYPE ztb_excelmapping-sheet
      RAISING   lcx_error.
    METHODS get_table
      RETURNING VALUE(rr_table) TYPE REF TO data.
    METHODS get_columns
      RETURNING VALUE(rt_cols) TYPE lcl_dyn_table=>ty_cols.
  PRIVATE SECTION.
    DATA: mr_table TYPE REF TO data,
          mt_cols  TYPE lcl_dyn_table=>ty_cols.
ENDCLASS.

CLASS lcl_data IMPLEMENTATION.
  METHOD get_data.
    DATA(lo_excel) = NEW lcl_excel( ).
    DATA(lv_xdoc)  = lo_excel->read_file( iv_file ).
    DATA(lr_raw)   = lo_excel->get_raw_table( iv_xdoc = lv_xdoc
                                              iv_name = iv_file ).
    NEW lcl_dyn_table( )->build( EXPORTING ir_raw    = lr_raw
                                           iv_header = iv_header
                                           iv_prog   = iv_prog
                                           iv_sheet  = iv_sheet
                                 IMPORTING er_table  = mr_table
                                           et_cols   = mt_cols ).
  ENDMETHOD.

  METHOD get_table.
    rr_table = mr_table.
  ENDMETHOD.

  METHOD get_columns.
    rt_cols = mt_cols.
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* LCL_ALV - display only (read-only SALV)
*----------------------------------------------------------------------*
CLASS lcl_alv DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor IMPORTING io_data TYPE REF TO lcl_data.
    METHODS display.
  PRIVATE SECTION.
    DATA mo_data TYPE REF TO lcl_data.
ENDCLASS.

CLASS lcl_alv IMPLEMENTATION.
  METHOD constructor.
    mo_data = io_data.
  ENDMETHOD.

  METHOD display.
    FIELD-SYMBOLS <lt_out> TYPE STANDARD TABLE.

    DATA(lr_table) = mo_data->get_table( ).
    IF lr_table IS INITIAL.
      RETURN.                         " get_data failed earlier
    ENDIF.
    ASSIGN lr_table->* TO <lt_out>.
    IF lines( <lt_out> ) = 0.
      MESSAGE TEXT-i05 TYPE 'S'.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_salv)
                                CHANGING  t_table      = <lt_out> ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    lo_salv->get_functions( )->set_all( ).
    DATA(lo_cols) = lo_salv->get_columns( ).
    lo_cols->set_optimize( ).

    DATA(lt_cols) = mo_data->get_columns( ).
    LOOP AT lt_cols INTO DATA(ls_col).
      TRY.
          DATA(lo_col) = lo_cols->get_column( ls_col-fieldname ).
          lo_col->set_short_text( CONV #( ls_col-header ) ).
          lo_col->set_medium_text( CONV #( ls_col-header ) ).
          lo_col->set_long_text( CONV #( ls_col-header ) ).
        CATCH cx_salv_not_found.
          " column not in grid: nothing to label
      ENDTRY.
    ENDLOOP.

    lo_salv->display( ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Unit tests - pure logic only (sanitize + classify), automatable proof
*----------------------------------------------------------------------*
CLASS ltc_dyn_table DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS sanitize_special_chars FOR TESTING.
    METHODS sanitize_duplicate     FOR TESTING.
    METHODS sanitize_leading_digit FOR TESTING.
    METHODS classify_integer       FOR TESTING.
    METHODS classify_decimal       FOR TESTING.
    METHODS classify_date_iso      FOR TESTING.
    METHODS classify_date_dmy      FOR TESTING.
    METHODS classify_text          FOR TESTING.
ENDCLASS.

CLASS ltc_dyn_table IMPLEMENTATION.
  METHOD sanitize_special_chars.
    cl_abap_unit_assert=>assert_equals(
      act = lcl_dyn_table=>sanitize_name( iv_header = `Net Weight (kg)`
                                          iv_index  = 1
                                          it_used   = VALUE #( ) )
      exp = 'NET_WEIGHT__KG_' ).
  ENDMETHOD.

  METHOD sanitize_duplicate.
    cl_abap_unit_assert=>assert_equals(
      act = lcl_dyn_table=>sanitize_name(
              iv_header = `Matnr`
              iv_index  = 2
              it_used   = VALUE #( ( CONV fieldname( 'MATNR' ) ) ) )
      exp = 'MATNR_2' ).
  ENDMETHOD.

  METHOD sanitize_leading_digit.
    cl_abap_unit_assert=>assert_equals(
      act = lcl_dyn_table=>sanitize_name( iv_header = `2024 Plan`
                                          iv_index  = 3
                                          it_used   = VALUE #( ) )
      exp = 'C2024_PLAN' ).
  ENDMETHOD.

  METHOD classify_integer.
    lcl_dyn_table=>classify_value( EXPORTING iv_value = `-1234`
                                   IMPORTING ev_kind  = DATA(lv_kind) ).
    cl_abap_unit_assert=>assert_equals( act = lv_kind exp = 'I' ).
  ENDMETHOD.

  METHOD classify_decimal.
    lcl_dyn_table=>classify_value(
      EXPORTING iv_value    = `12,50`
      IMPORTING ev_kind     = DATA(lv_kind)
                ev_decimals = DATA(lv_dec) ).
    cl_abap_unit_assert=>assert_equals( act = lv_kind exp = 'N' ).
    cl_abap_unit_assert=>assert_equals( act = lv_dec  exp = 2 ).
  ENDMETHOD.

  METHOD classify_date_iso.
    lcl_dyn_table=>classify_value( EXPORTING iv_value = `2026-07-19`
                                   IMPORTING ev_kind  = DATA(lv_kind) ).
    cl_abap_unit_assert=>assert_equals( act = lv_kind exp = 'D' ).
    cl_abap_unit_assert=>assert_equals(
      act = lcl_dyn_table=>to_date( `2026-07-19` )
      exp = CONV d( '20260719' ) ).
  ENDMETHOD.

  METHOD classify_date_dmy.
    cl_abap_unit_assert=>assert_equals(
      act = lcl_dyn_table=>to_date( `9.7.2026` )
      exp = CONV d( '20260709' ) ).
  ENDMETHOD.

  METHOD classify_text.
    lcl_dyn_table=>classify_value( EXPORTING iv_value = `ABC123`
                                   IMPORTING ev_kind  = DATA(lv_kind) ).
    cl_abap_unit_assert=>assert_equals( act = lv_kind exp = 'S' ).
  ENDMETHOD.
ENDCLASS.

*----------------------------------------------------------------------*
* Global objects + event blocks
*----------------------------------------------------------------------*
DATA: go_data TYPE REF TO lcl_data,
      go_alv  TYPE REF TO lcl_alv.

INITIALIZATION.
  go_data = NEW #( ).
  go_alv  = NEW #( go_data ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  DATA(gv_pick) = lcl_excel=>choose_file( ).
  IF gv_pick IS NOT INITIAL.
    p_file = gv_pick.
  ENDIF.

START-OF-SELECTION.
  TRY.
      go_data->get_data( iv_file   = CONV #( p_file )
                         iv_header = p_hdr
                         iv_prog   = p_prog
                         iv_sheet  = p_sheet ).
    CATCH lcx_error INTO DATA(gx_error).
      MESSAGE gx_error->mv_text TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
  ENDTRY.

END-OF-SELECTION.
  go_alv->display( ).
