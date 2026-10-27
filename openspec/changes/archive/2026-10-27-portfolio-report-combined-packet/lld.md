# Portfolio Report Combined Packet — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions and ends with
> **Reviewer checks** to tick.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Job signature is additive.** The first row stays in the existing positional arguments; later rows ride in a new optional `additional_parts:` keyword, so runs queued before deploy still perform — see [Background Jobs](#background-jobs).
- **Pieces are a mix of `Document`s and temp `.docx` paths**, ordered by the job, never re-sorted by the merger — see [Method Contracts](#method-contracts).
- **`DocxMerger` is believed to need no change but is spiked first** (tasks 2.1). Suspect: it copies every relationship from later files (including header/footer) into the base without copying the target parts — see [Risks](design.md#risks-and-open-questions).
- **The consolidated generator builds its own small company data**; nothing is shared with the normal generator, which is left unchanged — see [Method Contracts](#method-contracts).
- **Rows are validated in the browser first.** The server repeats the checks as a backstop and refuses with a plain redirect to the company step, because only a tampered request reaches it — see [Controllers](#controllers-params-and-responses).
- **The combined file is named by the first row's template.** No per-row choice (business decision).
- **Extract changes are a separate phase 0.** Extract generation without documents (notes + KPIs, KPIs only in that case, a `warning` toast), the widget's latest-with-data pick, and an extract `destroy` — see [Method Contracts](#method-contracts).
- **The extracts controller's lookup becomes entity scoped** (`policy_scope`) so `destroy` cannot reach another entity's extract; show, edit and update gain the same protection — see [Security Review](#security-review).
- **A template may appear once per list**, because `DocumentGeneratorBase#upload` destroys a same-named document of the same company — see [Controllers](#controllers-params-and-responses).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `db/migrate/20261023120000_add_consolidated_to_portfolio_reports.rb` | New | Adds `portfolio_reports.consolidated` |
| ① | `db/schema.rb`, `db/schema_test.rb` | Modified | Column added (test schema via `bin/sync_schema_test.rb`) |
| ① | `app/packs/funds/portfolios/models/portfolio_report.rb` | Modified | `consolidated` in `ransackable_attributes` |
| ① | `app/packs/funds/portfolios/views/portfolio_reports/_form.html.erb` | Modified | Consolidated checkbox + hint |
| ①② | `app/packs/funds/portfolios/controllers/portfolio_reports_controller.rb` | Modified | Permit `:consolidated`; parse/validate rows; Extracts Only per distinct normal report |
| ② | `app/packs/funds/portfolios/views/portfolio_reports/legacy_bulk_generate_options.html.erb` | Modified | Rows container, **Add report**, labelled report options, prefill from `@parts` |
| ② | `app/packs/funds/portfolios/views/portfolio_reports/_report_part_row.html.erb` | New | One row (also used for the blueprint `<template>`) |
| ② | `app/javascript/controllers/report_parts_controller.js` | New | Add / remove rows, reindex, hide last **Remove**; browser validation (template required, templates unique, Extracts Only needs a normal report) with inline messages (lazy-loaded; no registration needed) |
| ② | `app/javascript/controllers/report_template_filter_controller.js` | Reused | Per-row template filter, unchanged |
| ③ | `app/packs/funds/portfolios/jobs/portfolio_report_job.rb` | Modified | Parts loop, temp run folder, final-document decision |
| ③ | `app/packs/funds/portfolios/jobs/generate_portfolio_report_extracts_job.rb` | Reused | `generate_extract` per company |
| ③ | `app/packs/funds/portfolios/jobs/portfolio_report_doc_gen_silent_job.rb` | Reused | Quiet per-company generation |
| ⑤ | `app/packs/funds/portfolios/services/portfolio_report_consolidated_doc_generator.rb` | New | Renders one `.docx` for all companies; builds each company's small hash itself (company, latest and earliest PI, `funds` with IRR and MOIC, a `ratios` list per fund, logo) and, once all companies are built, the top-level `fund_totals` list (per fund: name, currency, summed FMV and cost of investment, summed numeric company custom fields) |
| ⑥ | `app/packs/funds/portfolios/services/portfolio_report_document_merger.rb` | Modified | Accepts mixed sources; no internal sorting; count and first template passed in |
| ⑥ | `app/packs/core/documents/services/docx_merger.rb` | Modified only if the spike requires | Fix for relationship targets that were not copied |
| ⑧ | `app/packs/funds/portfolios/jobs/generate_portfolio_report_extracts_job.rb` | Modified | Remove the no-documents early return; build `kpis` text when there are no documents; `warning` toast; keep the nothing-at-all path |
| ⑧ | `app/packs/core/documents/services/doc_llm_context.rb` | Modified | Optional `kpis:` input appended after the notes; absent means as before |
| ⑧ | `app/packs/core/investors/views/investors/widgets/_portfolio_report.html.erb` | Modified | One query for the latest extract with data, in an if/else on `portfolio_report_id`, instead of `scope.last` |
| ⑧ | `app/packs/funds/portfolios/controllers/portfolio_report_extracts_controller.rb` | Modified | `destroy` action; `set_portfolio_report_extract` through `policy_scope` |
| ⑧ | `app/packs/funds/portfolios/views/portfolio_report_extracts/show.html.erb` | Modified | **Delete** button |
| docs | `docs/user_guides/portfolio_report_legacy_user_guide.md` | Modified | Consolidated reports and the list of reports |
| tests | `features/fund/consolidated_portfolio_report.feature`, `portfolio_report_combined_packet.feature`, `portfolio_report_parts_list.feature`, `portfolio_report_extracts.feature` | New | Worked examples F1–F4 |
| tests | `features/fund/bulk_portfolio_report.feature` | Modified | ID comment on the existing merged-report scenario (H6) |
| tests | `features/step_definitions/portfolio_report_combined_packet_steps.rb`, `bulk_portfolio_report.rb` | New / Modified | New steps; reuse existing |
| tests | `public/sample_uploads/portfolio_reports_test/cover_and_summary_template.docx`, `legal_disclaimer_template.docx` | New | Template fixtures (binary) |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries (nothing in `app/models` / `app/controllers`)

---

## Schema Detail

**`portfolio_reports`** (existing): records whether a report is consolidated.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `consolidated` | Added | boolean | — | no | `false` | none | Picks the builder and the option label. Never filtered on at scale (a handful of reports per entity), so no index. `false` default keeps every existing report normal with no backfill |

**Migration safety:** the table holds one row per report definition per entity (small). Adding a boolean with a default is an instant/online DDL on MySQL 8 and trivial on SQLite. Reversible (`remove_column`). Order: migrate → deploy code (the column is read only by new code). `schema.rb` is updated by the migration; `schema_test.rb` is regenerated with `ruby bin/sync_schema_test.rb` and then `db:test:load_schema` (do not rely on `db:migrate`'s auto-sync).

**Reviewer checks**
- [ ] Every new column has a "why", and none is unjustified
- [ ] No foreign key added, so no index owed
- [ ] Column default matches the model's expectation (`consolidated?` is false for old rows)
- [ ] Migration is reversible and safe on the production table size
- [ ] `schema_test.rb` carries the column (regenerated with the sync script)

---

## Method Contracts

**`PortfolioReportJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform` | `portfolio_report_id, template_id, start_date, end_date, user_id, portfolio_company_ids: nil, generate_missing_extracts: false, additional_parts: []` | — | `ActiveRecord::RecordNotFound` if the first report is gone | Extracts, company `Document`s, combined `Document`, toast, error email | No: replaces same-named company documents, saves a new combined file (E10) |
| `#parts` (private) | first report, `template_id`, `additional_parts` | `Array<Part>` (`Part = Struct.new(:report, :template_id)`) in row order | `RecordNotFound` if a part's report is not in the first report's entity | none | Yes |
| `#extract_for` (private) | `company, report, start_date, end_date, user_id` | `PortfolioReportExtract` (never nil) | none (company errors are recorded, not raised) | May call the LLM when `generate_missing_extracts`; may create an empty extract | No |
| `#company_documents` (private) | `part, companies, ...` | `Array<Document>` in company order | none | Runs `PortfolioReportDocGenSilentJob#perform_now` per company; records errors | No |
| `#consolidated_file` (private) | `part, companies, run_dir` | `String` path or `nil` | none (error recorded) | Writes a `.docx` in `run_dir` | Yes |
| `#final_document` (private) | `sources, companies, first_part, ...` | `Document` or `nil` | none (error recorded) | Calls the merger | No |

**`GeneratePortfolioReportExtractsJob#generate_extract`** (Job method, modified; signature unchanged)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#generate_extract` | `portfolio_company, portfolio_report, start_date, end_date, user_id, notify: true` | `[extract, message_or_nil]`. `message_or_nil` is non-nil only when there was nothing at all to build from | none new | Creates the extract; with documents sends documents + notes as before; with no documents but notes or KPIs sends notes + `kpis`, and sends a `UserAlert` at level `warning` ("No documents found for <company> for <report>. Extract built from notes and KPIs."); with nothing at all, no LLM call | No: creates a new extract each call |
| `#kpi_lines` (private, new) | `portfolio_company, start_date, end_date` | `String` of lines "<name>: <display value, else value> (as of <date>)", or `""` | none | Reads approved KPIs of the company's KPI reports with `as_of` in the range | Yes |

**`DocLlmContext`** (Service, modified)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#populate_context_with_data` | `documents:, notes:, kpis: nil` (step keyword) | `true` | none new | Appends processed documents, then notes, then the `kpis` text when present | Yes |

**`PortfolioReportExtractsController#destroy`** (Action, new)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#destroy` | `id` | Redirect to `portfolio_report_extracts_path(portfolio_report_id:)` with notice "Portfolio report extract deleted successfully." | `RecordNotFound` (another entity's id), `Pundit::NotAuthorizedError` | Soft-deletes the extract (paranoid via `Trackable`) and its tear sheet presentation (`dependent: :destroy`) | A repeat finds nothing (not found) |

**`PortfolioReportConsolidatedDocGenerator`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.new(...).call` | `portfolio_companies, template (Document), start_date, end_date, user_id, output_dir:` | Path of the rendered `.docx` | Any Sablon/IO error (caller records it) | Writes the file and a logo copy into `output_dir`; **no** `Document`, **no** extract | Yes |

Private helpers added for the fund totals: `fund_totals(company_data_list)` (groups the companies' fund lines by fund, sums `Money` per fund, returns a decorated list) and `numeric_custom_field_names(companies)` (names of the `NumberField` and `Money` fields in the companies' distinct form types). Each entry's `custom_fields` is an `OpenStruct` of `name => BigDecimal` sums of the raw stored values over the fund's companies, blank as zero. Needs the fund id on each fund line and the company record behind each company hash. No new `TemplateDecorator` method.

**`PortfolioReportDocumentMerger`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call` | `sources` (ordered `Document` / `String`), `portfolio_report:, template:, company_count:, start_date:, end_date:, user_id:` | The saved combined `Document` | Merge / save errors | Downloads `Document`s to temp paths and deletes those temps; never deletes caller-supplied paths; saves under `/Portfolio Reports/Generated Portfolio Reports` | No: saves a new document each call |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (the job has no retry added; Sidekiq's default retry would re-run it, replacing company documents as it does today)
- [ ] `PortfolioReportDocGenerator` is unchanged from main
- [ ] The merger deletes only temp files it created itself
- [ ] `DocLlmContext` callers other than the extract job still work without `kpis:`
- [ ] With documents present, the arguments given to `DocLlmContext` are exactly today's (E13)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `PortfolioReportsController#legacy_bulk_generate_options` (no `mode`) | `portfolio_company_ids[]`, `back_to` | `bulk_generate?` | Options page | Redirect to company step when no companies |
| same, `mode=full_report` | `parts[<i>][portfolio_report_id]`, `parts[<i>][report_template_id]` (also the legacy `portfolio_report_id` / `report_template_id` when `parts` is absent), `start_date`, `end_date`, `generate_missing_extracts`, `portfolio_company_ids[]`, `back_to` | `bulk_generate?` | Redirect with "Queued report generation for N companies." | Backstop only: redirect to the company step with `alert:` (nothing preserved) |
| same, `mode=extracts_only` | as above plus `only_missing_extracts` | `bulk_generate?` | Redirect with the existing notices | Backstop only: redirect to the company step with the X14 alert |
| `PortfolioReportExtractsController#destroy` | `id` | `destroy?` (`create?` and the company admin role) | Redirect to the report's extract list with a notice | Not found (other entity) / Pundit refusal |
| `PortfolioReportsController#create` / `#update` | `portfolio_report: [..., :consolidated, ...]` | `create?` / `update?` | As today | As today |

Row rules the **server backstop** applies (checked in this order, first failure wins). The browser applies rules 3 and 4 and the Extracts Only rule before submitting (see below), so a real user never meets a server refusal:

| # | Rule | Failure |
|---|---|---|
| 1 | Rows = `params[:parts]` values ordered by `to_i` of the key; if `parts` is absent, one row from the legacy fields | n/a |
| 2 | Each row's report found via `policy_scope(PortfolioReport).find(id)` | 404 (X4) |
| 3 | Each row's `report_template_id` present | `redirect_to` the company step, alert "Choose a template for every report in the list." |
| 4 | `report_template_id`s unique across rows | same, "Each template can be used only once in a list. Remove the repeated template." |
| 5 | Each template in `portfolio_report.documents` | same, "The selected template does not belong to the chosen report." |

Browser rules (`report_parts_controller.js`): on every row change and on submit, a row with an empty template, or a template already used by an earlier row, gets `is-invalid` and a message under it and the form's submit is cancelled. For **Generate Extracts Only**, the submit is cancelled with the Extracts Only message when no row's selected report option has `data-consolidated="false"`. Messages are read from `data-` attributes on the rows container.

For `extracts_only`: distinct normal (`consolidated == false`) reports, one `GeneratePortfolioReportExtractsJob.perform_later` per report (the existing "only missing" filtering runs per report); if none are normal → redirect to the company step with "Consolidated reports don't use extracts, so there is nothing to generate."

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields; `parts` values are limited to the two ids
- [ ] A refused request enqueues nothing (assert in X1–X5)
- [ ] Every browser rule has a server twin (rules 3 to 5 and the Extracts Only rule) and a scenario for each (X1/X12, X2/X13, X5/X14)
- [ ] `destroy` finds the extract through `policy_scope` and calls `authorize`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Row report lookup | `policy_scope(PortfolioReport).find(id)` per row | PK | ≤ 5 rows | none needed |
| Row template check | `portfolio_report.documents.exists?(id:)` per row | PK + owner index | ≤ 5 | `exists?`, not `present?` |
| Options page | `entity.documents.where(owner_type: "PortfolioReport").includes(:owner)` (existing) and `policy_scope(PortfolioReport)` | existing | tens | `includes(:owner)` kept |
| Job part reports | `PortfolioReport.where(entity_id: first.entity_id).find(id)` per additional part | PK / `entity_id` | ≤ 4 | none |
| Company set | `entity.investors.portfolio_companies.where(id:)`, then sorted in Ruby by `investor_name` | `entity_id` | ≤ 100s | loaded once for the run |
| `kpi_lines` (no-documents extract) | `Kpi.approved.joins(:kpi_report).where(kpi_reports: { portfolio_company_id:, as_of: range })`; first the newest report id (`as_of DESC, id DESC`, `pick`), then its KPIs selecting `name`, `value`, `as_of`, ordered by `name` | `portfolio_company_id` / `as_of` on `kpi_reports` | Tens to hundreds per company (one report only), only when nothing else exists | `select` of the three columns; no `includes` |
| Widget | `@investor.portfolio_report_extracts.where.not(data: nil).where.not(data: "")` (plus `.where(portfolio_report_id:)` when the widget has one), `.order(end_date: :desc, id: :desc).first` | `portfolio_company_id` (and `portfolio_report_id`) | 1 row read, from a handful per company | `.first` on an ordered relation (a `LIMIT 1`), not a `present?` on the relation |
| Extract lookup (all actions) | `policy_scope(PortfolioReportExtract).find(id)` | PK + `entity_id` | 1 | none |
| Per-company data | Investments of the company up to the end date, its funds, one `FundRatio` query for IRR and MOIC, and the logo document, once per company per consolidated part | existing (`fund_ratios`, `portfolio_investments`) | per company | far fewer queries than a normal part; `as_of` is recomputed per investment |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not
- [ ] No `blank?` / `present?` on relations (use `exists?` / `none?`)
- [ ] No unbounded loads beyond the selected companies

---

## Transactions, Locking and Concurrency

N/A — no multi-row atomic write. Each `Document` save is independent, as today. Two simultaneous runs for the same companies and period can replace each other's same-named company documents (existing behaviour of `upload`), which this change does not alter.

**Reviewer checks**
- [ ] No external call or email inside a transaction (none is introduced)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `PortfolioReportJob` | `:low` (unchanged) | Options submit | Sidekiq default (unchanged) | Not discarded; first report missing raises | None (see above) | None added |

- Signature: `perform(portfolio_report_id, template_id, start_date, end_date, user_id, portfolio_company_ids: nil, generate_missing_extracts: false, additional_parts: [])`. The first five and the two existing keywords are unchanged so jobs serialised before deploy deserialise and run as a one-row list (E9). `additional_parts` elements are JSON-safe hashes with string keys `"portfolio_report_id"` and `"template_id"`.
- Run folder `tmp/portfolio_report_packet/<SecureRandom.hex(8)>` is created at the start and removed in `ensure` (as `PortfolioReportDocumentMerger` already does for its own working folder).

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (it replaces/re-saves; no unique constraint is hit)
- [ ] An enqueued old-signature job performs (E9)
- [ ] No new cron entries

---

## External Integrations

N/A — nothing external is added. `DocumentGeneratorBase#convert` is called with `to_pdf: false`, so LibreOffice is not invoked by the new generator. The LLM is called only by the existing extract path for normal parts when "Generate missing report extracts" is on.

**Reviewer checks**
- [ ] The consolidated generator never reaches `DocLlmContext`

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Any error building a company piece | `PortfolioReportDocGenSilentJob` (collected in `error_msg`) | `PortfolioReportJob` appends `{ msg:, model: }` | Red toast + email: names company and template | `Rails.logger.error` (existing) |
| Any error in the consolidated generator | `PortfolioReportConsolidatedDocGenerator#call` | `PortfolioReportJob#consolidated_file` `rescue StandardError` → error "Error generating <template> (consolidated): <message>" | Same | `Rails.logger.error` with report, template and user ids |
| Merge / save error | `PortfolioReportDocumentMerger` / `DocxMerger` | `PortfolioReportJob#final_document` (existing text "Error merging portfolio report documents for report …") | Same; company reports remain | `Rails.logger.error` |
| `RecordNotFound` on a part's report | `PortfolioReportJob#parts` | Not rescued: the run fails loudly (tampering or deletion) | Sidekiq failure | Sidekiq error tracking |
| Refusals (rows) | Browser (`report_parts_controller.js`) | Inline message, submit cancelled | Messages in the proposal | none |
| Refusals (rows), tampered request | Controller | Redirect to the company step with `alert:` | Same messages | none |
| No documents, but notes or KPIs | `GeneratePortfolioReportExtractsJob#generate_extract` | Not an error: `warning` `UserAlert` | Amber toast (a bulk run sends one toast listing every such company, at the end) | `Rails.logger.debug` |
| Nothing at all to extract from | same | Returned message goes to the run's error list (as today) | Danger toast + email | `Rails.logger.debug` (as today) |
| Another entity's extract id | `PortfolioReportExtractsController` | `RecordNotFound` through `policy_scope` | Not found page | Rails default |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently (each rescue records into `@errors` and logs)
- [ ] Log lines carry report id, template id and company id where known

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `authorize PortfolioReport.new(entity_id:), :bulk_generate?` on the action (unchanged); no new action |
| Tenant isolation | Reports via `policy_scope`; templates via `portfolio_report.documents`; companies via `Investor.where(entity_id:)`; the job re-scopes each additional part's report and the company set to the first report's entity |
| Secrets | none |
| Input / output sanitisation | Template rendering is Sablon, unchanged. Alert text built from template and company names is rendered `html_safe` by `UserAlert`; names are escaped before interpolation into the new error strings (existing messages interpolate raw — keep parity and escape only the new ones) |
| Extract access | `set_portfolio_report_extract` looks the extract up through `policy_scope` (entity scoped) before `authorize`. Today it uses `PortfolioReportExtract.find`, and `create?` checks the role only, so any permissioned user could address another entity's extract; a destructive `destroy` makes that unacceptable. The change also protects show, edit and update |
| Mass assignment | `:consolidated` added to the report params; `parts` values pick only `portfolio_report_id` and `report_template_id` |
| Temp files | Random folder under `tmp/`, removed in `ensure` |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route or job argument (X4, X10 prove it)
- [ ] New error strings escape user-supplied names
- [ ] A user of another entity cannot show, edit, update or destroy Alpha's extract (X16 proves destroy)
- [ ] The new warning text escapes the company and report names

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None; invisible until a report is marked consolidated or a second row is added |
| Cron / schedules | None |
| Deploy order | migration → code. Jobs queued across the deploy still run (E9) |
| Rollback | Redeploy the previous code; the extra column is harmless. Reports already ticked consolidated simply show no tick. No data cleanup needed |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/consolidated_portfolio_report.feature` (H1–H4, E1, E4) | Fixture `cover_and_summary_template.docx`; `stub_doc_llm_context_call` (existing) | Existing Background (user, entity, portfolio companies, KPI mappings, fund) | `Given a consolidated portfolio report "..." with template "..."`, `When the consolidated report is built for the selected companies`, `Then the document text lists "..." in order`, `Then no extract exists for ...` |
| `features/fund/portfolio_report_combined_packet.feature` (H5, E2, E3, E5, E7, E9, E10, E11, X6–X9) | Fixtures above plus `legal_disclaimer_template.docx`; stubs that make a named generator or `DocxMerger.merge` raise | Existing; a `:portfolio_report` with `consolidated: true` | `When I run the portfolio report with rows "..."`, `Then the combined document text is in order "..."`, `Then the combined document package is intact`, `Then no document exists for the consolidated part`, `Given generating "..." for "..." will fail` |
| `features/fund/portfolio_report_parts_list.feature` (H7–H10, E6, E8, E17, X1–X5, X10–X14) | JS driver as the bulk page features use (X1, X2, X5, E17); direct requests for the backstop (X3, X12–X14); second entity and user | Existing | `When I add a report row`, `When I remove report row 2`, `Then the options page has N rows`, `When I post rows numbered 0, 2 and 5`, `Then nothing is queued`, `Then I should see "..." beside row N`, `Then no request is sent` |
| `features/fund/portfolio_report_extracts.feature` (H11–H13, E12–E16, E18, X15, X16) | `stub_doc_llm_context_call` extended to record the `documents`, `notes` and `kpis` it was given; JS driver for the Delete popup | Existing Background plus a company with notes and KPIs and no documents; extracts with and without data | `Given the company has notes and KPIs but no documents`, `Then the LLM was given notes and KPIs`, `Then the LLM was given no KPIs`, `Then the dashboard widget shows the extract ending ...`, `When I delete the extract and confirm`, `Then the extract no longer exists` |
| `features/fund/bulk_portfolio_report.feature` (H6) | unchanged | unchanged | none (comment only) |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Template checks use `exists?`; company set is an Array after sorting |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | Row and company counts are small and already loaded; no bulk write |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No account entries touched |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | The options page keeps its existing `date_field`s (no new human-format dates). The combined document name keeps the ISO `start to end` shape used by company documents today. The error email is the existing one |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | No new date inputs; the new Stimulus controller handles no dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tool exposes portfolio reports in this change; confirm by running `features/ai/mcp_server/mcp_ontology.feature` once in phase 1 |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | All verification is Cucumber with a random `TEST_ENV_NUMBER`; Redis up on 6379 |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on every modified Ruby file at the end of each phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
