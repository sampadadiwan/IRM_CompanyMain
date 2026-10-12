# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Runs: `TEST_ENV_NUMBER=$RANDOM` on every cucumber run, Redis up on 6379; multi-file runs with
> `pcuc <files> -n 4` (check `pgrep -fa pcuc` first).

## 1. Approval refuses a NAV without its fee (R9.2)

- [x] 1.1 Add `EvergreenFeeCheck` (`exempt?`, `accrual_message` ending "…, then recalculate") per
      [LLD Method Contracts](lld.md#method-contracts); comment the exempt branches with E342, E343, E344.
      Verify: `bin/rails runner` on a fund 356 NAV returns nil for the 30/04 (no units) NAVs.
- [x] 1.2 Point `evergreen_mgmt_fee_warning` and `EvergreenAlerts#fee_accrual_behind?` at `EvergreenFeeCheck`
      (remove the duplicated rules). Verify: rubocop clean; the NAV page renders for fund 356.
- [x] 1.3 Add the accrual refusal to `FundNavApprove#check` after the stale check, re-checked under the lock
      ([LLD Transactions](lld.md#transactions-locking-and-concurrency)); comment X208 / H108. Show the same
      message as the NAV page's disabled-Approve reason. Verify: approving a fee-charging draft with no
      accrual in `bin/rails runner` returns the error.
- [x] 1.4 Audit existing evergreen features that approve fee-charging drafted NAVs without accruals
      (`grep` for `drafted and approved`, `charges a management fee`) and add accruals or a 0% fee where the
      fee isn't the point; update E35 (`fees.feature`) and the alert text in `notifications.feature` to
      "…, then recalculate". Verify: list of changed scenarios recorded in this task's commit message.
- [x] 1.5 Write `features/fund/evergreen/late_fees.feature` (header links to design.md#worked-examples) with
      H108, E342, E343, E344, E345, X208, each with its "ID — …" comment. Run
      `pcuc features/fund/evergreen/late_fees.feature features/fund/evergreen/fees.feature features/fund/evergreen/notifications.feature features/fund/evergreen/class_nav.feature -n 4`
      and confirm green before starting phase 2.

## 2. What each NAV accounted for, and finding late amounts

- [x] 2.1 Migration `add_late_fee_columns_to_fund_navs` with the backfill described in
      [LLD Schema Detail](lld.md#schema-detail); hand-edit `db/schema.rb` and `db/schema_test.rb`.
      Verify: `bin/rails db:migrate` on the dev DB (with the user's go-ahead — shared DB) logs the backfill and
      `FundNav.where(fund_id: 356).pluck(:mgmt_fee_accounted_cents)` equals each window's accruals.
- [x] 2.2 `NavInputs`: `mgmt_fee_sums_by_date(unit_type, after, upto)` and `mgmt_fee_paid_sum(after, upto)`
      aggregates ([LLD Queries](lld.md#queries-and-indexes)). Verify: runner output for fund 356 matches the
      Fees tab's accrued column.
- [x] 2.3 `EvergreenLateFees` returning the full `Result` (late, decided, included, outstanding, late paid,
      periods, % of NAV, redeemed investors, reopenable) — design [card ③](design.md#③-late-fee-finder);
      comment branches with E330, E331, E332, E338, E339, E340. Verify: runner on fund 356 returns 0 late.
- [x] 2.4 `FundNavBuilder`: payable = previous + window + included late − (window paid + late paid); save
      `mgmt_fee_accounted_cents` / `mgmt_fee_paid_accounted_cents`; add late paid into
      `fee_payments_by_class`; keep `late_fee_decisions` across rebuilds and drop decisions that exceed the
      late total with an audit note — design [card ④](design.md#④-nav-draft); comment H105, E336, E337, E341.
      Verify: drafting fund 356's next NAV leaves the payable unchanged (nothing late).
- [x] 2.5 Add to `late_fees.feature`: H105 (asserting the draft's late amount and % via steps, not the panel
      yet), E329, E330, E331, E332, E333, E336, E337, with steps in
      `features/step_definitions/evergreen_late_fee_steps.rb` ([LLD Test Plumbing](lld.md#test-plumbing)).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/late_fees.feature` and
      confirm green before starting phase 3.

## 3. Deciding, the panel and the second refusal (R9.12–R9.16)

- [x] 3.1 `FundNav#late_decided_cents` / `#late_included_cents`; `FundNavLateFeeDecision` op (lock, validate,
      append / clear, audit, rebuild) — [LLD Method Contracts](lld.md#method-contracts); comment H106, H107,
      E334, E335, X204, X206. Verify: runner include on a test draft rebuilds the payable.
- [x] 3.2 Route `patch :decide_late_fee`, `NavsController#decide_late_fee`, `FundNavPolicy#decide_late_fee?`
      ([LLD Controllers](lld.md#controllers-params-and-responses)); comment X205. Verify: `bin/rails routes`
      lists it.
- [x] 3.3 `FundNavApprove#check`: refuse with "Decide the late management fee for class X first" while
      outstanding > 0 (under the lock); comment X207. Verify: runner refusal on an undecided draft.
- [x] 3.4 `navs/_late_fees` panel + Bootstrap decide modal (no option pre-selected; reason required for
      Exclude), wired into `navs/show`; read-only after approval; reuse existing card / badge / action-summary
      styling. Verify: render the dev NAV page and screenshot it against the proposal mockup and the UI
      checklist.
- [x] 3.5 Fees tab: `EvergreenFeeSummary::NavRow` late fields and row notes ("+ ₹… late (period), included by …",
      "excluded: reason", "Late fee booked" with the reopen route). Verify: screenshot of the Fees tab.
- [x] 3.6 `EvergreenAlerts#nav_drafted`: add the "needs a late management fee decision" suffix to
      `nav_awaiting_approval` when outstanding > 0 (still once per NAV date). Verify: alert row created in a
      runner draft.
- [x] 3.7 Add to `late_fees.feature`: H106, H107, E334, E335, E338, E339, E340, E341, X204, X205, X206, X207;
      move H105's assertions to the panel. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/late_fees.feature` and confirm green
      before starting phase 4.

## 4. Docs, coverage and QA

- [x] 4.1 `evergreen_business_rules.md`: drop "Decided, not yet built" from R9.2 / R9.10–R9.16 and R8.5; state
      that late payments are always included; user guide FAQs ("Why can't I approve this NAV?", "What is the
      Late fees panel?") passing `UserGuideLint`. Verify: lint output clean.
- [x] 4.2 Coverage: list every H/E/X ID in design.md (H105–H108, E329–E345, X204–X208) and every ID comment
      in `features/`; confirm the sets are equal for this change. Verify: diff of the two lists is empty.
- [x] 4.3 Run `pcuc features/fund/evergreen -n 4` and confirm the evergreen suite is green.
- [ ] 4.4 (QA) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off.
