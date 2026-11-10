# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

## 1. Reproduce

- [ ] 1.1 Write `features/<path>/<feature>.feature` covering <!-- H/E/X IDs --> from the report's
      Verification table. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<path>/<feature>.feature` and
      confirm the rows listed as "Fails against current code" do fail. Record the failure output.

## 2. Fix

- [ ] 2.1 <!-- Task description — name the report's Fix row it implements -->
- [ ] 2.2 <!-- Task description, with how to verify it -->
- [ ] 2.3 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<path>/<feature>.feature`
      and confirm <!-- IDs --> now pass before starting phase 3.

<!-- Add further numbered phases only if the fix genuinely has separable parts, each ending in
     its own feature file + a green run before the next phase starts. -->

## 3. Regression and cleanup

- [ ] 3.1 Run the feature directory the fix touches:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<dir>` and confirm it is green.
- [ ] 3.2 Run the features of every caller listed in the report's Blast Radius that is marked as
      needing checking, and confirm they are green.
- [ ] 3.3 Run `bundle exec rubocop` on the changed files and confirm it is clean, including the
      `IRM/RelationBlankPresent` cop.
- [ ] 3.4 N+1 check (if the fix touches a query, a list page or a job): run the feature with
      `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/<path>/<feature>.feature`,
      read `log/prosopite.log` (truncate first, never commit) and fix any N+1 the fix introduced.
- [ ] 3.5 UI check (if the fix touches a screen): screenshot it beside its unchanged neighbours and
      confirm it still matches the app's standard screens (breadcrumbs, tabs, buttons, tooltips).
      Otherwise write "no screens touched".
- [ ] 3.6 Security: each item in the report's Security table is met and its test is green; Brakeman
      clean for the changed files (docs/security/feature_security_checklist.md).
- [ ] 3.7 Post-deploy steps: write `post_deploy_steps/<change-name>.md` from the report's *Post-deploy
      steps* (or `None — <reason>`); run `bin/rails post_deploy:lint` and
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/post_deploy_steps.feature` green.
