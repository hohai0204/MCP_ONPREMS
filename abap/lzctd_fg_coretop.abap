FUNCTION-POOL ZCTD_FG_CORE.                 "MESSAGE-ID ..

* INCLUDE LZCTD_FG_CORED...                  " Local class definition

*----------------------------------------------------------------------*
* ZCTD_FM_CREATE_CONT - kiểu dữ liệu dùng chung với LZCTD_FG_COREF01
*----------------------------------------------------------------------*
TYPES: gty_t_cont_item    TYPE STANDARD TABLE OF ztb_cont_item WITH DEFAULT KEY,
       gty_t_cont_partner TYPE STANDARD TABLE OF ztb_cont_header1 WITH DEFAULT KEY,
       gty_t_cont_cond_in TYPE STANDARD TABLE OF ztb_cond_item WITH DEFAULT KEY,
       gty_t_cont_cond    TYPE STANDARD TABLE OF zst_cond_item WITH DEFAULT KEY,
       gty_r_cont_matnr   TYPE RANGE OF matnr,
       gty_r_cont_mtart   TYPE RANGE OF mtart,

       BEGIN OF gty_cont_step,             " bước tổng của thủ tục giá ZRM000
         stunr TYPE stunr,
         vtext TYPE t683t-vtext,
       END OF gty_cont_step,
       gty_t_cont_step TYPE STANDARD TABLE OF gty_cont_step WITH DEFAULT KEY,

       BEGIN OF gty_cont_wbs,              " WBS cấp 4 thuộc WBS hợp đồng
         psphi TYPE prps-psphi,
         posid TYPE prps-posid,
       END OF gty_cont_wbs,
       gty_t_cont_wbs TYPE STANDARD TABLE OF gty_cont_wbs WITH DEFAULT KEY,

       BEGIN OF gty_cont_brand,            " giá trị Brand theo phân loại vật tư
         class TYPE klah-class,
         matnr TYPE inob-objek,
         atinn TYPE ksml-imerk,
         brand TYPE cawn-atwrt,
       END OF gty_cont_brand,
       gty_t_cont_brand TYPE STANDARD TABLE OF gty_cont_brand WITH DEFAULT KEY,

       " chứng từ đang xử lý (tương ứng các biến global của ZCCM_PG_ZCONT_NEW)
       BEGIN OF gty_cont_doc,
         head        TYPE ztb_cont_header,
         zbudg       TYPE zde_signbudg_plan_no,
         vendor_addr TYPE addr1_dia,
         t_item      TYPE gty_t_cont_item,
         t_partner   TYPE gty_t_cont_partner,
         t_cond_in   TYPE gty_t_cont_cond_in,  " điều kiện giá đầu vào
         t_cond_h    TYPE gty_t_cont_cond,     " tab Condition (gt_item_condition)
         t_cond_i    TYPE gty_t_cont_cond,     " điều kiện dòng (gt_item_condition_item_sum)
         t_step      TYPE gty_t_cont_step,
         t_wbs       TYPE gty_t_cont_wbs,
         t_brand     TYPE gty_t_cont_brand,
         r_zcont_tb  TYPE gty_r_cont_matnr,    " TVARVC ZCONT_TB
         r_mtart_eq  TYPE gty_r_cont_mtart,    " TVARVC ZCONT_EQUIPMENT
         pspid_ext   TYPE ps_pspid,            " mã dự án dạng hiển thị
         posid_ext   TYPE ps_posid,            " WBS hợp đồng dạng hiển thị
         step        TYPE stunr,               " Contract Amount
         step_tax    TYPE stunr,               " Total Contract Amount
         check_bomp  TYPE abap_bool,           " BOMG lấy theo BOQ đã duyệt KHNS
         bu_group    TYPE bu_group,
       END OF gty_cont_doc,

       BEGIN OF gty_cont_bapi,             " tham số BAPI_PO_CREATE1
         head       TYPE bapimepoheader,
         headx      TYPE bapimepoheaderx,
         addrvendor TYPE bapimepoaddrvendor,
         t_item     TYPE STANDARD TABLE OF bapimepoitem WITH DEFAULT KEY,
         t_itemx    TYPE STANDARD TABLE OF bapimepoitemx WITH DEFAULT KEY,
         t_sched    TYPE STANDARD TABLE OF bapimeposchedule WITH DEFAULT KEY,
         t_schedx   TYPE STANDARD TABLE OF bapimeposchedulx WITH DEFAULT KEY,
         t_account  TYPE STANDARD TABLE OF bapimepoaccount WITH DEFAULT KEY,
         t_accountx TYPE STANDARD TABLE OF bapimepoaccountx WITH DEFAULT KEY,
         t_profseg  TYPE STANDARD TABLE OF bapimepoaccountprofitsegment WITH DEFAULT KEY,
         t_partner  TYPE STANDARD TABLE OF bapiekkop WITH DEFAULT KEY,
         t_condh    TYPE STANDARD TABLE OF bapimepocondheader WITH DEFAULT KEY,
         t_condhx   TYPE STANDARD TABLE OF bapimepocondheaderx WITH DEFAULT KEY,
         t_cond     TYPE STANDARD TABLE OF bapimepocond WITH DEFAULT KEY,
         t_condx    TYPE STANDARD TABLE OF bapimepocondx WITH DEFAULT KEY,
         t_extin    TYPE STANDARD TABLE OF bapiparex WITH DEFAULT KEY,
       END OF gty_cont_bapi.

*----------------------------------------------------------------------*
* ZCTD_FM_CREATE_BP - kiểu dữ liệu dùng chung với LZCTD_FG_COREF02
*----------------------------------------------------------------------*
TYPES: gty_t_bp_company TYPE STANDARD TABLE OF zctd_s_bp_company WITH DEFAULT KEY,
       gty_t_bp_purch   TYPE STANDARD TABLE OF zctd_s_bp_purch WITH DEFAULT KEY.

" Giá trị phổ biến của nhà cung cấp nhóm Z001 (client 360, tạo từ 2025)
CONSTANTS: gc_bp_group_def  TYPE bu_group VALUE 'Z001',
           gc_bp_bukrs_def  TYPE bukrs    VALUE '1000',
           gc_bp_akont_def  TYPE akont    VALUE '3311000001',
           gc_bp_zterm_def  TYPE dzterm   VALUE '1045',
           gc_bp_ekorg_def  TYPE ekorg    VALUE '1000',
           gc_bp_waers_def  TYPE bstwa    VALUE 'VND',
           gc_bp_role_fi    TYPE bu_role  VALUE 'FLVN00',
           gc_bp_role_purch TYPE bu_role  VALUE 'FLVN01'.

" nhà cung cấp đã có (chế độ đổi của ZCTD_FM_CREATE_BP)
TYPES: BEGIN OF gty_bp_exist,
         lifnr      TYPE lifnr,
         partner    TYPE bu_partner,
         guid       TYPE bu_partner_guid,
         guid_c     TYPE bu_partner_guid_bapi,
         addr_guid  TYPE sysuuid_c,
         addrnumber TYPE ad_addrnum,
         country    TYPE land1,
         tel_cons   TYPE ad_consnum,
         smtp_cons  TYPE ad_consnum,
         t_role     TYPE STANDARD TABLE OF bu_role WITH EMPTY KEY,
         t_bukrs    TYPE STANDARD TABLE OF bukrs WITH EMPTY KEY,
         t_ekorg    TYPE STANDARD TABLE OF ekorg WITH EMPTY KEY,
       END OF gty_bp_exist.

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
