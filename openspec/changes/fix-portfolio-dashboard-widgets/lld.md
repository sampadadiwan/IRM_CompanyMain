# Fix Portfolio Dashboard Widgets — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/ui/dashboard-widgets/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

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

- **Month list needs the real policy, so full records are loaded** — `KpiReportPolicy#show_performance?` reaches `record.owner` and access rights, so a narrow `select` would break it. See [Queries and Indexes](#queries-and-indexes).
- **`show_menu:` is removed from three helper signatures** and from two view call sites; any caller not found by grep would raise `ArgumentError`. See [File Map](#file-map).
- **Budget View is removed from the Kpis form** (a saved value is ignored at render); `_kpis_grid_view` is unchanged. A Kpis widget saved with `budget_view: true` keeps showing the grid; the table is the Kpis Budget vs Actual widget. Renaming the frame `kpi_reports_budget` is rejected because it would collide with the Kpis grid widget. See [design decision 4](design.md#design-decisions).
- **The menu row is skipped entirely when no widget has Show Menu**, taking the Reports drop-down and layout selector with it (accepted); the logo/title/sector heading in the same `<nav>` must still render. See [design decision 11](design.md#design-decisions).
- **Group by forces the AG grid** even when Ag = OFF is saved explicitly. See [design decision 7](design.md#design-decisions).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/base/models/dashboard_widget.rb` | Modified | Add `METADATA_FIELD_HINTS`, `.field_hint`; remove the settings that never worked from the `metadata_help` strings of Kpis, Kpis Performance Table, Key Kpis, and both Documents widgets (Portfolio Company and Investor dashboards) |
| ② | `app/packs/core/base/views/dashboard_widgets/_metadata_fields.html.erb` | Modified | Use hint label/help/integer/choices |
| ② | `app/javascript/controllers/metadata_form_controller.js` | Modified | Integer key guard + paste cleanup; keep `<select>` handling |
| ③ | `app/packs/core/base/helpers/dashboard_widgets_helper.rb` | Modified | Drop `show_menu:` from `dashboard_widgets`, `configured_dashboard_widgets`, `lp_layout_widgets`; add `dashboard_menu_widgets`, `metadata_choices` |
| ④ | `app/packs/core/base/views/dashboard_widgets/_dashboard.html.erb` | Modified | Call `dashboard_widgets` once; menu from `dashboard_menu_widgets`; skip the `nav-pills` row when it is empty (logo/title header stays); body from the same local |
| ④ | `app/packs/core/investors/views/investors/multi_portfolio_dashboard.html.erb` | Modified | Same change at its menu call (line 28) and body call (line 90) |
| ⑤ | `app/packs/startups/kpis/controllers/kpi_reports_controller.rb` | Modified | `show_performance`: build `@report_months`, default `@as_of`; when two reports share a date (Actual and Budget) pick the one the viewer may see, else the first (so a direct request is still refused, X2) |
| ⑤ | `app/packs/startups/kpis/views/kpi_reports/performance_table.html.erb` | Modified | Options from `@report_months`; "no reports at all" message; nearest-months fallback |
| ⑤ | `app/packs/core/investors/views/investors/widgets/_kpis_grid_view.html.erb`, `_kpis_budget_vs_actual.html.erb`, `_kpi_key_numbers.erb`, `_performance_table.html.erb` | Reused | No code change |
| ⑥ | `app/packs/core/investors/views/investors/widgets/_documents.html.erb` | Modified | X1 leak fix: a Folder ID the viewer may not see (not `FolderPolicy#show?`, not shared with them as an investor) shows "No documents to show." and makes no frame request |
| ⑥ | `app/packs/core/documents/helpers/document_helper.rb` | Modified | Add `widget_folder_visible?(folder_id, user)`; the widget passes `show_root_docs` unless the viewer is a company admin of the folder's entity (`belongs_to_entity_id?` + `company_admin`, as in `get_tree_view_folders`), so the documents in the folder itself are listed (true when `FolderPolicy#show?` allows it or `Folder.for_investor` lists it); `DocumentsController` is left as it is (shared with the investor data-room flows) |
| ⑦ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/widgets/_portfolio_investments.html.erb` | Modified | AG frame when `ag` or `group_by_column`; grouping by `fund_name` also passes `show_fund_name` so the grid carries that column |
| Tests | `features/core/dashboard_widget_menu.feature`, `features/core/documents_widget.feature`, `features/startup/kpi_dashboard_widgets.feature`, `features/fund/portfolio_investments_widget_group_by.feature` | New | Scenarios per [Worked examples](design.md#worked-examples) |
| Tests | `features/core/dashboard_widget_metadata.feature`, `features/misc/multiple_portfolio_dashboard.feature` | Modified | Extend with H3–H6, H8, E5, E8–E11 |
| Tests | `features/step_definitions/dashboard_widget_menu_steps.rb`, `dashboard_widget_kpi_steps.rb`, `dashboard_widget_group_by_steps.rb` | New | Steps for the above |

**Reviewer checks**
- [ ] Every class in the design's [class diagram](design.md#class-diagram) has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`)
- [ ] `grep -rn "show_menu:" app` finds no remaining caller of the removed argument (the `DashboardWidget` column, form checkbox, import and export keep `show_menu`)
- [ ] Before creating each new `.feature` / step file, confirm the path does not already exist (Write replaces silently)

---

## Schema Detail

N/A — no table, column or index changes. `dashboard_widgets.show_menu` (boolean, default true, not null), `enabled` and `metadata` are used as they are.

**Reviewer checks**
- [ ] `git diff` shows no change under `db/`

---

## Method Contracts

**`DashboardWidget`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.field_hint(widget_name, key)` | String, String or Symbol | Hash `{label:, hint:, integer:, choices:}` (any key may be absent) or `nil` | none | none | Yes (pure lookup) |

`METADATA_FIELD_HINTS` (frozen, keyed by widget name then key string) holds exactly these entries; strings are the text QA verifies:

| Widget | Key | `label` | `hint` | Other |
|---|---|---|---|---|
| Kpis | `compound` | Data-only view | ON groups KPIs by category and shows data only (chart selection is off). OFF shows the full table with a plot checkbox per KPI. | |
| Kpis | `show_action_buttons` | Show action buttons | ON shows the heading and the filter, chart and settings buttons above the table. OFF by default. | |
| Kpis Budget vs Actual | `category` | Default category | Category pre-selected in the filter above the table. | |
| Documents | `owner_id` | Owner ID | Whole number: the ID of the Investor or Valuation whose documents to show. Leave empty for this company. | `integer: true` |
| Documents | `folder_id` | Folder ID | Whole number: the ID of any folder you may see. Leave empty for the company's own folder. | `integer: true` |
| Portfolio Investments | `group_by_column` | Group by column | Rows are grouped by this column. Choosing one uses the AG grid, whatever the Ag setting. | `choices: :portfolio_investment_columns` |

Settings removed from the `metadata_help` strings: Kpis Performance Table `chart`; Key Kpis `kpis`; Kpis `show_table`, `show_chart`, `budget_view`; Documents `entity_id`. Values already saved are cleared by a one-off script outside this change; until then the key shows in that widget's edit form as an ordinary field and rendering ignores it.

**`DashboardWidgetsHelper`** (Helper)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#dashboard_widgets(dashboard_name, entity_id, name:, owner:, tag_list:, lp:)` | as today minus `show_menu:` | Ordered Hash `"widget tags" => DashboardWidget` | `NoMethodError` if `dashboard_name` is unknown (as today) | none | Yes |
| `#dashboard_menu_widgets(widgets)` | Hash from above | Hash subset where `show_menu` is true | none | none | Yes |
| `#metadata_choices(source, entity)` | Symbol, Entity | `[[label, key], …]`; `[]` for an unknown source | none | none | Yes |

`metadata_choices(:portfolio_investment_columns, entity)`: take `entity.form_types.find_by(name: "PortfolioInvestment")&.ag_selected_columns`, falling back to `PortfolioInvestment.ag_grids_default_columns`; map each `{label:, key:}` to `[label, key]`; append `["Fund Name", "fund_name"]` if no entry has key `fund_name`; drop duplicate keys. No report-specific columns (the widget passes no `report_id`).

**`KpiReportsController#show_performance`** (Controller) — see next section.

**Reviewer checks**
- [ ] Every caller of `dashboard_widgets` is found by grep and none passes `show_menu:` (callers: `_dashboard.html.erb`, `multi_portfolio_dashboard.html.erb`, `investors/dashboard.html.erb`, and the entity landing partials)
- [ ] The default widgets reach `dashboard_menu_widgets` with `show_menu == true` (`DashboardWidget.new` takes the column default)
- [ ] The hint strings above are the ones in `qa-checklist.md`

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `KpiReportsController#show_performance` | `portfolio_company_id`, `as_of`, `metric_names`, `decimals` (unchanged) | `show_performance?` per report for the month list; `authorize @kpi_report` for the chosen one (unchanged) | renders `performance_table` inside frame `performance_table_frame` | Pundit refusal for the chosen report as today; "No KPI reports have been uploaded for this company yet." / "No KPI report found for the specified date. Try any of the dates below" in the body |
| `DashboardWidgetsController#metadata_help` | unchanged | unchanged | turbo stream renders the same `_metadata_fields` partial | — |

`show_performance` flow: build `@report_months` (distinct `as_of`, newest first, only reports allowed by `show_performance?`); `@as_of` = parsed `params[:as_of]` if present, else `@report_months.first`, else last month's end; `@kpi_report` = `KpiReport.find_by(portfolio_company_id:, as_of: @as_of)` (unchanged, still authorized); render. The "try these dates" list is the up-to-five months in `@report_months` nearest to `@as_of` (a sort by absolute day distance), replacing the fixed `(1..5)` months back. The portfolio company lookup stays `Investor.find`.

The select's option values are the report dates themselves (not `end_of_month`), so mid-month report dates (E19) match `find_by`.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`: the chosen report is still authorized; the month list uses the policy per report
- [ ] No new permitted params; the integer guard is client-side only, and server code still treats `folder_id`/`owner_id` as arbitrary strings that `Folder.find` / ids handle as today

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `show_performance` month list | `KpiReport.where(portfolio_company_id: id).where.not(as_of: nil).order(as_of: :desc)` loaded as full records, then `select { |r| policy(r).show_performance? }`, then `map(&:as_of).uniq` | `index_kpi_reports_on_portfolio_company_id_and_as_of` | ≤ ~150 (months × tag × period) | none; see note |
| `dashboard_widgets` | same single query as today (`DashboardWidget.enabled.where(dashboard_name:, name:, entity_id:)`), minus the second menu query | existing | ≤ ~40 | none |
| `metadata_choices` | one `form_types` lookup per form render | existing | 1 | none |

Note — why full records: `KpiReportPolicy#show?` → `permissioned_employee?` calls `get_model_with_access_rights`, which reads `record.owner` and `record.model_with_access_rights`, and `belongs_to_entity?` reads `entity_id`. A narrow `select(:id, :as_of, …)` would raise `MissingAttributeError` or silently misjudge. For a company admin of the owning entity the policy returns early on a cached role; for other employees it can issue an access-rights lookup per report. That is acceptable at ≤ ~150 rows on an interactive load. If measurement (task T3.5) shows more than ~30 queries on a 100-report company, switch to: `policy_scope(KpiReport)` for fund users plus an Actual-tag filter for portfolio-company users, which duplicates two policy rules and is why it is not the first choice.

`where.not(as_of: nil)`: `as_of` is nullable in the schema.

**Reviewer checks**
- [ ] Every query is scoped by `portfolio_company_id` and then by policy; no cross-entity listing
- [ ] No `present?`/`blank?` on a relation: the month query is loaded to an array first
- [ ] Query count measured for a company with 100 reports across several tags

---

## Transactions, Locking and Concurrency

N/A — no writes are added. The form's single save is the existing `DashboardWidget` update.

**Reviewer checks**
- [ ] No new write path

---

## Background Jobs

N/A — no jobs or cron entries.

**Reviewer checks**
- [ ] Nothing enqueued

---

## External Integrations

N/A — no third-party calls.

**Reviewer checks**
- [ ] No new outbound HTTP

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError` | `show_performance` (`authorize @kpi_report`) | App-wide rescue (unchanged) | Standard not-authorised response | As today |
| `ActiveRecord::RecordNotFound` | `Folder.find` / `Investor.find` | App-wide handler (unchanged) | Standard 404 in the frame | As today |
| `ArgumentError` (unknown keyword `show_menu:`) | Any missed caller of the old helper signature | none — caught by the grep review check and Cucumber | n/a | Fails in test, not in production |
| `ArgumentError`/`Date::Error` on a bad `as_of` | `Date.local_parse` | unchanged | as today | as today |

**Reviewer checks**
- [ ] No new `rescue` anywhere; nothing swallows an error

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Chosen report authorized as today; month list filtered by `show_performance?`; widget form actions keep `DashboardWidgetPolicy`; documents keep `policy_scope(Document)` |
| Tenant isolation | `dashboard_widgets` filters `entity_id`; months limited to one company and then policy; choices from the current entity's own form type; `Folder.find` is unscoped in `DocumentsController`, and with another entity's Folder ID the widget's folder tree named that entity's folders (X1 found this); the widget now only uses its own entity's folder or one shared with the viewer (`widget_folder_visible?`) |
| Secrets | None |
| Input / output sanitisation | Labels, hints and options pass through ERB escaping; the saved group value is read by the grid as a column name and is never evaluated. `metadata` still goes through `ApplicationRecord.safe_eval!` before `eval` (unchanged) |
| Mass assignment | `dashboard_widget_params` unchanged; the form can still not set `entity_id` beyond the existing hidden fields |

**Reviewer checks**
- [ ] A Beta Fund user cannot reach Acme's widgets, report months or documents through the form, the page, the frame URLs or a direct request
- [ ] The integer guard is not the only validation anyone relies on

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | none |
| Cron / schedules | none |
| Deploy order | single deploy, code only; confirm whether `metadata_form_controller.js` needs an asset rebuild (importmap vs esbuild bundle) and include it if so |
| Rollback | Revert the deploy. This change does not alter saved data. |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] JS build path for `metadata_form_controller.js` identified

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/dashboard_widget_menu.feature` | none (rack_test; no network) | `:entity`, `:user`, `:investor` (Portfolio Company), `DashboardWidget.create!` | `dashboard_widget_menu_steps.rb`: `Given the dashboard has widgets …`, `Then the menu lists …`, `Then no menu row is shown` |
| `features/core/dashboard_widget_metadata.feature` (extended) | existing `@javascript` driver | existing | reuse existing steps; add `Then the field {string} should have the label {string}`, `… helper text {string}`, `When I type {string} into {string}` |
| `features/startup/kpi_dashboard_widgets.feature` | none | `:kpi_report` (Actual/Budget), `:kpi`, `:investor_kpi_mapping` | `dashboard_widget_kpi_steps.rb` (reuse `performance_table_steps.rb` setup where it fits) |
| `features/core/documents_widget.feature` | none | `:folder`, `:document` | in `dashboard_widget_menu_steps.rb` or a small shared file |
| `features/fund/portfolio_investments_widget_group_by.feature` | none | `:portfolio_investment`, `:fund`, `:investment_instrument` | `dashboard_widget_group_by_steps.rb`: assert the frame `src` of the rendered widget |
| `features/misc/multiple_portfolio_dashboard.feature` (extended) | existing | existing | reuse |

Run each with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber <file>` (Redis up on 6379).

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | The month query is converted to an array before any `empty?`; `dashboard_widgets` already loads widgets first |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | N/A | Rows ≤ ~150 and the policy needs full records; dedup is on `as_of` in Ruby after policy |
| Select only needed columns when loading many `account_entries` | N/A | No `account_entries` involved |
| Screen dates via `l(...)`; no human-format `strftime` | Applies | Option labels use `l(as_of, format: :month_year)`, the format already used on this page |
| Date inputs use `f.date_field`; JS dates via `locale_date_format.js` | N/A | No date inputs added |
| Every query entity-scoped; Pundit on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP surface touched |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | See Test Plumbing |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run on the modified Ruby files; ERB and JS are not covered by RuboCop |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
