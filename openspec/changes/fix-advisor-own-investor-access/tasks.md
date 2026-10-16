# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

## 1. Reproduce

- [x] 1.1 Write `features/advisor/investor_advisor_own_investor_access.feature` with one scenario
      per row H1–H7, E1–E12, X1–X5 of the report's Verification table. Each scenario has an
      `# <ID> — Happy path/Edge case/Error case: …` comment above it, and the feature header links
      to report.md#verification. Add step definitions in
      `features/step_definitions/investor_advisor_own_investor_access_steps.rb`, reusing the
      existing advisor/notification steps where they fit. Verify: the file parses
      (`--dry-run` shows no undefined steps).
- [x] 1.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/advisor/investor_advisor_own_investor_access.feature`
      and confirm H1, H2, H3, H5, H7, E1, E8, E9, E12, X5 fail against current code and the rest pass. Record
      the failure output.

## 2. Fix

- [x] 2.1 `ApplicationPolicy#permissioned_investor?`: advisor rule, or, when not switched
      (`!user.investor_advisor?`), the investor rule (report: Fix row 1). Comment the IDs
      (H1–H3, H5, H7, E3, E4, E7, E11, E12, X4). Verify: H3 passes.
- [x] 2.2 `ApplicationPolicy#permissioned_investor_non_advisor?`: for an advisor-role user, count
      only approved accesses with `investor_entity_id = user.entity_id` (report: Fix row 2).
      Verify: E4 passes with 2.1 in place.
- [x] 2.3 `User#build_home_persona`: set `curr_role` the way `setup_defaults` would on revert,
      via `User#home_curr_role` (report: Fix row 3). `setup_defaults` itself is left untouched
      (it has side effects); E9 compares persona and real revert so the two can't drift silently.
      Verify: E1, E9 pass; NOTIF-9 still passes.
- [x] 2.4 `Investor#notification_users`: log an approved, subscribed contact dropped by the
      policy filter (report: Fix row 4). Verify: X5 passes.
- [x] 2.5 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/advisor/investor_advisor_own_investor_access.feature`
      and confirm all of H1–H7, E1–E12, X1–X5 pass before starting phase 3.

## 3. Regression and cleanup

- [x] 3.1 Run `features/advisor` (pcuc, 4 workers) and confirm it is green, including NOTIF-1..9.
- [x] 3.2 Run the Blast Radius features: `features/core/access_rights.feature`,
      `features/core/access_rights_core_models.feature`, `features/fund/fund_access.feature`,
      `features/fund/capital_calls.feature`, `features/fund/capital_call_notify_decoupling.feature`,
      `features/core/investor_access_tag_notifications.feature`,
      `features/core/investor_kyc_notification_delivery.feature`,
      `features/fund/evergreen/advisor_portal.feature`, and confirm they are green.
- [x] 3.3 Run `bundle exec rubocop` on the changed files and confirm it is clean, including the
      `IRM/RelationBlankPresent` cop.
- [x] 3.4 Re-run the prod-dump probe (read-only, rolled back): `Investor.find(4800).notification_users(Fund.find(159), with_tag: 'CapitalCall')`
      includes user 2564.

## 4. Review fixes and the Access Denied switch

- [x] 4.1 Run three read-only reviews (access paths, notification paths, adversarial diff) and
      triage each finding into: introduced by this diff (fix), same bug class (fix), pre-existing
      product question (report: "Review findings left out of scope").
- [x] 4.2 Fix rows 5–12 of the report's Fix table (advisor_at_home?, advisor_notifiable?, preview
      parity, email opt-out, overview?, KYC show?, advisor accounts without the role, deleted home).
- [x] 4.3 Access Denied guidance with the switch button and `return_to` (Fix rows 13–14).
- [x] 4.4 Run `features/advisor/investor_advisor_own_investor_access.feature` and confirm H1–H8,
      E1–E18, X1–X11 pass.
- [x] 4.5 Re-run the phase 3 regression set (pcuc, 4 workers) plus
      `features/core/investor_kyc_notification_delivery.feature`, and confirm green.
      Result after rebasing onto origin/main cdb92779f: 401/402. The one failure,
      `features/advisor/investor_advisor.feature:5` ("₹18.00 Lakhs" vs "₹18.00 L"), fails
      identically on clean origin/main; it comes from #1832's folio stats cards, not this fix.
- [x] 4.6 `bundle exec rubocop` on every changed file: no new offences.
