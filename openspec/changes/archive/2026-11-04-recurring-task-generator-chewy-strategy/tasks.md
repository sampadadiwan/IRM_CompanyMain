# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

> **Status note:** the code change (2.1) is already in commit `3d56c6035` on branch
> `RecurringTaskGeneratorJob-chewy-fix`. To watch phase 1 fail, check out `26ce7bcbd`'s version of
> `recurring_task_generator_job.rb` temporarily, or stash that change, then restore it.

## 1. Reproduce

- [x] 1.1 Add scenario X1 (job runs with no ambient Chewy strategy) to
      `features/core/recurring_task_generation.feature`, plus any step it needs in
      `features/step_definitions/recurring_task_steps.rb`. The suite runs under a global
      `Chewy.strategy :bypass` (`features/support/env.rb:49`), so the step must clear it for the
      job run and restore it afterwards. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/recurring_task_generation.feature`
      against the pre-fix job and confirm X1 fails with `UndefinedUpdateStrategy`. Record the
      failure output.
- [x] 1.2 Add H1 and E1 to the same feature if the existing scenarios do not already cover them
      ("Successfully generating recurring tasks…" and "Do not duplicate existing tasks" likely do;
      reuse them rather than adding duplicates). Confirm both pass before the fix.

## 2. Fix

- [x] 2.1 Wrap the `find_each` loop in `Chewy.strategy(:sidekiq)` and comment why (report: Fix,
      row 1). Done in `3d56c6035`; verify with
      `git show 3d56c6035 -- app/packs/core/tasks/jobs/recurring_task_generator_job.rb`.
- [x] 2.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/recurring_task_generation.feature`
      and confirm H1, E1 and X1 now pass before starting phase 3.

## 3. Regression and cleanup

- [x] 3.1 Run the feature directory the fix touches:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core` and confirm it is green.
- [x] 3.2 Run the Blast Radius caller's feature:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/side_letter_obligation_e2e.feature`
      and confirm it is green.
- [x] 3.3 Run `bundle exec rubocop app/packs/core/tasks/jobs/recurring_task_generator_job.rb` and
      the changed feature steps, and confirm it is clean, including the
      `IRM/RelationBlankPresent` cop.

## 4. Rollout (no code)

- [x] 4.1 Deploy and restart Sidekiq so retries pick up the fixed job. Verify by checking the
      Sidekiq retry set no longer holds `RecurringTaskGeneratorJob` and no new
      `UndefinedUpdateStrategy` email arrives (QA B1).
- [x] 4.2 From the Rails console, reindex the tasks created during the failed 2026-10-01 runs:
      `TaskIndex.import(Task.where.not(task_recurrence_rule_id: nil).where(created_at: <window>))`.
      Verify a recurring task appears in Tasks list search (QA R1). Repeat per region if the
      failure occurred in both.
- [x] 4.3 The cron timing correction (job firing at 18:30 IST vs 00:00 IST) is stated to happen
      automatically and is out of scope here. No task. Confirm only that the next scheduled run
      succeeds.

## Deferred (not in this change)

- A default Chewy strategy for all Sidekiq jobs (for example in `ApplicationJob`'s
  `around_perform`), with an override for `process_deal_ingest_job.rb`, which uses `:atomic`.
  Possible future improvement.
