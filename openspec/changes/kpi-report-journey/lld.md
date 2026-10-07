# KPI Report Journey — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links to its diagrams and
> [worked examples](design.md#worked-examples) rather than repeating them.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **No auto-assignment callbacks on `KpiReport`**: both `Workflowable` callbacks are overridden to
  no-ops; `start_journey!` is called from exactly four places. Check none was missed — see
  [Method Contracts](#method-contracts) and [design Decision 1](design.md#design-decisions).
- **Generic owner list** in `WorkflowAutoReminderJob.owners_for` with `owner_for` kept as `.first`: every
  existing call site must keep its behaviour — see [Method Contracts](#method-contracts).
- **`JourneySetup` sign-off guard**: a kind with `SIGN_OFF_NAME = nil` must never get a CFO step added on
  re-run (today `plan` sets `cfo: true` whenever the Full template lacks a step of that name) — see
  [Configuration and Rollout](#configuration-and-rollout).
- **Mapping delete skips KPI callbacks** (`delete_all`) and relies on one recompute job afterwards — see
  [Transactions](#transactions-locking-and-concurrency).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Request | `app/packs/startups/kpis/models/kpi_report.rb` | Modified | `include Workflowable`, `has_journey`, `start_journey!`, callback no-ops, owner overrides, `journey_undo_evaluate` override, `journey_progress_for_portco` / `journey_undo_for_portco`; remove `launch_portfolio_company_workflow` |
| ① | `app/packs/startups/kpis/controllers/kpi_reports_controller.rb` | Modified | `start_journey!` after create; `WithJourneyPanel`; `journey`, `send_completion_email`; `mark_reviewed` via `KpiReportClose`; hooks in `update`/`reopen` |
| ① | `app/packs/startups/kpis/services/kpi_report_create_shell.rb` | Modified | `start_journey!` after create |
| ① | `app/packs/startups/kpis/services/send_portco_notification.rb` | Modified | `start_journey!` + `journey_progress!` after notify |
| ① | `app/packs/startups/kpis/services/kpi_report_journey_setup.rb` | New | Constants for the kind |
| ① | `app/packs/core/workflow_templates/services/journey_setup.rb` | Modified | `KINDS["kpi_report"]`; skip sign-off when `SIGN_OFF_NAME` nil |
| ① | `lib/tasks/kpi_report_journeys.rake` | New | Dry-run / `EXECUTE=1` / `ENTITY_ID` |
| ① | `app/packs/core/entities/services/setup_company.rb` | Modified | `setup_kpi_report_journeys` step |
| ② Data | `db/migrate/2026100700000{1,2}_*.rb`, `db/schema.rb`, `db/schema_test.rb` | New / Modified | Two columns + index |
| ② | `app/packs/core/investors/models/investor.rb` | Modified | `belongs_to :managed_by`, employee validation |
| ② | `app/packs/core/investors/controllers/investors_controller.rb`, `views/investors/_form_fields.html.erb`, show page | Modified | Permit + dropdown (Portfolio Company only) + display |
| ③ Checks | `app/packs/startups/kpis/workflow_checks/kpi_report/{support,setup_mappings,send_request,submit,import,approve,close,send_completion_email,fund_uploaded}.rb` | New | Step rules |
| ③ | `config/initializers/workflow_checks.rb` | Modified | Register 8 classes |
| ④ Evaluator | `app/packs/core/workflow_templates/services/workflow_evaluator.rb` | Modified | `owner_mail` loops `owners_for` |
| ⑤ Page | `app/packs/startups/kpis/views/kpi_reports/show.html.erb`, `_journey.html.erb` (new) | Modified / New | Panel, subscription, two buttons with ids |
| ⑤ | `app/packs/startups/kpis/helpers/kpi_reports_helper.rb` | Modified | `close_report_action_summary`, `completion_action_summary` (action-summary cards) |
| ⑤ | `app/packs/startups/kpis/services/kpi_report_close.rb` | New | Approve portco pending + `reviewed` + hooks |
| ⑤ | `app/packs/startups/kpis/services/kpi_report_completion_email.rb` | New | Idempotent send + column + hook |
| ⑤ | `app/packs/startups/kpis/mailers/kpi_report_completed_notifier.rb`, `kpi_reports_mailer.rb#completed`, `views/kpi_reports_mailer/completed.html.erb` | New / Modified | The email |
| ⑤ | `app/packs/startups/kpis/policies/kpi_report_policy.rb` | Modified | `include WorkflowablePolicyMethods`; `send_completion_email?` |
| ⑤ | `config/routes/startup.rb` | Modified | `get 'journey'`, `patch 'send_completion_email'` (member) |
| ⑤ | `app/packs/core/workflow_templates/models/workflow_template.rb`, `controllers/workflow_instances_controller.rb` | Modified | Add `KpiReport` to type lists |
| ⑤ | `app/packs/core/workflow_templates/models/workflow_step.rb`, `views/workflow_steps/_form.html.erb`, `workflow_step_kind_controller.js` | Modified | `ACTOR_CHECK_KEYS`; show Actors for those checks |
| ⑥ Who | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | Modified | `workflow_override_owners`, `workflow_default_owners` |
| ⑥ | `app/packs/core/workflow_templates/jobs/workflow_auto_reminder_job.rb` | Modified | `owners_for`; reminders per owner |
| ⑥ | `app/packs/core/workflow_templates/helpers/journey_helper.rb`, `views/workflow_instances/_journey_panel.html.erb`, `controllers/workflow_instances_controller.rb` | Modified | Show one or several owner names |
| ⑦ Hooks | `app/packs/startups/kpis/jobs/import_kpi_workbook_job.rb` | Modified | `start_journey!` for own report; reviewed→submitted undo; progress; remove portco workflow launch |
| ⑦ | `app/packs/startups/kpis/controllers/kpis_controller.rb` | Modified | Progress after approve/reject/approve_all; undo after unapprove |
| ⑦ | `app/packs/startups/kpis/controllers/investor_kpi_mappings_controller.rb`, `services/import_investor_kpi_mapping.rb` | Modified | Progress after create/import; destroy via op |
| ⑧ Delete | `app/packs/startups/kpis/services/investor_kpi_mapping_delete.rb` | New | `impact` + delete |
| ⑧ | `app/packs/startups/kpis/views/investor_kpi_mappings/show.html.erb`, `helpers/investor_kpi_mappings_helper.rb` | Modified | Popup cards |
| Removal | `lib/tasks/investor_workflow_seeds.rake` (scenario 2 + demo report), `features/core/investor_workflow_auto_assignment.feature` (KPI scenarios), `features/step_definitions/investor_workflow_auto_assignment_steps.rb` (KPI steps) | Modified | Remove the replaced path |
| Docs | `docs/user_guides/kpi_upload_user_guide.md` | Modified | "Tracking a report: the journey step bar" + FAQs; Managed by; Close report |

**Reviewer checks**
- [ ] Every class in the [class diagram](design.md#class-diagram) has a file here
- [ ] `WorkflowChecks::KpiReport` module never shadows `::KpiReport` inside checks (always `::KpiReport` / pass the record)
- [ ] `workflow_checks/` stays a namespace dir (not an autoload root), as `config/application.rb` requires

---

## Schema Detail

**`investors`** (existing): a portfolio company needs one named owning employee.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `managed_by_user_id` | Added | bigint | — | yes | NULL | `index_investors_on_managed_by_user_id`, FK `users` | Optional per-portco owner; bigint matches `users.id`; nullable because most portcos won't set it |

**`kpi_reports`** (existing): evidence for the completion email step.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `completion_notified_at` | Added | datetime | — | yes | NULL | none | Check reads it per report by PK; never filtered in lists, so no index |

**Migration safety:** `investors` and `kpi_reports` are small (≈1k reports); `add_column` + `add_index`
online in MySQL 8 (INSTANT/INPLACE). Reversible. Per memory, after `db:migrate` restore `schema.rb` /
`schema_test.rb` and hand-insert the two columns, then `db:clean_schema`.

**Reviewer checks**
- [ ] FK has an index
- [ ] Both `schema.rb` and `schema_test.rb` carry the columns
- [ ] Migration is reversible

---

## Method Contracts

**`KpiReport`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#start_journey!(actor = nil)` | `User` or nil | `Result` or nil | never (logs) | `WorkflowAutoAssignmentService.call(workflowable: self)` | Yes — no-op when `workflow_assignment` exists, no portfolio company, or the investor's category isn't "Portfolio Company" |
| `#apply_workflow_auto_assignment`, `#apply_workflow_auto_assignment_on_update` | — | nil | — | none (overrides) | Yes |
| `#workflow_override_owners` | — | `[User]` | — | — | — `[portfolio_company.managed_by].compact` |
| `#workflow_default_owners` | — | `[User]` | — | — | — `entity.employees.with_tag('Kpi').where(active: true)` (a relation-backed array; memoized) |
| `#journey_undo_evaluate(note:, started_at:, actor:)` | as `Workflowable` | evaluator result | never | `update_columns(completion_notified_at: nil)` then `super` (so `journey_undo` and the portco helper both clear it) | Yes |
| `.journey_progress_for_portco(entity_id, pc_id, actor:)` / `.journey_undo_for_portco(entity_id, pc_id, note:, started_at:, actor:)` | ids | nil | never (logs) | evaluates every report of the pc that has a journey (filtered in SQL) | Yes |

**`Workflowable`** (Concern) — new defaults

| Method | Returns | Default |
|---|---|---|
| `#workflow_override_owners` | `[User]` | `[]` |
| `#workflow_default_owners` | `[User]` | `[workflow_default_owner].compact` |

**`WorkflowAutoReminderJob`** (Job)

| Method | Arguments | Returns | Notes |
|---|---|---|---|
| `.owners_for(instance, step_data, use: :owner)` | `use: :owner \| :actors` | `[User]` active, uniq | override → live step `owner_user` (or `actor_users`) → defaults; first non-empty level after the active filter wins |
| `.owner_for(instance, step_data)` | — | `User` or nil | `owners_for(...).first` — keeps the six existing call sites working |

**`KpiReportJourneySetup`** (Service) — constants: `WORKFLOWABLE_TYPE "KpiReport"`, `KEY_PREFIX
"kpi_report."`, `FULL_KEY "kpi_report_full"`, `FULL_NAME "KPI Report Review"`, `SIGN_OFF_NAME nil`,
`ENTITY_TYPES ["Investment Fund"]`, `FULL_STEPS` (6 rows: mappings, request+`fund_uploaded`,
submit+`fund_uploaded`, import, approve, close). No rollout onto existing reports.

**`KpiReportClose`** (Service): `.call(kpi_report:, user:)` → `{approved: Integer, periods: Integer}`. Collects pending ids
with `KpiReportClose.pending_scope(report)` — `Kpi.unapproved.where(entity_id:, portfolio_company_id:)`, or the report's own `kpis.unapproved` when it has no portfolio company, `KpiApproveService.call(ids,
user.id)`, `update!(status: 'reviewed')`, then `KpiReport.journey_progress_for_portco(entity_id, pc_id,
actor: user)`. Idempotent (a second call approves 0 and keeps `reviewed`).

**`KpiReportCompletionEmail`** (Service): `.call(kpi_report:, user:)` → `:sent | :already_sent |
:no_recipients`. `with_lock` on the report; returns `:already_sent` when `completion_notified_at`
present; recipients `owners_for(instance, completion_step, use: :actors)`; enqueue
`KpiReportCompletedNotifier` per recipient after the lock commits; set column; `journey_progress!`.

**`InvestorKpiMappingDelete`** (Service): `.impact(mapping)` → `{kpis:, periods:, approved:, formulas:
[names], children: [names]}` (counts only). `.call(mapping:, user:)` → Result: Failure "Move or delete <children> first" when `children.exists?` (checked first, before any write); otherwise see Transactions.

**Reviewer checks**
- [ ] Every existing `owner_for` caller still gets the same user for capital call, distribution and KYC
- [ ] `start_journey!` never raises into a request or job
- [ ] Completion email cannot be sent twice under a double click (lock + column)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `KpiReportsController#journey` | — | `journey?` | frame HTML | 403 |
| `KpiReportsController#mark_reviewed` (Close report) | — | `mark_reviewed?` | redirect to report, "Closed — N KPIs approved across M periods" | redirect with alert |
| `KpiReportsController#send_completion_email` | — | `send_completion_email?` (= `update?` and fund employee) | redirect, "Completion email sent to Priya S." / "Already sent" / "No recipients — set Managed by or the step's actors" | 403 |
| `InvestorsController#update` | `+ :managed_by_user_id` | `update?` | as today | 422 with "must be an employee of this organisation" |
| `InvestorKpiMappingsController#destroy` | — | `destroy?` | redirect, "Revenue and 214 KPIs deleted" | redirect, "Could not delete Revenue — nothing was changed" |

**Reviewer checks**
- [ ] `managed_by_user_id` is validated against `investor.entity_id` server-side, not only by the dropdown
- [ ] No action without `authorize`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `Approve` check | `Kpi.unapproved.where(entity_id:, portfolio_company_id:).pick(Arel.sql("COUNT(*), COUNT(DISTINCT kpi_report_id)"))` | `index_kpis_on_entity_pc_status_name` | 1 row | — |
| `SetupMappings` check | `InvestorKpiMapping.not_compute.where(investor_id:).exists?` | `investor_id` FK idx | — | — |
| `Import` check | report columns + `documents.where(name: "KPIs").order(created_at: :desc).pick(:created_at)` + `kpis.exists?` | owner idx on documents; `kpi_report_id` | — | — |
| `journey_progress_for_portco` | `KpiReport.journey_progress_for(KpiReport.where(entity_id:, portfolio_company_id:).select(:id))` — Workflowable filters to records with an evaluated, non-archived instance in SQL | `portfolio_company_id` idx | ≤ ~10 | ids only |
| Mapping impact | `Kpi.where(investor_kpi_mapping_id:).count`, `.distinct.count(:kpi_report_id)`, `.approved.count` | `investor_kpi_mapping_id` idx | 3 counts | — |
| `workflow_default_owners` | `entity.employees.with_tag('Kpi').where(active: true)` | tags | ≤ 20 | memoized per record |

**Reviewer checks**
- [ ] Every query filters `entity_id` (or a PK reached from an entity-scoped record)
- [ ] No `present?`/`blank?` on a relation (`IRM/RelationBlankPresent`)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Completion email | report row | `kpi_report.with_lock` | double click sends twice | `completion_notified_at` |
| Close report | per-KPI (existing `KpiApprover`), then status | none | concurrent Close: second approves 0 | `KpiApprover` raises on already-approved → collect ids fresh, rescue "already approved" per id |
| Mapping delete | refuse if `children.exists?`; else KPIs (batched `delete_all`) + `mapping.destroy!` | none | partial delete | transaction |
| Journey hooks | after commit (`after_commit` or after the transaction block) | — | evaluating uncommitted data | — |

**Reviewer checks**
- [ ] No email enqueued inside a DB transaction (notifier after the lock block)
- [ ] `KpiApprover` "already approved" race handled in Close report

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `ImportKpiWorkbookJob` (modified) | `:low` | upload | existing | existing | `import_status` | existing |
| `KpiCumulateJob` + `KpiPercentageChangeJob` (reused) | existing | after mapping delete | existing | existing | — | — |
| `WorkflowEvaluateJob` (reused) | existing | 15-min tick | existing | — | — | — |
| `WorkflowAutoReminderJob` (modified) | existing | cron 00:30 | existing | — | — | — |

`ImportKpiWorkbookJob` additions, after the existing status block: (1) `kpi_report.start_journey!(user)` unless
`@kpi_reader.errors?`; (2) `KpiReport.journey_progress_for_portco(entity_id, pc_id, actor: user)`.

**Reviewer checks**
- [ ] Re-running the import job is harmless (start is idempotent; undo on an unchanged report is a no-op move)

---

## External Integrations

N/A — no third-party API.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| any in `start_journey!` | `WorkflowAutoAssignmentService` | rescue in `start_journey!` | nothing (request succeeds) | `Rails.logger.warn "[KpiReport#start_journey!] KpiReport#<id>: …"` |
| check error | a check | `WorkflowEvaluator` (existing) | "Could not check this step — support has been notified" | ExceptionNotifier with instance + step |
| `ActiveRecord::ActiveRecordError` in mapping delete | op | op rescue → Failure | flash alert | warn with mapping id, investor id, entity id |
| `ActiveRecord::RecordInvalid` on `managed_by` | Investor save | form | field error | — |

**Reviewer checks**
- [ ] No bare rescue that hides a failed delete

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `KpiReportPolicy#journey?`, `#mark_reviewed?`, `#send_completion_email?`; `InvestorKpiMappingPolicy#destroy?`; magic-link (portco) users get `false` for all journey actions |
| Tenant isolation | All checks filter by the report's `entity_id`; `managed_by` must be an employee of the investor's entity; recipients are always the fund's users |
| Secrets | none |
| Input / output sanitisation | Popup cards built with `tag`/`safe_join` (mapping and formula names escaped) |
| Mass assignment | Only `managed_by_user_id` added to investor params; no params on the new actions |

**Reviewer checks**
- [ ] A user from another entity cannot reach `journey`, `mark_reviewed` or `send_completion_email` for a report
- [ ] A portco magic-link user cannot see the panel

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | Per entity: journeys exist only after setup (rake, SetupCompany or the Set up journeys menu) |
| Cron / schedules | none new |
| Deploy order | migrations → code → `rake kpi_report_journeys:setup` dry run → `EXECUTE=1`, separately on IN and US |
| Rollback | Disable the "KPI Report Review" template per entity; journeys stop being launched; columns are inert |
| `JourneySetup` change | `plan[:cfo]` and `add_cfo_step` only when `SIGN_OFF_NAME` present; `confirm_message` drops the approver sentence then; `rollout` skips entities a kind's `available_for?` refuses (KPI: `enable_kpis`) |

**Reviewer checks**
- [ ] Re-running setup for capital call / distribution / KYC produces identical plans as before
- [ ] Safe to deploy with no entity set up

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/startup/kpi_report_journey_setup.feature` | — | entity, employees | `Given KPI report journeys are set up`, rake runner |
| `features/startup/kpi_report_journey.feature` | fixture workbook (31 periods) in `features/fixtures/`; `ImportKpiWorkbookJob` inline | portco, mappings, report | `When the workbook "…" is imported on …`, `Then only the report … has a journey` |
| `features/startup/kpi_report_journey_page.feature` | — | — | reuse capital-call panel/marker steps; `When I click Close report and confirm` |
| `features/startup/kpi_report_journey_undo.feature` | — | — | reuse "history shows moved back" steps |
| `features/startup/kpi_report_journey_owners.feature` | travel_to | tagged employees | `Given … is managed by …`, `When the reminder job runs` |
| `features/startup/kpi_mapping_deletion.feature` | stub a DB error for X2 via `define_singleton_method` | KPIs on a mapping | popup card assertions |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Checks use `exists?`/counts; cop runs |
| Dedup in SQL, batch bulk operations | Applies | `COUNT(DISTINCT)`; `in_batches.delete_all` |
| Select only needed columns on `account_entries`; no speculative `includes` | N/A | No account entries touched |
| Screen dates via `l(...)`; emails `Mon dd, yyyy` | Applies | Completion email uses `l(report.as_of)` (email override); panel dates via `l` |
| Date inputs via `f.date_field` | N/A | No date inputs |
| Entity scoping; Pundit on every action | Applies | See Security Review |
| MCP ontology | N/A | No MCP tool or ransackable change (`managed_by_user_id` not added to ransackable) |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | Test Plumbing |
| Rubocop clean | Applies | Run before each phase close |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
