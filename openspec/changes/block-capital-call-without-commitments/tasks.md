# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

Every cucumber run uses a fresh `TEST_ENV_NUMBER=$RANDOM`, and Redis must be up on 6379.

## 1. Guard in the create operation (form and JSON)

- [x] 1.1 In `app/packs/funds/capital_calls/services/capital_call_create.rb`, add the frozen
      `NO_APPLICABLE_COMMITMENTS_MESSAGE` constant and the `check_applicable_commitments` step, first in
      the pipeline and wired `Output(:failure) => End(:failure)`. It returns `true` when `capital_call.fund`
      is nil or `capital_call.applicable_to.exists?`. Otherwise it adds the message on `:base`, sets
      `ctx[:errors]` and returns `false` (lld.md [Method Contracts](lld.md#method-contracts),
      [Queries and Indexes](lld.md#queries-and-indexes)). Verify: `bundle exec rubocop
      app/packs/funds/capital_calls/services/capital_call_create.rb` is clean and
      `bin/rails runner 'puts CapitalCallCreate::NO_APPLICABLE_COMMITMENTS_MESSAGE'` prints the message.
- [x] 1.2 Add `features/step_definitions/capital_call_requires_commitments_steps.rb` with the new steps
      listed in lld.md [Test Plumbing](lld.md#test-plumbing) (form submit for given closes, operation call
      with closes and basis, JSON post, "no capital call is created", "create error is shown", edit closes).
      Reuse existing fund/investor/commitment setup steps and `I get the error {string}`. Verify: `bundle
      exec rubocop features/step_definitions/capital_call_requires_commitments_steps.rb` is clean and
      `bundle exec cucumber --dry-run features/fund/capital_call_requires_commitments.feature` reports no
      undefined steps after 1.3 is written.
- [x] 1.3 Write `features/fund/capital_call_requires_commitments.feature` covering H1, H2, H3, E1, E2,
      X1, X2, X3 and X4 from design.md Part 4 (one scenario each). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_requires_commitments.feature`
      and confirm it passes before starting phase 2.

## 2. Import, regressions and docs

- [x] 2.1 Create `public/sample_uploads/capital_calls_no_commitments.xlsx` with the same columns as
      `capital_calls_no_remittances.xlsx`: row 1 for "SAAS Fund" with Fund Closes "All", row 2 for
      "SAAS Fund" with Fund Closes "Second Close" (lld.md [Test Plumbing](lld.md#test-plumbing)). Verify:
      `bin/rails runner 'p Roo::Spreadsheet.open("public/sample_uploads/capital_calls_no_commitments.xlsx").parse(headers: true).size'`
      prints 3 (header + 2 rows).
- [x] 2.2 Add `docs/user_guides/capital_calls_user_guide.md`: under creating a call, one line saying a
      call needs at least one commitment in the selected closes, with the message. Also add an FAQ entry:
      import commitments before calls (lld.md [File Map](lld.md#file-map),
      [Configuration and Rollout](lld.md#configuration-and-rollout)). Verify: the guide renders in the
      in-app user guide link from the Calls tab.
- [x] 2.3 Run the existing call and import features for regressions:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_calls.feature
      features/fund/capital_call_journey.feature features/fund/capital_call_journey_ui.feature
      features/fund/capital_call_journey_undo.feature features/fund/capital_call_live_remittances.feature
      features/fund/capital_call_notify_decoupling.feature features/fund/fund_import.feature`. Any scenario
      that now fails because it creates a call through the form/importer before commitments exist gets
      its setup fixed (add commitments first), not the guard (design.md
      [Risks](design.md#risks-and-open-questions)). Verify: all listed features green.
- [x] 2.4 Add the X5 scenario to `features/fund/capital_call_requires_commitments.feature`, reusing
      `Given I upload {string} file for {string} of the fund with errors` and `the capital call should
      fail with error {string}`, plus a check that the "All" row's call exists. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_requires_commitments.feature`
      (H1–H3, E1–E2, X1–X5) and confirm it passes. Then run `bundle exec brakeman -q` and `bundle exec
      rubocop` on all changed Ruby files, and confirm both are clean.
- [ ] 2.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record
      the sign-off.
