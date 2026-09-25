FUNCTION-POOL zctd_fg_core_int.             "MESSAGE-ID ..
*----------------------------------------------------------------------*
* CTD Core - dữ liệu cho OData ZCTD_CORE_INT_SRV.
* Mỗi đối tượng tích hợp có FM ZCTD_FM_INT_<ĐỐI TƯỢNG>_GET cùng kiểu
* interface: IV_TOP / IV_SKIP / IT_FILTER (ZCTD_S_INT_FILTER) ->
* EV_TOTAL / ET_RETURN + bảng dữ liệu. Form dùng chung ở LZCTD_FG_CORE_INTF01.
*----------------------------------------------------------------------*
TYPES ty_t_filter TYPE STANDARD TABLE OF zctd_s_int_filter WITH DEFAULT KEY.

CONSTANTS: gc_default_top TYPE i VALUE 100,
           gc_max_top     TYPE i VALUE 1000.

* INCLUDE LZCTD_FG_CORE_INTD...              " Local class definition

*----------------------------------------------------------------------*
* Message class ZMC_CTD -> BAPIRET2 (ID, NUMBER, MESSAGE_V1..V4, text).
* Dùng: APPEND VALUE #( BASE lcl_msg=>get( iv_no = '001' iv_v1 = .. )
*                       type = 'E' parameter = .. ) TO et_return.
*----------------------------------------------------------------------*
CLASS lcl_msg DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS gc_msgid TYPE symsgid VALUE 'ZMC_CTD'.
    CLASS-METHODS get
      IMPORTING iv_no            TYPE symsgno
                iv_v1            TYPE csequence OPTIONAL
                iv_v2            TYPE csequence OPTIONAL
                iv_v3            TYPE csequence OPTIONAL
                iv_v4            TYPE csequence OPTIONAL
      RETURNING VALUE(rs_return) TYPE bapiret2.
ENDCLASS.

CLASS lcl_msg IMPLEMENTATION.
  METHOD get.
    rs_return = VALUE #( id = gc_msgid number = iv_no
                         message_v1 = iv_v1 message_v2 = iv_v2 message_v3 = iv_v3 message_v4 = iv_v4 ).
    MESSAGE ID gc_msgid TYPE 'S' NUMBER iv_no
            WITH rs_return-message_v1 rs_return-message_v2 rs_return-message_v3 rs_return-message_v4
            INTO rs_return-message.
  ENDMETHOD.
ENDCLASS.
