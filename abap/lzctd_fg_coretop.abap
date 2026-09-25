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
