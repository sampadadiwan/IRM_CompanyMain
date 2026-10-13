# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Conventions for every phase:**
> - Run every Cucumber command with a fresh `TEST_ENV_NUMBER` (distinct explicit numbers below
>   62000 for parallel runs), with Redis up on 6379.
> - Run `bundle exec rubocop` on the phase's files before its feature task.
> - Comment code with the worked-example IDs it implements, linking `design.md#worked-examples`.
> - Each scenario has a `# ID — Happy path|Edge case|Error case: …` comment directly above it, and
>   each feature header links to `openspec/changes/evergreen-share-classes/design.md#worked-examples`.
> - Never commit; the user commits.
> - The "shares" wording (plan item 2) is a separate change on its own branch, not in these tasks.

## 1. Class stake: a fair split between classes (box ③)

- [x] 1.1 Change `ClassApportioner.shares` to the stake rule with a `paid:` keyword (previous NAV +
      own lines owed − own payments since, × units now ÷ previous units, clamped at 0; initial price
      when there's no previous NAV or no previous units; single class → 1; zero total → equal) per
      [LLD Method Contracts](lld.md#method-contracts). Until phase 2 adds the column, own lines are
      the management fee payable, the performance fee payable and the performance fee accrued.
      Verify: in the console, the H2 inputs give 0.5 / 0.5.
- [x] 1.2 Reorder `FundNavBuilder#build_navs`: `fee_payments_by_class` using
      `ClassApportioner.value_shares` (today's rule, for the excess) → shares with `paid:` =
      management + performance payments per class (design [card ③](design.md#③-class-stake)). Verify: drafting the H3 data twice gives
      identical rows, and Class A's management fee payable is ₹0.
- [x] 1.3 Re-run the existing `features/fund/evergreen/nav.feature` (E7) and `nav_corrections.feature`
      (E197–E200). Any scenario whose figures change because a class owed unpaid fees gets new
      figures and a comment naming the reason (design Risks). Verify: both features are green.
      Result 9 Oct 2026: nav, nav_corrections and fees — 67/67 green, no figures changed.
- [x] 1.4 Docs: in `docs/modules/funds/evergreen_business_rules.md`, rewrite R8.14 to the stake rule
      and remove the "Known issue" box. In `docs/user_guides/evergreen_funds_user_guide.md`, remove
      the known-issue note and add a FAQ on why an unpaid fee doesn't change the other class. Mark
      item 1 Done in `docs/modules/funds/evergreen_share_classes_plan.md`. Verify:
      `bin/rails runner 'l=UserGuideLint.new; p %i[route_errors link_errors faq_shape_errors faq_length_errors faq_render_errors].map{|m| l.send(m)}'`
      prints only empty arrays.
- [x] 1.5 Write `features/fund/evergreen/class_nav.feature` covering H1, H2, H3, E1, E2, E3, E4, E5,
      E6, E7, E8, E9, E10, E11, E12, E13, with steps in
      `features/step_definitions/evergreen_class_nav_steps.rb` ([LLD Test Plumbing](lld.md#test-plumbing)).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/class_nav.feature`
      until green before starting phase 2.

## 2. Class-only expenses (boxes ① ② ④ ⑤)

- [x] 2.1 Migrations: `evergreen_class_terms.class_expense_entry_name`,
      `class_expense_paid_entry_name` and `fund_navs.class_expenses_payable_cents`, per
      [LLD Schema Detail](lld.md#schema-detail). Run `db:migrate`, restore `db/schema.rb` and
      `db/schema_test.rb`, hand-insert the columns, run `db:clean_schema`. Verify: `git diff db/schema.rb`
      shows only the three additions. Done by hand-editing both schema files; the dev database (prod
      dump) was not migrated.
- [x] 2.2 `EvergreenClassTerm` length validations; `EvergreenFundSetting` cross-class checks X1, X2,
      X3, X4, X5, X7; expose both names through `EvergreenTerms` / `terms_for` (design
      [card ①](design.md#①-class-settings)). Verify: the X1–X5 inputs give the exact messages in the
      console.
- [x] 2.3 Settings UI: add both names to `CLASS_FIELDS` in `Evergreen::SettingsController`, add two
      inputs with tooltips inside "Customise this class", and list them on the Review step, reusing
      the existing form-group markup. Verify: H6 by hand in dev.
- [x] 2.4 `FundNav::LIABILITY_LINES` gains `class_expenses_payable`. In `FundNavBuilder`, add the
      line (previous + expenses since − paid since), its breakdown text, and class expense payments
      in the stake's `paid:`. `ClassApportioner` includes the previous `class_expenses_payable_cents`
      in its own lines (design [card ④](design.md#④-class-nav)). Verify: the H4 and H5 figures in
      the console.
- [x] 2.5 `NavInputs#unclaimed_class_entries` (`distinct.pluck`, fund-scoped, at most 20), stored in
      `breakdown["unclaimed_class_entries"]` on draft (LLD Queries and Indexes). Verify: the E22 data
      lists "Class C Legal".
- [x] 2.6 NAV page: a "Class expenses payable" label in `EvergreenNavHelper::LINE_LABELS`; the row
      shown only when the class has entries or a non-zero value; `#unclaimed_class_entries_warning`
      using the existing warning pattern (design [card ⑤](design.md#⑤-nav-page)). Verify: J1.1–J1.4
      by hand in dev.
- [x] 2.7 Docs: add class-only expenses to the business rules (section 8 table and rules) and the
      user guide (settings table, NAV section, FAQ "How do I charge an expense to one class?"). Mark
      item 3 Done in the plan doc. Verify: the UserGuideLint command from 1.4 prints only empty
      arrays.
- [x] 2.8 Write `features/fund/evergreen/class_expenses.feature` covering H4, H5, H6, E14, E15, E16,
      E17, E18, E19, E20, E21, E22, E23, E24, X1, X2, X3, X4, X5, X6, X7. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/evergreen/class_expenses.feature
      features/fund/evergreen/class_nav.feature` until green before starting phase 3.

## 3. Coverage, regression and sign-off

- [x] 3.1 Coverage: list every H/E/X ID in `design.md` and every ID comment in
      `features/fund/evergreen/class_nav.feature` and `class_expenses.feature`. Confirm the sets are
      equal (H1–H6, E1–E24, X1–X7). An edge case found during apply gets a design row and a scenario.
      Result 9 Oct 2026: 37 design IDs = 37 labelled scenarios; X7 was found during apply and added.
- [x] 3.2 Full regression: the evergreen suite in three groups with distinct `TEST_ENV_NUMBER`s,
      green. Record the counts in this task.
      Result 9 Oct 2026: 379/379 green — 127 + 125 + 127 scenarios, 6,247 steps, no re-runs needed.
- [x] 3.3 (QA, not the apply agent) Run `qa-checklist.md` on a deployed build and record the
      sign-off.
