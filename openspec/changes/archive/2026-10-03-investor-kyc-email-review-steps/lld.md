# Set up and preview the KYC email before it reaches the LP — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/kyc/investor-kyc-journey/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

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

The five decisions most worth arguing about:

- **`JourneyEmailEdit.records_for` gains an `Entity`-owner branch**, and only the KYC config narrows
  it with `link_sent_at: nil`. One company-level email edit therefore touches many KYCs — see
  [Queries and Indexes](#queries-and-indexes).
- **A new optional `email_methods:` key in `JourneyEmailEdit::CONFIGS`** limits the KYC reset to
  `notify_kyc_required`; `nil` preserves today's behaviour for calls and distributions — see
  [Method Contracts](#method-contracts).
- **Backfill anchors on name *and* `check_key`.** `insert_missing_steps` finds "Send KYC form" by
  name, falling back to `check_key == "investor_kyc.send_form"`, and treats a step carrying either
  new check key as already present. This resolves the rename risk left open in
  [design.md → risks](design.md#risks-and-open-questions).
- **Both new checks return `WorkflowChecks::Result.review`, not `pass`**, because only `review` makes
  the evaluator emit `review_action_*` for the panel's second button — see
  [Method Contracts](#method-contracts).
- **Links are built with `RansackQueryBuilder.single`, never `.multiple`.** `.multiple` generates
  random group keys per call, which would make `step_results` differ on every evaluation and turn
  each page view into a write — see [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/investor_kycs/services/investor_kyc_journey_setup.rb` | Modified | Two new `FULL_STEPS` rows at the head; `BACKFILL_STEPS`; update the step-list comment |
| ② | `app/packs/core/workflow_templates/services/journey_setup.rb` | Modified | `BACKFILL_STEPS = {}` default, `report[:steps]`, `insert_missing_steps`, `create_step` extracted from `find_or_seed`, `shift_positions_from` shared with `add_cfo_step`, `confirm_message` and `rollout` output |
| ③ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/review_email.rb` | New | "Set up KYC email" check |
| ④ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/check_preview.rb` | New | "Preview the email" check |
| ⑤ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/review_not_needed.rb` | New | Skip check for both |
| ③④⑤ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/support.rb` | Modified | `kyc_required_notification`, `preview_button_id`, `kyc_notifications_path`, `new_kyc_notification_path` |
| ③④⑤ | `config/initializers/workflow_checks.rb` | Modified | Register the three new check classes |
| ⑥ | `app/packs/core/workflow_templates/services/journey_email_edit.rb` | Modified | `CONFIGS["InvestorKyc"]`, `email_methods` filter, `Entity` branch in `records_for` |
| ⑦ | — | — | No change (panel and evaluator reused as is) |
| Docs | `docs/user_guides/investor_kyc_user_guide.md` | Modified | Journey task table, the two tasks, FAQs |
| Tests | `features/core/investor_kyc_journey.feature` | Modified | H1, H2, H6–H8, E1–E14, X1, X2 |
| Tests | `features/core/investor_kyc_journey_ui.feature` | Modified | H3, H4 |
| Tests | `features/core/investor_kyc_journey_end_to_end.feature` | New | H5, X3 |
| Tests | `features/step_definitions/investor_kyc_journey_steps.rb` | Modified | New steps (company KYC email, backfill, two-actor walk) |

**Reviewer checks**
- [ ] Every class in [design.md → class diagram](design.md#class-diagram) has a row here, and no row is missing from it
- [ ] The three new checks live in the `investor_kycs` pack beside the existing ones, not in `app/models`
- [ ] `config/initializers/workflow_checks.rb` lists all three, or `Registry.fetch` raises `KeyError` at evaluation time
- [ ] No change to `_journey_panel.html.erb`, `workflow_evaluator.rb` or `custom_notifications_controller.rb`

---

## Schema Detail

N/A — no table or column changes. The two tasks are `workflow_steps` rows written by setup;
confirmations use `workflow_actor_responses` and withdrawals `workflow_state_changes`, both existing.
`db/schema.rb` and `db/schema_test.rb` are untouched.

**Reviewer checks**
- [ ] No migration is added by this change
- [ ] `git diff db/` is empty

---

## Method Contracts

**`WorkflowChecks::InvestorKyc::ReviewEmail`** (Check)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#call(kyc)` | `InvestorKyc` | `Result.review(message:, action_label:, action_path:)` — always `review`, never `pass`/`fail` | nothing (a nil entity would raise `NoMethodError`, rendered as an errored step) | none — read only | Yes; no writes |

- `key = "investor_kyc.review_email"`, `label = "Set up KYC email (acknowledge)"`,
  `workflowable_type = "InvestorKyc"`.
- Message, per [spec](specs/kyc/investor-kyc-journey/spec.md): with a notification,
  `Your KYC email "#{notification.subject}" will be sent — check it and mark reviewed` and
  `action_label: "Open KYC emails"`; without one, the default-text warning and
  `action_label: "Custom KYC Notification"`.
- No `action_target`: both destinations are other screens (design D8 applies to ④ only).

**`WorkflowChecks::InvestorKyc::CheckPreview`** (Check)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#call(kyc)` | `InvestorKyc` | `Result.review(message:, action_label: "Preview KYC Required Notification", action_path:, action_target:)` | nothing | none | Yes |

- `key = "investor_kyc.check_preview"`, `label = "Preview the email (acknowledge)"`.
- `action_path = investor_kyc_path(kyc)` (fallback), `action_target = preview_button_id(kyc, "notify_kyc_required")`.
- The investor's name in the message comes from `kyc.full_name` — the same method
  `InvestorKycMailer::PLACEHOLDERS["investor_name"]` uses, so the panel and the email agree.

**`WorkflowChecks::InvestorKyc::ReviewNotNeeded`** (Skip check)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#call(kyc)` | `InvestorKyc` | `Result.pass(message:)` when not applicable, else `Result.fail` | nothing | none | Yes |

- Order is fixed: `FilledByFund` first ("Filled in by the fund"), then
  `kyc.link_sent_at.present? || kyc.submission_status != "not_sent"` ("The KYC form has already been
  sent"), else fail. Both conditions can hold at once; the first gives the more useful reason.
- It composes `FilledByFund.new.call(kyc).passed?` rather than copying its rule.

**`WorkflowChecks::InvestorKyc::Support`** (module, private helpers)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#kyc_required_notification(kyc)` | `InvestorKyc` | `CustomNotification` or `nil` | nothing | none | Yes |
| `#preview_button_id(kyc, email_method)` | KYC, string | DOM id string | nothing | none | Yes |
| `#kyc_notifications_path(_kyc)` | — | path string | nothing | none | Yes |
| `#new_kyc_notification_path(kyc)` | `InvestorKyc` | path string | nothing | none | Yes |

- `kyc_required_notification` is exactly
  `kyc.entity.custom_notification("notify_kyc_required", for_type: "InvestorKyc")` —
  `WithCustomNotifications#custom_notification`, i.e. `enabled` + `last`, the same resolution
  `InvestorKycMailer#set_kyc` performs. Do not substitute `latest` or `exists?`.
- `preview_button_id` mirrors the existing `email_button_id`: `..._custom_0_btn` when
  `kyc.entity.custom_notifications.for_type("InvestorKyc").exists?(email_method:)`, else
  `..._default_btn`, matching `investor_kycs/_preview_notifications.html.erb`.

**`JourneySetup`** (Trailblazer::Operation, base)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#plan(ctx, entity:, **)` | entity | `true`; fills `ctx[:report][:steps]` | nothing | none (read only) | Yes |
| `#apply(ctx, entity:, execute:, **)` | entity, execute | `true` | `ActiveRecord::RecordInvalid` → rolled back per entity | creates template / steps / rules | Yes — `plan` recomputes what is missing |
| `-#insert_missing_steps(template)` | template | number inserted | `RecordInvalid` | creates `WorkflowStep` rows, shifts positions | Yes |
| `-#create_step(template, row, position)` | `FULL_STEPS` row | `WorkflowStep` | `RecordInvalid` | one insert | No (caller decides position) |
| `-#shift_positions_from(template, position, by)` | — | nil | `RecordInvalid` | updates positions bottom-up | No |

- `BACKFILL_STEPS = {}` on the base; `InvestorKycJourneySetup::BACKFILL_STEPS = { "Send KYC form" => ["Set up KYC email", "Preview the email"] }.freeze`.
- `plan` returns `[]` for `:steps` when the Full template does not exist (it will be seeded whole) or
  the anchor is absent by both name and `check_key`.
- `add_cfo_step` keeps its signature and switches to `shift_positions_from` + `create_cfo_step`, so
  there is one position-shifting implementation.

**`JourneyEmailEdit`** (service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(notification:, actor:, started_at:)` | `CustomNotification`, `User`, `Time` | nil | never — `rescue StandardError` logs and notifies | invalidations + one journey evaluation per affected record | Yes — re-running re-invalidates already-invalidated steps harmlessly |
| `.records_for(notification, type)` | notification, type string | `ActiveRecord::Relation` | `NameError` only if `CONFIGS` gained a bad key | none | Yes |

- `CONFIGS["InvestorKyc"] = { review_keys: %w[investor_kyc.review_email investor_kyc.check_preview], sent_key: "investor_kyc.send_form", email_methods: %w[notify_kyc_required] }`.
- `.call` skips a config when `config[:email_methods].present? && !config[:email_methods].include?(notification.email_method)`.
- `records_for` new branch, before the existing `Fund` branch:
  `notification.owner_type == "Entity" && notification.for_type == type` →
  `klass.where(entity_id: notification.owner_id)`, then `.where(link_sent_at: nil)` for `InvestorKyc`
  (expressed as an optional `scope:` lambda in the config rather than a type test in the method).

**Reviewer checks**
- [ ] Both new checks return `Result.review` — a `pass` would silently drop the second button
- [ ] No check writes anything, and none reads another KYC's rows
- [ ] `kyc_required_notification` uses `entity.custom_notification(...)`, not a hand-rolled query
- [ ] `create_step` is used by both `find_or_seed` and `insert_missing_steps` (no duplicated row → step mapping)
- [ ] Calls and distributions still have no `email_methods` key, and `nil` means "any method"
- [ ] `add_cfo_step` behaviour is unchanged after the shift extraction

---

## Controllers, Params and Responses

N/A — no controller action, route or permitted param changes. `CustomNotificationsController`'s
existing `after_action :invalidate_journey_reviews` already covers create, update and destroy, and the
confirmations go through the existing `acknowledge_workflow_instance_path`.

**Reviewer checks**
- [ ] `config/routes/` is untouched
- [ ] `custom_notification_params` is untouched

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `Support#kyc_required_notification` | `custom_notifications WHERE owner_type='Entity' AND owner_id=? AND email_method=? AND for_type=? AND enabled` | `[owner_type, owner_id]` | ≤ 3 | none needed (one row taken) |
| `Support#preview_button_id` | same table, `exists?` by `email_method` | same | existence only | — |
| `ReviewNotNeeded#call` | the KYC's own `link_sent_at`, `submission_status` columns | primary key | 1 | — |
| `JourneyEmailEdit.records_for` (KYC) | `investor_kycs WHERE entity_id=? AND link_sent_at IS NULL AND id IN (SELECT workflowable_id FROM workflow_instances WHERE evaluated AND workflowable_type='InvestorKyc' AND status<>'archived')` | `[entity_id]` on `investor_kycs`; `[workflowable_type, workflowable_id]` on `workflow_instances` | tens | existing `find_each` |
| `JourneySetup#plan` | `workflow_steps WHERE workflow_template_id=?` names | `[workflow_template_id]` | ≤ 20 | `pluck(:name, :check_key)` |
| `#shift_positions_from` | `workflow_steps WHERE workflow_template_id=? AND position >= ?` `reorder(position: :desc)` | `[workflow_template_id, position]` | ≤ 20 | row-by-row update, bottom-up |

- Links are built with `RansackQueryBuilder.single("for_type", :eq, "InvestorKyc")` (deterministic
  `idx`-keyed hash) plus `filter: true` — the same params the KYC index's "View All Custom
  Notifications" item uses. `.multiple` is forbidden here: its random group keys would change
  `step_results` on every evaluation.
- Every query is scoped by `entity_id` or by the record's own id; `records_for` derives `entity_id`
  from the notification's `owner_id`, never from params.
- `investor_kycs` is a modest table (thousands per entity), and the predicate excludes sent KYCs, so
  no large-table batching rules apply.

**Reviewer checks**
- [ ] `records_for` is scoped by the notification's own `owner_id`, with no fallback that widens it
- [ ] `link_sent_at IS NULL` is in SQL, not a Ruby `select`
- [ ] No `RansackQueryBuilder.multiple` in any check
- [ ] `plan` reads step names with `pluck`, not by loading `WorkflowStep` objects

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Backfill insert | the existing `ActiveRecord::Base.transaction` in `JourneySetup#apply` (one per entity) | none | a half-inserted pair, or a position collision mid-shift | the template's unique `(workflow_template_id, position)` index |
| Position shift | same transaction | none (bottom-up ordering instead) | unique-index violation while renumbering | — |
| `JourneyEmailEdit` per record | no wrapping transaction (per-record invalidate + evaluate, as today) | none | — | re-invalidation is harmless |

- Two concurrent setups for one entity: the second finds the steps present and inserts nothing; worst
  case one of them raises on the unique position index and that entity is reported as failed, which
  `rollout` already handles per entity.
- No email, HTTP call or job enqueue happens inside the setup transaction.

**Reviewer checks**
- [ ] Positions are shifted in descending order (`reorder(position: :desc)`), matching `add_cfo_step`
- [ ] Nothing external is called inside `JourneySetup#apply`'s transaction
- [ ] A second rollout run on the same entity writes nothing

---

## Background Jobs

N/A — no job or cron entry is added. The existing periodic journey evaluation and the next page view
pick the new tasks up; `SendKycFormJob` is untouched.

**Reviewer checks**
- [ ] No new Sidekiq job, and no change to `SendKycFormJob` or `KycReminderJob`

---

## External Integrations

N/A — no third-party call.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `StandardError` during the reset | `JourneyEmailEdit.call` (per record) | its existing `rescue StandardError` | the notification save still succeeds and redirects | `Rails.logger.error("[JourneyEmailEdit] notification <id>: …")` + `ExceptionNotifier` with `custom_notification_id` |
| `KeyError` | `WorkflowChecks::Registry.fetch` when a check key is unregistered | the evaluator renders an errored step with no action | the task shows as errored, nothing else breaks | existing evaluator logging |
| `ActiveRecord::RecordInvalid` | `insert_missing_steps` / `create_step` | `JourneySetup.rollout`'s per-entity `rescue` | the rollout line says `FAILED — <message>`; other entities continue | printed by the rake task |
| `NoMethodError` (KYC without an entity) | `ReviewEmail#call` | the evaluator's per-check rescue | the task shows as errored | existing evaluator logging |

The existing `rescue StandardError` in `JourneyEmailEdit` is deliberate and already carries both a log
line with the notification id and an `ExceptionNotifier` call — it is not a silent swallow.

**Reviewer checks**
- [ ] No new bare `rescue`
- [ ] The rollout's per-entity failure path still prints the entity id and name

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Confirmations go through the existing `acknowledge_workflow_instance_path`; the panel renders **Mark reviewed** only under `policy(record).update?`. The preview uses the existing authorised `InvestorKycsController#preview`. No new action, so no new policy method. |
| Tenant isolation | Checks read only the KYC passed to them and that KYC's own `entity`. `records_for` scopes by the notification's `owner_id` (the entity) — a company's edit can never reach another company's KYCs. `JourneySetup` is always called with one `entity`. |
| Secrets | None involved. The preview renders the same signed link the email already contains, through the existing route. |
| Input / output sanitisation | The task message interpolates `notification.subject` and `kyc.full_name` into a plain-text message rendered by ERB with default escaping; no `html_safe` anywhere in the new code. |
| Mass assignment | No new params. |

**Reviewer checks**
- [ ] No `html_safe` / `raw` in the new checks or in any message
- [ ] A user from another entity cannot confirm these tasks (existing panel + policy path, unchanged)
- [ ] `records_for` has no branch that returns records outside the notification's entity

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | none — the tasks exist wherever the journey is seeded |
| Cron / schedules | unchanged |
| Deploy order | code (no migration), then `bin/rails investor_kyc_journeys:rollout` dry run, then `EXECUTE=1` |
| Rollout command | `bin/rails investor_kyc_journeys:rollout` (dry run) → `EXECUTE=1 bin/rails investor_kyc_journeys:rollout`, optionally `ENTITY_ID=<id>`; run separately on IN and US |
| Rollback | Remove the two steps from each affected template (an admin action, or a one-off script); the checks then go unreferenced and dormant. No data cleanup — confirmations and invalidations are inert rows. |

Deploying the code without running the rollout is safe: existing templates keep nine tasks and
nothing changes. Running the rollout twice is safe (nothing missing). The release note worth giving
support: a KYC sitting at "Send KYC form" becomes current at "Set up KYC email" (E11).

**Reviewer checks**
- [ ] Safe to deploy before the rollout runs, and safe to run the rollout twice
- [ ] IN and US are rolled out separately, each with its own dry run first

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/investor_kyc_journey.feature` | none (data-driven, no browser) | existing entity / investor / `investor_kyc` factories | "the entity has a KYC email …", "the entity's KYC email is disabled", "I edit the entity's KYC email", "I delete the entity's KYC email", "the entity has a KYC reminder email", "the investor KYC journey template has only the original nine tasks", "the rollout output should mention …" |
| `features/core/investor_kyc_journey_ui.feature` | Capybara (existing `@journey` setup) | same | reuses "the panel review action {string} should click {string}" and "I mark {string} reviewed on the KYC" |
| `features/core/investor_kyc_journey_end_to_end.feature` (new) | Capybara + the magic-link session switch | same | reuses `investor_kyc_send_workflow_steps.rb` ("I am logged in as the investor user", "I open the KYC edit page as the investor via a valid signed link"); new: "the investor submits the KYC with the documents {string} via their link", "I log back in as the fund user" |

- Shared `Background` already seeds the journey, AML and required documents; only the company-email
  steps are new. Nine-task setup for the backfill scenarios is produced by deleting the two seeded
  steps from the template, which is also what a pre-release company looks like.
- Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber <feature>`; Redis must be up on 6379.
- `features/core/user_guide_lint.feature` must stay green after the user-guide edit.

**Reviewer checks**
- [ ] Every worked example in [design.md → worked examples](design.md#worked-examples) maps to exactly one scenario
- [ ] No RSpec spec file is added anywhere
- [ ] The end-to-end scenario really switches actor (LP acts through their own session/link, not as the fund user)

---

## Project Rules Checklist

| Rule | Applies / N/A | How it is satisfied |
|---|---|---|
| Large-table hygiene (no `in_batches` + `update_all` on `account_entries`-scale tables) | N/A | No bulk update; the largest scan is one entity's unsent KYCs |
| Query scoping by `entity_id` (multi-tenancy) | Applies | See [Security Review](#security-review); every read is entity- or record-scoped |
| Pundit `authorize` in every controller action | N/A | No controller change |
| Strong parameters | N/A | No new params |
| Date formatting through `I18n.l` | Applies | No new date is rendered; `Support#date` is available if one is added |
| Chewy index updates | N/A | Neither `WorkflowStep` nor `CustomNotification` is indexed |
| Money via `money-rails` | N/A | No amounts |
| Packs layout (`app/packs/<domain>/<sub_domain>/...`) | Applies | New checks sit beside the existing KYC checks; the shared backfill sits in `workflow_templates` |
| Enumerize / Audited / Paranoia conventions | N/A | No model change |
| Cucumber only, factories in `spec/factories/` | Applies | See [Test Plumbing](#test-plumbing) |
| RuboCop + Brakeman clean | Applies | `bundle exec rubocop <changed files>`; Brakeman unaffected (no controller or raw SQL change) |
| Inline comments on the steps inside methods | Applies | Each new check and the backfill carry step-level comments plus H/E/X ids linking to [design.md](design.md#worked-examples) |
| User guide updated when a journey's steps change | Applies | `docs/user_guides/investor_kyc_user_guide.md`, verified by `user_guide_lint` |

**Reviewer checks**
- [ ] Every "Applies" row has visible evidence in the diff
- [ ] New code carries worked-example ids (H/E/X) in its comments, as the existing KYC checks do

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | approved / changes requested |
