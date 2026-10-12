# Late management fees on evergreen NAVs — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/funds/open-ended-fees/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links rather than repeats.

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

- **The late arithmetic** (ledger since the last upload, dated ≤ previous NAV, minus Σ accounted) is the part
  most likely to be wrong at boundaries — see [Queries and Indexes](#queries-and-indexes) and design
  [card ③](design.md#③-late-fee-finder).
- **Backfill of `mgmt_fee_accounted_cents`** for already-approved NAVs decides whether old late entries
  surface — see [Schema Detail](#schema-detail).
- **Decisions keyed by amount** and kept across recalculation; one dropped if the late total shrinks below
  it — see [Method Contracts](#method-contracts).
- **Two new refusals in `FundNavApprove#check`**, re-checked under the existing lock — see
  [Transactions](#transactions-locking-and-concurrency).
- **Existing features break by design** where they approve fee-charging NAVs without accruals — see
  [Test Plumbing](#test-plumbing).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ② | `db/migrate/20261012090000_add_late_fee_columns_to_fund_navs.rb` | New | 3 columns + backfill |
| ② | `db/schema.rb`, `db/schema_test.rb` | Modified | Columns |
| ②⑤ | `app/packs/funds/evergreen/models/fund_nav.rb` | Modified | `late_fee_decisions` readers, `late_decided_cents`, `late_included_cents` |
| ③ | `app/packs/funds/evergreen/services/evergreen_late_fees.rb` | New | Late arithmetic + facts → `Result` |
| ③ | `app/packs/funds/evergreen/services/nav_inputs.rb` | Modified | `mgmt_fee_sums_by_date(unit_type, after, upto)`, `mgmt_fee_paid_sum(after, upto)` aggregates |
| ④ | `app/packs/funds/evergreen/services/fund_nav_builder.rb` | Modified | Late included / paid into payable; accounted figures; keep decisions |
| ⑤ | `app/packs/funds/evergreen/services/fund_nav_late_fee_decision.rb` | New | Validate, append / clear, rebuild |
| ⑤ | `app/packs/funds/evergreen/controllers/evergreen/navs_controller.rb` | Modified | `decide_late_fee` |
| ⑤ | `config/routes/fund.rb` | Modified | `patch :decide_late_fee` on evergreen navs |
| ⑤ | `app/packs/funds/evergreen/policies/fund_nav_policy.rb` | Modified | `decide_late_fee?` = `approve?` |
| ⑥ | `app/packs/funds/evergreen/services/evergreen_fee_check.rb` | New | `exempt?`, `accrual_message` (shared) |
| ⑥ | `app/packs/funds/evergreen/services/fund_nav_approve.rb` | Modified | Two refusals |
| ⑥⑦ | `app/packs/funds/evergreen/helpers/evergreen_nav_helper.rb` | Modified | `evergreen_mgmt_fee_warning` → `EvergreenFeeCheck` |
| ⑦ | `app/packs/funds/evergreen/services/evergreen_alerts.rb` | Modified | `fee_accrual_behind?` → `EvergreenFeeCheck`; awaiting-approval suffix |
| ⑦ | `app/packs/funds/evergreen/views/evergreen/navs/_late_fees.html.erb` | New | Panel + modal |
| ⑦ | `app/packs/funds/evergreen/views/evergreen/navs/show.html.erb` | Modified | Render panel; Approve disabled reason |
| ⑦ | `app/packs/funds/evergreen/services/evergreen_fee_summary.rb`, `views/evergreen/fees/show.html.erb` | Modified | Row notes |
| Docs | `docs/modules/funds/evergreen_business_rules.md`, `docs/user_guides/evergreen_funds_user_guide.md` | Modified | Drop "not yet built"; payments always included; FAQs |
| Tests | `features/fund/evergreen/late_fees.feature`, `features/step_definitions/evergreen_late_fee_steps.rb` | New | H105–H108, E329–E345, X204–X208 |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/funds/evergreen/...`)

---

## Schema Detail

**`fund_navs`** (existing): stores what each NAV accounted for and its late-fee decisions.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `mgmt_fee_accounted_cents` | Added | decimal | (20,2) | no | 0 | — | Same precision as `mgmt_fee_payable_cents`; Σ'd by ③ |
| `mgmt_fee_paid_accounted_cents` | Added | decimal | (20,2) | no | 0 | — | As above, payments |
| `late_fee_decisions` | Added | json | — | yes | nil | — | Small array (≤ a few items); same storage choice as `overrides` |

**Migration safety:** `fund_navs` is small (tens of rows per fund). Plain `add_column` ×3, then a data step
over evergreen funds' approved computed NAVs, ordered by `nav_date`:
- accounted = `breakdown["mgmt_fee_accrued_cents"]`, else `NavInputs#mgmt_fee_accrued_cents(unit_type, prev_date)`
  as of now;
- paid accounted = `breakdown["mgmt_fee_paid_cents"]`, else the window's payments split by `FundNavBuilder#split_payment`.

The data step logs NAV ids where the ledger window sum differs from the saved breakdown value. It is
reversible (`remove_column`). Per the repo's local-migrate note, `schema.rb` / `schema_test.rb` are edited by
hand.

**Reviewer checks**
- [ ] Every new column has a "why"
- [ ] Decimal precision matches `mgmt_fee_payable_cents`
- [ ] Data step touches evergreen funds only, and never `account_entries` rows (sums only)

---

## Method Contracts

**`EvergreenLateFees`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund, unit_type, nav_date, draft: nil)` | Fund, String, Date, the draft FundNav (for its decisions) | `Result` (Data): `late_cents`, `decided_cents`, `included_cents`, `outstanding_cents`, `late_paid_cents`, `periods` [FundNav], `pct_of_nav`, `redeemed_investors` Integer, `reopenable` [FundNav] | — | None (reads) | Yes |

**`EvergreenFeeCheck`** (Service, module functions)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.exempt?(fund_nav)` | FundNav | Boolean: uploaded, fee 0 or units ≤ 0 | — | — | Yes |
| `.accrual_message(fund_nav)` | FundNav | String or nil ("…, then recalculate") | — | — | Yes |

**`FundNavLateFeeDecision`** (Trailblazer op, like `FundNavReopen`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(fund_nav:, choice:, reason:, current_user:)` | `choice` ∈ include / exclude / clear | Result with `errors` | — | Appends `{amount_cents: outstanding, choice, reason, user_id, decided_at}` (or clears), audit comment, `FundNavBuilder.call` for the date | Re-submitting with 0 outstanding is refused ("Nothing left to decide") |

**`FundNav`** (Model)

| Method | Returns |
|---|---|
| `late_decided_cents` | Σ amount of decisions |
| `late_included_cents` | Σ amount where choice = include |

**`FundNavBuilder`** (modified): `build_class_nav` reads `EvergreenLateFees.call(..., draft: nav)` before saving;
when `late_cents < late_decided_cents` it drops decisions newest-first until they fit, with audit
comment "Late fee decision removed: the late amount changed" (E341).

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] A double click on Save can't record the same amount twice (outstanding is re-read under lock)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `Evergreen::NavsController#decide_late_fee` (PATCH) | `late_fee: [:choice, :reason]` | `decide_late_fee?` (= `approve?`: draft, approver role, fund update) | Redirect to NAV, notice "Late fee included" / "Late fee excluded" / "Late fee decision cleared" | Redirect to NAV with alert = op error |

**Reviewer checks**
- [ ] `authorize @fund_nav, :decide_late_fee?` present
- [ ] `amount_cents` is never a param (taken from the finder under lock)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| ③ last upload | `FundNav.approved.where(fund_id:, unit_type:, source: "uploaded", nav_date: ..d).maximum(:nav_date)` | `fund_id, unit_type, nav_date` | 1 | — |
| ③ previous NAV | existing `NavInputs#previous_nav` | same | 1 | — |
| ③ accruals by date | `AccountEntry.where(fund_id:, entry_type: MGMT_FEE_ENTRY_TYPE, capital_commitment_id: class_folio_ids, reporting_date: (U+1)..P).group(:reporting_date).sum(:amount_cents)` | existing account_entries fund/date indexes | ≤ NAV count | aggregate only |
| ③ Σ accounted | `FundNav.approved.where(fund_id:, unit_type:, source: "computed", nav_date: (U+1)..P).sum(:mgmt_fee_accounted_cents)` | as above | 1 | — |
| ③ paid late | fund ledger `sum` for paid entry name in (U_fund, P] minus Σ `mgmt_fee_paid_accounted_cents` across classes | fund account entries | 1 | — |
| ③ redeemed | `DealingFill.joins(:dealing_order, :dealing_date).where(fund_id:, kind: "redemption").where("units > 0").where(dealing_dates: { date: (earliest_period+1)..d }).distinct.count("dealing_orders.investor_id")` | dealing_fills fund | 1 | — |
| ③ reopenable | `DealingFill.where(fund_nav_id: period_ids).distinct.pluck(:fund_nav_id)` | fund_nav_id | ≤ periods | one query |

**Reviewer checks**
- [ ] Every query is scoped by `fund_id` (fund already entity-scoped)
- [ ] No `account_entries` rows loaded; `distinct` in SQL

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Decide | Decision write + rebuild | `fund_nav.with_lock` | Two approvers deciding the same outstanding twice | outstanding re-read under lock |
| Approve | existing | existing `fund_nav.lock!` | Approving after a concurrent clear / new late entry | refusals re-checked under lock |
| Draft | existing builder transaction | — | — | — |

**Reviewer checks**
- [ ] No email inside the transaction (the alert is fired by the existing `nav_drafted` after commit)
- [ ] Lock order: NAV row only

---

## Background Jobs

N/A — everything runs in the request; alerts use the existing `EvergreenAlerts` path.

---

## External Integrations

N/A — no third-party calls.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Validation (no choice / blank reason / nothing outstanding / approved NAV) | Decision op | Controller | Flash alert with the message | — |
| `ActiveRecord::RecordInvalid` in rebuild (e.g. negative NAV) | Builder | Decision op rescues → errors, rolls back | Builder's message | — |
| Backfill window mismatch | Migration | — | — | `say` line per NAV id |

**Reviewer checks**
- [ ] No bare `rescue => e`
- [ ] Audit comments carry user and amounts

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `FundNavPolicy#decide_late_fee?` = approve rules; `FundNavApprove` re-checks |
| Tenant isolation | NAV loaded through `policy_scope`; finder scoped by `fund_id` |
| Secrets | None |
| Input / output sanitisation | Reason: string ≤ 255, rendered escaped |
| Mass assignment | Only `choice`, `reason` |

**Reviewer checks**
- [ ] A user from another entity cannot reach `decide_late_fee` for a NAV they can't see

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None — evergreen funds only, by fund type |
| Cron / schedules | None |
| Deploy order | Migration (with backfill) → code |
| Rollback | Revert code; the columns are harmless; `down` removes them |

**Reviewer checks**
- [ ] Safe to deploy: after backfill, no existing draft shows a surprise late amount (check the migration log)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/evergreen/late_fees.feature` | Redis up (fund creation) | existing evergreen steps | `Given class {string} has an approved computed NAV on {string} of {string} with no fee accrued`; `When the approver decides to {string} the late fee( with reason {string})`; `Then the late fees panel for class {string} should show {string}`; `Then approving the NAV for {string} is refused with {string}` |
| `fees.feature` (E35), `notifications.feature` (accrual alert) | — | — | Text "…, then recalculate" |
| Other evergreen features approving fee-charging NAVs without accruals | — | — | Add accruals or 0% fee (audit list in tasks) |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Finder uses `sum`/`maximum`/`exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | `distinct.count`, `distinct.pluck` |
| Select only needed columns when loading many `account_entries` | Applies | Aggregates only — no rows loaded |
| Screen dates via `l(...)`; emails `Mon dd, yyyy` | Applies | Panel and alert use `l` / `I18n.l` |
| Date inputs use `f.date_field` | N/A | No date inputs |
| Every query entity-scoped; Pundit on every action | Applies | `authorize`; fund-scoped queries |
| MCP ontology | N/A | No MCP surface changed |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | `late_fees.feature`; run with pcuc -n 4 |
| rubocop clean incl. `IRM/RelationBlankPresent` | Applies | Run on touched files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
