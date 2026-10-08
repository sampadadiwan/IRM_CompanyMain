# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

## 1. Remove tracking from Kpi and KpiReport (LLD: File Map, Method Contracts)

- [x] 1.1 Grep `app`, `lib` and `features` for `really_destroy!`, `with_deleted`, `only_deleted` and `restore` on `Kpi`/`KpiReport`; confirm none (found `Entity#nuclear_destroy` calling `really_destroy!` on kpis/kpi_reports; switched to `destroy`)
- [x] 1.2 Remove `include Trackable.new(...)` from `app/packs/startups/kpis/models/kpi.rb` and `include Trackable.new` from `kpi_report.rb`
- [x] 1.3 Drop `deleted_at` from the name uniqueness scope in `kpi.rb`, and refresh the paranoia comment in `app/packs/startups/kpis/jobs/kpi_percentage_change_job.rb`
- [x] 1.4 Write `features/startup/kpi_hard_delete.feature` (+ `features/step_definitions/kpi_hard_delete_steps.rb`) for H1, H2, H3, E1, E3, X1. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_hard_delete.feature` until green.

## 2. Purge soft-deleted rows and drop deleted_at (LLD: Schema Detail)

- [x] 2.1 Add migration `purge_soft_deleted_kpis_and_reports_and_drop_deleted_at`: batched hard delete of `kpis` (deleted, or whose report is deleted) then `kpi_reports`; then drop the `deleted_at` columns and indexes from both tables (guarded); irreversible `down`
- [x] 2.2 Update `db/schema.rb` and sync `schema_test.rb` per `bin/sync_schema_test.rb`
- [x] 2.3 Add E2 and E4 to the feature file (legacy soft-deleted rows purged, live rows intact, mapping then deletable) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_hard_delete.feature` until green; then run `features/startup/kpis.feature` and `features/startup/investor_kpi_mappings.feature` for regressions
- [x] 2.4 Run `bundle exec rubocop` on changed files

## 3. Release and QA

- [ ] 3.1 Deploy code before running the migration (old code must not need `deleted_at`). Count soft-deleted `kpis`/`kpi_reports` in staging/prod and take a DB backup before release
- [ ] 3.2 Run qa-checklist.md on a deployed build and record the sign-off (for QA, not the apply agent)
