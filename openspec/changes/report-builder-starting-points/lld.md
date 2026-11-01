# Report Builder starting points — Low-Level Design

> **Audience:** The engineer implementing and the reviewer. **Companion documents:** [Design](design.md) · [Business rules](business-rules.md) · [Tasks](tasks.md)

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Template file](#template-file)
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

| Area | Risk | Look at |
|---|---|---|
| Spec applier | Medium — writes reports; must roll back fully | [Transactions](#transactions-locking-and-concurrency) |
| Validator vs catalog | Medium — must accept exactly what the builder accepts | [Method Contracts](#method-contracts) |
| Removing Apply Template | Low — deletes a feature and its Phase 1 scenarios | [File Map](#file-map) |
| Templates' columns | Low — checked against the catalog; drift guard keeps them so | [Template file](#template-file) |

---

## File Map

| Box | Path | New / Modified / Removed | What |
|---|---|---|---|
| ① | `app/packs/core/base/views/reports/_new_report.html.erb` | Modified | "Builder Report" → **New report** dropdown (From a template, Guided setup) |
| ① | `app/packs/core/base/views/reports/_cards.html.erb`, `_index.html.erb` | Modified | Remove "New Custom Report" |
| ① ⑥ | `app/packs/core/base/views/reports/_card.html.erb` | Modified | "Guided Wizard" → "Guided setup"; **Duplicate** (builder reports) |
| ② | `config/report_builder_templates.yml` | New | The ten templates |
| ② | `app/packs/core/base/models/report_builder_templates.rb` | New | Load, list per entity, find |
| ② | `app/packs/core/base/models/report_builder_model_discovery.rb` | Modified | `pack_enabled_for?` public |
| ② | `config/initializers/report_builder.rb` | Modified | Reset the template cache with the catalog's |
| ③ ⑥ | `app/packs/core/base/controllers/concerns/report_builder/starting.rb` | New | `templates`, `create_from_template`, `duplicate` |
| ③ | `app/packs/core/base/controllers/report_builder_controller.rb` | Modified | Include `ReportBuilder::Starting`; remove `apply_template`, `report_templates`; `duplicate` in `set_report` |
| ③ | `app/packs/core/base/views/report_builder/templates.html.erb`, `_template_card.html.erb`, `_template_modal.html.erb` | New | Template page |
| ③ | `app/packs/core/base/views/report_builder/_builder_header.html.erb`, `_builder_modals.html.erb` | Modified | Remove Templates button and `#templateModal` |
| ③ | `app/packs/core/base/helpers/report_builder_helper.rb` | Modified | Remove `apply_template_summary` |
| ④ | `app/packs/core/base/models/report_spec_validator.rb` | New | `errors_for` |
| ⑤ | `app/packs/core/base/models/report_spec_applier.rb` | New | `apply!`, `spec_from`, `Invalid` |
| ⑤ | `app/packs/core/base/models/report_builder_fund_target.rb` | New | Where a fund filter goes |
| ⑤ | `app/packs/core/base/controllers/concerns/report_builder/wizard.rb` | Modified | `wizard_fund_targets` → `ReportBuilderFundTarget.for` |
| ⑥ | `app/packs/core/base/views/report_builder/view.html.erb` | Modified | **Duplicate** next to Edit Builder |
| ⑧ | `app/packs/core/base/models/report_builder_health_check.rb` | Modified | Fund-rows note |
| ST2 | `app/packs/core/base/views/report_builder/wizard/*.html.erb`, `new.html.erb` | Modified | Titles "Guided setup"; "New report" |
| Routes | `config/routes/core.rb` | Modified | `templates`, `templates/:key`, `:id/duplicate`; remove `:id/apply_template` |
| Tests | `features/core/report_builder/{starting_points,templates,templates_check,duplicate}.feature` | New | business-rules IDs |
| Tests | `features/step_definitions/report_builder_starting_steps.rb` | New | Steps |
| Tests | `features/core/report_builder/builder_ui.feature`, `report_builder_ui_steps.rb` | Modified | Remove Apply Template scenarios (trust H23, E26) and their steps |
| Docs | `docs/user_guides/report_builder_user_guide.md` | Modified | New report, templates, Duplicate, FAQs |

---

## Template file

Keys checked against `ReportBuilderColumnCatalog` on 2026-10-31 (dev). Totals not given use `ReportBuilderColumnType#default_aggregate`. `cc.` = `capital_commitments.`.

| Key | Area · fund | Columns (in order) | Related data | Filters | Formulas (key: expression) | Sort · grouping |
|---|---|---|---|---|---|---|
| `lp_capital_account` | Investors · required | `investor_name`, `category`, `city`, `tag_list`, `cc.committed_amount` Committed, `cc.call_amount` Called, `cc.collected_amount` Collected, `cc.distribution_amount` Distributed, `cc.folio_id` (count) # Commitments, formula `called_pct`, `unpaid`, `uncalled` | `capital_commitments` | `category_eq: LP` | `called_pct`: `IF([cc.committed_amount] > 0, [cc.call_amount] / [cc.committed_amount] * 100, 0)` · `unpaid`: `[cc.call_amount] - [cc.collected_amount]` · `uncalled`: `[cc.committed_amount] - [cc.call_amount]` | `unpaid` desc |
| `fund_scorecard` | Fund overview · none | `name`, `currency`, `category`, `first_close_date`, `cc.committed_amount` Committed, `cc.folio_id` (count) # Commitments, `capital_calls.call_amount` Called, `capital_calls.call_date` (max) Last call, `capital_distribution_payments.net_payable` Distributed net, `capital_distribution_payments.payment_date` (max) Last distribution, `portfolio_investments.portfolio_company_name` (list) Portfolio companies, formulas | `capital_commitments`, `capital_calls`, `capital_distribution_payments`, `portfolio_investments` | — | `called_pct`: called ÷ committed × 100 (IF guard) · `dist_to_called`: `IF([capital_calls.call_amount] > 0, [capital_distribution_payments.net_payable] / [capital_calls.call_amount], 0)` | `cc.committed_amount` desc |
| `fundraising_by_close` | Fund overview · none | `name`, `currency`, `first_close_date`, `last_close_date`, pivot `capital_commitments` | `capital_commitments` pivot `[fund_close, unit_type]` × `committed_amount`, sum | — | — | `name` asc |
| `call_collection` | Capital calls · required (root) | `fund.name` Fund, `name`, `call_date`, `due_date`, `percentage_called`, `call_amount`, `collected_amount`, pivot `capital_remittances` | `fund` (one per row), `capital_remittances` pivot `[status]` × `call_amount`, sum | fund | — | `due_date` desc |
| `overdue_chase` | Capital calls · required (root) | `investor_name`, `investing_entity_name`, `folio_id`, `remittance_date`, `call_amount`, `collected_amount`, `arrear_amount`, `status`, `capital_remittance_payments.amount` Received, `capital_remittance_payments.payment_date` (max) Last payment, `capital_remittance_payments.reference_no` (list) Payment refs, formula `shortfall` | `capital_remittance_payments` | `status_in: [Overdue, Pending]`; fund | `shortfall`: `[call_amount] - [collected_amount]` | `remittance_date` asc · group by `investor_name` |
| `distribution_statement` | Distributions · required (root) | `investor_name`, `investor_kyc_full_name`, `folio_id`, `fund_close`, `unit_type`, `committed_amount`, `capital_distribution_payments.gross_payable`, `.cost_of_investment_with_fees` Return of capital, `.income_with_fees` Income, `.reinvestment_with_fees` Reinvestment, `.net_payable`, `.payment_date` (max) Last paid, `capital_remittances.collected_amount` Paid-in, formulas | `capital_distribution_payments` (`completed_eq: true`), `capital_remittances` | fund | `deductions`: gross − net · `dpi`: `IF([capital_remittances.collected_amount] > 0, [capital_distribution_payments.net_payable] / [capital_remittances.collected_amount], 0)` | `investor_name` asc · group by `fund_close` |
| `lp_holdings` | Investors · required (both related) | `investor_name`, `category`, pivot `capital_commitments`, `fund_units.quantity` Units held, `fund_units.amount` Unit value, `fund_units.issue_date` (max) Last allotment | `capital_commitments` pivot `[unit_type]` × `committed_amount`, sum; `fund_units` | `category_eq: LP`; fund on both | — | `investor_name` asc |
| `unverified_kyc` | Compliance · optional (commitments, remittances) | `full_name`, `investor_name`, `kyc_type`, `verified`, `aml_status`, `expiry_date`, `docs_completed`, `completed_by_investor`, `cc.committed_amount` Committed, `cc.folio_id` (count) # Folios, `capital_remittances.collected_amount` Money received | `capital_commitments`, `capital_remittances` | `verified_eq: false` | — | `cc.committed_amount` desc |
| `portfolio_moic` | Portfolio · required (root) | `portfolio_company_name`, `investment_instrument_name`, `bought_amount`, `sold_amount`, `fmv`, `gain`, `unrealized_gain`, `portfolio_investments.investment_date` (min) First investment, `portfolio_investments.amount` (count) # Transactions, formula `moic` | `portfolio_investments` | fund | `moic`: `IF([bought_amount] > 0, ([fmv] + [sold_amount]) / [bought_amount], 0)` | `portfolio_company_name` asc · group by `portfolio_company_name` if stored, else none |
| `kpi_matrix` | Portfolio · none | `entity_name` Company, `as_of`, `period`, `tag_list`, pivot `kpis` | `kpis` pivot `[name]` × `value`, latest | `period_eq: Quarter` | — | `as_of` desc |

Changes from plan Appendix A, found while checking: "# Payments" (overdue_chase) dropped — no spare column to count; "Last activity" (portfolio_moic) dropped — the same date column can't hold both min and max; KPI matrix has no Excel grouping — "For" is a display-only column.

---

## Schema Detail

N/A — no tables or columns change.

**Reviewer checks**
- [ ] No migration in the diff

---

## Method Contracts

**`ReportBuilderTemplates`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.all` | — | `{key => template}` (symbolized, frozen) | `Psych::SyntaxError` at load | Memoized | Yes |
| `.available_for(entity)` | Entity | `{area => [template]}` in area order | — | — | Yes |
| `.find(key, entity)` | String, Entity | template or nil (nil when not available to the entity) | — | — | Yes |
| `.reset!` | — | — | — | Clears memo | Yes |

**`ReportSpecValidator`**

| Method | Arguments | Returns | Raises |
|---|---|---|---|
| `.errors_for(spec, entity:, name:)` | Hash, Entity, String | `["<name>: <problem>"]`, empty when valid | — |

**`ReportSpecApplier`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.apply!(report:, spec:, fund: nil, validate: true)` | unsaved Report (its name prefixes errors), Hash, Fund; `validate: false` for Duplicate | the saved Report | `ReportSpecApplier::Invalid` (errors) | Saves report + GVPs in one transaction | No |
| `.spec_from(report)` | Report | spec Hash | — | — | Yes |

**`ReportBuilderFundTarget`**

| Method | Returns |
|---|---|
| `.for(config)` | `{root: true, relations: []}` or `{root: false, relations: [String]}` |

**Reviewer checks**
- [ ] `apply!` never leaves a report without its columns (transaction)
- [ ] `spec_from(report)` round-trips: `spec_from(apply!(spec))` equals `spec` (fund aside)
- [ ] Validator uses the catalog calls the builder uses — no second allow-list

---

## Controllers, Params and Responses

| Action | Params | Authorize | Success | Failure |
|---|---|---|---|---|
| `GET templates` | `q` (search, client-side only) | `Report.new(entity:) create?` | 200 page | — |
| `POST templates/:key` | `name`, `fund_id` | `create?` on the new report | 302 → `edit_report_builder_path`, notice "Created from <template>" | 302 → templates, alert "That template isn't available" (unknown / not available); 422 page with "Choose a fund — this template adds up amounts"; Access denied (other company's fund — the app's `RecordNotFound` handler); 302 → templates, alert "That template can't be used right now" (Invalid) |
| `POST :id/duplicate` | — | `update?` on the original; `create?` on the copy | 302 → builder, notice "Copied from <name>" | Pundit refusal (other company); 302 back, alert "Only Report Builder reports can be duplicated" |
| `POST :id/apply_template` | — | — | Removed (404) | — |

---

## Queries and Indexes

| Query | Where | Bound |
|---|---|---|
| `Fund.where(entity_id:).order(:name)` | Template page, create | Entity's funds |
| `Report.where(entity_id:, name: candidates)` | Duplicate name | One query with `IN` over "Copy of X", "(2)"…"(20)" |

No new indexes.

---

## Transactions, Locking and Concurrency

| Operation | Scope | Lock | Race | Handling |
|---|---|---|---|---|
| `apply!` | Report save + all GVP inserts | None (new rows) | Two Creates | Two reports — correct |
| Duplicate name | Read names then insert | None | Two Duplicates at once may both pick "Copy of X (2)" | Names aren't unique in the DB; acceptable, the user renames |

**Reviewer checks**
- [ ] Validation runs inside the transaction before any write

---

## Background Jobs

N/A — everything is synchronous and small.

## External Integrations

N/A.

---

## Error Mapping and Logging

| Error | Source | Response | Logged |
|---|---|---|---|
| Unknown / unavailable template | `ReportBuilderTemplates.find` → nil | alert | No |
| Missing required fund | Controller | 422 page | No |
| Other company's fund | `find` → `RecordNotFound` | Access denied redirect (`WithAuthentication#deny_access`) | No |
| `ReportSpecApplier::Invalid` | Validator | alert "can't be used right now" | `Rails.logger.error` with the errors |
| Pundit | Policy | Standard refusal | As today |

---

## Security Review

| Item | Check |
|---|---|
| Tenant isolation | Funds scoped by `entity_id`; Duplicate needs `update?` (same entity) |
| Input → code | Template key looked up in a hash; spec tables from `ReportBuilderModelDiscovery.roots` and reflections only; no `constantize` on params |
| Mass assignment | Only `name`, `fund_id` read |

**Reviewer checks**
- [ ] A user of another entity can't duplicate a report, use another entity's fund, or see templates of a disabled pack

---

## Configuration and Rollout

| Item | Detail |
|---|---|
| Config | `config/report_builder_templates.yml` (reviewed content) |
| Flag | None |
| Rollout | Deploy |
| Rollback | Revert. Reports created from templates or by Duplicate are ordinary reports and keep working. |

---

## Test Plumbing

| Feature | Fixtures | Steps file |
|---|---|---|
| `starting_points`, `templates`, `templates_check`, `duplicate` | Phase 1 Acme fixture; extras: Beta Fund (E8, X2), Funds off (E2), C4 on K2 (E3), a schedule on "LPs" (E5) | `report_builder_starting_steps.rb` (HTTP via `rb_session`) |

The X1 and X5 scenarios load a copy of a template with one bad column through a test-only hook on `ReportBuilderTemplates` (reset in an `After`).

---

## Project Rules Checklist

| Rule | How |
|---|---|
| Cucumber only | Four features above |
| Pundit in policies | Existing `ReportPolicy`; no controller-side permission rules |
| Reuse existing UI | Cards like guided setup step 1; Bootstrap modal; `badge bg-X-subtle text-X` |
| Comment steps and IDs | Code comments name the H/E/X IDs |
| No auto commit | — |

---

## Sign-off

| Role | Name | Date |
|---|---|---|
| Implementer | | |
| Reviewer | | |
