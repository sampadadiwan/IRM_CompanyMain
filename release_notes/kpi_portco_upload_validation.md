# Portfolio Company KPI Uploads — What's Changed

*For the business, customer-success and sales teams. August 2026.*

## In one paragraph

When a portfolio company (portco) uploads its KPI workbook — via the magic link the fund sends, or by a fund user on the portco's behalf — the file is now checked by CapHive **before** it is saved, the portco is shown exactly how every number will be read, and nothing that would produce bad or empty data can be submitted. Formatting is no longer the portco's problem: `1,200`, `(500)`, `₹ 12,50,000`, `$1.2M`, `2.5 Cr`, `42%` are all understood and stored as the intended numbers. The fund is told a report is "submitted" only once the data has actually landed, and can see at a glance what was staged, what looks unusual, and reopen a report if something is wrong.

## Why we did this

Until now, the only check on an uploaded KPI file ran in the portco's browser and could be out of step with what our importer actually did. As a result:

- a portco could submit with **no file**, or a file with no usable header, and the fund still got a "submitted" email;
- import problems were only emailed to the portco **after** submission, when the report was already locked;
- text like `1,200` or `#DIV/0!` was quietly stored as `1` or `0`, feeding wrong numbers into charts, growth % and cumulative figures;
- the file didn't have to contain the period the fund asked for;
- duplicate rows, hidden sheets and figures 10,000,000× off (rupees vs crores) went unnoticed until a reviewer spotted them.

## What the portco sees now

1. **A "Workbook check" panel** appears as soon as a file is uploaded, before anything is saved. It shows:
   - whether the period the fund asked for is present and filled ("You were asked for **Jun 2026 (Month)** — column present, KPIs filled 9 of 12");
   - **blocking errors** in red (must be fixed before submitting) and **warnings** in amber (worth a look, do not block);
   - how many of the expected KPIs were found, which are missing, which periods the file covers;
   - a **"How we read your file"** table: for every value, the cell reference, what was in the file, what will be stored, and how it was interpreted (e.g. "stripped currency; stripped thousands separators; unit 'Cr' × 10,000,000"). Values that differ from figures the fund has already approved are highlighted with old → new.
2. **Submit Report is disabled** until a workbook has been checked, and while there are blocking errors. Save Draft stays available.
3. Only spreadsheet files (.xlsx, .xls, .csv) can be selected.
4. A **"Download KPI template"** button gives them a workbook pre-filled with their KPI names, the unit each is expected in, and the requested period (plus the two before it) — the quickest way to a clean upload.
5. On **Submit**, the same check runs again on the server. If it fails, nothing is submitted: the changes are kept as a draft, the errors are shown, and the fund is not notified.
6. If a portco's fund hasn't yet configured which KPIs to collect, the upload is refused with a clear "please contact your fund" message rather than a green tick.

## What "understood" means (formatting rules, no surprises)

| Portco types | We store |
|---|---|
| `1,200` · `12,50,000` · `1 200` | 1200 · 1250000 · 1200 |
| `(500)` · `500-` | −500 |
| `₹ 5,00,000` · `INR 42` · `$1.2M` | 500000 · 42 · 1200000 |
| `45 L` · `2.5 Cr` · `12 Bn` | 4500000 · 25000000 · 12000000000 (a unit written in the cell overrides the mapping's denomination) |
| `42%` on a percentage KPI | 0.42 (matches how Excel stores percentages) |
| `n/a` · `TBD` · `—` | left blank, with a warning |
| `#DIV/0!` · `#REF!` · `ten` · `10 (prev 8)` · a sheet mixing `1.234,56` and `1,234.56` | **blocking error** — we never guess, and we never store 0 for text |

Fiscal-year labels (`FY26`, `Q1 FY26`, `H1 FY26`) follow the fund's configured financial-year start (April by default, January or other where set), and a portco can have its own setting.

## What the fund sees now

- The **"KPIs submitted"** email is sent only when the data has actually been staged, and states how many values/KPIs were staged and how many warnings to look at. If the import fails after submission (rare), the report is automatically reopened for the portco, the portco is emailed the details, and the fund receives a "KPI import failed" notice instead of a false "submitted".
- The report page shows a **Workbook import** row (Imported / Import pending / Import failed, error and warning counts, values staged, how many differ from approved figures) and a collapsible **Workbook check details** card with the same panel the portco saw — so reviewers can see, for any figure, what was in the file and how it was read.
- A **"Reopen & ask to re-upload"** button on submitted reports puts the report back to the portco and re-sends the link.
- Sending a KPI request to a portco that has **no KPI mappings** now warns immediately, and the report page shows a red "No KPI mappings configured" badge.
- Historical periods in an uploaded file are still imported (as before), but the panel and summary now list which periods were touched and which approved figures would change; those changes remain **unapproved until the fund approves them**, exactly as before.

## Warnings the fund and portco will start seeing (none of these block)

- A KPI in the fund's list that isn't in the file.
- Columns for future dates (ignored, with the date we read them as — useful when fiscal-year labels are misread).
- The file uses monthly columns for a quarterly/annual request (imported; quarterly figures derived where the fund has set up cumulation; KPIs that won't be derived are listed).
- A value ~1,000× or more away from the last approved figure ("is the sheet in crores?"), a percentage typed as `42` where history is `0.42`, a change beyond the mapping's thresholds, a value in the red RAG band vs budget, a sign flip vs recent history, or a >200 % swing where no thresholds are set.
- The same KPI repeated with the **same** value; a hidden sheet being ignored; a placeholder like `TBD`.

## Things that now block a submission (and why)

- No workbook, or a file that isn't a spreadsheet.
- No sheet has a header row with period columns.
- None of the fund's KPI names appear in the file.
- The period the fund asked for is missing, or present but empty for every KPI.
- Excel error cells, non-numeric text, ambiguous numbers.
- The same KPI on two rows with **different** values for the same period; the same period appearing twice in the header.
- The portco has no KPI mappings configured.

Each is a case where importing would either store nothing for the request or store a number nobody intended — the portco is right there and can fix it in a minute; a wrong or empty "submitted" costs everyone more.

## When a fund user uploads

Fund users see exactly the same Workbook check on the report's edit page and on the *New report* page. A workbook with blocking errors cannot be saved by anyone — the fund's **Save** button is disabled while the check shows errors, and the server refuses the save if forced. Two things are gentler for the fund: Save is never disabled just because no file has been chosen yet, and "the file doesn't contain this report's period" is a warning rather than an error (a fund user often uploads a whole MIS onto one report).

## Behind the scenes (kept short)

- One server-side check is used for the pre-save panel, the submit gate and the import itself, so what the portco is shown is what gets stored — the old browser-side check has been removed.
- Fund-only fields (which portfolio company, period, tag, deleting KPIs, adding KPI rows by hand) are now enforced on the server for portco users, not just hidden in the form.
- Full details, sign-offs and QA scripts: `docs/technical/kpi_portco_upload_validation_review.md`; portco flow QA: `docs/manual_qa/portco_kpi_upload_workflow.md`.

## Rollout notes

- Two small database changes ship with this; no data migration is required.
- Funds whose financial year does **not** start in April and who have previously imported `FY…`/`Q… FY…`-labelled workbooks: those labels now resolve to the correct dates (they used to assume April). Existing reports are untouched; new imports land on the right periods. Worth a heads-up to those customers.
- Two product calls were made during build and can be revisited: (1) a sheet with a single period column is accepted only when the KPI names beneath it match the fund's list; (2) monthly columns answering a quarterly/annual request are accepted with a warning rather than rejected. An optional per-fund "strict mode" (all mapped KPIs required) is not built.
