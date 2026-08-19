# Sample KPI workbooks — S Pvt Ltd (investor 280, Demo Fund)

Set-up: KPI Reports → *Send notification* to **S Pvt Ltd** for **June 2026, period Month** (Actual). Open the
magic link (letter_opener in dev) and upload these one at a time; or on the fund side open the report's
edit page. File 09 needs a **Quarter** shell (Apr–Jun 2026) instead.

Mapped KPIs for this portco: Revenue, EBITDA, No. of orders, Total shareholders equity (all numeric,
no denomination). Fiscal year: April start (default).

| File | What's in it | Expected result |
|---|---|---|
| `01_success_realistic_mis.xlsx` | Title rows above the header, a *Unit* column, formatted numbers (`2,310`, `(310)`, `₹ 2,450`, `28.4`), a *Comments* column, an unmapped "Gross margin %" row, a **hidden** sheet "Scratch" | **Passes** (Submit enabled). Warnings: Comments column ignored, hidden sheet ignored, "also updates Apr/May 2026", EBITDA sign-flip/outlier vs history. Table shows raw → stored (e.g. `₹ 2,450` → 2450, `(310)` → −310) |
| `02_success_template_shape.xlsx` | The *Download KPI template* layout with only the Jun 2026 column filled | **Passes**, minimal warnings — the ideal upload |
| `03_error_no_header.xlsx` | Header is `KPI \| Notes \| Comments` | **Blocked**: "No sheet in the file has a header row with at least two period columns" |
| `04_error_requested_period_missing.xlsx` | Only Jan–Mar 2026 columns | **Blocked**: "You were asked for Jun 2026 (Month), but no column in the file is that period. Periods found: …"; also warns 2 KPIs missing |
| `05_error_bad_values.xlsx` | `#DIV/0!`, `10 (prev 8)`, `ten`, `TBD` | **Blocked**: 3 cell errors (Excel error, ambiguous, not a number) with cell references; `TBD` treated as blank (warning) |
| `06_error_duplicates.xlsx` | `Jun 2026` header twice; `Revenue` on two rows with different Jun values, same May value | **Blocked**: duplicate period header + conflicting duplicate KPI row; identical duplicate → warning only |
| `07_warnings_showcase.xlsx` | Tag row `Actual \| Budget \| Variance`, `2.5 Cr` with an explicit unit, a future `Dec 2027` column, `No. of orders` repeated with identical values | **Passes** with warnings: Variance column ignored, future column ignored, identical repeats imported once, Budget column staged to the Budget report, one KPI missing. `2.5 Cr` → 25,000,000 (unit in the cell wins) |
| `08_error_not_a_spreadsheet.xlsx` | A text file wearing `.xlsx` | **Blocked**: "could not be opened as a spreadsheet". (The picker itself only offers .xlsx/.xls/.csv — this tests the server) |
| `09_quarter_request_answered_monthly.xlsx` | Monthly Apr/May/Jun columns for a **Quarter** shell | **Passes** with warning: "You were asked for Jun 2026 (Quarter) but the file has monthly columns… quarter figures derived where cumulation is configured; not derived: …" |
| `10_success_european_numbers.xlsx` | European formatting `2.380,50`, `-295,25`, `29,10` | **Passes**: read as 2380.5, −295.25, 29.1 (locale detected per sheet) |

Also worth trying on the same shell:
- Submit with **no file** → Submit Report is disabled; forcing it → "Not submitted — …", status stays.
- Upload 05, then Save Draft, then reload → panel shows the stored verdict for the attached file; *Re-check file* button.
- After a clean submit → report page shows *Workbook import: Imported*, staged counts, *Workbook check details*, and *Reopen & ask to re-upload*.

These outcomes are pinned by `features/startup/kpi_upload_sample_files.feature` (run with `bundle exec cucumber features/startup/kpi_upload_sample_files.feature`).
