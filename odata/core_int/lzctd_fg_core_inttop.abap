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
