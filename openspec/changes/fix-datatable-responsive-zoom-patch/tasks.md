# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

> **No Playwright.** By decision, the new feature is tagged `@rack_test` and runs without a
> browser. Runtime behaviour at a real fractional zoom is covered by the QA checklist.

## 1. Reproduce

- [x] 1.1 Add `features/step_definitions/datatable_steps.rb` with rack_test steps that check the
      `datatable` wrapper markup and the "Actions" header on `/favorites`, read the page's
      importmap and assert `controllers/datatable_controller` is pinned, and read
      `app/javascript/controllers/datatable_controller.js` and assert no line calls
      `columns.forEach(` / `columns.map(` (report: Verification, Fix row 3). Reuse the
      "Im logged in as a user … for an entity …" step. Verify:
      `bundle exec cucumber --dry-run features/core/datatable_responsive_zoom.feature` reports no
      undefined steps.
- [x] 1.2 Write `features/core/datatable_responsive_zoom.feature` (`@rack_test`) covering H1 and
      X1. With the fix stashed (`git stash push app/javascript/controllers/datatable_controller.js`),
      run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/datatable_responsive_zoom.feature`
      and confirm X1 fails and H1 passes. Recorded: X1 failed listing
      `22: const saved = columns.map(...)`, `23: columns.forEach(...)` and
      `29: columns.forEach(...)`, and H1 passed.

## 2. Fix

- [x] 2.1 Restore the fix (`git stash pop`). In `patchResponsiveZoomTolerance()` the save, shrink
      and restore of `minWidth` use index-based `for (let i = 0; i < columns.length; i++)` loops
      instead of `columns.map` / `columns.forEach` (report: Fix row 1). Verify:
      `grep -n "columns\.\(map\|forEach\)" app/javascript/controllers/datatable_controller.js`
      returns nothing.
- [x] 2.2 One-line comment saying `s.columns` is a DataTables Api instance (array-like, no
      forEach) (report: Fix row 2). Verify: it sits directly above `const columns = this.s.columns;`.
- [x] 2.3 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/datatable_responsive_zoom.feature`
      and confirm H1 and X1 pass. Result: 2 scenarios passed, 9 steps passed.

## 3. Regression and cleanup

- [ ] 3.1 Run the feature directory the fix touches:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core` and confirm it is green.
      **Blocked locally:** every other scenario uses the Playwright driver, and its browsers aren't
      installed here. Run this in CI or on a machine that has them.
- [ ] 3.2 Run the features of the Blast Radius callers that render `.jqDataTable` index pages,
      e.g. `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund features/deal`, and confirm
      no new failures compared with `main`. **Blocked locally** for the same reason as 3.1.
- [x] 3.3 Run `bundle exec rubocop features/step_definitions/datatable_steps.rb` and confirm it
      is clean, including the `IRM/RelationBlankPresent` cop. Result: no offenses.
- [ ] 3.4 Hand the build to QA with `qa-checklist.md` (B1 first). Verify: the Sign-off row is
      filled in.
