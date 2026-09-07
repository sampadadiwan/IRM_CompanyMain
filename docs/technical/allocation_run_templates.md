# Allocation Run Templates and Groups

Lets an employee define a close once — which funds, in what order, with which allocation
options — and run it for any period with one action. Business background and the decisions
this implements are in `docs/business_requirements/allocation_run_sequences.md`; the decision
numbers below refer to that document.

## Models

| Model | Table | Purpose |
|-------|-------|---------|
| `AllocationRunTemplate` | `allocation_run_templates` | One fund plus every option on the allocation screen except the period: `rule_for`, `tag_list`, `run_allocations`, `generate_soa`, `statement_for`, `statement_document_id`, `fund_ratios`, `explain`, `sample` (decision 14a). Unique `name` per entity. |
| `AllocationRunTemplateGroup` | `allocation_run_template_groups` | A named close. `accepts_nested_attributes_for :items`. Must have at least one item. |
| `AllocationRunTemplateGroupItem` | `allocation_run_template_group_items` | Membership with a numeric `position` (decision 18a). Unique template per group. |
| `AllocationGroupRun` | `allocation_group_runs` | One execution of a group for a period. `status`: queued → running → success / failed. `group_name` is a snapshot; `allocation_run_template_group_id` is nullified when the group is deleted (decision 17). `resumed_from_id` points at the earlier run whose successes were reused (decision 8c). |
| `AllocationGroupRunItem` | `allocation_group_run_items` | One template's slot in a run, in `position` order. `status`: pending → running → success / failed / skipped / reused. Links to the `AllocationRun` it produced; `template_name` and `fund_id` are snapshots. |

Association hooks elsewhere:

- `Fund has_many :allocation_run_templates, dependent: :restrict_with_error` — a fund with templates cannot be deleted until they are removed.
- `AllocationRunTemplate has_many :group_items, dependent: :restrict_with_error` — a template in a group cannot be deleted (decision 17b).
- `Document has_many :allocation_run_templates, foreign_key: :statement_document_id, dependent: :nullify` — the template then fails its pre-flight instead of silently producing no statements (decision 15b).
- `AllocationRun has_one :allocation_group_run_item` — a run produced by a group can be traced back to it.
- `Entity` declares the three new `has_many`s *before* `:funds` so entity deletion tears them down in an order the restrictions allow.

## Services

### `AllocationGroupRunPreflight` (Trailblazer operation)

`call(group:, user:, start_date:, end_date:, resume: true)` never fails; it describes. It returns:

- `checks` — one `Check` per template in run order with `status` `:ready | :warning | :blocked | :reused` and a list of `Message(severity, text)`.
- `group_blockers` — problems with the group as a whole.
- `startable` — `group_blockers` empty, no check blocked, at least one check will run.
- `resume_from` — the most recent finished run of this group for exactly the same period that had at least one success, when `resume` is true.

Per-template checks, in order:

| Check | Severity | Decision |
|-------|----------|----------|
| `FundPolicy#allocate?` on the template's fund | blocker | 4 |
| `generate_soa` with a missing statement document | blocker | 15b |
| Template tags not in `entity_setting.formula_tag_list` | blocker | 16c |
| `sample` on | warning | 14a |
| `AllocationRun.locked_and_overlapping` (only when `run_allocations`) | blocker | same rule as a manual run |
| `ValidationRuleEvaluator` on a temporary `AllocationRun` | blocker / warning as the rule says | 3 |
| Period does not start the day after the last locked run | warning | 12b |

Group-level blockers: missing or inverted dates, an empty group, another `AllocationGroupRun` active for the entity (decision 10b), or every template already reused (nothing would run).

### `AllocationGroupRunStart` (Trailblazer operation)

Runs the preflight again (the confirmation page may be stale), fails with `error` unless `startable`, then in one transaction creates the `AllocationGroupRun` and its items (reused checks are stored as `reused` with the earlier `allocation_run_id`) and enqueues `AllocationGroupRunJob`.

### `AllocationGroupRunJob`

Queue `high`, `retry: 0`. For each item in position order that is not finished:

1. If an earlier item failed, mark this one `skipped`.
2. Otherwise mark `running`, create a new `AllocationRun` from `template.allocation_run_attributes` (inside `WithValidationRules.skip`, as `FundsController#allocate` does), and call `AccountEntryAllocation::Engine` directly with `template.engine_options` under the same `Chewy.strategy(:bypass)` / `Audited.as_user` wrappers as `AccountEntryAllocationJob`.
3. Success (decision 7a): the engine result is not a failure **and** the `AllocationRun` status is `Success` when formulas ran (blank or `Success` for a statements-only run). Anything else, including a run left at `Pending`, is `failed` and stops the group.

When the loop ends the run is `success` or `failed`, a `UserAlert` is broadcast to the triggering user and `AllocationGroupRunMailer#completed` is delivered (decision 19b).

Restart safety (decision 9b): the job is idempotent over item status. If Sidekiq re-queues the job after a worker restart, `perform` skips finished items and re-runs the one that was `running` (creating a fresh `AllocationRun` for it). The old run stays in the fund's history at whatever status it reached. A hard kill (`kill -9`) without Sidekiq's shutdown push-back leaves the group at `running`; the entity is then blocked from starting another group until the row is fixed by hand (`status: "failed"`), which is deliberate — a silently abandoned close is worse than a visible stuck one.

### Guard on manual runs (decision 10c)

`AllocationGroupRun.fund_busy?(fund_id)` is true while an active group run has a `pending` or `running` item on the fund. `FundsController#allocate` refuses a manual run with a flash, and the allocation screen shows a banner and disables Submit.

## Controllers, routes, policies

```
resources :allocation_run_templates            # + GET statement_documents (JSON for the form)
resources :allocation_run_template_groups, except: :index
  GET  :preflight  # the up-front check page
  POST :run        # AllocationGroupRunStart
resources :allocation_group_runs, only: %i[index show]
```

- `AllocationRunTemplatesController#index` is the single "Allocation Run Templates" page (tabs: groups, templates, run history). `create` accepts either the full form or `from_allocation_run_id` + a name (the "Save as template" modal on the allocation screen), and honours a same-site `return_to`.
- `AllocationRunTemplatePolicy`: company admin or `FundPolicy#allocate?` on the template's fund.
- `AllocationRunTemplateGroupPolicy`: company admin or `allocate?` on **every** fund in the group (`run?` and `preflight?` included).
- `AllocationGroupRunPolicy#show?`: company admin or `allocate?` on every fund the run touched.

Pack helpers are not auto-included, so each controller declares `helper AllocationRunTemplatesHelper` (status badges, option badges, durations).

## UI

- **Allocation screen** (`funds/allocate_form`): a *Save as template* button per unlocked past run opens `allocation_run_templates/_save_as_template_modal` (action-summary pattern; asks only for a name). A warning banner and disabled Submit while `fund_busy?`.
- **Index**: three-step explainer, active-run banner, tabs. Group cards show templates in run order with option badges and the last run's status. Run modals are rendered after the tabs, never inside a card.
- **Run modal** (`_run_modal`): action-summary cards explaining the checks, the order, fail-early and the notification; start/end date (`date_field_tag`), *Resume from the failed template* (default on, shown once the group has been run). Submits `GET preflight` — nothing runs from the modal.
- **Pre-flight page**: summary strip (ready / warnings / blocked / already done), a left-bordered row per template with its messages, then *Start run* (POST with hidden dates + resume) only when startable; otherwise "Nothing will run" and *Check again*.
- **Group run page**: tabs *Progress* and *Details*. The progress panel lives in a `turbo_frame_tag "group_run_progress"`; the `auto-refresh` Stimulus controller on the inner div reloads the frame every 5 s while the run is active and stops itself once the server renders `active=false`.
- **Group form**: every entity template as a row with an *Include* tick and a *Position* number. Unticked rows post `_destroy=1`, which Rails drops for new rows and removes for existing ones — no JavaScript needed.
- **Template form**: same fields as the allocation screen minus the period, with tooltips; `allocation-run-template-form` Stimulus controller refills the *Statement document* select from the JSON endpoint when the fund changes.

Styles are in `app/assets/stylesheets/custom/allocation_run_templates.scss` (layout only; badge colours are theme classes).

## Sequence diagrams

### Running a group

```mermaid
sequenceDiagram
    actor Employee
    participant UI as Templates page
    participant GC as AllocationRunTemplateGroupsController
    participant PF as AllocationGroupRunPreflight
    participant ST as AllocationGroupRunStart
    participant Job as AllocationGroupRunJob
    participant Eng as AccountEntryAllocation::Engine
    participant Mail as AllocationGroupRunMailer

    Employee->>UI: Run "Quarterly close" (modal: dates, resume)
    UI->>GC: GET preflight?start_date&end_date&resume
    GC->>PF: call(group, user, period, resume)
    PF-->>GC: checks, group_blockers, startable
    alt not startable
        GC-->>Employee: "Nothing will run" + blocked templates and why
    else startable
        GC-->>Employee: what will run, warnings, Start run
        Employee->>GC: POST run
        GC->>ST: call(...)
        ST->>PF: call (re-check)
        ST->>ST: create AllocationGroupRun + items (reused ones pre-filled)
        ST->>Job: perform_later(group_run_id)
        GC-->>Employee: redirect to progress page (auto-refreshing)
        loop items in position order, not yet finished
            Job->>Job: item running; create AllocationRun
            Job->>Eng: new(fund, period, **template.engine_options).call
            Eng-->>Job: result + AllocationRun.status
            alt Success
                Job->>Job: item success
            else failure or Pending
                Job->>Job: item failed; remaining items skipped
            end
        end
        Job->>Job: group run success / failed
        Job-->>Employee: UserAlert (in-app)
        Job->>Mail: completed.deliver_later
        Mail-->>Employee: email with per-template results
    end
```

### Saving a template from a past run

```mermaid
sequenceDiagram
    actor Employee
    participant AS as Allocation screen (allocate_form)
    participant TC as AllocationRunTemplatesController
    participant T as AllocationRunTemplate

    Employee->>AS: Save as template (past run row)
    AS-->>Employee: modal: what is copied, period not saved, name field
    Employee->>TC: POST create (from_allocation_run_id, name, return_to)
    TC->>T: from_allocation_run(run)
    T->>T: copy fund + options; resolve statement document by name on the fund
    TC->>T: assign name; save
    TC-->>Employee: redirect back to the allocation screen with notice
```

### Resume after a failure

```mermaid
sequenceDiagram
    actor Employee
    participant PF as AllocationGroupRunPreflight
    participant Prev as Previous AllocationGroupRun (failed)
    participant New as New AllocationGroupRun

    Employee->>PF: preflight, same period, resume=true
    PF->>Prev: latest finished run for group + period with a success
    Prev-->>PF: items: Master=success, Feeder=failed
    PF-->>Employee: Master "Already done" (reused), Feeder checked normally
    Employee->>New: Start run (resumed_from = Prev)
    New->>New: Master item = reused (links Prev's AllocationRun); Feeder item = pending
    Note over New: the job only runs Feeder
```

## Deferred from the first version

- **Explain button per group** (decision 13b): explain is carried as a template option instead; a read-only group-level rehearsal is not built because explain mode today writes explanations onto real entries rather than producing a report.
- A fixed finance mailbox on failure (decision 19c), pending the business naming it.
- Everything listed under "Deliberately out of scope" in the requirements document.

## Tests

`features/fund/allocation_run_templates.feature` with steps in
`features/step_definitions/allocation_run_templates.rb`. The engine is stubbed at
`AllocationGroupRunJob#run_engine` so the ordering, fail-early, Pending-as-failure, resume
and restart behaviours are tested without running real allocations; two `@javascript`
scenarios cover the templates page → run modal → pre-flight → progress flow and the
*Save as template* modal.
