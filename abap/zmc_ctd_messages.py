"""Message class ZMC_CTD - danh mục message của các FM nghiệp vụ ZCTD_FM*.

Nguồn duy nhất cho: tạo message class (create_msag.py) và thay message viết
tay trong code (refactor_msgs.py). Mỗi message tối đa 73 ký tự; biến &1..&4
(mỗi biến tối đa 50 ký tự) theo đúng thứ tự giá trị động của câu cũ.

    OLD: câu cũ trong code (nội dung giữa |...|)  -> (số, câu mới)
"""

# Khoảng số: 001-069 hợp đồng, 070-079 + 110-119 nhà cung cấp, 080-089 đọc PO,
# 090-099 API tích hợp, 100-109 log API.
# (số, câu mới, [câu cũ ...])  - câu cũ rỗng = message dùng ở chỗ sửa tay
MESSAGES = [
    # ---- ZCTD_FM_CREATE_CONT: kiểm tra đầu vào --------------------------
    ('001', 'Chưa nhập loại hợp đồng.', []),
    ('002', 'Chưa nhập mã dự án.', []),
    ('003', 'Chưa nhập WBS hợp đồng.', ['Chưa nhập WBS hợp đồng.']),
    ('004', 'Chưa nhập nhà cung cấp.', []),
    ('005', 'Chưa nhập số hợp đồng tham chiếu.', ['Chưa nhập số hợp đồng tham chiếu.']),
    ('006', 'WBS &1 không thuộc dự án &2.',
     ['WBS { is_doc-posid_ext } không thuộc dự án { is_doc-pspid_ext }.']),
    ('007', 'Nhà cung cấp &1 không tồn tại hoặc chưa có dữ liệu mua hàng.',
     ['Nhà cung cấp { is_doc-head-lifnr ALPHA = OUT } không tồn tại hoặc chưa có dữ liệu mua hàng.']),
    ('008', 'Hợp đồng &1 của số HĐ tham chiếu &2 đang bị khóa bởi eConstruction.',
     ['Hợp đồng { ls_po_lock-ebeln } của số HĐ tham chiếu { is_doc-head-zcont } đang bị khóa bởi eConstruction.']),
    ('009', 'Số HĐ tham chiếu &1 đã dùng cho đơn mua hàng &2, hãy tạo phụ lục.',
     ['Số HĐ tham chiếu { is_doc-head-zcont } đã được dùng cho đơn mua hàng { lv_ebeln }. Hãy tạo phụ lục trên ZCONT.']),
    ('010', 'Số HĐ tham chiếu &1 không có trên DMS (NCC &2, dự án &3, WBS &4).',
     ['Số HĐ tham chiếu { is_doc-head-zcont } không có trên DMS cho nhà cung cấp { is_doc-head-lifnr ALPHA = OUT }, dự án { is_doc-pspid_ext }, WBS { is_doc-posid_ext }.']),
    ('011', 'Không tìm thấy dự án &1 để kiểm tra quyền.',
     ['Không tìm thấy dự án { is_doc-pspid_ext } để kiểm tra quyền.']),
    ('012', 'Người dùng &1 không có quyền tạo HĐ cho dự án &2 (TT lợi nhuận &3).', []),
    ('013', 'Người dùng &1 không có quyền tạo HĐ cho dự án &2 (chưa có TT lợi nhuận).', []),
    ('014', 'Dòng &1: thành tiền vượt giới hạn, kiểm tra lại số lượng và đơn giá.',
     ['Dòng { CONV i( cs_item-sttit ) }: thành tiền vượt quá giới hạn cho phép, kiểm tra lại số lượng và đơn giá.']),
    ('015', 'Thuế GTGT tính tự động theo vật tư, không nhập ở điều kiện chung.',
     ['Thuế GTGT được tính tự động theo vật tư, không nhập ở điều kiện chung của hợp đồng.']),
    ('016', 'Số HĐ tham chiếu &1 đã có đơn mua hàng gốc &2, hãy dùng ZCONT.',
     ['Số HĐ tham chiếu { is_doc-head-zcont } đã có đơn mua hàng gốc { lv_ebeln }. Chức năng này không tạo phụ lục, hãy dùng ZCONT.']),
    ('017', 'Số kế hoạch ký kết &1 không tồn tại.',
     ['Số kế hoạch ký kết { is_doc-head-zsign } không tồn tại.']),
    ('018', 'Chỉ nhập một trong hai: số kế hoạch ký kết hoặc số kế hoạch ngân sách.',
     ['Chỉ được nhập một trong hai: số kế hoạch ký kết hoặc số kế hoạch ngân sách.']),
    ('019', 'Số kế hoạch ngân sách &1 không tồn tại.',
     ['Số kế hoạch ngân sách { is_doc-zbudg } không tồn tại.']),
    ('020', 'Chưa xác định được tổ chức mua hàng, vui lòng nhập.',
     ['Chưa xác định được tổ chức mua hàng, vui lòng nhập.']),
    ('021', 'Chưa xác định được nhóm mua hàng, vui lòng nhập.',
     ['Chưa xác định được nhóm mua hàng, vui lòng nhập.']),
    ('022', 'Chưa xác định được công ty, vui lòng nhập.',
     ['Chưa xác định được công ty, vui lòng nhập.']),
    ('023', 'Dự án &1 không thuộc công ty &2.',
     ['Dự án { is_doc-pspid_ext } không thuộc công ty { is_doc-head-bukrs }.']),
    ('024', 'WBS hợp đồng &1 phải là WBS cấp 1 của dự án &2.',
     ['WBS hợp đồng { is_doc-posid_ext } phải là WBS cấp 1 của dự án { is_doc-pspid_ext }.']),
    ('025', 'Chưa xác định được nhà máy (dự án &1 chưa khai nhà máy), vui lòng nhập.',
     ['Chưa xác định được nhà máy (dự án { is_doc-pspid_ext } chưa khai nhà máy), vui lòng nhập.']),
    ('026', 'Nhà máy &1 không thuộc công ty &2.',
     ['Nhà máy { is_doc-head-werks } không thuộc công ty { is_doc-head-bukrs }.']),
    ('027', 'Nhà cung cấp &1 là NCC vãng lai, cần nhập tên và địa chỉ.',
     ['Nhà cung cấp { is_doc-head-lifnr ALPHA = OUT } là NCC vãng lai, cần nhập tên và địa chỉ nhà cung cấp.']),
    ('028', 'Chưa có loại TK ngân hàng của đối tác (không có trên DMS), hãy nhập.',
     ['Chưa có loại tài khoản ngân hàng của đối tác (không tìm thấy trên DMS), vui lòng nhập.']),
    ('029', 'Loại TK ngân hàng &1 không tồn tại hoặc đã lưu trữ ở đối tác &2.',
     ['Loại tài khoản ngân hàng { is_doc-head-zzbvtyp } không tồn tại hoặc đã bị lưu trữ ở đối tác { lv_partner ALPHA = OUT }.']),
    ('030', 'Hợp đồng chưa có dòng hàng nào.', ['Hợp đồng chưa có dòng hàng nào.']),
    ('031', 'Tổng số lượng các dòng quá lớn.', ['Tổng số lượng các dòng quá lớn.']),
    # ---- ZCTD_FM_CREATE_CONT: kiểm tra dòng -----------------------------
    ('032', 'Dòng &1: chưa nhập vật tư.', ['Dòng { CONV i( is_item-sttit ) }: chưa nhập vật tư.']),
    ('033', 'Dòng &1: Brand "&2" không có trong giá trị đặc tính &3 (lớp &4).',
     ['Dòng { CONV i( is_item-sttit ) }: Brand "{ is_item-brand }" không có trong danh sách giá trị của đặc tính { lv_charact } (lớp { ls_brand-class }).']),
    ('034', 'Dòng &1: vật tư &2 không khai Brand, không nhập Brand "&3".',
     ['Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } không được khai Brand, không nhập Brand "{ is_item-brand }".']),
    ('035', 'Dòng &1: chưa nhập mã BOMG.', ['Dòng { CONV i( is_item-sttit ) }: chưa nhập mã BOMG.']),
    ('036', 'Dòng &1: BOMG &2 không có trong BOQ số &3 đã duyệt của WBS &4.',
     ['Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không có trong BOQ số { lv_boq } đã duyệt của WBS { is_doc-posid_ext }.']),
    ('037', 'Dòng &1: BOMG &2 không có trong danh sách BOMG đã duyệt của WBS &3.',
     ['Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không có trong danh sách BOMG đã duyệt của WBS { is_doc-posid_ext }.']),
    ('038', 'Dòng &1: BOMG &2 không tồn tại hoặc không được dùng để mua hàng.',
     ['Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } không tồn tại hoặc không được dùng để mua hàng.']),
    ('039', 'Dòng &1: BOMG &2 đã bị đánh dấu xóa.',
     ['Dòng { CONV i( is_item-sttit ) }: BOMG { is_item-zbomg_code } đã bị đánh dấu xóa.']),
    ('040', 'Dòng &1: chưa nhập WBS cấp 4.', ['Dòng { CONV i( is_item-sttit ) }: chưa nhập WBS cấp 4.']),
    ('041', 'Dòng &1: WBS &2 không phải WBS cấp 4 thuộc WBS hợp đồng &3.',
     ['Dòng { CONV i( is_item-sttit ) }: WBS { lv_wbs_text } không phải WBS cấp 4 thuộc WBS hợp đồng { is_doc-posid_ext }.']),
    ('042', 'Dòng &1: nhóm CSI của BOMG (&2) khác nhóm CSI của WBS &3 (&4).',
     ['Dòng { CONV i( is_item-sttit ) }: nhóm CSI của BOMG ({ is_item-csi_group }) khác nhóm CSI của WBS { ls_prps-posid_edit } ({ ls_prps-zcsi }).']),
    ('043', 'Dòng &1: vật tư &2 không tồn tại hoặc chưa được kích hoạt.',
     ['Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } không tồn tại hoặc chưa được kích hoạt.']),
    ('044', 'Dòng &1: nhóm vật tư &2 không thuộc BOMG &3.',
     ['Dòng { CONV i( is_item-sttit ) }: nhóm vật tư { is_item-matkl } không thuộc BOMG { is_item-zbomg_code }.']),
    ('045', 'Dòng &1: vật tư thuê thầu phụ, cần nhập mã và tên nhà thầu phụ.',
     ['Dòng { CONV i( is_item-sttit ) }: vật tư thuộc nhóm thuê thầu phụ, cần nhập mã và tên nhà thầu phụ.']),
    ('046', 'Dòng &1: vật tư &2 chưa được mở rộng cho nhà máy &3.',
     ['Dòng { CONV i( is_item-sttit ) }: vật tư { is_item-matnr ALPHA = OUT } chưa được mở rộng cho nhà máy { is_doc-head-werks }.']),
    ('047', 'Dòng &1: đơn vị &2 chưa khai quy đổi sang đơn vị cơ sở &3 của vật tư.',
     ['Dòng { CONV i( is_item-sttit ) }: đơn vị đặt hàng { is_item-meins } chưa khai quy đổi sang đơn vị cơ sở { ls_mara-meins } của vật tư.']),
    ('048', 'Dòng &1: vật tư không cho đặt hàng theo đơn vị &2, hãy dùng &3.',
     ['Dòng { CONV i( is_item-sttit ) }: vật tư không cho phép đặt hàng theo đơn vị { is_item-meins }, hãy dùng { ls_mara-meins }.']),
    ('049', 'Dòng &1: đơn giá phải lớn hơn 0 (trừ dòng hàng tặng).',
     ['Dòng { CONV i( is_item-sttit ) }: đơn giá phải lớn hơn 0 (trừ dòng hàng tặng).']),
    ('050', 'Dòng &1: chưa nhập mã thiết bị thuê.', ['Dòng { CONV i( is_item-sttit ) }: chưa nhập mã thiết bị thuê.']),
    ('051', 'Dòng &1: chưa nhập số lượng thiết bị thuê.',
     ['Dòng { CONV i( is_item-sttit ) }: chưa nhập số lượng thiết bị thuê.']),
    ('052', 'Dòng &1: chưa nhập đơn vị tính của thiết bị thuê.',
     ['Dòng { CONV i( is_item-sttit ) }: chưa nhập đơn vị tính của thiết bị thuê.']),
    ('053', 'Dòng &1: mã &2 không phải là thiết bị.',
     ['Dòng { CONV i( is_item-sttit ) }: mã { is_item-matnr_e ALPHA = OUT } không phải là thiết bị.']),
    # ---- ZCTD_FM_CREATE_CONT: giá trị, lưu -------------------------------
    ('054', 'Tổng giá trị theo HĐ &1 (&2 &3) vượt giá trị hợp đồng trên DMS (&4).',
     ['Tổng giá trị đặt hàng theo HĐ { is_doc-head-zcont } ({ lv_total NUMBER = USER } { is_doc-head-cuky }) vượt giá trị hợp đồng trên DMS ({ lv_limit NUMBER = USER }).']),
    ('055', 'Điều kiện giá &1 (&2) không được dùng làm điều kiện chung của HĐ.',
     ['Điều kiện giá { ls_cond-kschl } ({ ls_cond-vtext }) không được dùng làm điều kiện chung của hợp đồng.']),
    ('056', 'Không tạo được đơn mua hàng, xem các thông báo của SAP ở trên.',
     ['Không tạo được đơn mua hàng, xem các thông báo của SAP ở trên để biết nguyên nhân.']),
    ('057', 'Chạy thử thành công: dữ liệu hợp lệ, chưa lưu chứng từ.',
     ['Chạy thử thành công: dữ liệu hợp lệ, chưa lưu chứng từ.']),
    ('058', 'Không lưu được PO và hợp đồng, đã hủy toàn bộ. Vui lòng báo bộ phận IT.',
     ['Không lưu được đơn mua hàng và hợp đồng, toàn bộ dữ liệu đã được hủy. Vui lòng báo bộ phận IT.']),
    ('059', 'Đã tạo hợp đồng và đơn mua hàng &1 thành công.',
     ['Đã tạo hợp đồng và đơn mua hàng { cv_ebeln } thành công.']),
    # ---- ZCTD_FM_CONT_SAVE_UPD (update task, MESSAGE type A) -------------
    ('060', 'Không lưu được thông tin chung của hợp đồng cho đơn mua hàng &1.', []),
    ('061', 'Không lưu được dòng hàng của hợp đồng cho đơn mua hàng &1.', []),
    ('062', 'Không lưu được đối tác của hợp đồng cho đơn mua hàng &1.', []),
    ('063', 'Không lưu được điều kiện giá của hợp đồng cho đơn mua hàng &1.', []),
    # ---- ZCTD_FM_CREATE_BP -----------------------------------------------
    ('070', 'Chưa nhập tên nhà cung cấp.', ['Chưa nhập tên nhà cung cấp.']),
    ('071', 'Chưa nhập quốc gia của nhà cung cấp.', ['Chưa nhập quốc gia của nhà cung cấp.']),
    ('072', 'Không tạo được nhà cung cấp, xem các thông báo của SAP ở trên.', []),
    ('073', 'Không cập nhật được nhà cung cấp, xem các thông báo của SAP ở trên.', []),
    ('074', 'Chạy thử thành công: dữ liệu hợp lệ, chưa lưu nhà cung cấp.',
     ['Chạy thử thành công: dữ liệu hợp lệ, chưa lưu nhà cung cấp.']),
    ('075', 'Không lưu được nhà cung cấp, toàn bộ thay đổi đã được hủy.',
     ['Không lưu được nhà cung cấp, toàn bộ thay đổi đã được hủy.']),
    ('076', 'Không tìm thấy nhà cung cấp &1 để cập nhật.',
     ['Không tìm thấy nhà cung cấp { cs_exist-lifnr ALPHA = OUT } để cập nhật.']),
    ('077', 'Không tạo được mã định danh cho nhà cung cấp mới.',
     ['Không tạo được mã định danh cho nhà cung cấp mới.']),
    ('078', 'Đã cập nhật nhà cung cấp &1 (BP &2).', []),
    ('079', 'Đã tạo nhà cung cấp &1 (BP &2) kèm dữ liệu công ty và mua hàng.', []),
    # ---- ZCTD_FM_GET_PO_INFO / ZCTD_FM_FIND_PO ---------------------------
    ('080', 'Chưa nhập số đơn mua hàng.', ['Chưa nhập số đơn mua hàng.']),
    ('081', 'Không tìm thấy đơn mua hàng &1.', ['Không tìm thấy đơn mua hàng { iv_ebeln ALPHA = OUT }.']),
    ('082', 'Đã đọc đơn mua hàng &1 (&2 dòng).',
     ['Đã đọc đơn mua hàng { lv_ebeln ALPHA = OUT } ({ lines( et_item ) } dòng).']),
    ('083', 'Không có đơn mua hàng nào thỏa điều kiện.', ['Không có đơn mua hàng nào thỏa điều kiện.']),
    ('084', 'Tìm thấy &1 đơn mua hàng, trả về &2.',
     ['Tìm thấy { ev_total } đơn mua hàng, trả về { lines( et_po ) }.']),
    # ---- ZCTD_FM_INT_VENDOR_GET / ZCTD_FM_INT_PR_GET ---------------------
    ('090', 'Danh sách nhà cung cấp chưa hỗ trợ lọc theo &1.', []),
    ('091', 'Danh sách yêu cầu mua hàng chưa hỗ trợ lọc theo &1.', []),
    ('092', 'Không có nhà cung cấp nào thỏa điều kiện.', ['Không có nhà cung cấp nào thỏa điều kiện.']),
    ('093', 'Tìm thấy &1 nhà cung cấp, trả về &2.',
     ['Tìm thấy { ev_total } nhà cung cấp, trả về { lines( et_vendor ) }.']),
    ('094', 'Không có yêu cầu mua hàng nào thỏa điều kiện.', ['Không có yêu cầu mua hàng nào thỏa điều kiện.']),
    ('095', 'Tìm thấy &1 yêu cầu mua hàng, trả về &2.',
     ['Tìm thấy { ev_total } yêu cầu mua hàng, trả về { lines( et_header ) }.']),
    # ---- ZCTD_FM_API_LOG_WRITE (EV_MESSAGE) -------------------------------
    ('100', 'Đã ghi log &1.', []),
    ('101', 'Log &1 lúc &2 &3 đã tồn tại.', []),
    ('102', 'Không ghi được log gọi API: &1', []),
    # ---- ZCTD_FM_CREATE_BP (bổ sung: kiểm tra trùng, mã số thuế) --------
    ('110', 'Mã số thuế &1 đã được dùng cho nhà cung cấp &2 (BP &3).', []),
    ('111', 'Tên "&1" đã có ở nhà cung cấp &2 (BP &3), vẫn tiếp tục tạo.', []),
    ('112', 'Nhà cung cấp &1 đã có mã số thuế &2, không đổi qua chức năng này.', []),
    ('113', 'Chưa nhập mã số thuế của nhà cung cấp.', []),
    ('114', 'Mã số thuế "&1" không đúng định dạng (chỉ gồm số hoặc số-số).', []),
]


def check():
    import re
    seen = set()
    for no, text, olds in MESSAGES:
        assert no not in seen, no
        seen.add(no)
        assert len(text) <= 73, (no, len(text), text)
        n = len(re.findall(r'&\d', text))
        for old in olds:
            m = len(re.findall(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', old))
            assert m == n, (no, 'placeholders', n, 'values', m, old)
    return True


if __name__ == '__main__':
    check()
    print(len(MESSAGES), 'messages OK')
