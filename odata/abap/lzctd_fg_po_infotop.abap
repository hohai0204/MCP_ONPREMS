FUNCTION-POOL ZCTD_FG_PO_INFO.              "MESSAGE-ID ..

* INCLUDE LZCTD_FG_PO_INFOD...               " Local class definition

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
