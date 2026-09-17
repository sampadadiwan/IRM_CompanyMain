# Portco KPI Upload (Magic Link) — Validation Review and Enhancement Plan

**Status:** Review complete; all ten gaps signed off 2026-08-18 (see per-section sign-off notes). No code changes made yet.
**Open decisions:** §2.3 single-period rule — implemented provisionally as **Option C** (a lone period cell is accepted only when rows beneath it carry mapped KPI names; warning `single_period_header`), pending confirmation; §2.2 optional per-entity strict mode ("all mapped KPIs required").
**Date:** 2026-08-18
**Scope:** The self-reporting flow where a Portfolio Company (portco) receives a magic link
and uploads a KPI workbook against a pre-created `KpiReport` shell. This note reviews every
validation layer between "portco picks a file" and "KPI values appear on the fund's dashboard",
lists the gaps that let bad data through, and proposes enhancements.

**Design principles agreed during sign-off (2026-08-18):**
1. **All validation is backend-only.** Every rule lives in `KpiWorkbookReader#validate` (Ruby); the
   browser only uploads, calls `validate_upload`, renders the response, and toggles the submit guard.
   No regexes, counting or rules in JavaScript.
2. **Interpret, don't reject.** Formatting (`1,200`, `(500)`, `₹`, `1.2M`, `12%`) is the system's
   problem: strip/understand it and store the number the portco meant. Only genuine ambiguity or
   Excel error cells are thrown back. Nothing is ever silently stored as `0`.
3. **No surprises.** The portco sees the *interpreted* values (raw → stored) before saving; the same
   code runs at the submit gate and at import, so what they saw is what lands in the DB.
4. **No file-size limits** — large workbooks are normal for this feature.

Related docs: `release_notes/kpi_portco_upload.md`, `docs/kpi_management/kpi_parser_fixes_user_guide.md`,
`app/packs/startups/kpis/jobs/kpi_import_process.md`.

---

## 1. The flow today

### 1.1 Files involved

| Concern | Location |
|---|---|
| Shell creation + notification | `app/packs/startups/kpis/services/kpi_report_create_shell.rb`, `send_portco_notification.rb`, `KpiReportNotifier` |
| Magic-link auth | `KpiReportsController#set_kpi_report` → `ApplicationController#find_by_signed_id_for_user`; `pundit_user` falls back to `@signed_id_user` |
| Portco form | `app/packs/startups/kpis/views/kpi_reports/_form.html.erb`, `edit.html.erb`, `_xlsx_preview.html.erb` |
| File upload widget | `app/packs/misc/form_custom_fields/views/form_custom_fields/_file.html.erb` (Uppy via `single_upload_controller.js`) |
| Client-side KPI check | `app/javascript/controllers/kpi_xlsx_report_controller.js` |
| Client-side preview | `app/javascript/controllers/xlsx_preview_controller.js` |
| Update + submit | `KpiReportsController#update`, `#resolve_status_transition`, `#notify_fund_on_submission` |
| Model | `app/packs/startups/kpis/models/kpi_report.rb` (`after_commit :import_kpis`) |
| Import | `ImportKpiWorkbookJob` → `KpiWorkbookReader` → `Kpi` rows (status `unapproved`) |
| Review gate | `KpiReportsController#mark_reviewed` → `KpiApproveService` |
| Policy | `app/packs/startups/kpis/policies/kpi_report_policy.rb` |

### 1.2 Sequence — what happens on upload and submit

```mermaid
sequenceDiagram
    autonumber
    participant P as Portco user (browser)
    participant U as Uppy / S3
    participant JS as kpi-xlsx-report (Stimulus)
    participant C as KpiReportsController
    participant M as KpiReport (after_commit)
    participant J as ImportKpiWorkbookJob (async, queue :low)
    participant R as KpiWorkbookReader
    participant F as Fund admin

    P->>C: GET /kpi_reports/:id/edit?signed_id=…
    C-->>P: form (portco fields disabled), preview + analyzer containers
    P->>U: choose file (any MIME type accepted)
    U-->>P: upload-success → dispatch `upload:complete`
    U-->>JS: `upload:complete` {file}
    JS->>JS: SheetJS parse; row-1 header check; KPI name lookup
    alt errors
        JS-->>P: red alert, disable [data-kpi-submit-guard] buttons
    else ok / warnings
        JS-->>P: found/missing table, enable buttons
    end
    P->>C: PATCH update (submit_action=final)
    C->>C: status → submitted, submitted_at
    C->>F: KpiReportSubmittedNotifier (immediately)
    C-->>P: redirect "submitted, fund notified"
    C->>M: after_commit import_kpis
    M->>J: perform_later
    J->>R: extract_kpis
    R->>R: detect header (best of first 10 rows), parse periods, match mappings
    R->>R: write Kpi rows as unapproved (may create other KpiReports for other periods)
    alt error_msg present
        J-->>P: EntityMailer.send_report (email to uploader only)
    end
    J->>M: launch_portfolio_company_workflow (only if no errors)
```

Two things stand out from the diagram and drive most of the findings below:

1. **The only blocking validation is client-side** (step 7–8). The server never inspects the file
   before accepting the submission.
2. **The submission is acknowledged before the import runs** (steps 12–14 vs 15–19). Import
   errors are discovered later, in a background job, and reported by email to the portco — who
   by then can no longer edit the report.

### 1.3 What each layer validates today

| Layer | Checks performed | Checks *not* performed |
|---|---|---|
| **Uppy / `_file.html.erb`** | none — `FileUploader::ALLOWED_TYPES = %w[*/*]` | file type; whether a file is required |
| **`kpi_xlsx_report_controller.js`** (runs once per `upload:complete`) | per sheet: `!ref` present, ≥1 row, **row 1** (`data[0]`) has ≥1 date-like cell after col A, some row below has a non-empty col A. Per configured `reported_kpi_name`: found in *any* column of *any* row (whitespace/case-insensitive) → counts non-blank cells. Errors disable Submit/Save Draft. Missing KPIs → **warning only** ("You can still submit"). | value types; duplicates; hidden sheets; the requested period; consistency with the server's header rules; anything when no file is uploaded |
| **`xlsx_preview_controller.js`** | renders tabs/tables (all sheets) | nothing KPI-specific |
| **`KpiReportsController#update`** | Pundit `update?` (blocks portco once submitted/reviewed) | that a KPIs document exists; that it parses; strong-params still permit portco-disabled fields (`as_of`, `period`, `portfolio_company_id`, `entity_id`, `tag_list`, `kpis_attributes`) |
| **`KpiReport` model** | `as_of` presence, `period` length ≤ 12, uniqueness | anything about the document |
| **`KpiWorkbookReader`** (async) | header row = row (of first 10) with most distinct date-like cells, min 2, cells must contain a letter or `/`/`-`; period parse via `KpiDateUtils`; KPI name must match a `not_compute` mapping (parent-aware); duplicate period in a row → skipped; future `Actual` period → skipped silently; `n/a`/`na` skipped; denomination multiplier applied | numeric-ness of values (see §2.4); the requested `as_of`; whether anything was imported at all; hidden sheets/rows |
| **Review gate** | Imported values are `unapproved` until the fund calls `mark_reviewed` | — |

The `unapproved` gate is the main reason bad data does not immediately hit dashboards. It does
**not** stop bad data being *submitted*, and it puts the entire quality burden on the fund's
reviewer, who has no per-file diagnostics in the UI (errors went to the portco's inbox).

---

## 2. Gaps — ranked by risk

Each gap lists a concrete reproduction so it can be turned into a Cucumber scenario in
`features/startup/portco_kpi_workflow.feature`.

### 2.1 Submit works with no file, or with a non-spreadsheet — HIGH

> **Sign-off: APPROVED (2026-08-18)** — proceed with §3 items D (server gate on final submit: KPIs document must exist and open with Roo), G (spreadsheet-only types), H (start guarded / re-analyse on load).

- `file_fields("KPIs", …, required: false)` — the field is optional.
- The guard in `kpi_xlsx_report_controller.js` is only ever *set*; it is never initialised. Until an
  `upload:complete` fires, both **Save Draft** and **Submit Report** are enabled.
- Uppy accepts `*/*`. A PDF/DOCX fails SheetJS parsing → guard on. **Reload the page** → the
  guard is gone (nothing re-analyses the attached document), Submit is enabled again.

Repro: open a `link_sent` shell via magic link → click **Submit Report** → status becomes
`submitted`, fund is emailed "KPI report submitted", `kpis.count == 0`.

### 2.2 Submission is decoupled from import success — HIGH

> **Sign-off: APPROVED (2026-08-18)** — proceed with §3 items D (synchronous dry-run validation gates final submit; errors block, warnings allowed) and E (fund notified only after a clean import; import summary persisted and shown on the fund's report page; import failures visible via a state/flag so reminders and the portco agent don't treat the report as done; fund can reopen and ask for re-upload — §3.4 Q). Default: allow submit with warnings; optional per-entity strict mode ("all mapped KPIs required") left as a product decision.

- `resolve_status_transition('final')` flips status and `notify_fund_on_submission` runs inside
  the request. `ImportKpiWorkbookJob` runs later on the `low` queue.
- If the reader finds no header, no matching KPIs, unparseable periods, etc., `error_msg` is
  **emailed to the uploader** (`EntityMailer.send_report` with `user.entity_id` = the portco's
  entity). Nothing is shown in the UI, nothing changes on the report, and the fund's
  notification has already gone out.
- The report is now `submitted`, so `KpiReportPolicy#update?` blocks the portco from fixing it.

Repro: upload a workbook whose only header row is `2023 | 2024 | 2025` (passes the JS check,
see §2.3) → Submit → job logs "No valid header found in KPI import file for sheet: Sheet1" →
fund sees a submitted report with zero staged KPIs.

### 2.3 Client-side header check disagrees with the server — HIGH

> **Sign-off: APPROVED (2026-08-18) — with a design change.** Decision: **all validation moves to the backend; JS holds no rules.** On `upload:complete` the browser POSTs the Shrine cached-file reference to a new `validate_upload` endpoint, which runs `KpiWorkbookReader#validate` (dry run) against the shell and returns errors/warnings/summary/cell refs; the browser only renders the result and toggles the submit guard. The same method is the gate on Save/Submit, so pre-save feedback and enforcement can never drift. `isDateLike`/`analyzeWorkbook` in `kpi_xlsx_report_controller.js` are removed; `xlsx_preview_controller.js` stays display-only (plus server-directed cell highlighting). See §3.1 C and §3.3 as revised. **Open:** single-period rule — Option A (keep ≥2 distinct, template pads columns) vs Option B (accept 1 period cell when it equals the requested period; recommended).

`kpi_xlsx_report_controller.js#analyzeWorkbook` / `#isDateLike` vs `KpiWorkbookReader#detect_header_row` / `KpiDateUtils.date_like?`:

| Rule | JS (blocks the portco) | Ruby (decides what imports) | Effect |
|---|---|---|---|
| Which row is the header | `data[0]` only | best-scoring of rows 1–10 | Title rows above the header → **false block** in UI (file would import fine) |
| Minimum date-like cells | ≥ 1 | ≥ 2 **distinct** | Single-period sheets pass UI, fail server |
| Pure numbers | `\b\d{4}\b` matches; Excel serials 10000–60000 accepted | cell must contain a letter or `/`/`-` — pure numerics excluded | `2023 \| 2024` headers pass UI, fail server (→ §2.2) |
| Month/apostrophe forms | own regex list | `KpiDateUtils` list (slightly different, e.g. `[\s']*`) | Drift over time as one side is patched |

The JS comment says "Mirrors KpiDateUtils.date_like?" — it has already drifted. Any future
change to either side will widen this.

### 2.4 Values are never type-checked; text silently becomes a number — HIGH

> **Sign-off: APPROVED (2026-08-18) — direction changed from "strict reject" to "normalise".** Build a server-side number normaliser (§3.1 B as revised) that understands separators, accounting negatives, currency symbols/codes, unit suffixes (K/L/M/Cr/B — an explicit unit overrides the mapping denomination), and `%`; placeholders skip with a warning; Excel error cells and genuinely ambiguous text are errors that block submission; the pre-save panel shows raw → stored per cell so the portco confirms the interpretation. Backend-only.

`KpiWorkbookReader#save_kpi_entry` writes `value` into a `decimal(20,6)` column. Rails' decimal
cast (and the explicit `value.to_d` on the denomination path) turns non-numeric strings into a
number without error:

| Cell text | Stored value | Why it happens in real MIS files |
|---|---|---|
| `1,200` | **1** | text-formatted numbers with thousands separators |
| `(500)` | **0** | accounting negatives |
| `12%` | **12** (or should have been 0.12) | percentage typed as text |
| `₹ 5,00,000` / `$1.2M` | **0** / **1.2** | currency prefixes, unit suffixes |
| `TBD`, `—`, `n.m.`, `nil`, `NA ` (with trailing text) | **0** | only literal `n/a` and `na` are skipped |
| `#DIV/0!`, `#REF!`, `#N/A`, `#VALUE!` | **0** | Excel error cells — Roo returns the error string |

The UI counts every one of these as a "non-blank value" (green ✔). A `0` revenue for a month
is far more damaging than a missing one: it drives MoM/YoY %-change, cumulation, forward-fill and
common-size calculations downstream.

Note: `extract_kpis` rescues `invalid value for Float()` with a friendly message — that path
only triggers for Roo-level cell parsing failures, not for these strings.

### 2.5 The file is not tied to the request — MEDIUM/HIGH

> **Sign-off: APPROVED (2026-08-18) with decisions.** (a) requested period missing → error; (b) requested period present but blank → error if no mapped KPI has a value, warning listing blank KPIs otherwise; (c) historical periods in the file are **always imported — no period scoping** (the "requested + look-back window" option is dropped); restaged historical values remain `unapproved` and still need fund approval, and the panel/summary must show them as *changed vs approved* (old → new). Future-dated `Actual` columns stay skipped but now emit a **warning** naming the column and the parsed date. Fiscal year start: **no new setting** — reuse the existing `month_offset_for_fy` (`EntitySetting#start_of_financial_year_date` / `WithCustomField#start_of_financial_year_date`, resolution order as in `KpiCumulative`: portco's own json_fields → fund entity setting → default April) and pass it into `KpiDateUtils.parse_period` (offset+1 → `fiscal_year_start_month`), which the importer currently omits.

The shell has an `as_of` and `period` ("Month ending 2026-06-30"). The reader:

- imports **every** date column it finds and `find_or_create`s a `KpiReport` per
  period/tag (`find_or_create_kpi_report`), so a portco can restage 24 months of history from
  a single magic link;
- does not check that the requested period is present, or that it has values;
- drops future-dated `Actual` periods **silently** (`process_kpi_row`, "Skipping future 'Actual'
  KPI") — a portco who mislabels columns (e.g. `FY26` meaning FY25-26 under a March year-end
  vs the parser's assumption) gets nothing imported and no message.

The UI shows "n / periodCount non-blank" per KPI but never asks "is the column you were asked
for present and filled?".

### 2.6 Duplicates and structural ambiguities are not flagged — MEDIUM

> **Sign-off: APPROVED (2026-08-18).** Rules (all in `KpiWorkbookReader#validate`, backend-only): same mapping matched on 2+ rows (any sheet) with **conflicting** values for a period → **error** `duplicate_kpi_row` (sheet/row/values listed); identical repeated values → warning; duplicate period header in a row (not distinguished by a tag row) → **error** `duplicate_period` with column refs; **hidden sheets are skipped** (not imported) with warning `hidden_sheet_skipped` naming the sheet — a hidden sheet is the portco saying "not this one"; hidden rows are treated as normal rows (conflicts still surface via `duplicate_kpi_row`); the expected-KPI list / `kpis_missing` use `not_compute` mappings only. Conflicting duplicates must block because §2.5 imports all data — otherwise last-sheet-wins remains.

- Same KPI name on two rows (common: "Revenue" in a summary block and again in a P&L block) →
  `first_or_initialize` on the same unapproved `Kpi` → **last row wins, silently**.
- Same period header twice in a row → second is skipped; message goes to email only.
- **Hidden sheets** and hidden rows are read by Roo. A "scratch"/"working" sheet with the same
  KPI names will be imported. SheetJS exposes `workbook.Workbook.Sheets[i].Hidden` but the JS
  ignores it and the preview shows hidden sheets as ordinary tabs.
- Compute-type mappings are excluded server-side (`investor_kpi_mappings.not_compute`) but the
  UI receives `@kpi_mappings` **unfiltered** (`KpiReportsController#edit`), so computed KPIs
  are reported as "Missing" — noise that trains portcos to ignore the warning.

### 2.7 Zero mappings → green "All 0 KPIs found" — MEDIUM

> **Sign-off: APPROVED (2026-08-18).** `validate` returns error `no_mappings` first when the portco has no `not_compute` mappings, with a portco-facing "your fund has not configured KPIs to collect yet — contact them" message; the fund's shell/pending dashboard shows a "no KPI mappings" badge, and `SendPortcoNotification` warns the fund at send time.

If the fund has not configured `InvestorKpiMapping`s for the portco, `reportedKpis` is `[]`,
the analyzer renders `All 0 KPIs found` in a success alert, and the importer imports nothing.

### 2.8 Read-only fields are enforced only by the browser — MEDIUM (security-flavoured)

> **Sign-off: APPROVED (2026-08-18).** (1) Actor-scoped strong params: portco actors (`@signed_id_user` present, or `portfolio_company_user?`) may send only `notes`, `documents_attributes`, `upload_new_kpis`, `properties`; `update_existing_kpis` is set server-side for portcos; fund users keep the full list. (2) `kpis_attributes` unreachable for portcos; defence in depth — nested KPIs from non-fund actors forced `unapproved`. (3) `delete_kpis` fund-only, logged (who/when/count). (4) For fund users changing `portfolio_company_id`, verify the target portco belongs to `current_user.entity_id` and re-authorise on the mutated record; `entity_id` never reassignable via update. Cucumber cases listed in §5.

For portco users `_form.html.erb` sets `disabled: true` on `portfolio_company_id`, `as_of`,
`period`, `tag_list`, but `kpi_report_params` still permits them — plus `entity_id`, `user_id`
and `kpis_attributes` (`id name period value display_value notes _destroy`). With a valid
signed link a crafted PATCH can:

- re-point the report to another portfolio company or change its period/tag;
- create `Kpi` rows directly via nested attributes — and `Kpi` defaults to
  `status: approved`, so these **bypass the unapproved review gate**.

### 2.9 No plausibility checks against mapping metadata — MEDIUM

> **Sign-off: APPROVED (2026-08-18).** Warnings only, never blocking, all in `validate` and shown pre-save and in the fund's import summary: `denomination_suspect` (≥3 orders of magnitude vs last approved, no explicit unit in cell — fires first and suppresses `outlier`/`threshold_breach` for the same cell), `percentage_scale_suspect`, `threshold_breach` (mapping `lower_/upper_threshold`), `rag_red` (mapping `rag_rules`), `sign_flip`, `outlier` (default ±200% when no thresholds). History-based rules only when ≥1 prior approved value exists. Fund pages show the warning count; approving a flagged value resets the baseline. **No auto-correction** of suspected denominations.

`InvestorKpiMapping` already carries `data_type` (money/numeric/percentage), `denomination`
(thousands/lakhs/millions/crores), `lower_threshold`/`upper_threshold`, `rag_rules`. None are
consulted at upload time:

- revenue reported in absolute rupees against a "crores" mapping is multiplied by 10⁷;
- a percentage KPI entered as `12` vs `0.12` is indistinguishable;
- a 500% swing vs the last approved value raises no flag until the fund's reviewer notices.

### 2.10 Guard state is per-page-load — LOW

> **Sign-off: APPROVED (2026-08-18).** Correctness already covered by §2.1 H / §2.3 / D (browser re-asks the server on load; final submit recomputes). Decision: **persist the last validation result** (JSON + timestamp) on the report for display — instant panel on reload, fund pending dashboard can show "draft saved — N errors outstanding" without opening the file; "Re-check" button and auto re-run when the portco's mappings changed after the stored check; the stored copy is never used for the submit decision. Same storage as the post-import summary (§2.2 E).

The guard is DOM state. Save Draft reloads the page; the previously attached document is not
re-analysed (no `data-xlsx-preview-url` is passed for KPI reports), so the analyzer panel is
empty on return and no guard is applied.

---

## 3. Recommended enhancements

Ordering principle: **the server must be the enforcement point**; the browser is for fast,
friendly feedback. Both should run the *same* rules, so a portco is never told "OK" by the UI
and "invalid" by the import (or vice versa).

Deliberately **not** proposed: a file-size cap. Portco MIS workbooks are legitimately large
(multi-sheet, multi-year). Cost should be controlled by scoping *what is imported* (§3.2 D),
not by rejecting files.

### 3.1 Shared validation core (do this first)

**A. `KpiWorkbookReader#validate` (dry run).**
Refactor the reader so header detection, period parsing, mapping resolution and value
extraction can run **without writing** and return a structured result:

```ruby
{
  errors:   [ { code:, sheet:, row:, col:, kpi:, period:, message: } ],  # block submission
  warnings: [ ... ],                                                      # shown, don't block
  summary:  { sheets:, header_row_by_sheet:, kpis_found:, kpis_missing:,
              periods_found:, requested_period_present:, values_flagged: }
}
```

Error codes to emit (all currently either silent or email-only):

| Code | Condition |
|---|---|
| `no_file` / `not_spreadsheet` | no KPIs document, or Roo cannot open it |
| `no_header` | no row with ≥2 distinct date-like cells |
| `no_mappings` | portco has zero `not_compute` mappings |
| `no_kpis_matched` | header found but no row matched any mapping |
| `requested_period_missing` | shell's `as_of`/`period` column not in the header (any sheet) |
| `requested_period_blank` | column exists but no matched KPI has a value in it |
| `non_numeric_value` | cell text is not a clean number (see §3.1 B) |
| `excel_error_cell` | `#DIV/0!`, `#REF!`, `#N/A`, `#VALUE!`, `#NAME?`, `#NUM!` |
| `duplicate_kpi_row` | same mapping matched on more than one row in a sheet |
| `duplicate_period` | same parsed period + tag twice in a header (not distinguished by a tag row) |
| `duplicate_kpi_row` | same mapping matched on 2+ rows (any sheet) with conflicting values for a period; identical values → warning only |

Plausibility warning codes (§2.9): `denomination_suspect`, `percentage_scale_suspect`, `threshold_breach`, `rag_red`, `sign_flip`, `outlier`. Other warning codes: `hidden_sheet_skipped` (hidden sheets are not imported), `duplicate_kpi_row_identical`. Warning-only period codes: `future_period_skipped` (column + parsed date), `historic_periods_touched` (list; flags periods already `reviewed`), `historic_value_changed` (per KPI × period: approved old → staged new).

Warning codes: `kpi_missing` (a mapping not found anywhere), `future_period_skipped`,
`hidden_sheet_skipped`, `historic_periods_touched` (list of periods other than the requested
one), `outlier_vs_last_approved`, `percentage_scale_suspect`, `denomination_suspect`.

**B. Number normalisation (replaces the implicit decimal cast).**
A single parser used by both `validate` and `save_kpi_entry`. Principle: interpret formatting,
store the intended number, never silently store `0`. Rules, first match wins, on the trimmed cell:

| Input | Interpretation | Stored |
|---|---|---|
| Numeric cell from Roo | as-is | `1250000` |
| Thousands separators (Western or Indian grouping): `1,200`, `12,50,000`, `1 200`, `1'200` | strip separators | `1200`, `1250000` |
| Accounting negative `(500)`, `(1,20,000)`, trailing `500-` | negate | `-500` |
| Currency prefix/suffix `₹ $ € £`, `INR`, `USD`, `Rs.` | strip | number |
| Unit suffix `K`/`thousand`, `L`/`Lac`/`Lakh`, `M`/`Mn`/`million`, `Cr`/`crore`, `B`/`Bn`/`billion` | multiply; **explicit unit in the cell overrides the mapping's `denomination`** (not stacked) | `1.2M` → `1200000`, `45 L` → `4500000` |
| `12%`, `12.5 %`, `-3%` | if mapping `data_type` = `percentage`: `/100` (consistent with Excel native % cells arriving as `0.12` and the helper displaying `value*100`); on a non-percentage KPI: store `12` + warning | `0.12` |
| Bare number on a `percentage` KPI | store as given; **warn** if magnitude disagrees with the KPI's history (`>1` while prior `<1`, or vice versa) | `12` + warning |
| Placeholders `n/a`, `na`, `-`, `—`, `nm`, `n.m.`, `tbd`, `nil`, `pending` (configurable; today's `n/a`/`na` become the default list) | skip, warning "blank for <period>" | nothing |
| Excel error strings `#DIV/0!`, `#REF!`, `#N/A`, `#VALUE!`, `#NAME?`, `#NUM!` | **error** `excel_error_cell` | — |
| Genuinely ambiguous: mixed `1.234,56` / `1,234.56` styles in one sheet, `12,34`, `(1)` next to a footnote, two numbers in one cell `10 (prev 8)`, `1.2 M Cr` | **error** `ambiguous_value` — show candidate readings, don't guess | — |
| Any other non-numeric text (`ten`, `see note`) | **error** `non_numeric_value` | — |

Decimal/thousand convention is detected **per sheet** (a sheet consistently using `1.234,56` is
European; a mixed sheet is ambiguous → error), so `1,234` is never misread.

**Transparency:** `validate` returns per matched cell
`{sheet, row, col, raw: "₹ 12,50,000", stored: 1250000, applied: [...]}`. The pre-save panel renders
a "How we read your file" table (KPI × period → raw → stored) and the preview highlights transformed
cells (neutral), warnings (amber) and errors (red). The same table is persisted with the import
summary (E) so the fund reviewer can audit interpretations later.

**Blocking:** errors block the whole submission (the portco can fix the sheet immediately; partial
imports recreate §2.2). Warnings show but do not block.

**C. Single source of truth: the backend validates, the browser only displays.**
Rather than mirroring `KpiDateUtils`/`detect_header_row` in JavaScript, remove all rules from
`kpi_xlsx_report_controller.js` and add a `validate_upload` endpoint on `KpiReportsController`
(magic-link aware via `set_kpi_report`/`pundit_user`, with a matching `validate_upload?` policy
method). Flow:

1. Uppy finishes → `upload:complete` carries the Shrine cached-file JSON (already what the hidden
   field submits with the form).
2. JS POSTs that JSON (+ `signed_id`) to `validate_upload`.
3. Server opens the cached object (`Shrine.uploaded_file(json)` → Roo) — no `Document` row is
   created — and runs `KpiWorkbookReader#validate` against the shell's `as_of`, `period`, and
   `not_compute` mappings.
4. Response (turbo_stream or JSON): `{errors, warnings, summary, cells: [{sheet,row,col,code}]}`.
5. JS renders the panel, disables Submit when `errors.any?`, and asks `xlsx_preview_controller`
   to highlight the referenced cells.
6. Save Draft / final Submit call the **same** `validate` on the server (D) — identical verdict.

Large workbooks: run inline with a spinner; if validation exceeds a few seconds, hand off to a
background job and deliver the result via Turbo Stream/polling. No size limit in either path.

Header/period regexes therefore live only in Ruby (`KpiDateUtils`, `detect_header_row`,
`detect_first_date_column`); the "≥2 distinct date-like cells" and "letter or `/`/`-`" rules apply
to the pre-save check automatically because it *is* the server.

**Single-period rule (open decision):** the current `best_score >= 2` rejects a one-column file
(`KPI | Jun 2026`), which is the natural reply to a monthly request. Option A: keep ≥2 and make
the template always carry ≥2 period columns. Option B (recommended): accept a single date-like
cell **only** when it parses to the shell's requested `as_of`/`period`; otherwise keep ≥2.

### 3.2 Server-side enforcement

**D. Gate the final submission.**
In `KpiReportsController#update`, when `submit_action == 'final'` and the actor is a portco
(`@signed_id_user` or `portfolio_company_user?`):

1. require a KPIs document;
2. run `KpiWorkbookReader#validate` synchronously;
3. if `errors.any?` → re-render the edit form with the errors listed inline (row/col/sheet) and
   **do not** change status or notify the fund;
4. import **all** periods in the file (no scoping — decided in §2.5), but report every period other
   than the requested one as `historic_periods_touched`, and for each restaged value that differs from
   an approved value show `old → new` (they stay `unapproved` until the fund approves).
5. resolve the fiscal-year start from the existing `month_offset_for_fy` setting (portco json_fields →
   fund `EntitySetting` → default) and pass it to `KpiDateUtils.parse_period` so `FY26`/`Q1 FY27`
   parse the way the portco means; today the importer silently uses the hard-coded April default.

**E. Notify the fund only after a clean import.**
Move `notify_fund_on_submission` (or add an `import_failed` state) into `ImportKpiWorkbookJob`
so the fund's "submitted" email means "and the data is staged". Persist the validate/import
summary on the report (a JSON column or an attached document) so the fund's show page can
display "3 warnings, 0 errors" next to the *View Including Staged* link.

**F. Actor-scoped strong params (approved §2.8).**
When `@signed_id_user` is present, permit only `notes`, `documents_attributes`,
`upload_new_kpis` (and `properties` if custom fields are intended). Drop `kpis_attributes`,
`as_of`, `period`, `portfolio_company_id`, `entity_id`, `user_id`, `tag_list`. If nested
`kpis_attributes` must remain for fund users, force `status: unapproved` when the actor is a
portco.

**G. Restrict accepted types for this field.**
Pass `allowed_types: %w[.xlsx .xls .csv]` (Uppy) to `file_fields` for the KPIs document and
verify the extension/MIME server-side in the gate (D). This is a type restriction, not a size
restriction.

### 3.3 Client-side (display) changes — `kpi_xlsx_report_controller.js` / `xlsx_preview_controller.js`

Per the §2.3 decision the browser performs **no validation**. Its responsibilities are:

**H. Start guarded.** On `connect`, if no KPIs document exists, disable **Submit Report** (Save
Draft stays enabled) with the hint "Upload your KPI workbook to enable submission". If a document
already exists, call `validate_upload` for it on load so the panel and guard reflect the server's
verdict after Save Draft.

**I. Call the server on upload.** On `upload:complete`, POST the cached-file JSON to
`validate_upload` (C); show a spinner; render errors (blocking) and warnings (non-blocking) with
sheet/row/col; toggle the guard from `errors.any?`.

**J. Cell highlighting.** `xlsx_preview_controller.js` keeps rendering all sheets; it accepts the
server's `cells[]` list and applies a CSS class (error/warning) to those cells so the portco can
see exactly which values are `non_numeric_value`, `excel_error_cell`, duplicates, etc.

**K. Period-fit panel.** Render the server's `summary.requested_period_present` /
`requested_period_blank` and `historic_periods_touched` prominently ("You were asked for **Jun
2026 (Month)** — present ✔, 3 KPIs blank ✖; this file also touches Jan–May 2026").

**L/M/N.** Structural warnings (duplicates, hidden sheets), the "no mappings configured" error, and
plausibility hints (percentage scale, denomination, swings vs last approved) are all **server
rules** emitted by `validate` (A); the browser just displays them under the codes returned.

**O. Server verdict is the only verdict.** There is no separate "client says OK" state — the
panel always shows the last `validate` result and the guard follows it.

### 3.4 Process / template

**P. Downloadable template per portco.** Generate an XLSX from the portco's `not_compute`
mappings: KPI names in column A exactly as `reported_kpi_name`, the requested period as the
header (plus optionally the previous 2 periods for context), denomination noted in a header
comment, cells pre-formatted as numbers. Most of §2.3–2.7 disappears when portcos start from
the template rather than pasting an MIS.

**Q. Fund-side visibility.** On the fund's KPI report page show the last import summary
(A/E), with a one-click "Ask portco to re-upload" that reopens the report (`draft_saved`) and
re-sends the link.

---

## 4. Proposed sequence after the changes

```mermaid
sequenceDiagram
    autonumber
    participant P as Portco user (browser)
    participant U as Uppy → Shrine cache
    participant JS as kpi-xlsx-report (display only)
    participant C as KpiReportsController
    participant V as KpiWorkbookReader#validate (dry run)
    participant J as ImportKpiWorkbookJob
    participant F as Fund admin

    P->>U: upload workbook (xlsx/xls/csv only)
    U-->>JS: upload:complete {cached file JSON}
    JS->>C: POST validate_upload {file, signed_id}
    C->>V: open cached file, validate vs shell (as_of, period, mappings)
    V-->>C: {errors, warnings, summary, cells}
    C-->>JS: turbo_stream / JSON
    JS-->>P: panel + highlighted cells; Submit disabled if errors
    P->>C: Submit Report (submit_action=final)
    C->>V: validate again (server is the gate)
    alt errors.any?
        C-->>P: 422 — form re-rendered with row/col errors; status unchanged; fund NOT notified
    else clean
        C->>C: status → submitted
        C->>J: perform_later (all periods in the file)
        J->>J: import; persist summary on report
        J->>F: KpiReportSubmittedNotifier ("submitted and staged: 14 KPIs, 2 warnings")
    end
```

## 5. Suggested test coverage (Cucumber, `features/startup/portco_kpi_workflow.feature`)

- Submit with no file → blocked, status unchanged, no fund email.
- Submit a PDF renamed `.xlsx` → blocked with `not_spreadsheet`.
- Header only on row 3 (title rows above) → **allowed** by UI and server (regression for §2.3).
- Header `2023 | 2024 | 2025` → UI and server agree (either both accept plain years or both reject).
- Cell `1,200` → 1200; `12,50,000` → 1250000; `(500)` → -500; `₹ 5,00,000` → 500000; `1.2M` → 1200000; `45 L` → 4500000; `2.5 Cr` → 25000000; `12%` on a percentage KPI → 0.12; explicit `Cr` in a cell on a `crores`-denominated mapping → not stacked.
- `#DIV/0!` → `excel_error_cell` error; `10 (prev 8)` / mixed locale sheet → `ambiguous_value` error; `ten` → `non_numeric_value`; `tbd` → skipped with warning. In every error case no `Kpi` row is written and status is unchanged.
- Pre-save panel shows raw → stored for each cell, and the stored value after import equals what the panel showed.
- Requested period column missing → `requested_period_missing` error.
- Requested period present but blank for all KPIs → `requested_period_blank` error; blank for some → warning listing them.
- File with 24 months → all imported as `unapproved`; panel lists `historic_periods_touched` and `old → new` for values differing from approved ones; approved values unchanged until `mark_reviewed`.
- Portco with `month_offset_for_fy = 0` (calendar FY): `FY26` parses to 31-Dec-2026 (fund default would give 31-Mar-2026); a column parsing to a future date shows `future_period_skipped` naming the column and date.
- Same KPI on two rows → error, no silent overwrite.
- Hidden sheet containing KPI names → skipped, warning names the sheet, no `Kpi` rows from it.
- Same KPI on two rows with different values → `duplicate_kpi_row` error; identical values → warning, imported once.
- Expected-KPI summary excludes `compute` mappings.
- Portco PATCH via magic link carrying `as_of`, `period`, `portfolio_company_id`, `entity_id`, `tag_list` → all unchanged; notes saved.
- Portco PATCH carrying `delete_kpis=true` on a report with approved KPIs → count unchanged.
- Portco PATCH carrying `kpis_attributes` (new row, `_destroy` on an approved id) → no new `Kpi`, existing intact.
- Logged-in portco user (no signed_id) → same three assertions.
- Fund user sets `portfolio_company_id` to another fund's Investor → 403; own portco → succeeds; normal `as_of`/`period` edit still works.
- Import job produces errors → status not `submitted`, or (with E) fund notified only on clean import.
- Zero mappings configured → `no_mappings` error on validate/submit; fund sees a badge on the shell; sending the notification warns the fund.
- Value 10⁷× last approved on a `crores` mapping → `denomination_suspect` warning, submit still allowed; brand-new portco (no history) → no plausibility warnings.
- Change beyond mapping thresholds → `threshold_breach` warning shown pre-save and in the fund summary.
- Large workbook (many sheets/columns) → accepted; no size-based rejection.
- `validate_upload` via magic link: valid signed_id → verdict returned; tampered/expired → 410; other portco's report → 403.
- Pre-save panel and final-submit gate return the same verdict for the same file (same fixture through both paths).

---

## 6. Implementation order and status

1. ✅ **Done 2026-08-18 (phase 1, awaiting manual test)** — `KpiWorkbookReader#validate` (dry run sharing the import code path), `KpiValueNormalizer` (§2.4 rules), fiscal-year plumbing from `month_offset_for_fy` (incl. `KpiDateUtils` FY/half-year/January-start fixes), hidden sheets skipped, duplicate/requested-period/plausibility checks, verdict persisted on `kpi_reports.validation_result` / `validated_at` (§2.10); `KpiUploadValidate` Trailblazer op; `KpiReportsController#validate_upload` (member for saved reports incl. magic link, collection for the New page) + `validate_upload?` policy; `_validation_panel.html.erb` (errors / warnings / requested period / "How we read your file" raw → stored table); JS reduced to display only (`kpi_xlsx_report_controller.js` posts, `kpi_validation_panel_controller.js` toggles the guard from the server's error count); import job persists the same verdict and skips the workflow launch only on blocking errors. Cell highlighting in the sheet preview deferred (preview drops blank rows/cols, so coordinates don't map 1:1). Cucumber: `features/startup/kpi_upload_validation.feature` (15 scenarios) + updated reader/portco features (72/72 passing).

### 6.1 Manual QA — phase 1 (server-side workbook check + pre-save panel)

Setup (dev): `bundle exec rails db:migrate` has been run; log in as a fund user with KPIs enabled.
Pick a portfolio company (Investors → category Portfolio Company) and make sure it has a few
`InvestorKpiMapping`s (Investors → KPI Mappings), e.g. Revenue, EBITDA, Headcount, Gross Margin (data type
percentage). Note the fund's fiscal-year start (Entity Settings → month offset for FY; default April).

Create a shell + magic link: KPI Reports → *Send notification* to that portco for a month (e.g. Jun 2026,
period Month). Open the link from the email (letter_opener in dev) in a private window — you are now the
portco user, unauthenticated.

| # | Steps | Expect |
|---|---|---|
| 1 | Open the magic link before uploading anything | Panel says "Upload your KPI workbook and we will check it…"; Save Draft / Submit enabled (gating comes in phase 2) |
| 2 | Upload an .xlsx: row 1 `KPI \| May 2026 \| Jun 2026`, rows `Revenue \| 1,200 \| ₹ 12,50,000`, `EBITDA \| (500) \| $1.2M`, `Headcount \| 45 L \| 2.5 Cr`, `Gross Margin \| 42% \| 0.41` (type the numbers as text) | Spinner, then **Workbook check** card: "No blocking errors", "You were asked for Jun 2026 (Month) — column present, KPIs filled 4 of N", "How we read your file" table shows raw → stored: 1,200→1200; ₹ 12,50,000→1250000; (500)→-500; $1.2M→1200000; 45 L→4500000; 2.5 Cr→25000000; 42%→0.42; the *How* column lists the transformations |
| 3 | Reload the page | Same panel is shown from the stored verdict (`validation_result`); *Re-check file* button present once a document is saved |
| 4 | Upload a file whose header is `KPI \| Notes \| Comments` | Red error "No sheet in the file has a header row with at least two period columns…"; Save Draft & Submit **disabled** |
| 5 | Upload a file with periods `Apr 2026 \| May 2026` only | Error `You were asked for Jun 2026 (Month), but no column in the file is that period. Periods found: …`; buttons disabled |
| 6 | Same file but Jun 2026 column present with all cells blank | Error "…present but none of the expected KPIs has a value in it"; with only some KPIs blank → amber warning listing them, buttons enabled |
| 7 | Put `#DIV/0!` (or an Excel formula that errors), `10 (prev 8)`, `ten`, `TBD` in value cells | Errors for the first three naming the cell (e.g. `MIS!B2`); `TBD` → warning "treated as blank"; table rows red / grey |
| 8 | Add a second row `Revenue` with different values | Error `duplicate_kpi_row` naming both cells; identical values → warning only |
| 9 | Add a hidden sheet containing KPI names | Warning "Sheet 'X' is hidden … ignored"; nothing from it in the table |
| 10 | Add a title row above the header (row 1 "Company MIS", header on row 3) | Still valid — header found on row 3 |
| 11 | Add a future column (e.g. Dec 2027) | Warning `'Dec 2027' was read as 31-Dec-2027, which is in the future — Actual values under it are ignored`; row shows "future — ignored" |
| 12 | Add columns for older months that already have **approved** values (approve some via the fund UI first), with different numbers | Warnings "This file also updates N other periods…" and "N values differ from figures your fund has already approved"; those rows amber with *Approved now* → *Will be stored*; after Save Draft the values are staged **unapproved**, approved values unchanged |
| 13 | Use `FY25`/`FY26` headers with the fund's FY offset set to January (0) vs April (3) | Period labels in the panel change accordingly (FY26 → Dec 2026 vs Mar 2026) |
| 14 | Portco with **no** KPI mappings | Error "Your fund has not configured which KPIs to collect…" |
| 15 | Value 1000× the last approved value on a crores-denominated mapping | Amber `denomination_suspect` warning, still submittable |
| 16 | Fund side: KPI Reports → *New* → pick portco, upload a workbook before saving | Same panel (context taken from the form's portco / as-of / period); requested-period findings are warnings here, not errors |
| 17 | Save Draft, then Submit as portco; check the fund's report page after the import job | Import wrote the same numbers the panel showed; `kpi_reports.validation_result` refreshed by the job |

2. ✅ **Done 2026-08-18 (phase 2, awaiting manual test)** — server-side submit gate in `KpiReportsController#update` (portco final submit re-runs `KpiUploadValidate` on the workbook being submitted — fresh cached upload or attached document; errors → saved as draft, status unchanged, fund not notified, alert + panel show why); actor-scoped `kpi_report_params` (portco: `notes`, `upload_new_kpis`, `properties`, `documents_attributes` only; `update_existing_kpis` set server-side; `entity_id` only on create; `delete_kpis` fund-only and logged); fund re-pointing `portfolio_company_id` re-checked against the fund's entity; Uppy restricted to `.xlsx/.xls/.csv` (`KpiReport::WORKBOOK_FILE_TYPES`); Submit Report starts disabled until a workbook has been checked (Save Draft stays usable), all portco buttons disabled on blocking errors. Review-gate fixes folded in: informational warnings no longer trigger the import error email/toast (`LEGACY_EMAIL_WARNING_CODES`); `validate_upload` accepts only Shrine **cache** references; the New-page (collection) route verifies the portco belongs to the caller's entity; a stored verdict is only shown when it describes the attached document (`document_id`/`source` on the verdict); Quarter/Half-Year/Year requests answered with monthly columns ending on the requested date are accepted with warning `requested_period_derived` (KPIs without cumulation listed) — *judgment call, please confirm*. Cucumber: 78/78 across the three KPI features.

   **Deployment notes from the review:** (a) entities whose `month_offset_for_fy` is not April and who already imported `FY…`/`Q…FY…`-labelled workbooks will see those labels resolve to different dates from now on (previously the importer hard-coded April) — their existing FY-labelled reports stay as they are; new imports create reports at the correct dates. Check such entities before deploying. (b) `save_kpi_entry` still does two small queries per cell (pre-existing); the import runs in a background job, left as is.

### 6.2 Manual QA — phase 2 (submit gate, param scoping, file types)

| # | Steps | Expect |
|---|---|---|
| 1 | Open a fresh magic link (no workbook yet) | Panel placeholder; **Submit Report disabled**, Save Draft enabled |
| 2 | Choose a PDF in the file picker | Uppy refuses it (only .xlsx/.xls/.csv are selectable) |
| 3 | Upload a workbook with a blocking error (e.g. missing requested period) | Both buttons disabled |
| 4 | With that bad file selected, in dev tools remove `disabled` from *Submit Report* → Confirm & Submit | Red flash "Not submitted — the KPI workbook has N blocking errors. Your changes were saved as a draft…"; status becomes *Draft Saved* (not Submitted); no "submitted" email to the fund; the panel shows the errors |
| 5 | Upload a valid workbook → Submit Report → Confirm | "KPI report submitted. The fund team has been notified."; status *Submitted*; fund email sent |
| 6 | As portco (magic link or logged in), send a PATCH with dev tools / curl carrying `kpi_report[as_of]`, `[period]`, `[portfolio_company_id]`, `[tag_list]`, `[entity_id]`, `[delete_kpis]=true`, `[kpis_attributes][0][name]=X&[value]=1` (include the page's CSRF token) | Only `notes` (and document) change; nothing else moves; no KPI deleted or created |
| 7 | As fund admin, edit a report and set `portfolio_company_id` (dev tools) to an Investor id from another fund | 403 / not authorised; report unchanged. Own portco → allowed |
| 8 | Fund admin: check the "Delete existing KPIs" box and save | Still works; a warning line "delete_kpis requested by user …" appears in the Rails log |
| 9 | Portco: Save Draft after uploading a workbook, reload | Panel shows the verdict for the attached document (not a stale one); Submit enabled iff no errors |
| 10 | Import job after a normal multi-period upload (fund side) | No "Errors in extracting KPIs" email/toast unless there are blocking errors or missing KPIs; import summary stored on the report |
| 11 | Fund admin: KPI Reports → New → pick portco → upload `05_error_bad_values.xlsx` | Panel shows the 3 errors and "This report is for …"; **Save disabled**; forcing the form → "Not saved — the KPI workbook has 3 blocking errors"; no report created. Upload `02_success_template_shape.xlsx` → Save enabled |

3. ✅ **Done 2026-08-18 (phase 3, awaiting manual test)** — `kpi_reports.import_status` (`pending`/`imported`/`failed`) + `fund_notified_at`; a portco's final submit sets `pending`, `ImportKpiWorkbookJob` flips it and is the only place the fund is notified (`KpiReport#notify_fund_of_submission!`, idempotent); the submitted email now states what was staged (values / KPIs / warnings); a post-gate import failure reopens the report (`draft_saved`, `import_status: failed`), emails the portco the details (existing report mail) and the fund a "KPI import failed" notice (`KpiReportImportFailedNotifier`); fund show page: *Workbook import* row (status, error/warning counts, values staged, changed-vs-approved, checked-at), a "No KPI mappings configured" badge, a collapsed *Workbook check details* card (same panel the portco saw), and a **Reopen & ask to re-upload** button (`PATCH reopen`, fund-only) that clears submission markers and re-sends the link — the lifecycle restarts at `link_sent`; sending a notification to a portco without mappings warns the fund at send time.
4. ✅ **Done 2026-08-18 (phase 4, awaiting manual test)** — `KpiTemplateGenerate` + `GET /kpi_reports/:id/template.xlsx` (magic-link aware, `template?` policy) and a **Download KPI template** button on the form: note row, `KPI | Unit | prev-2 | prev-1 | requested` header with labels that round-trip through `KpiDateUtils` under the entity's fiscal-year start (`Jun 2026`, `Apr-Jun 2026`, `FY26`/`CY2026`, `H1 FY27`/`H1 2026`, `YTD Jun 2026`), one row per non-computed mapping with its unit.
5. **Review gate (phases 2–4) folded in 2026-08-19:** portco shells are normalised to the period's month end at creation (`KpiReportCreateShell`) and the requested-period match compares against `as_of.end_of_month`; unrecognised labels in a tag row ("Variance", "Var %") make that column ignored (`unrecognized_tag_column`) instead of colliding with Actual as a duplicate; any 3-month range header (`Mar-May 2026`) is a Quarter, so odd-quarter templates round-trip; the import job stores `document_id`/`source` on the verdict so the edit page trusts it and does not re-check on load; a job crash after a submission reopens the report (`import_status: failed`) instead of leaving it `pending`; RAG rules with string `-Infinity` bounds no longer raise; the panel shows the uploaded filename rather than the label "KPIs"; portco submit forces `upload_new_kpis` so the import (and hence the fund notification) always runs.
6. **Parent/child hardening (2026-08-19):** filled-down layouts (parent name repeated on every child row, child in the next column) are now read as child rows (`pick_row_mapping`); an unmapped label in the parent column resets the parent context; a child name mapped under two parents with no parent context in the sheet is **skipped with warning `parent_context_unknown`** instead of guessed; a new hint `children_sum_mismatch` fires when a parent with 2+ mapped children does not equal their sum (±1 %). Existing indented/column layouts, idempotent re-upload and same-name-under-two-parents behave as before (pinned by `kpi_workbook_reading.feature` + new scenarios in `kpi_upload_validation_extended.feature`).
7. **Fund-side gate (2026-08-19):** blocking errors now stop a fund user's save as well — the fund's Save button carries the "draft" guard (disabled only on blocking errors, never on "no file yet"), and `create`/`update` refuse to save when the workbook being attached has blocking errors (`uploaded_workbook_blocked?`, alert "Not saved — the KPI workbook has N blocking errors…", form re-rendered with the verdict). The requested-period rule stays a warning on fund-created reports; the panel says "This report is for …" there instead of "You were asked for …".
8. Cucumber: `kpi_upload_validation_extended.feature` (22 scenarios: plausibility warnings, header quirks, locales, tag rows, fund-side severity, endpoint auth incl. expired link and cross-tenant New page, stale verdicts, upload types, import-job emails, fund show page, submitted email content, template variants, review fixes) + `parse_period.feature` fiscal-start outline. Whole KPI suite: 239+ scenarios green. Demo workbooks in `public/sample_uploads/kpi_portco_uploads/` (README lists each file's expected verdict) are pinned by `features/startup/kpi_upload_sample_files.feature` (14 scenarios, incl. one end-to-end magic-link upload). History-based plausibility hints only look back `HISTORY_MAX_AGE` (36 months).

### 6.3 Manual QA — phases 3 & 4 (notify-after-import, fund summary, reopen, template)

| # | Steps | Expect |
|---|---|---|
| 1 | Portco: upload a valid workbook, Submit Report → Confirm | Notice "…being imported and the fund team will be notified"; report shows *Submitted*; within seconds (Sidekiq) `import_status` = imported and the fund's Kpi-tagged users (or all employees) get "KPIs submitted: …" with the staged counts |
| 2 | Submit again from the same report (fund reopens first, or a second portco user) | Fund is not emailed twice for the same submission (`fund_notified_at`) |
| 3 | Simulate a post-gate failure: after the gate passes but before Sidekiq runs, delete the portco's KPI mappings, then let the job run (or run `ImportKpiWorkbookJob.perform_now(report_id, user_id)` in a console) | Report back to *Draft Saved*, *Workbook import* row shows "Import failed — reopened for the portco"; fund gets "KPI import failed: …" listing the errors; portco gets the details email and can edit again |
| 4 | Fund: open a submitted report | *Workbook import* row: Imported / N errors / N warnings / values staged; "Workbook check details" card at the bottom shows the same panel the portco saw (raw → stored table) |
| 5 | Fund: click **Reopen & ask to re-upload** → confirm | Notice "Report reopened…"; status *Link Sent*; portco Kpi users receive the reminder email with a fresh link; the link opens an editable report |
| 6 | Fund: KPI Reports → Send notification to a portco that has no KPI mappings | Alert "No KPI mappings configured for: <portco> — …"; the report's show page shows the red "No KPI mappings configured" badge |
| 7 | Portco (magic link) or fund: click **Download KPI template** on the report form | `KPI_template_<portco>_<as_of>.xlsx` downloads: row 1 note, row 3 `KPI | Unit | <prev-2> | <prev-1> | <requested>` (e.g. `Apr 2026 | May 2026 | Jun 2026` for a June Month shell, `Oct-Dec 2025 | Jan-Mar 2026 | Apr-Jun 2026` for a Quarter shell), one row per KPI with its unit (Crores / % (e.g. 42% or 0.42) / absolute) |
| 8 | Fill the requested column in the template and upload it | Panel: no errors, requested period present, all KPIs filled; Submit enabled |
| 9 | Change the fund's FY start to January (Entity Settings) and download a Year-period template | Header uses `CY2025 | CY2026 | …` instead of `FY..` |


## 7. Summary

The current design has one blocking check — a browser-side header/name scan that runs once
per upload — and an asynchronous importer whose failures are reported by email after the report
is already locked and the fund already told "submitted". The `unapproved` review gate limits
the blast radius but does not stop bad or empty submissions, and the reviewer gets no
diagnostics. The fix is a shared, dry-runnable validator used by both the browser (for feedback)
and the controller (as the gate on final submit), strict numeric coercion so text never becomes
`0`, period-fit checks against the shell, and tightened params for magic-link actors. Size limits
are intentionally out of scope; large workbooks are normal for this feature.
