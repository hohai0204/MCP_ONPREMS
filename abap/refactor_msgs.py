"""Thay message viết tay trong FM nghiệp vụ ZCTD_FM* bằng message class ZMC_CTD.

    python abap/refactor_msgs.py

`APPEND VALUE #( ... message = |<câu cũ>| ... ) TO x.`
 -> `APPEND VALUE #( BASE lcl_msg=>get( iv_no = 'NNN' iv_v1 = |{ .. }| ... ) ... ) TO x.`
Giá trị động của câu cũ ({ ... }) thành &1..&4 theo đúng thứ tự.
"""
import re
import sys

sys.path.insert(0, 'abap')
from zmc_ctd_messages import MESSAGES, check  # noqa: E402

FILES = ['abap/lzctd_fg_coref01.abap', 'abap/lzctd_fg_coref02.abap', 'abap/zctd_fm_create_bp.func.abap',
         'odata/abap/zctd_fm_get_po_info.abap', 'odata/abap/zctd_fm_find_po.abap',
         'odata/core_int/zctd_fm_int_vendor_get.abap', 'odata/core_int/zctd_fm_int_pr_get.abap']

EXPR = re.compile(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}')


def get_call(no, old):
    args = [f"iv_v{i} = |{e}|" for i, e in enumerate(EXPR.findall(old), 1)]
    return f"lcl_msg=>get( iv_no = '{no}'" + (' ' + ' '.join(args) if args else '') + ' )'


def replace_one(src, old, call):
    token = f'message = |{old}|'
    pos = src.find(token)
    if pos < 0:
        return src, False
    start = src.rfind('VALUE #(', 0, pos)
    assert start >= 0 and src.count('.', start, pos) - src.count("'.'", start, pos) >= 0
    # bỏ "message = |...|" (và khoảng trắng / xuống dòng thừa phía trước)
    before, after = src[:pos], src[pos + len(token):]
    before = re.sub(r'[ \t]*\n?[ \t]*$', lambda m: '' if '\n' in m.group(0) else ' ', before)
    src = before + after
    # chèn BASE ngay sau "VALUE #( "
    ins = start + len('VALUE #(')
    src = src[:ins] + f' BASE {call}' + src[ins:]
    return src, True


def main():
    check()
    todo = [(no, old) for no, _, olds in MESSAGES for old in olds]
    done = set()
    for f in FILES:
        src = open(f, encoding='utf-8').read()
        for no, old in todo:
            while True:
                src, ok = replace_one(src, old, get_call(no, old))
                if not ok:
                    break
                done.add((no, old))
        # "VALUE #( BASE x type" -> gọn: khoảng trắng đôi
        src = re.sub(r'VALUE #\( BASE (lcl_msg=>get\([^()]*(?:\([^()]*\)[^()]*)*\)) +', r'VALUE #( BASE \1 ', src)
        open(f, 'w', encoding='utf-8').write(src)
    missing = [t for t in todo if t not in done]
    print('replaced', len(done), 'of', len(todo))
    for t in missing:
        print('NOT FOUND', t)


if __name__ == '__main__':
    main()
