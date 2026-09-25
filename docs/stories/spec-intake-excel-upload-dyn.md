# Spec Intake — Dynamic Excel Upload ALV Viewer

## Source

Ad-hoc user request (2026-07-19, Vietnamese): "tạo 1 chức năng upload excel
động trên SAP bằng ABAP — đầu vào là file Excel không có định cột, khi upload
thì tự động tạo structure theo cấu trúc file và view lên ALV."
Interview answers: .xlsx only; auto-detect column types; package $TMP
(prototype, no transport); read-only CL_SALV_TABLE display.

## Summary

A GUI-executed ABAP report `ZR_EXCEL_UPLOAD_DYN` that uploads an .xlsx file
with arbitrary/unknown columns, builds a dynamic internal table matching the
file layout (column names from the header row, column types auto-detected as
date / integer / decimal / text), and displays the data in a read-only SALV
grid with the original Excel headers as column labels.

## Selection Screen

| Field | Type | Meaning |
| --- | --- | --- |
| P_FILE | localfile, LOWER CASE, OBLIGATORY, F4 = frontend file dialog (*.xlsx) | Path of the Excel file on the user's PC |
| P_HDR | checkbox, default 'X' | First row contains column headers |

## Processing Rules

1. Upload the file binary via `cl_gui_frontend_services=>gui_upload` and
   convert to xstring (`cl_bcs_convert=>solix_to_xstring`).
2. Parse via `CL_FDT_XL_SPREADSHEET` → first worksheet → raw table (all
   columns string-typed).
3. Header handling: row 1 = headers when P_HDR = 'X', else generated
   "Column n". Sanitize headers into valid ABAP component names (uppercase,
   invalid chars → `_`, digit-leading → `C` prefix, max 30 chars, empty →
   `COL_nn`, duplicates → `_2/_3` suffix). Keep original header text for ALV
   labels. Hard cap 300 columns.
4. Type detection per column over all non-empty cells: date patterns → `d`;
   integer → `p LENGTH 16 DECIMALS 0`; decimal (dot/comma) → `p LENGTH 16`
   with max observed decimals (cap 14); anything mixed/unmatched or all-empty
   → `string`. Integer + decimal mix promotes to decimal.
5. Build the table dynamically: `cl_abap_structdescr=>create` →
   `cl_abap_tabledescr=>create` → `CREATE DATA ... TYPE HANDLE`.
6. Fill rows with per-cell TRY/CATCH on conversions (failed cell stays
   initial); comma decimals normalized to dot; ragged rows tolerated.

## Output Layout

Read-only `CL_SALV_TABLE` grid over the dynamic table: all standard functions
on, optimized column widths, short/medium/long column texts = original Excel
headers. Header-only file → empty typed grid + info message.

## Data Sources

Frontend file only. No database reads or writes.

## Acceptance Criteria

- An .xlsx with arbitrary columns displays in ALV with correct column labels
  and row values without any code or DDIC change.
- Numeric columns sort numerically; date columns display as dates; mixed
  columns fall back to text without data loss.
- Duplicate/empty/long/special-character headers never cause a dump.
- All user-visible texts come from the textpool (EN).
- Errors (unreadable file, invalid workbook, no worksheet) surface as
  S-messages displayed like errors, never dumps.

## Harness Delta

None. Runtime smoke proof is manual (frontend-services program cannot run via
RFC) — recorded as a waiver in the story validation section.
