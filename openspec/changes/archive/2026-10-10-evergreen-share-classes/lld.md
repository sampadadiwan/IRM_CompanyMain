# Share Classes: Fair Split and Class-Only Expenses — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document adds to [design.md](design.md).

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

- **The stake formula is the correctness core.** It is previous NAV + own lines owed − own
  payments since, scaled by units now ÷ previous units, and clamped at 0. Fee over-payments keep
  today's value split (`value_shares`), so open-ended-funds E199 and E200 don't move. See [Method Contracts](#method-contracts) and design
  [card ③](design.md#③-class-stake).
- **`fee_payments_by_class` now feeds the stake as well as the payables.** A wrong split shows up
  twice, so check E6 (excess) closely.
- **Class expense payments go straight to their class.** They are not part of
  `fee_payments_by_class`'s owed-ratio split.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `db/migrate/20261010000001_add_class_expense_entries_to_evergreen_class_terms.rb` | New | Two columns |
| ① | `app/packs/funds/evergreen/models/evergreen_class_term.rb`, `evergreen_fund_setting.rb`, `evergreen_terms.rb` | Modified | Length validation; cross-class checks (X1–X5); expose on `terms_for` |
| ① | `app/packs/funds/evergreen/controllers/evergreen/settings_controller.rb`, `views/evergreen/settings/show.html.erb` | Modified | `CLASS_FIELDS`; two inputs in "Customise this class"; Review step |
| ② | `app/packs/funds/evergreen/services/nav_inputs.rb` | Modified | `unclaimed_class_entries` |
| ③ | `app/packs/funds/evergreen/services/class_apportioner.rb` | Modified | Stake rule, `paid:` keyword |
| ④ | `db/migrate/20261010000002_add_class_expenses_payable_to_fund_navs.rb` | New | One column |
| ④ | `app/packs/funds/evergreen/models/fund_nav.rb` | Modified | `LIABILITY_LINES` + `class_expenses_payable` |
| ④ | `app/packs/funds/evergreen/services/fund_nav_builder.rb` | Modified | Two-pass shares, class expense line, breakdown |
| ⑤ | `app/packs/funds/evergreen/helpers/evergreen_nav_helper.rb`, `views/evergreen/navs/show.html.erb` | Modified | Label, conditional row, warning |
| all | `db/schema.rb`, `db/schema_test.rb` | Modified | Three column additions |
| docs | `docs/modules/funds/evergreen_business_rules.md`, `docs/user_guides/evergreen_funds_user_guide.md`, `docs/modules/funds/evergreen_share_classes_plan.md` | Modified | Stake rule, class expenses, remove the "known issue" |
| tests | `features/fund/evergreen/class_nav.feature`, `class_expenses.feature`, `features/step_definitions/evergreen_class_nav_steps.rb` | New | H/E/X scenarios |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here
- [ ] No file outside `app/packs/funds/evergreen`, the migrations, schema files, docs and features

---

## Schema Detail

**`evergreen_class_terms`** (existing): the class's own expense entries.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `class_expense_entry_name` | Added | string | 125 | yes | none | — | Matches the 125 limit on the fund's other ledger-name settings |
| `class_expense_paid_entry_name` | Added | string | 125 | yes | none | — | Same |

**`fund_navs`** (existing): the class expenses line.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `class_expenses_payable_cents` | Added | decimal | (20,2) | no | 0.0 | — | Same type as `mgmt_fee_payable_cents`; a default of 0 keeps existing rows valid and `recompute_totals!` unchanged for them |

**Migration safety:**
- **Table sizes:** both tables are small (one row per class, and per class per NAV date).
- **Locking:** `add_column` is instant on MySQL 8.
- **Reversibility and data:** both are reversible, with no back-fill.
- **Schema files:** update `schema.rb` and `schema_test.rb` by hand after migrating (local migrate
  drops tables), then run `db:clean_schema`.

**Reviewer checks**
- [ ] Column limits match the validation limits (125)
- [ ] `schema_test.rb` (SQLite) has the same three columns

---

## Method Contracts

**`ClassApportioner`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.value_shares(inputs, unit_types)` | — | Today's rule: units × previous NAV per unit (or initial price), for sharing fee over-payments | — | — | Yes |
| `.shares(inputs, unit_types, paid: {})` | `paid`: `{ut => BigDecimal cents}`, the class's own payments since its previous NAV | `{ut => BigDecimal}` rounded to 10 dp, summing to 1 ± 1e-9 | — | — | Yes |

The stake per class, when the previous NAV exists and its units are above 0:
- `gross_prev = prev.nav_cents + prev.mgmt_fee_payable_cents + prev.perf_fee_payable_cents + prev.perf_fee_accrued_cents + prev.class_expenses_payable_cents`
- `stake = max(gross_prev × units_now ÷ prev.units_outstanding − paid[ut], 0)`

Otherwise `stake = units_now × initial_price_cents`. One class → `{ut => 1}`. A total of 0 → an
equal split.

**`FundNavBuilder`** (Operation, private but reviewed)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#build_navs` | — | — | — | Computes `@paid = fee_payments_by_class(inputs, unit_types, value_shares)` (excess by value, as today), then `@class_paid[ut] = ledger_sum(paid entry)`, then `shares(…, paid: mgmt + perf + class_paid)` | Yes (a re-draft replaces drafts) |
| `#class_expenses_payable(prev, term, inputs)` | — | BigDecimal: `prev.class_expenses_payable_cents + ledger_sum(expense) − ledger_sum(paid)`; 0 when the class has no entries | — | — | Yes |

**`NavInputs`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#unclaimed_class_entries` | — | `Array<String>`, sorted, at most 20 | — | One `distinct.pluck` | Yes |

**`EvergreenFundSetting`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `validate :class_expense_entries` | — | Errors X1, X2, X3, X5 on `base` | — | One `pick` per class being cleared (X5) | Yes |

**Reviewer checks**
- [ ] `ledger_sum_cents` windows are `(prev_date, nav_date]`, so a payment on the previous NAV date
  isn't counted twice (E13)
- [ ] A class whose previous NAV is uploaded reads 0 for every own-line column (E5)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `Evergreen::SettingsController#update` / `#create` | `CLASS_FIELDS` adds `:class_expense_entry_name, :class_expense_paid_entry_name` | The existing evergreen settings policy | As today | Review step with errors (X1–X5) |

**Reviewer checks**
- [ ] No new action and no new route

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `NavInputs#unclaimed_class_entries` | `fund.fund_account_entries.where(reporting_date: ..date).where("account_entries.name LIKE 'Class %'").distinct.pluck(:name)` | `fund_id` (+ `reporting_date`) | ≤ dozens of names | Once per draft |
| Class expense sums | `ledger_sum_cents(name, prev_date, nav_date)` × 2 per class | As the existing fee-paid sums | Aggregate | — |
| X5 check | `FundNav.where(fund_id:, unit_type:).order(nav_date: :desc).pick(:class_expenses_payable_cents)` | `[fund_id, unit_type, nav_date]` unique | 1 | Only when entries are being cleared |

**Reviewer checks**
- [ ] No row loads of `account_entries`: aggregates and `distinct.pluck(:name)` only
- [ ] Every query is fund-scoped

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| NAV draft | The existing `build_navs` transaction | none new | — | `[fund_id, unit_type, nav_date]` unique (existing) |

**Reviewer checks**
- [ ] The drafted alert stays after the transaction, as today

---

## Background Jobs

N/A. No new jobs.

---

## External Integrations

N/A. No external calls.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordInvalid` (a negative NAV from class expenses) | `FundNav` validation | The `FundNavBuilder#build_navs` rescue (existing) | The existing negative-NAV message (X6) | No |
| Validation errors X1–X5 | `EvergreenFundSetting` | The settings controller (existing) | The design's messages | No |

**Reviewer checks**
- [ ] No new `rescue`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | The existing evergreen settings and NAV policies |
| Tenant isolation | Every query is fund-scoped |
| Secrets | None |
| Input / output sanitisation | Entry names are escaped by ERB and used as bound SQL values |
| Mass assignment | Two fields added to `CLASS_FIELDS` |

**Reviewer checks**
- [ ] The entry names can't be set without fund update rights

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None. Funds that owe nothing get the same figures |
| Deploy order | Migrations → code |
| Rollback | Revert the code. The columns are nullable or defaulted, so they are safe to leave |

**Reviewer checks**
- [ ] Release note for multi-class funds with unpaid fees: the next draft's split shifts, correctly

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/evergreen/class_nav.feature` | Ledger entries via the existing evergreen ledger steps | The existing evergreen fund, classes and NAV | `Given class "A" owed a management fee of …`, `Then the class NAVs are …` |
| `features/fund/evergreen/class_expenses.feature` | Same | Same | `Given class "B" uses expense entries …`, `Then class "B" shows class expenses payable …` |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | Aggregates, `pick` and `pluck` only |
| Dedup in SQL, batch bulk operations | Applies | `distinct.pluck(:name)`; no bulk writes |
| Needed columns only on `account_entries`; no speculative `includes` | Applies | `pluck(:name)` and `sum` |
| Screen dates via `l(...)`; email date format | Applies | Messages reuse `I18n.l`; no new dates |
| Date inputs via `f.date_field` | N/A | No date inputs |
| Entity-scoped queries; Pundit on every action | Applies | No new actions; fund-scoped |
| MCP ontology | N/A | No MCP change |
| Cucumber only; distinct `TEST_ENV_NUMBER` | Applies | Two new features |
| `bundle exec rubocop` clean | Applies | Run before each phase's feature task |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
