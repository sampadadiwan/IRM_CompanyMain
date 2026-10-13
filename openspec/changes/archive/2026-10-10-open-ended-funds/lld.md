# Evergreen (Open-Ended) Funds — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md) · [QA checklist](qa-checklist.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions a reviewing developer must check. It adds to [design.md](design.md): it links to its diagrams and worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions and ends with **Reviewer checks**.

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

Start here: these are the decisions most likely to be wrong or contested.

- **Guards on existing code are indexed `EXISTS` lookups, not columns** (`dealing_dates.subscription_call_id`, `dealing_fills.capital_distribution_payment_id`, …). This keeps the existing schema untouched, and every closed-end record pays one indexed `EXISTS` per commit. See [Queries and Indexes](#queries-and-indexes) and design [Backward compatibility](design.md#backward-compatibility).
- **The `Workflowable` early return is the only change in shared framework code.** `apply_workflow_auto_assignment(_on_update)` returns when `respond_to?(:skip_journey?) && skip_journey?`. See [Method Contracts → Existing classes](#existing-classes-guarded-changes).
- **Exact redemption units:** the new `DefaultUnitAllocationEngine#allocate_dealing_redemption` and a delegating first line in `allocate_distribution_payment`. See [Method Contracts](#defaultunitallocationengine-modified).
- **Confirm is inline in the request, in one transaction, under `dealing_date.lock!`, with a preview-hash compare.** Document and email work goes to jobs after commit. See [Transactions](#transactions-locking-and-concurrency).
- **Precision:** units are `decimal(26,8)`, matching `fund_units.quantity`, but gate maths truncates to 4 dp. NAV per unit is stored as `decimal(24,4)` cents. Unit prices on calls and distributions are written as major-unit strings, which is the existing YAML shape. See [Schema Detail](#schema-detail).
- **Notifications claim before they send** (card ⑩): an insert into `evergreen_notification_logs` under a unique (`key`, `record_type`, `record_id`, `sent_on`) index decides who sends; switches are a JSON column with code defaults. The only existing-code touch is three values appended to `User::NOTIFICATION_TAGS` (B9). See [Schema Detail](#schema-detail) and [Method Contracts](#method-contracts).
- **Dealing-date documents are optional, per kind, and approved before they are sent** (design card ⑨, *Dealing-date documents*). No template → `EvergreenDealingDocuments.settled` emails at once and stamps `document_sent_at`; template → nothing at settlement, then **Generate documents** (`EvergreenDocumentsJob`) and **Approve & send**. No schema change; `Document#approved` is the approval. Resolves [D5](#implementation-deviations-recorded-during-apply).
- **The `enable_evergreen_funds` permission is appended as bit 36 of `entities.permissions` (bigint)**; existing bits are unchanged. See [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

Pack: `app/packs/funds/evergreen/`, a new sub-domain inside the existing `funds` package, so there is no new `package.yml`. Paths below are relative to `app/packs/funds/evergreen/` unless they start with `app/`, `config/`, `db/` or `features/`.

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Settings | `models/evergreen_fund_setting.rb` | New | Terms, validations, `terms_for`, calendars |
| ① | `models/evergreen_class_term.rb` | New | Per-class terms and overrides |
| ① | `models/evergreen_terms.rb` | New | Frozen value object returned by `terms_for` (`Data.define`) |
| ① | `services/evergreen_enable.rb`, `services/evergreen_disable.rb` | New | Make or unmake evergreen (Trailblazer ops) |
| ① | `services/evergreen_presets.rb`, `config/evergreen_presets.yml` | New | Preset values |
| ① | `services/dealing_calendar.rb` | New | Dates, cut-offs, notice deadlines (pure) |
| ① | `controllers/evergreen/settings_controller.rb`, `views/evergreen/settings/*` | New | Settings UI |
| ① | `policies/evergreen_fund_setting_policy.rb` | New | `< FundBasePolicy` |
| ② Orders | `models/dealing_order.rb` | New | Order, `ready_to_deal?`, `queue_position` |
| ② | `services/dealing_order_create.rb`, `services/dealing_order_cancel.rb`, `services/order_eligibility.rb` | New | Accept, cancel, validate |
| ② | `services/import_dealing_order.rb`, `services/import_dealing_order_service.rb` | New | Upload (`ImportUtil`) |
| ② | `services/dealing_order_journey_setup.rb` | New | `< JourneySetup`; seeds subscription and redemption templates |
| ② | `workflow_checks/dealing_order/*.rb` (check_investor_kyc, collect_signed_form, accept_order, verify_request, collect_money, ready_to_deal, allotted, paid, cancelled, support.rb) | New | Journey checks |
| ② | `controllers/evergreen/orders_controller.rb`, `views/evergreen/orders/*` (index, wizard steps, `_gate_summary`), `services/evergreen_gate_forecast.rb`, `helpers/evergreen_orders_helper.rb` | New | Order book and wizards |
| ② | `policies/dealing_order_policy.rb` | New | GP / investor access |
| ③ NAV builder | `models/fund_nav.rb` | New | NAV row, lines, overrides, `stale?` |
| ③ | `services/fund_nav_builder.rb`, `services/nav_inputs.rb`, `services/class_apportioner.rb`, `services/performance_fee_calculator.rb`, `services/nav_staleness.rb` | New | Draft computation |
| ③ | `services/import_fund_nav.rb`, `services/import_fund_nav_service.rb` | New | NAV upload |
| ④ NAV approval | `services/fund_nav_approve.rb`, `services/fund_nav_reopen.rb`, `services/crystalliser.rb` | New | Maker-checker, crystallise |
| ③④ | `controllers/evergreen/navs_controller.rb`, `views/evergreen/navs/*`, `policies/fund_nav_policy.rb` | New | NAV UI and policy |
| ⑤ Dealing date | `models/dealing_date.rb`, `models/dealing_fill.rb` | New | Records |
| ⑤ | `services/dealing_pricer.rb`, `services/gate_allocator.rb`, `services/dealing_confirm.rb`, `services/dealing_undo.rb`, `services/dealing_roll.rb`, `services/dealing_date_close.rb` | New | Pricing, gating, lifecycle |
| ⑤ | `services/dealing_date_journey_setup.rb`, `workflow_checks/dealing_date/*.rb` | New | Journey templates (pre-funded, pay-after) and checks |
| ⑤ | `jobs/dealing_date_generate_job.rb` | New | Daily calendar generation |
| ⑤ | `controllers/evergreen/dealing_dates_controller.rb`, `controllers/evergreen/dealing_fills_controller.rb`, `views/evergreen/dealing_dates/*` | New | Workspace and tracker |
| ⑤ | `policies/dealing_date_policy.rb` | New | |
| ⑥ Settlement | `services/dealing_settlement.rb`, `services/folio_opener.rb` | New | Drives existing call, remittance, distribution and payment services |
| ⑥ | `app/packs/funds/capital_calls/models/capital_call.rb` | **Modified** | `skip_journey?` (guarded lookup) |
| ⑥ | `app/packs/funds/capital_distributions/models/capital_distribution.rb` | **Modified** | `skip_journey?` |
| ⑥ | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | **Modified** | Early return in the two auto-assignment methods |
| ⑥ | `app/packs/funds/capital_calls/controllers/capital_calls_controller.rb`, `app/packs/funds/capital_distributions/controllers/capital_distributions_controller.rb` | **Modified** | `#show`: redirect evergreen settlement records (S4) |
| ⑥ | `controllers/evergreen/settlements_controller.rb`, `views/evergreen/settlements/*` | New | Evergreen settlement page (read-only plus tracker actions) |
| ⑦ Units | `models/concerns/evergreen_settlement_hooks.rb` | New | `after_commit` guard and enqueue |
| ⑦ | `app/packs/funds/capital_remittances/models/capital_remittance.rb`, `app/packs/funds/capital_distribution_payments/models/capital_distribution_payment.rb` | **Modified** | `include EvergreenSettlementHooks` (one line each) |
| ⑦ | `jobs/dealing_settlement_sync_job.rb`, `services/evergreen_allotment.rb` | New | Allot or cancel, then notify |
| ⑦ | `app/packs/funds/funds/services/default_unit_allocation_engine.rb` | **Modified** | New `allocate_dealing_redemption`; first-line delegation in `allocate_distribution_payment` |
| ⑧ Fees | `services/evergreen_fee_formula_seed.rb` | New | Creates the "Management Fee on NAV" `FundFormula` on request |
| ⑧ | `models/concerns/evergreen_fund.rb` + `app/packs/funds/funds/models/fund.rb` | New + **Modified** (one include) | Associations, `evergreen?`, `evergreen_nav_per_unit` |
| ⑨ Views | `controllers/evergreen/overview_controller.rb`, `investors_controller.rb`, `fees_controller.rb`, `folios_controller.rb` + views | New | GP tabs, register, fees, folio page |
| ⑨ | `views/evergreen/funds/_show_gp.html.erb`, `_show_investor.html.erb`, `_fund_card.html.erb`, `_lp_card.html.erb` | New | Evergreen fund page, funds-list card, landing card |
| ⑨ | `app/packs/funds/funds/views/funds/show.html.erb` (S1), funds card partial (S2), `app/packs/core/entities/views/entities/widgets/_lp_funds.html.erb` (S3), `app/packs/funds/capital_commitments/controllers/capital_commitments_controller.rb#show` (S5) | **Modified** | One `fund.evergreen?` branch each |
| ⑨ | `helpers/evergreen_labels.rb`, `config/locales/evergreen.en.yml` (+ `evergreen.en-US.yml`, `evergreen.ja.yml` copies) | New | Labels (`evergreen.labels.*`) |
| ⑨ | `mailers/evergreen_notifier.rb`, `mailers/evergreen_mailer.rb`, `views/evergreen_mailer/*.html.erb` | New | Seven emails |
| ⑨ | `services/evergreen_document_generator.rb` | **Retired** (delete) | Built-in HexaPDF contract note / advice; replaced by the template path below (D5) |
| ⑨ Documents | `services/evergreen_dealing_documents.rb` | New | Path per fill (`template_for`, `templates?`, `settled`), `to_generate`, `awaiting_approval`, `generate`, `approve_and_send`, `regenerate`, `send_email` |
| ⑨ Documents | `services/evergreen_doc_template_generator.rb` | New | Sablon → PDF from the fund's / folio's tagged template via `DocumentGeneratorBase`; `evergreen.*` context fields; uploads an unapproved "Generated" `Document` on the folio |
| ⑨ Documents | `jobs/evergreen_documents_job.rb` | New | **Generate documents** in the background (`:doc_gen`), `UserAlert` with counts and failures |
| ⑨ Documents | `workflow_checks/dealing_date/documents_generated.rb`, `documents_sent.rb`, `no_document_templates.rb` | New | The two document steps and their skip check |
| ⑨ Documents | `services/dealing_date_journey_setup.rb`, `services/dealing_progress.rb`, `workflow_checks/dealing_date/allotted.rb`, `units_cancelled.rb` | Modified (files of this change) | Steps renamed *Allot units* / *Cancel units* (no document part); two document steps before Close; `documents_generated?`, `documents_sent?`; `closable?` requires `documents_sent?` |
| ⑨ Documents | `services/evergreen_allotment.rb` | Modified (file of this change) | After units move, calls `EvergreenDealingDocuments.settled(fill)` instead of generating and emailing |
| ⑨ Documents | `controllers/evergreen/dealing_dates_controller.rb` (`generate_documents`, `approve_documents`), `controllers/evergreen/dealing_fills_controller.rb` (`regenerate`), `policies/dealing_date_policy.rb` (`generate_documents?`, `approve_documents?`), `views/evergreen/dealing_dates/{show,_tracker,_fill_status}.html.erb` (Actions menu, approve popup, View · Regenerate) | Modified (files of this change) | UI and access for the two actions and the row actions |
| ⑨ Documents | `mailers/evergreen_mailer.rb`, `views/evergreen_mailer/{contract_note,redemption_advice}.html.erb` | Modified (files of this change) | Body carries the figures (email-only path); attach the fill's document only when it is approved |
| ⑨ Documents | `services/evergreen_alerts.rb`, `services/evergreen_recipients.rb` (approvers), `views/evergreen/settings/_notifications_step.html.erb`, `config/locales/evergreen.*.yml` | Modified (files of this change) | `documents_awaiting_approval` catalogue key (team, default on), `documents_generated(dealing_date)` |
| ⑨ Documents | `config/routes/fund.rb` | **Modified** | `post :generate_documents`, `post :approve_documents` on dealing dates; `post :regenerate` on fills |
| ⑨ | `app/packs/funds/capital_commitments/services/soa_generator.rb` | **Modified** | `add_evergreen_context` when `fund.evergreen?` (S6) |
| ⑨ | `app/packs/core/investors/models/concerns/for_investor.rb` | **Modified** | Add `FundNav`, `DealingOrder` to the fund-child lists |
| ⑩ Notifications | `services/evergreen_notifications.rb` | New | Catalogue (key → audience, roles, default), `enabled?(fund, key)`, `notify(key, record)` (switch → claim → recipients → deliver) |
| ⑩ | `services/evergreen_recipients.rb` | New | Resolves investor users / approvers / RM (fallback Fund ops) / tagged users; `FundPolicy#show?` filter; de-duplication |
| ⑩ | `models/evergreen_notification_log.rb` | New | `claim!(key, record, on:)` → true / false via the unique index |
| ⑩ | `jobs/evergreen_notifications_job.rb` | New | Daily: reminder day, lock-up ends, day after cut-off, ready to confirm, overdue |
| ⑩ | `mailers/evergreen_ops_notifier.rb`, `mailers/evergreen_ops_mailer.rb`, `views/evergreen_ops_mailer/*.html.erb`, `config/locales/evergreen.*.yml` (`evergreen.notifications.*`) | New | Ten team alerts (nine + `documents_awaiting_approval`), in-app + email, fixed wording |
| ⑩ | `mailers/evergreen_mailer.rb`, `mailers/evergreen_notifier.rb`, `views/evergreen_mailer/{payment_reminder,action_needed,payment_received,units_unlocked,nav_update}.html.erb` | Modified (files of this change) | Five new `SUBJECTS` keys and placeholders; `set_order` also loads a folio / NAV for folio-level emails |
| ⑩ | `services/evergreen_notification_copy.rb`, `controllers/evergreen/notification_copies_controller.rb`, `views/evergreen/notification_copies/*` | New | Copy from fund… |
| ⑩ | `views/evergreen/settings/show.html.erb` (+ `_notifications_step.html.erb`), `models/evergreen_fund_setting.rb` | Modified (files of this change) | Notifications wizard step before Review; `notifications` validation |
| ⑩ | Hooks in `DealingOrderCreate`, `FundNavBuilder`, `ImportFundNav`, `FundNavApprove`, `DealingConfirm`, `EvergreenSettlementHooks` | Modified (files of this change) | One `EvergreenAlerts.notify` call after commit each |
| ⑩ | `app/packs/core/users/models/user.rb` | **Modified** | Append "FundOps", "FundAccounting", "Compliance" to `NOTIFICATION_TAGS` (B9) |
| Platform | `app/packs/core/entities/models/concerns/entity_enabled.rb` | **Modified** | Append `enable_evergreen_funds` |
| Platform | `config/routes/fund.rb` | **Modified** | `scope "funds/:fund_id/evergreen"` routes |
| Platform | `config/initializers/sidekiq.rb` | **Modified** | Register `DealingDateGenerateJob` and `EvergreenNotificationsJob` crons |
| Platform | `db/migrate/*_create_evergreen_tables.rb`, `db/schema.rb`, `db/schema_test.rb` | New + Modified | Six new tables |
| Platform | `db/migrate/*_add_evergreen_notifications.rb` | New | `evergreen_fund_settings.notifications` + `evergreen_notification_logs` |
| Tests | `features/fund/evergreen/*.feature`, `features/step_definitions/evergreen/*_steps.rb`, `features/support/evergreen_helpers.rb` | New | See [Test Plumbing](#test-plumbing) |
| Docs | `docs/user_guides/evergreen_funds_user_guide.md` | New | User guide with FAQs (user-guide FAQ standard) |

**Reviewer checks**
- [ ] Every class in the design's class diagrams has a file here, and nothing here is missing from them
- [ ] All new files live under `app/packs/funds/evergreen/`; `bin/packwerk check` has no new violations (the `funds` package already depends on `core`)
- [ ] Every **Modified** row appears in design [Backward compatibility](design.md#backward-compatibility) (B1–B8)

### Implementation deviations (recorded during apply)

| # | Planned | Built | Why |
|---|---|---|---|
| D1 | `deleted_at` soft delete on the new tables, with a virtual `generated_deleted` column for NAV uniqueness | No soft delete; plain unique indexes (`fund_navs(fund_id, unit_type, nav_date)`) | Nothing needs soft delete — NAV drafts are deleted outright, approved NAVs never are, orders are cancelled by status. Virtual columns don't port cleanly to the SQLite test schema. `Trackable` (which needs `deleted_at`) is therefore not included |
| D2 | Two dealing-date templates (pre-funded, pay-after) chosen at generation | One template whose pre-funded-only and pay-after-only steps are skipped by the dealing date's `payment_timing` | Lets `JourneySetup`'s catch-all auto-assignment rule launch it unchanged; the step bar shows only the applicable steps |
| D3 | Separate subscription and redemption order templates, launched from the fund's chosen template | One order template; kind-specific steps skipped by kind. `DealingOrder#skip_journey?` keeps funds with order journeys off (or the other kind) out, via the same `Workflowable` guard. The per-fund template picker (`*_journey_template_id`) is stored but not yet offered in the UI | Same auto-assignment reuse; per-fund picker deferred to a follow-up |
| D5 | Contract notes and redemption advices generated from per-fund Sablon templates chosen in settings (`contract_note_template_id`, `redemption_advice_template_id`; null = a sample template), emailed on allotment / payment | Phase 6 built a fixed HexaPDF layout (`EvergreenDocumentGenerator`), generated and emailed automatically at allotment / payment, with per-fund templates left as a follow-up. **Resolved by tasks section 12 (approved 2026-10-08):** templates are optional and per kind, found by tag ("Contract Note Template" / "Redemption Advice Template") through `CapitalCommitment#templates(tag)` so folio overrides work; no template → email at once with the figures, no PDF; template → **Generate documents** (unapproved PDFs) → **Approve & send** (approver; PDF attached). The built-in layout is retired. The two settings columns remain in the schema, unused | Tagged templates reuse the existing template upload, folio override and Sablon → PDF pipeline; approval before sending is the control funds asked for; a sample template is unnecessary once the email-only path exists |
| D6 | **Generate documents** as a `DocGenJob` subclass (the brief for section 12) | `EvergreenDocumentsJob < ApplicationJob` on the `:doc_gen` queue, calling `EvergreenDealingDocuments.generate`; the generator (`EvergreenDocTemplateGenerator`) reuses `DocumentGeneratorBase` like `CapitalDistributionPaymentDocGenerator` | `DocGenJob#generate` loops one template list over all models; here the template differs per fill and kind (folio override, contract note vs advice) and each result must be linked back to its fill (`document_id`). Same queue, same generator base, same unapproved "Generated" documents. **Reviewer: confirm or ask for the subclass** |

There is no D4 row; D5 keeps the number the code comment in `evergreen_document_generator.rb` cites.

---

## Schema Detail

One migration creates all six tables, with no changes to existing tables. Money columns use the repo's `*_cents` decimal convention.

**`evergreen_fund_settings`** (new): the fund's evergreen terms and the evergreen flag.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | idx, FK entities | Tenancy |
| `fund_id` | Added | bigint | — | no | — | **UK**, FK funds | One per fund; `has_one` for `evergreen?` |
| `subscription_calendar`, `redemption_calendar` | Added | string | 15 | no | "monthly" / "quarterly" | — | Enum string (inclusion validation); 15 fits "semi_annual" |
| `subscription_dates`, `redemption_dates` | Added | json | — | yes | null | — | Custom date lists; JSON array of ISO dates |
| `dealing_day` | Added | string | 10 | no | "first" | — | first / last / day_n |
| `dealing_day_n` | Added | integer | — | yes | null | — | 1–28 when `day_n` |
| `payment_timing` | Added | string | 10 | no | "before" | — | before / after |
| `pay_after_days` | Added | integer | — | no | 7 | — | 1–30 |
| `subscription_cutoff_days` | Added | integer | — | no | 5 | — | 0–30 |
| `unready_handling` | Added | string | 10 | no | "roll" | — | roll / cancel |
| `order_journeys` | Added | string | 15 | no | "off" | — | off / subscriptions / both |
| `subscription_journey_template_id`, `redemption_journey_template_id` | Added | bigint | — | yes | null | FK workflow_templates | Template to launch per kind |
| `redemption_forms` | Added | json | — | no | `["units","amount","all"]` | — | At least one value (validation) |
| `redemption_settlement_days` | Added | integer | — | no | 10 | — | 1–90 business days |
| `notice_days` | Added | integer | — | no | 30 | — | 0–180 |
| `lock_up_months` | Added | integer | — | no | 0 | — | 0–60 |
| `lock_up_type` | Added | string | 5 | no | "hard" | — | hard / soft |
| `early_redemption_fee` | Added | json | — | no | `{"pct":0}` | — | `{"pct":x}` or `{"schedule":[{"from":0,"to":12,"pct":3},…]}` |
| `min_initial_subscription_cents`, `min_additional_subscription_cents`, `min_holding_cents` | Added | decimal | 20,2 | no | 0 | — | Repo money precision |
| `gate_pct`, `investor_gate_pct` | Added | decimal | 7,4 | no | 0 | — | 0–100; 4 dp allows 2.5 % and similar |
| `gate_level` | Added | string | 5 | no | "fund" | — | fund / class |
| `gate_period` | Added | string | 15 | no | "dealing_date" | — | dealing_date / quarter / year |
| `gate_method` | Added | string | 10 | no | "pro_rata" | — | fifo / pro_rata |
| `cash_entry_name`, `other_assets_entry_name`, `other_liabilities_entry_name`, `mgmt_fee_paid_entry_name`, `perf_fee_paid_entry_name` | Added | string | 125 | no | spec defaults | — | Matches `account_entries.name` limit |
| `fund_close_name` | Added | string | 255 | no | "Evergreen" | — | Matches `capital_commitments.fund_close` (string, 255) |
| `payment_instructions` | Added | text | — | yes | null | — | Free text shown in emails |
| `contract_note_template_id`, `redemption_advice_template_id` | Added | bigint | — | yes | null | FK documents | **Unused** after D5 — templates are found by tag; kept to avoid a migration |
| `preset` | Added | string | 40 | yes | null | — | Display only |
| `enabled_by_id` | Added | bigint | — | yes | null | FK users | Audit |
| `created_at`, `updated_at`, `deleted_at` | Added | datetime | — | — | — | idx `deleted_at` | Soft delete via the repo's `acts_as_paranoid` pattern |

**`evergreen_class_terms`** (new): per-class terms.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id`, `fund_id`, `evergreen_fund_setting_id` | Added | bigint | — | no | — | idx; FK | Tenancy, parent |
| `unit_type` | Added | string | 40 | no | — | **UK (fund_id, unit_type)** | Same limit as `capital_commitments.unit_type` |
| `initial_price_cents` | Added | decimal | 24,4 | yes | null | — | Required before dealing (validation on use, not on create) |
| `perf_fee_model` | Added | string | 15 | no | "none" | — | none / class_hwm |
| `perf_fee_pct`, `hurdle_pct` | Added | decimal | 7,4 | no | 0 | — | 0–50 |
| `hurdle_type` | Added | string | 5 | no | "hard" | — | hard / soft |
| `crystallisation` | Added | string | 15 | no | "annual" | — | quarterly / semi_annual / annual |
| `notice_days`, `lock_up_months` | Added | integer | — | **yes** | null | — | null means use the fund value |
| `lock_up_type` | Added | string | 5 | yes | null | — | Override |
| `early_redemption_fee` | Added | json | — | yes | null | — | Override |
| `min_initial_subscription_cents`, `min_additional_subscription_cents`, `min_holding_cents` | Added | decimal | 20,2 | yes | null | — | Overrides |
| `created_at`, `updated_at` | Added | datetime | — | — | — | — | |

**`fund_navs`** (new): NAV per class per date.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id`, `fund_id` | Added | bigint | — | no | — | idx; FK | |
| `unit_type` | Added | string | 40 | no | — | composite idx | Class |
| `nav_date` | Added | date | — | no | — | composite idx | As-of date |
| `status` | Added | string | 10 | no | "draft" | composite idx | draft / approved |
| `source` | Added | string | 10 | no | "computed" | — | computed / uploaded |
| line columns (`investments_fmv_cents`, `cash_cents`, `other_assets_cents`, `mgmt_fee_payable_cents`, `perf_fee_payable_cents`, `perf_fee_accrued_cents`, `other_liabilities_cents`, `nav_cents`) | Added | decimal | 20,2 | no | 0 | — | Money precision of the repo |
| `units_outstanding` | Added | decimal | 26,8 | no | 0 | — | Same as `fund_units.quantity` |
| `nav_per_unit_before_perf_cents`, `nav_per_unit_cents`, `hwm_cents`, `hwm_after_cents` | Added | decimal | 24,4 | yes | null | — | 4 dp cents keeps ₹10,160.94 exact (101,50,00,000 ÷ 99,892.3679) without float drift |
| `class_share` | Added | decimal | 12,10 | no | 1 | — | Audit of the split |
| `crystallised` | Added | boolean | — | no | false | — | Reopen reversal |
| `mgmt_fee_accrued_to` | Added | date | — | yes | null | — | Warning |
| `overrides`, `breakdown` | Added | json | — | yes | null | — | Audit |
| `inputs_fingerprint` | Added | string | 64 | yes | null | — | SHA-256 hex |
| `prepared_by_id`, `approved_by_id` | Added | bigint | — | yes | null | FK users | Maker-checker |
| `approved_at` | Added | datetime | — | yes | null | — | |
| `import_upload_id` | Added | bigint | — | yes | null | idx | Upload link |
| `created_at`, `updated_at`, `deleted_at` | Added | datetime | — | — | — | idx `deleted_at` | |
| index `(fund_id, unit_type, nav_date, status)` | New index | — | — | — | — | — | Latest-approved lookups |

Uniqueness: at most one non-deleted NAV per (fund, class, date). This is validated in the model. MySQL can't partially index on `deleted_at IS NULL`, so it is also covered by a `generated_deleted`-style virtual column and a unique index on (`fund_id`, `unit_type`, `nav_date`, `generated_deleted`), the same pattern as `account_entries.generated_deleted`.

**`dealing_dates`**, **`dealing_orders`** and **`dealing_fills`** (new):

| Table.Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `dealing_dates.date` | Added | date | — | no | — | **UK (fund_id, date)** | One per date |
| `dealing_dates.cutoff_at` | Added | datetime | — | no | — | — | End of the cut-off day in `Time.zone` |
| `dealing_dates.has_subscriptions` / `has_redemptions` | Added | boolean | — | no | false | — | Calendar membership |
| `dealing_dates.payment_timing` | Added | string | 10 | no | — | — | Snapshot |
| `dealing_dates.status` | Added | string | 10 | no | "open" | idx (fund_id, status) | Lifecycle |
| `dealing_dates.subscription_call_id` | Added | bigint | — | yes | null | **idx**, FK capital_calls | Guard B3/B4 lookup |
| `dealing_dates.redemption_distribution_id` | Added | bigint | — | yes | null | **idx**, FK capital_distributions | Guard B3/B4 lookup |
| `dealing_dates.settings_snapshot`, `gate_snapshot` | Added | json | — | yes | null | — | Frozen at confirm |
| `dealing_dates.confirmed_by_id`, `closed_by_id` | Added | bigint | — | yes | null | FK users | |
| `dealing_dates.confirmed_at`, `closed_at` | Added | datetime | — | yes | null | — | |
| `dealing_orders.kind` | Added | string | 12 | no | — | composite idx | subscription / redemption |
| `dealing_orders.status` | Added | string | 20 | no | "pending" | composite idx | pending / partially_filled / dealt / cancelled / rejected |
| `dealing_orders.amount_cents` | Added | decimal | 20,2 | yes | null | — | Form = amount, or subscription amount |
| `dealing_orders.units` | Added | decimal | 26,8 | yes | null | — | Form = units |
| `dealing_orders.all_units` | Added | boolean | — | no | false | — | Form = all |
| `dealing_orders.received_at` | Added | datetime | — | no | — | composite idx | Queue order, cut-off |
| `dealing_orders.capital_commitment_id` | Added | bigint | — | yes | null | idx, FK | Folio |
| `dealing_orders.capital_remittance_id` | Added | bigint | — | yes | null | **idx**, FK | Guard B5 for pre-funded payment rows |
| `dealing_orders.dealing_date_id` | Added | bigint | — | no | — | idx, FK | Current date |
| `dealing_orders.rolled_count` | Added | integer | — | no | 0 | — | |
| `dealing_orders.source` | Added | string | 10 | no | "portal" | — | portal / admin / upload |
| `dealing_orders.early_fee_pct` | Added | decimal | 7,4 | no | 0 | — | Soft lock-up |
| `dealing_orders.locked_units` | Added | decimal | 26,8 | no | 0 | — | |
| `dealing_orders.rejected_reason` | Added | string | 255 | yes | null | — | |
| `dealing_orders` other FKs (`investor_id`, `entered_by_id`, `import_upload_id`, `accepted_by_id`, `signatory_verified_by_id`, `cancelled_by_id`) and timestamps (`accepted_at`, `signatory_verified_at`, `cancelled_at`, `deleted_at`), `note` (text) | Added | bigint / datetime / text | — | yes (`investor_id` no) | — | idx `investor_id` | Audit and journey data |
| index `dealing_orders(fund_id, kind, status, received_at)` | New index | — | — | — | — | — | Queue, order book |
| `dealing_fills.dealing_date_id`, `dealing_order_id` | Added | bigint | — | no | — | **UK pair** | One fill per order per date |
| `dealing_fills.fund_nav_id` | Added | bigint | — | yes | null | idx, FK | Reopen guard (null for subscriptions-only on a class with no NAV is impossible; validation) |
| `dealing_fills.requested_units`, `units`, `carried_units` | Added | decimal | 26,8 | no | 0 | — | Values truncated to 4 dp before storing |
| `dealing_fills.amount_cents`, `early_fee_cents` | Added | decimal | 20,2 | no | 0 | — | |
| `dealing_fills.nav_per_unit_cents` | Added | decimal | 24,4 | no | — | — | |
| `dealing_fills.capital_remittance_id` / `capital_distribution_payment_id` | Added | bigint | — | yes | null | **idx each** | Guards B5/B6 |
| `dealing_fills.fund_unit_id`, `document_id` | Added | bigint | — | yes | null | FK | Steps |
| `dealing_fills.instructions_sent_at`, `document_sent_at` | Added | datetime | — | yes | null | — | Steps |

All tables also get `entity_id` (idx) and `created_at`/`updated_at`.

**Notifications (card ⑩)** — a second migration, `*_add_evergreen_notifications.rb`. Both tables belong to this change; no pre-existing table is touched.

| Table.Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `evergreen_fund_settings.notifications` | Added | json | — | yes | null | — | Per-fund switches + `reminder_days` (1–30) + `large_redemption_pct` (> 0, ≤ 100). Null / missing key = catalogue default, so new notifications need no backfill. JSON, not a column per switch, because the list will grow |
| `evergreen_notification_logs.entity_id` | Added | bigint | — | no | — | idx, FK entities | Tenancy |
| `evergreen_notification_logs.fund_id` | Added | bigint | — | no | — | idx, FK funds | Per-fund audit and lookups |
| `evergreen_notification_logs.key` | Added | string | 40 | no | — | UK part | Catalogue key; longest is `nav_awaiting_approval` (21) |
| `evergreen_notification_logs.record_type` | Added | string | 40 | no | — | UK part | Polymorphic type (`DealingOrder`, `CapitalRemittance`, `FundUnit`, `FundNav`, `DealingDate`) |
| `evergreen_notification_logs.record_id` | Added | bigint | — | no | — | UK part | Polymorphic id |
| `evergreen_notification_logs.sent_on` | Added | date | — | no | — | UK part | Day sent (`Time.zone.today`); daily checks claim per day |
| `evergreen_notification_logs.created_at` | Added | datetime | — | no | — | — | Claim time; no `updated_at` (insert-only) |
| UK `(key, record_type, record_id, sent_on)` | New index | — | — | — | — | — | The claim: `insert` raises `ActiveRecord::RecordNotUnique` on a duplicate, which `claim!` turns into `false` |

Event keys (`payment_received`, `nav_update`, `nav_approved`, …) are once per record on any day, so `claim!` for them first checks `exists?(key:, record_type:, record_id:)` (the UK's leading columns serve it) and then inserts; daily keys only insert.

**Migration safety:**
- New tables only, created empty, with no lock on existing tables and no backfill. Reversible (`drop_table`).
- Run `db:migrate` against the dev DB, then restore `db/schema.rb` and `db/schema_test.rb`, hand-insert the six tables, and run `db:clean_schema` (the local dev DB lags the schema; see the memory note on schema drift).
- `schema_test.rb` gets the same tables.

**Reviewer checks**
- [ ] Every column above has a "why"; none is unjustified
- [ ] Every FK has an index; `fund_id` + `unit_type` uniqueness on class terms and (`fund_id`, `date`) on dealing dates are unique indexes
- [ ] String limits match inclusion validations; `unit_type` is 40 everywhere
- [ ] No migration touches an existing table
- [ ] `schema.rb` and `schema_test.rb` both list all six tables

---

## Method Contracts

Services are Trailblazer operations (`step :x`), like the repo's existing services. "Result" below means a Trailblazer result with `ctx[:errors]`.

**`EvergreenFundSetting`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#terms_for(unit_type)` | String | `EvergreenTerms` (frozen: notice_days, lock_up_months, lock_up_type, early_fee, min_initial, min_additional, min_holding, initial_price, perf_fee_model, perf_fee_pct, hurdle_pct, hurdle_type, crystallisation) | `ArgumentError` for an unknown class | Lazily creates an `EvergreenClassTerm` with fund defaults | Yes |
| `#early_fee_pct_for(term, unit_age_months)` | `EvergreenTerms`, Integer | BigDecimal | — | — | Yes (pure) |

**`DealingCalendar`** (Service, pure)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.dates(setting, kind, from:, to:)` | setting, `:subscription`/`:redemption`, Date, Date | Array<Date> (Mon–Fri adjusted) | — | — | Yes |
| `.next_dealing_date(setting, kind, unit_type, received_at)` | … Time | Date | `DealingCalendar::NoDate` (custom list exhausted) | — | Yes |
| `.cutoff_at(setting, date)` | | Time (end of day, `Time.zone`) | — | — | Yes |

**`DealingOrderCreate`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(params:, fund:, current_user:, source:)` | params: kind, unit_type, amount_cents/units/all_units, investor_id, capital_commitment_id, received_at (admin only), note | Result (`ctx[:order]`) | — (errors in result) | Saves the order. Pre-funded subscription: `FolioOpener`, `AdjustmentCreate` top-up, `DealingSettlement.ensure_subscription_payment`. Launches the order journey. Enqueues the acknowledgement | No; the upload dedups by row |

**`OrderEligibility`** (Service, pure apart from reads)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.errors_for(order)` | unsaved `DealingOrder` | Array<String> (first failure only, in the design's order) | — | Sets `order.early_fee_pct`, `order.locked_units` | Yes |

**`DealingOrder`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#ready_to_deal?` | — | Boolean (design rule) | — | — | Yes |
| `#queue_position` | — | Integer or nil (subscriptions) | — | One `COUNT` query | Yes |
| `#resolved_units(at:)` | Time | BigDecimal (all → units held at that time; amount → amount ÷ NAV per unit) | `DealingOrder::NoNav` | — | Yes |

**`FundNavBuilder`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund:, nav_date:, current_user:)` | | Result (`ctx[:fund_navs]`, one per class) | `NavInputs::MissingValuation` is mapped to a result error | Replaces existing **draft** rows for that date, keeping overrides; refuses if an approved row exists | Yes (same inputs → same drafts) |

**`PerformanceFeeCalculator`** (Service, pure)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.accrued(term:, nav_per_unit_before:, hwm:, units:, days_since_crystallisation:)` | BigDecimals | `{fee_cents:, hurdle_adjusted:}` | — | — | Yes |

**`NavStaleness`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.fingerprint(fund_nav)` | | SHA-256 hex String | — | 4 aggregate queries | Yes |

**`FundNavApprove` / `FundNavReopen` / `Crystalliser`** (Services)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `FundNavApprove.call(fund_nav:, current_user:)` | | Result | — | Status approved; `Crystalliser` on crystallisation dates | No; a second call is refused ("already approved") |
| `FundNavReopen.call(fund_nav:, current_user:)` | | Result | — | Deletes crystallisation entries, restores `hwm_cents`, status draft | No; refused unless approved and unused |
| `Crystalliser.call(fund_nav:)` | | Integer (entries inserted) | — | `AccountEntry.insert_all` per batch of 500 folios | Guarded by `fund_nav.crystallised` |

**`DealingPricer` / `GateAllocator`** (Services)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `DealingPricer.preview(dealing_date)` | | `Pricing` value object (subscription rows, redemption rows, unready rows, gate, `hash`) | — | Reads only | Yes |
| `GateAllocator.allocate(requests:, pools:, method:, investor_caps:)` | requests: Array of {order_id, investor_id, unit_type, units, nav_per_unit, queue_key}; pools: {level_key => BigDecimal value}; caps: {investor_id => units} | Array of {order_id, filled_units, carried_units, value_cents} | — | Pure | Yes |

**`DealingConfirm` / `DealingUndo` / `DealingRoll` / `DealingDateClose`** (Services)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `DealingConfirm.call(dealing_date:, preview_hash:, current_user:)` | | Result | — | Fills, statuses, snapshots, `DealingRoll`, `DealingSettlement.settle`; after commit, enqueues sync and notifications | No; refused unless open |
| `DealingUndo.call(dealing_date:, current_user:)` | | Result | — | `DealingSettlement.unsettle`, deletes fills, restores orders | No; refused unless confirmed and unsettled |
| `DealingRoll.call(dealing_date:, orders:)` | | Integer | — | Moves orders and pre-funded remittances, or cancels them | — (inside confirm) |
| `DealingDateClose.call(dealing_date:, current_user:)` | | Result | — | `closed_at`, status | No; refused unless every step passes |

**`DealingSettlement`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.ensure_subscription_payment(order, user)` | | `CapitalRemittance` | `DealingSettlement::Error` wrapping service failures | Creates the call if missing (`CapitalCallCreate`, Upload, approved, flags false) and the remittance (`CapitalRemittanceCreate`) | Yes (returns the existing one) |
| `.settle(dealing_date, user)` | | true | `DealingSettlement::Error` | Sets call `unit_prices`. Pay-after: folios, top-ups, remittances. Redemptions: distribution, `DistributionFee`, fee `AccountEntry`, `CapitalDistributionPaymentCreate` per fill. Links ids on the dealing date and fills | No (inside the confirm transaction) |
| `.unsettle(dealing_date, user)` | | true | `DealingSettlement::Error` | Reverses `settle` | No |

**`DealingSettlementSyncJob` / `EvergreenAllotment`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `DealingSettlementSyncJob#perform(record_type, record_id, user_id = nil)` | `"CapitalRemittance"`/`"CapitalDistributionPayment"`, id | — | Re-raises after `UserAlert` so Sidekiq retries | Calls `EvergreenAllotment` | Yes |
| `EvergreenAllotment.allot(fill)` / `.cancel(fill)` | | `FundUnit` or nil | — | Engine call, sets `fill.fund_unit_id`, enqueues the document | Yes (no-op when `fund_unit_id` is set) |

**Notifications (card ⑩)**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `EvergreenAlerts.enabled?(fund, key)` | Fund, String | Boolean (`notifications[key]`, else `CATALOGUE[key][:default]`) | `KeyError` for an unknown key | — | Yes (pure) |
| `EvergreenAlerts.notify(key, record, on: Time.zone.today)` | String, record | Boolean (sent?) | — (errors logged, never raised to the caller) | `enabled?` → `EvergreenNotificationLog.claim!` → `EvergreenRecipients` → `EvergreenNotifier` / `EvergreenOpsNotifier` `deliver` | Yes (the claim) |
| `EvergreenNotificationLog.claim!(key, record, on:, daily:)` | | Boolean | — (rescues `RecordNotUnique` → false) | Inserts one row | Yes |
| `EvergreenRecipients.for(role, record)` | `:investor`, `:approvers`, `:rm`, `:fund_ops`, `:fund_accounting`, `:compliance`; record | Array<User> (unique) | — | Reads only | Yes |
| `EvergreenNotificationsJob#perform(date = Time.zone.today)` | Date | — | Per-fund errors are rescued, reported via `ExceptionNotifier`, then the next fund runs | `find_each` over `EvergreenFundSetting`; calls `notify` per due record | Yes (claims) |
| `EvergreenNotificationCopy.call(fund:, source_fund:, current_user:)` | | Result (`ctx[:copied]`, `ctx[:skipped]`) | — | Creates `CustomNotification` rows (for_type "Evergreen", owner = fund) in one transaction | Yes (skips existing `email_method`s) |

**Dealing-date documents (card ⑨, D5)** — `EvergreenDealingDocuments` (Service, class methods)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.kind(fill)` | `DealingFill` | `:contract_note` / `:redemption_advice` | — | — | Yes (pure) |
| `.template_for(fill)` | `DealingFill` | `Document` template or nil — `folio.templates(TAGS[kind]).first` (folio override first) | — | Reads | Yes |
| `.templates?(fund)` | `Fund` | Boolean — `fund.documents.templates.exists?(owner_tag: TAGS.values)` | — | One `EXISTS` | Yes |
| `.settled(fill)` | `DealingFill` after `fund_unit_id` is set | — | — | No template: `send_email(fill)`. Always: `journey_progress!` on the order and the dealing date | Yes (called once per fill, under the allotment lock) |
| `.to_generate(dealing_date)` | | Array<DealingFill>: `fund_unit_id` present, `document_id` and `document_sent_at` null, with a template | — | Preloads `dealing_order: :capital_commitment` | Yes |
| `.awaiting_approval(dealing_date)` | | Array<DealingFill>: `document_id` present, `document_sent_at` null, document not `approved` | — | Preloads `:document` | Yes |
| `.generate(dealing_date, user_id)` | | `[made, errors]` | — (per-fill `StandardError` rescued into `errors`, logged with fill id) | One `EvergreenDocTemplateGenerator` + `fill.update!(document:)` per fill; `EvergreenAlerts.documents_generated` if `made > 0`; `journey_progress!` | Yes — only fills still without a document |
| `.approve_and_send(dealing_date, user)` | | Integer sent | — | Per fill: `document.update!(approved: true, approved_by_id: user.id)`, `send_email`; then `journey_progress!(actor: user)` | Yes — sent fills drop out of `awaiting_approval` |
| `.regenerate(fill, user_id)` | | nil, or an error String ("Approved documents can't be regenerated", "No template for this document") | — | Clears `document_id`, destroys the old document, generates and links a new one | No; refused once approved |
| `.send_email(fill)` | | — | — | `EvergreenNotifier.contract_note` / `.redemption_advice`; `document_sent_at = now`; order `journey_progress!` | Guarded by callers (`document_sent_at` / `to_generate`) |

| Other | Contract |
|---|---|
| `EvergreenDocumentsJob#perform(dealing_date_id, user_id)` | Queue `:doc_gen`; `Chewy.strategy(:sidekiq)`; calls `generate`; `UserAlert` "N documents generated for <l(date)> — approve and send them on the dealing date" (+ "K failed: …", level warning) |
| `EvergreenDocTemplateGenerator.new(fill, template, user_id).generated_document` | Downloads the template, Sablon context = decorated fill / order / folio / fund + `evergreen.*` formatted values (email date format, 4-dp units, fund-currency money), converts to PDF, `upload` to the folio named "<template> - <ISO dealing date> - <folio id>", owner_tag "Generated", unapproved |
| `DealingProgress#documents_generated?` | `confirmed? && settled_fills.exists? && to_generate.empty?` |
| `DealingProgress#documents_sent?` | `confirmed? && settled_fills.where(document_sent_at: nil).none?` |
| `DealingProgress#closable?` | Previous rule **and** `documents_sent?` |
| `WorkflowChecks::DealingDate::NoDocumentTemplates` | Passes (= skip) when `!EvergreenDealingDocuments.templates?(fund)` |
| `EvergreenMailer` `contract_note` / `redemption_advice` | Body always lists the figures; attaches `@fill.document` only when present and `approved` |

#### DefaultUnitAllocationEngine (modified)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#allocate_dealing_redemption(payment, fill, reason)` **new** | `CapitalDistributionPayment`, `DealingFill`, String | `[FundUnit, errors]` (same shape as existing methods) | — | `FundUnit` quantity = −`fill.units`, price = `fill.nav_per_unit_cents`, owner = payment, `issue_date` = `payment.payment_date` | Yes (skips when the payment owns a unit) |
| `#allocate_distribution_payment` **guarded** | unchanged | unchanged | unchanged | First line: `if (fill = DealingFill.find_by(capital_distribution_payment_id: payment.id)) then return allocate_dealing_redemption(payment, fill, reason)`. Otherwise the existing body runs byte-identical | unchanged |

#### Existing classes (guarded changes)

| Class | Change | Exact shape |
|---|---|---|
| `Workflowable` | Early return | First line of `apply_workflow_auto_assignment` and `apply_workflow_auto_assignment_on_update`: `return if respond_to?(:skip_journey?) && skip_journey?` |
| `CapitalCall` | New method | `def skip_journey? = evergreen_settlement_flag \|\| (persisted? && DealingDate.exists?(subscription_call_id: id))` (`evergreen_settlement_flag` is an `attr_accessor` set by `DealingSettlement` before create, because the after_create runs before the link is saved) |
| `CapitalDistribution` | New method | Same, with `redemption_distribution_id` |
| `CapitalRemittance`, `CapitalDistributionPayment` | `include EvergreenSettlementHooks` | `after_commit :enqueue_evergreen_sync, if: :evergreen_settlement_record?` where `evergreen_settlement_record?` = `DealingFill.exists?(fk: id) \|\| (CapitalRemittance && DealingOrder.exists?(capital_remittance_id: id))` |
| `Fund` | `include EvergreenFund` | `has_one :evergreen_fund_setting`; `has_many :fund_navs, :dealing_dates, :dealing_orders`; `evergreen?` = `entity.enable_evergreen_funds? && evergreen_fund_setting.present?` (memoised per instance); `evergreen_nav_per_unit(unit_type, date)` |
| `CapitalCallsController#show`, `CapitalDistributionsController#show` | First line | `return redirect_to evergreen_settlement_path(...) if (dd = DealingDate.find_by(subscription_call_id: @capital_call.id))` |
| `CapitalCommitmentsController#show` | First line | `return redirect_to evergreen_folio_path(...) if @capital_commitment.fund.evergreen?` |
| `SoaGenerator` | One call | `add_evergreen_context(context) if fund.evergreen?` |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in [Error Mapping](#error-mapping-and-logging)
- [ ] The sync job, `allot`/`cancel`, `ensure_subscription_payment` and `NavStaleness` are idempotent
- [ ] The body of `allocate_distribution_payment` below the new first line is unchanged in the diff
- [ ] `skip_journey?` returns false for a call or distribution created outside `DealingSettlement` (E2)
- [ ] A fill whose kind has a template is never emailed before Approve & send; a fill without one is emailed exactly once, at settlement (E66, E68, H61)
- [ ] `generate` never regenerates a fill that already has a document, and one failing fill does not stop the others (E67, X30)
- [ ] `EvergreenMailer` attaches only an approved document

---

## Controllers, Params and Responses

All under `scope "funds/:fund_id/evergreen", module: :evergreen, as: :evergreen` in `config/routes/fund.rb`. Every action runs `authorize` / `policy_scope`, with `fund` loaded through `policy_scope(Fund)`.

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SettingsController#create` | `evergreen_fund_setting: [all setting fields except entity_id, fund_id, enabled_by_id], class_terms: [:unit_type, …overridable fields]` | `create?` (fund `update?` + entity flag) | Redirect to overview, flash "This fund is now evergreen" | 422, form errors |
| `SettingsController#update` | same | `update?` | Turbo Stream form, "Settings saved" | 422 |
| `SettingsController#preset` | `name` | `update?` | Turbo Stream form, unsaved | 404 for an unknown preset |
| `SettingsController#destroy` | — | `destroy?` | Redirect | Flash "Dealing dates exist — cannot switch back" |
| `NavsController#create` | `nav_date` | `create?` | Redirect to the draft | Flash with the builder error (e.g. missing valuation) |
| `NavsController#override` | `line`, `value`, `reason` | `update?` (draft only) | Turbo Stream NAV card | 422 with reason error |
| `NavsController#approve` / `#reopen` / `#recalculate` / `#destroy` | — | `approve?` / `reopen?` / `update?` / `destroy?` | Turbo Stream / redirect | Flash with the service error |
| `OrdersController#preview` | `dealing_order: [:kind, :unit_type, :amount, :units, :all_units, :capital_commitment_id]` | `new?` | Turbo Stream indicative block | Turbo Stream errors |
| `OrdersController#create` | same + `:note`; admins also `:investor_id, :received_at` | `create?` | Done step / redirect | 422 with eligibility message |
| `OrdersController#cancel` / `#accept` / `#reject` (`rejected_reason`) / `#verify_signatory` | — | `cancel?` / `accept?` / `reject?` / `verify?` | Turbo Stream row or step bar | Flash |
| `DealingDatesController#show` | — | `show?` | HTML | — |
| `DealingDatesController#confirm` | `preview_hash` | `confirm?` | Redirect to tracker | Flash "Pricing changed — review again" / "Approve the NAV …" |
| `DealingDatesController#undo` / `#close` | — | `undo?` / `close?` | Redirect | Flash with reason |
| `DealingFillsController#record_payment` | `amount, payment_date, reference` | `update?` on the dealing date | Turbo Stream row | 422 |
| `DealingFillsController#verify` / `#mark_paid` (`payment_date, reference`) / `#resend` | — | `update?` | Turbo Stream row | Flash |
| `DealingDatesController#generate_documents` | — | `generate_documents?` (fund `update?`) | Enqueue `EvergreenDocumentsJob`; redirect, flash "Generating N documents — you'll be notified when they are ready" | Redirect, alert "Nothing to generate — every settled order already has its document or email" (no job) |
| `DealingDatesController#approve_documents` | — | `approve_documents?` (`generate_documents?` + approver role) | Redirect, flash "N documents approved and sent" | Alert "No documents waiting for approval"; 403 via Pundit without the role |
| `DealingFillsController#regenerate` | — | `generate_documents?` on the dealing date | Turbo Stream row, "Document regenerated" | Flash with the `regenerate` error |
| `OverviewController#show`, `InvestorsController#index` (+ `.xlsx`), `FeesController#show`, `SettlementsController#show`, `FoliosController#show` | — | `show?` / `index?` | HTML / xlsx | — |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params never include `entity_id`, `fund_id`, `prepared_by_id`, `approved_by_id`, `enabled_by_id`, `status`
- [ ] Investors cannot pass `investor_id` or `received_at` (stripped for non-GP users)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Guard B3/B4 | `DealingDate.exists?(subscription_call_id: id)` | `index_dealing_dates_on_subscription_call_id` | 0–1 | — |
| Guard B5/B6 | `DealingFill.exists?(capital_remittance_id: id)` / `(capital_distribution_payment_id: id)`; `DealingOrder.exists?(capital_remittance_id: id)` | idx on each | 0–1 | — |
| `NavInputs` ledger balance | `fund.fund_account_entries.where(name:, reporting_date: ..date).order(reporting_date: :desc).pick(:amount_cents)` | `idx_fund_id_and_name_and_reporting_date` | 1 | `pick`, never loads rows |
| Management fee window | `AccountEntry.where(fund_id:, entry_type: "Management Fees", reporting_date: (prev+1)..date, capital_commitment_id: class_folio_ids).sum(:amount_cents)` and `.maximum(:reporting_date)` | `idx_fund_id_and_entry_type_and_reporting_date` | aggregate | `class_folio_ids` via `pluck(:id)` on commitments (small) |
| Units by class | `FundUnit.where(fund_id:, issue_date: ..date).group(:unit_type).sum(:quantity)` | `index_fund_units_on_fund_id` | aggregate | — |
| Units per folio (register, investor cap, crystallisation split) | `FundUnit.where(fund_id:, issue_date: ..date).group(:capital_commitment_id).sum(:quantity)` | same | ≤ folios | — |
| Lot ages (lock-up) | `FundUnit.where(capital_commitment_id:, unit_type:).where("quantity > 0").order(:issue_date).pluck(:issue_date, :quantity)` | `index_fund_units_on_capital_commitment_id` | tens | `pluck` |
| Latest approved NAV | `FundNav.where(fund_id:, unit_type:, status: "approved", nav_date: ..date).order(nav_date: :desc).first` | composite | 1 | — |
| Queue position | `DealingOrder.where(fund_id:, kind: "redemption", status: %w[pending partially_filled]).where("(received_at, id) < (?, ?)", received_at, id).count + 1` | composite | count | — |
| Order book | `policy_scope(DealingOrder).where(fund_id:, status: <filter>).includes(:investor, :capital_commitment, :dealing_date, :dealing_fills)` | composite | ≤ hundreds | paginated (`pagy`, 50); Open by default |
| Gate forecast | open redemptions of the fund `.includes(:investor, :dealing_date, :dealing_fills).in_queue_order` | composite | tens | whole set (gate needs every queued order, not one page) |
| Tracker | `dealing_date.dealing_fills.includes(:dealing_order, :fund_unit, capital_remittance: [], capital_distribution_payment: [])` | UK | ≤ hundreds | preload |
| Gate consumption | `DealingFill.joins(:dealing_date).where(fund_id:, kind: "redemption", dealing_dates: { status: %w[confirmed closed], date: period_range })` with `.sum(:amount_cents)` / `.group(:unit_type)` | dealing_dates UK + fills idx | aggregate | — |
| Staleness | four `count` + `maximum(:updated_at)` aggregates (account entries with `capital_commitment_id: nil` via `idx_ae_report_fund_cumulative_date`; management-fee window; `fund_units`; valuations of the fund's portfolio companies) | as listed | aggregate | Computed only for drafts and the latest approved NAV per class |

**Reviewer checks**
- [ ] Every query is scoped by `fund_id` (and so by entity, through the fund policy scope)
- [ ] No `account_entries` row is loaded into Ruby: only `pick`/`sum`/`maximum`/`count`
- [ ] No N+1 on the order book, tracker or register (checked with the Bullet log in development)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `DealingConfirm` | Fills, order updates, roll, `DealingSettlement.settle`, dealing date status | `dealing_date.lock!` first, then nothing else explicitly | Double confirm; a confirm racing a cancel (the hash compare catches it) | Status must be `open`; UK (dealing_date_id, dealing_order_id) on fills |
| `DealingUndo` | Reverse settle, delete fills, restore orders | `dealing_date.lock!` | Undo racing an allotment | Status must be `confirmed`; no `fund_unit_id` |
| `DealingOrderCreate` (pre-funded) | Order + folio + adjustment + call (if missing) + remittance | `DealingDate` row `lock!` when creating the call | Two first orders creating two calls | `dealing_dates.subscription_call_id` set under lock |
| `DealingOrderCancel` | Order + remittance destroy + adjustment reverse | `order.lock!` | Cancel racing confirm (confirm locks the date and re-reads statuses) | Status must be `pending` |
| `FundNavApprove` / `FundNavReopen` | Status + crystallisation entries | `fund_nav.lock!` | Double approve; reopen racing a confirm (confirm re-reads `fund_nav.status`) | Status checks |
| `EvergreenAllotment.allot/cancel` | Engine call + `fill.update!(fund_unit_id:)` | `fill.lock!` | Duplicate units from two sync jobs | `fund_unit_id` null check after lock |
| `EvergreenDealingDocuments.generate` / `approve_and_send` | None spanning fills: one `update!` per fill, emails after each approval | None (a double click on Approve & send can at worst race on one fill; `document_sent_at` is re-read per fill — reviewer: consider `fill.with_lock` around approve + send) | Two Generate runs at once (both see the same fill without a document) | `document_id` / `document_sent_at` null checks |

Lock order is always `dealing_date` → `fund_nav` → `fill` / `order`. Emails and documents are always enqueued after commit (`after_commit` / `ActiveRecord.after_all_transactions_commit`), never inside the transaction.

**Reviewer checks**
- [ ] No mail or document generation inside any transaction above
- [ ] Lock order is the same everywhere two rows are locked
- [ ] Counter-culture updates inside `settle` use the existing `skip_counter_culture_updates` + `CapitalRemittancesCountersJob` pattern

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `DealingSettlementSyncJob` | `:default` | `after_commit` on guarded settlement records; enqueued by `DealingConfirm` | Sidekiq default (25, exponential) | `ActiveRecord::RecordNotFound` | `fill.lock!` + `fund_unit_id` check | — |
| `DealingDateGenerateJob` | `:low` | Cron `"15 1 * * *"` (UTC), registered in `config/initializers/sidekiq.rb` beside `WorkflowEvaluateJob` | 3 | — | UK (fund_id, date) + `find_or_create_by!` | — |
| `EvergreenDocumentsJob` (**Generate documents**) | `:doc_gen` (the existing document queue) | `DealingDatesController#generate_documents` | Sidekiq default; a retry regenerates only fills still without a document | `RecordNotFound` | `to_generate` excludes fills with `document_id` or `document_sent_at` | — |
| `EvergreenNotifier` deliveries | Noticed default | Events | Noticed default | — | One event per (record, kind) | — |
| `EvergreenNotificationsJob` | `:low` | Cron `"30 2 * * *"` (UTC, after `DealingDateGenerateJob`), registered beside it | 3 | — | `evergreen_notification_logs` UK claim | — |
| `EvergreenOpsNotifier` deliveries | Noticed default | `EvergreenAlerts.notify` | Noticed default | — | Log claim before `deliver` | — |
| Journey re-evaluation | existing `WorkflowEvaluateJob` (every 15 min) | Picks up cut-off passing for dealing-date journeys | existing | — | existing | — |

**Reviewer checks**
- [ ] A sync job that runs twice, or before confirm, is harmless (it no-ops)
- [ ] The cron entry is registered in the non-local branch of `config/initializers/sidekiq.rb`
- [ ] Cut-off steps rely on `WorkflowEvaluateJob` and also re-evaluate on page load (`journey_progress!`)

---

## External Integrations

N/A — no third-party APIs. Bank reconciliation is the existing in-app flow.

**Reviewer checks**
- [ ] No new outbound HTTP calls

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `NavInputs::MissingValuation` (wraps the `fmv_on_date` raise) | `NavInputs` | `FundNavBuilder` → result error | "No valuation for Pharma Co on or before 31 Oct 2026 — add one or upload the NAV" | info log |
| `DealingCalendar::NoDate` | `DealingCalendar` | `DealingOrderCreate` | "No dealing date is available — check the fund's dealing calendar" | warn log (fund id) |
| `DealingOrder::NoNav` | `resolved_units` (amount form with no approved NAV) | `OrderEligibility` | "No approved NAV yet — enter units or try after the next NAV is approved" | — |
| `DealingSettlement::Error` | `DealingSettlement` | `DealingConfirm` (rolls back) / `DealingOrderCreate` | "Couldn't settle: <reason>" | error log with fund, date, order ids + `ExceptionNotifier` |
| `DealingConfirm::PricingChanged` | `DealingConfirm` | Controller | "Pricing changed — review again" | info |
| Engine errors (existing return shape) | `EvergreenAllotment` | Sync job: `UserAlert` to the actor; tracker row "Units not allotted — retry" | as described | the engine's existing `EntityMailer` mail |
| `Noticed` / mailer failure | `EvergreenNotifier` | Noticed retries; after the final failure the row shows "Not sent — Resend" | as described | error log |
| Any `StandardError` generating one document (bad template, Sablon/PDF conversion) | `EvergreenDocTemplateGenerator` | `EvergreenDealingDocuments.generate` (rescued per fill) | Job alert "… K failed: <investor>: <message>"; row "Not generated — Regenerate" | error log with fill id |
| Regenerate refused | `EvergreenDealingDocuments.regenerate` | Controller | "Approved documents can't be regenerated" / "No template for this document" | — |

All log lines carry `entity_id`, `fund_id`, `dealing_date_id` and/or `fund_nav_id`.

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors; the sync job re-raises after alerting
- [ ] Each user-visible message above matches the proposal's Behavior Rules verbatim

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | One policy per model, all `< FundBasePolicy`. Approve, reopen, accept and reject need `user.has_cached_role?(:approver)` + fund `update?` (same as `CapitalCallPolicy#approve?`). Confirm, undo, close and tracker actions need fund `update?`. Investor `create?` needs `permissioned_investor?` on the fund + own investor |
| Maker-checker | Enforced in `FundNavApprove` (`current_user != fund_nav.prepared_by`), not only in views |
| Document approval | `DealingDatePolicy#approve_documents?` requires the approver role; investors never see a generated document until it is approved (existing "Generated" document rule); an approved document cannot be regenerated |
| Tenant isolation | Every table has `entity_id`; `policy_scope` builds on `FundBasePolicy::Scope`; `ForInvestor` lists include `FundNav` (approved only, via `FundNavPolicy::Scope`) and `DealingOrder` |
| Secrets | None stored. `payment_instructions` is plain text shown to investors of the fund only |
| Input / output sanitisation | ERB escaping; `payment_instructions` rendered with `simple_format` (escaped); uploads through `ImportUtil` (xlsx only); override reason max 255 |
| Mass assignment | See [Controllers](#controllers-params-and-responses); ownership and status fields are never permitted |
| Formula eval | The seeded formula string is checked against `SAFE_EVAL_REGEX` in `EvergreenFeeFormulaSeed` before save |
| MCP | No ontology changes; new models are not exposed |

**Reviewer checks**
- [ ] A user from another entity cannot reach any evergreen record through any route, job, upload or document link (X19, C4)
- [ ] An investor cannot see draft NAVs or another investor's orders (E12, X19)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new. IN and US deploy independently with the same code |
| Feature flag | `Entity#enable_evergreen_funds` (36th bit of `entities.permissions`, appended); default off; turned on per entity by support (admin entity settings) |
| Cron / schedules | `DealingDateGenerateJob` daily 01:15 UTC; `EvergreenNotificationsJob` daily 03:30 (cron `30 3 * * *`) |
| Notification tags | Support / admins tick "FundOps", "FundAccounting", "Compliance" on the users who should get team alerts; with no one tagged, Fund ops alerts go nowhere (RM fallback included) |
| Seeds | `DealingDateJourneySetup` / `DealingOrderJourneySetup` seed templates per entity on first `EvergreenEnable` (idempotent); `rake evergreen:seed_journeys[entity_id]` for support |
| Deploy order | Migration → code → cron registration (restart Sidekiq) |
| Rollback | Turn the entity flag off: all evergreen UI disappears and closed-end behaviour is unaffected. Code rollback with the tables left in place is safe because nothing reads them when the flag is off. Dropping the tables is a manual, separate step |

**Reviewer checks**
- [ ] With the flag off on every entity, the app behaves identically (regression features green)
- [ ] Rolling back the code leaves no closed-end record depending on new tables

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/evergreen/settings.feature` | Entity flag helper | `:evergreen_fund_setting`, `:evergreen_class_term` | `Given the fund "…" is evergreen with:` (table of settings) |
| `nav.feature` | Valuations and account entries via existing steps | `:fund_nav` | `When I draft the NAV for …`, `Then the NAV line "…" is …` |
| `orders.feature`, `order_journeys.feature` | `travel_to` for received times; KYC via existing steps | `:dealing_order` | Wizard steps, order assertions, queue assertions |
| `dealing.feature`, `gates.feature` | `travel_to` cut-off | `:dealing_date` | `When I confirm the dealing date …`, `Then the fills are:` (table) |
| `settlement.feature` | Existing remittance-payment and verify steps | — | `When I mark the redemption of "…" paid` |
| `fees.feature` | Existing allocation-run steps | `:fund_formula` (seeded) | Fee and high-water-mark assertions |
| `gp_screens.feature`, `investor_portal.feature` | Investor login steps (existing) | — | Screen assertions |
| `documents.feature` | Existing email steps | — | Contract note / advice email-body assertions (E51) |
| `dealing_documents.feature` | Word templates uploaded as fund documents tagged "Contract Note Template" / "Redemption Advice Template" (fixtures under `features/support/files/`), a folio override (H60) and a broken file (X30); `EvergreenDocumentsJob` run inline; existing mail steps with attachment checks | — | `When I generate documents for the dealing date`, `When I approve and send the documents`, `Then the folio "…" has an unapproved "…" document`, `Then "…" receives the "…" email with a PDF attached` |
| `regression.feature` | Beta Growth Fund via existing call, distribution and unit steps | — | Reuses existing steps only |
| `notifications.feature` | `travel_to` for job dates; user tags and `managed_by` set in Given steps; existing email steps; Noticed rows for in-app | `:evergreen_notification_log` | `When the evergreen notifications job runs on "…"`, `Then "…" receives the "…" alert`, `Then no "…" notification is sent` |

Shared helper `features/support/evergreen_helpers.rb` builds the design's shared setup (Alpha fund, folios, NAVs, A/B/C redemptions). Runs: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/<file>.feature` with Redis on 6379.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | All guards and checks use `exists?`; `evergreen_fund_setting.present?` is on a `has_one` record, not a relation |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Folio id lists via `distinct.pluck`; crystallisation `insert_all` in batches of 500; `DealingDateGenerateJob` uses `find_each` over evergreen settings |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies | Only aggregates/`pick`; never `includes(:account_entries)`; reopen deletes by `fund_id`+`reporting_date`+`parent` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Every evergreen view uses `l(date)`; `EvergreenMailer < ApplicationMailer` inherits `EmailDateLocalization`; settlement names ("Subscription settlement — 2 Nov 2026") built with `I18n.l(date, format: :long)`-style formats, not `strftime` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | NAV date, received at, payment date, custom dealing dates use `f.date_field`; the wizard's dealing-date preview is server-rendered |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See [Security Review](#security-review) |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP exposure in this change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | See [Test Plumbing](#test-plumbing) |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run per phase in tasks |
| Backward compatibility (this change) | Applies | Guards B1–B8; `regression.feature` plus existing call, distribution and unit features run unchanged |
| Inline comments with worked-example IDs | Applies | Each guard and service step comments its H/E/X id and links `design.md#worked-examples` |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
