# Tasks

> **Reproduce first**, then fix. Every cucumber run needs a fresh `TEST_ENV_NUMBER` and Redis on 6379.

## 1. Reproduce

- [x] 1.1 Write `features/core/investor_access_advisor_own_lp.feature` (H1–H2, E1–E4, X1–X3, each with
      an `# <ID> — …` comment) and `features/step_definitions/investor_access_advisor_own_lp_steps.rb`.
      Verify: `--dry-run` shows no undefined or ambiguous steps.
- [x] 1.2 Run it against current code: H1, H2, E1–E4 fail ("belongs to a user with the Investor
      Advisor role…"), X1–X3 pass.

## 2. Fix

- [x] 2.1 `InvestorAccess#block_investor_advisor_from_ui`: no error when the investor's entity is
      the user's home (`advisor_entity_id`, else `entity_id`); flag unchanged (report: Fix row 1).
- [x] 2.2 Run the feature: all 9 scenarios pass.

## 3. Regression and cleanup

- [x] 3.1 Run `features/core/investor_access.feature` (incl. the #1557 block scenario),
      `features/advisor`, `features/core/investor_access_tag_notifications.feature` (pcuc, 4 workers).
- [x] 3.2 `bundle exec rubocop` on the changed files: no new offences.
