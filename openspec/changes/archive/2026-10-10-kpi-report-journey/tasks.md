# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Every run: `TEST_ENV_NUMBER=$RANDOM`, Redis up on 6379. Annotate code with H/E/X ids and
> `openspec/changes/kpi-report-journey/design.md#worked-examples`. Never commit.

## 1. Generic owners and setup plumbing (engine)

- [x] 1.1 Add `workflow_override_owners` / `workflow_default_owners` to `Workflowable` (LLD Method Contracts); verify capital call `workflow_default_owners == [creator]` in a console
- [x] 1.2 Add `WorkflowAutoReminderJob.owners_for(instance, step, use:)`; make `owner_for` = `.first`; send one reminder per owner; loop `owners_for` in `WorkflowEvaluator#owner_mail`; show one or several names in `JourneyHelper`, `_journey_panel`, `WorkflowInstancesController` (LLD File Map ⑥)
- [x] 1.3 `JourneySetup`: skip CFO plan/backfill when `SIGN_OFF_NAME` is nil (LLD Configuration and Rollout); verify capital call / distribution / KYC `rake …:setup` dry runs print the same plans as before
- [x] 1.4 `WorkflowStep::ACTOR_CHECK_KEYS` + step form/Stimulus show Actors for those checks (empty list for now); verify the human-step form is unchanged
- [x] 1.5 Re-run the existing journey features (`features/fund/capital_call_journey*.feature`, distribution and KYC journey features) with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber …` and confirm green (covers E17) before starting phase 2

## 2. Data: Managed by and completion column

- [x] 2.1 Migrations for `investors.managed_by_user_id` (+ index, FK) and `kpi_reports.completion_notified_at`; restore schema.rb / schema_test.rb per memory and run `db:clean_schema` (LLD Schema Detail); verify both schema files contain the columns
- [x] 2.2 `Investor belongs_to :managed_by` + employee validation; permit param; dropdown on the Portfolio Company form; show on the investor page (LLD Controllers)
- [x] 2.3 Write `features/startup/kpi_report_journey_owners.feature` scenarios H6 and X1 only (manager set / outsider refused) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_report_journey_owners.feature` until green before starting phase 3

## 3. KPI report journey: checks, setup, start

- [x] 3.1 Write the 8 check classes under `app/packs/startups/kpis/workflow_checks/kpi_report/` and register them (LLD File Map ③, design card ③); verify `WorkflowChecks::Registry.keys_for("KpiReport")` lists 8 keys
- [x] 3.2 `KpiReport`: `include Workflowable`, `has_journey`, callback no-ops, `start_journey!`, owner overrides, `journey_undo` override, `open_journey_ids_for`; add `KpiReport` to `WORKFLOWABLE_TYPE_OPTIONS` / `ALLOWED_WORKFLOWABLE_TYPES`; `WorkflowablePolicyMethods` in `KpiReportPolicy`
- [x] 3.3 `KpiReportJourneySetup` (+ `KINDS`), `lib/tasks/kpi_report_journeys.rake`, `SetupCompany#setup_kpi_report_journeys`; verify the dry run lists the template, rule and flag for the entity, and that no existing report gets a journey
- [x] 3.4 Call `start_journey!` from `KpiReportsController#create`, `KpiReportCreateShell`, `SendPortcoNotification`, `ImportKpiWorkbookJob` (own report only); remove `launch_portfolio_company_workflow`, its call, seed scenario 2 and its feature scenarios/steps
- [x] 3.5 Write `features/startup/kpi_report_journey_setup.feature` (H1, E1, E4) and `features/startup/kpi_report_journey.feature` (H3, H4, H14, H15, E2, E3, E5, E14, E18) and run both with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber …` until green before starting phase 4

## 4. Report page: panel, Close report, completion email

- [x] 4.1 `WithJourneyPanel` in `KpiReportsController`, `journey` route/action, `kpi_reports/_journey.html.erb`, `turbo_stream_from` on show (design card ⑤); verify the panel renders for H4 data
- [x] 4.2 `KpiReportClose` + rewire `mark_reviewed`; **Close report** button `#kpi_report_close_btn` with action-summary popup (`close_report_action_summary`)
- [x] 4.3 `KpiReportCompletionEmail`, `KpiReportCompletedNotifier`, `KpiReportsMailer#completed` + view; route + action + policy; button `#kpi_report_send_completion_btn`; add `kpi_report.send_completion_email` to `ACTOR_CHECK_KEYS`
- [x] 4.4 Write `features/startup/kpi_report_journey_page.feature` (H5, H8, H9, E6, E10, E11) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_report_journey_page.feature` until green before starting phase 5

## 5. Hooks: forward and undo

- [x] 5.1 Forward hooks: `SendPortcoNotification`, `KpiReportsController#update` (submit), `ImportKpiWorkbookJob` (portco-wide progress), `KpisController#approve/#reject/#approve_all`, mapping create/import (design card ⑦)
- [x] 5.2 Undo hooks: `reopen_for_portco!`, `reopen_after_failed_import!`, `Kpi#unapprove!` path, `delete_kpis`
- [x] 5.3 Finish `kpi_report_journey_owners.feature` (H7, E7, E8, E9, X3) and write `features/startup/kpi_report_journey_undo.feature` (E12, E13, X4) plus H10 in `kpi_report_journey.feature`; run all three with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber …` until green before starting phase 6

## 6. Mapping delete with warning

- [x] 6.1 `InvestorKpiMappingDelete` (`impact`, refusal when the mapping has children, transactional batched delete, recompute jobs, portco journey undo); controller `destroy` uses it (design card ⑧)
- [x] 6.2 Delete popup on the mapping page via `delete_action_summary` (≤4 cards); plain confirm when unused; Delete disabled with a children tooltip for parents
- [x] 6.3 Write `features/startup/kpi_mapping_deletion.feature` (H11, H12, H13, E15, E16, X2, X5) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_mapping_deletion.feature` until green before starting phase 7

## 7. End-to-end browser journeys (added at the user's request)

- [x] 7.1 Write `features/startup/kpi_report_journey_end_to_end.feature`: H16 (portco upload — mapping form, request, magic-link upload and submit, Close report, Send completion email) and H17 (fund upload on the New KPI Report screen — portco tasks n/a, Close report completes), checking the step bar on the report page after each task; run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_report_journey_end_to_end.feature` until green before starting phase 8

## 8. Docs and regression

- [x] 8.1 User guide `docs/user_guides/kpi_upload_user_guide.md`: "Tracking a report: the journey step bar" with a task table and mermaid diagrams, Managed by, Close report, mapping delete; FAQs via the `user-guide-faqs` skill (why no step bar, why it moved back, how to set up, who gets reminders, live updates)
- [x] 8.2 Update `workflow_templates_user_guide.md` for multiple owners / Managed by, and the OpenSpec artifacts for anything built differently
- [x] 8.3 Run `features/core/user_guide_lint.feature`, the existing KPI features (`features/startup/portco_kpi_workflow.feature` and other KPI features) and `bundle exec rubocop` on changed files until green

## 8b. Send upload request on the report page (added at the user's request, after local QA)

- [x] 8b.1 `SendPortcoNotificationJob` / `send_portco_notification` take `kpi_report_id` (one portco, this entity's report) and send for exactly that report
- [x] 8b.2 Report page button `#kpi_report_send_request_btn` (fund side, portco upload, link not sent) with action-summary popup; disabled with the reason when there is no approved portal user; `kpi_report.send_request` targets it
- [x] 8b.3 H18 and E19 in `kpi_report_journey_page.feature`; user guide task table + FAQ
- [x] 8b.4 Portco on a submitted/reviewed report sees a "KPIs submitted" page instead of the wizard (`kpi_reports/_portco_submitted.html.erb`); existing locked-state scenarios moved to it, plus scenario 50 in `portco_kpi_workflow.feature`
- [x] 8b.6 "Review pending KPIs" opens the grid in a new tab (`Result.fail(new_tab:)` → `action_new_tab`, panel `target=_blank`); grid banner back to the report via `journey_report_id` (`kpi_reports/_journey_return_banner.html.erb`); H19 in `kpi_report_journey_page.feature`
- [x] 8b.5 Staged review grid (`view_unapproved=true`) no longer renders the empty approved-only KPIs chart; scenario 51 in `portco_kpi_workflow.feature`

## 9. QA

- [ ] 9.1 (QA) Run `qa-checklist.md` on a deployed build and record the sign-off
