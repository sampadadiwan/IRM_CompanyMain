# Capital Call & Distribution Maker–Checker — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/funds/capital-call-distribution-maker-checker/spec.md) · [Business rules](business-rules.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This adds to [design.md](design.md); it links to its diagrams and worked
> examples rather than repeating them.

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
- [Pattern Conformance](#pattern-conformance)
- [Security Detail](#security-detail)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Callbacks, not ops, record preparers** ([D3](design.md#d3-record-via-model-callbacks-deduped-per-requestjob)) —
  check the [bypass-writer list](#queries-and-indexes) is complete: any `update_columns`/`update_all`/`insert_all` on a
  figure column escapes the rule.
- **Withdrawal runs inside the change's transaction with a parent `lock!`** — see
  [Transactions](#transactions-locking-and-concurrency); a failed withdrawal rolls the user's edit back (X16).
- **Child creates on an approved parent are ignored** so late-closer remittances keep the approval (E43) — confirm no
  other "create on approved parent" path should count.
- **Create-audit creator is always a preparer** — one `audits` lookup on `auditable_index`; confirm `limit(1)` and
  `select(:user_id)` keep it off the wide `audited_changes` column.
- **Throttle reads `noticed_events`** — confirm the index used (`record_type, record_id` is on `noticed_notifications`,
  not events): the query filters events by `type` + `params` JSON, see [Queries](#queries-and-indexes).
- **Off by default, everywhere** — migration default `false`; nothing changes for any firm on deploy.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `db/migrate/2026111xxxxxxx_add_approval_maker_checker_to_entity_settings.rb` | New | Boolean column |
| ① | `app/packs/core/entities/models/entity_setting.rb` | Modified | `after_commit :announce_maker_checker_off`, only on true → false |
| ① | `app/packs/core/entities/policies/entity_policy.rb` | Modified | Add `:approval_maker_checker` to `ENTITY_SETTING_ATTRIBUTES` (`:73-79`) |
| ① | `app/packs/core/entities/views/entities/_form_fields.html.erb` | Modified | "Approvals" block after the Weekly Task Digest block (`:124-135`) |
| ③ | `db/migrate/2026111xxxxxxx_create_approval_makers.rb` | New | Table + indexes |
| ③ | `app/packs/funds/maker_checker/models/approval_maker.rb` | New | Model, `belongs_to :approvable, polymorphic`, `:user`, `:entity`; `ROLES` |
| ③ | `app/packs/funds/maker_checker/models/concerns/with_approval_makers.rb` | New | `record_preparer!`, `preparer_ids`, `preparers`, `approved_by_preparer?`, `maker_checker_on?`, `maker_checker_exempt?` |
| ② | `app/packs/funds/maker_checker/models/concerns/approval_figure_watch.rb` | New | `after_save`/`after_destroy` hooks; `FIGURES` contract; `approval_parent` |
| ② | `app/packs/funds/maker_checker/models/approval_maker_cache.rb` | New | `ActiveSupport::CurrentAttributes` with `seen` Set |
| ② | `app/packs/funds/capital_calls/models/capital_call.rb` | Modified | include both concerns; `APPROVAL_FIGURES`; `attr_accessor :approval_withdrawn` |
| ② | `app/packs/funds/capital_distributions/models/capital_distribution.rb` | Modified | same |
| ② | `app/packs/funds/capital_remittances/models/capital_remittance.rb` | Modified | include `ApprovalFigureWatch`; `APPROVAL_FIGURES`; parent `capital_call` |
| ② | `app/packs/funds/capital_distribution_payments/models/capital_distribution_payment.rb` | Modified | same; parent `capital_distribution` |
| ② | `app/packs/funds/capital_calls/models/call_fee.rb` | Modified | same; parent `capital_call` |
| ② | `app/packs/funds/capital_distributions/models/distribution_fee.rb` | Modified | same; parent `capital_distribution` |
| ④ | `app/packs/funds/maker_checker/policies/maker_checker_policy_methods.rb` | New | `maker_checker_allows?`, `awaiting_second_approver?`, `request_approval?` |
| ④ | `app/packs/funds/capital_calls/policies/capital_call_policy.rb` | Modified | include mixin; `approve?` (`:43-45`) gains `&& maker_checker_allows?` |
| ④ | `app/packs/funds/capital_distributions/policies/capital_distribution_policy.rb` | Modified | same at `:164-166` |
| ⑤ | `app/packs/funds/capital_calls/jobs/capital_calls_bulk_action_job.rb` | Modified | Failure text at `:22` |
| ⑤ | `app/packs/funds/capital_distributions/jobs/capital_distributions_bulk_action_job.rb` | Modified | Failure text at `:21` |
| ⑥ | `config/routes/fund.rb` | Modified | `post 'request_approval', on: :member` in both resources (`:164-177`, `:192-210`) |
| ⑥ | `app/packs/funds/capital_calls/controllers/capital_calls_controller.rb` | Modified | `request_approval` action; add to `set_capital_call` `only:` (`:6`); withdrawal sentence in `update` notice |
| ⑥ | `app/packs/funds/capital_distributions/controllers/capital_distributions_controller.rb` | Modified | same (`:4`) |
| ⑥ | `app/packs/funds/capital_remittances/controllers/capital_remittances_controller.rb`, `capital_distribution_payments_controller.rb` | Modified | Append withdrawal sentence to the update notice when the parent's `approval_withdrawn` |
| ⑥ | `app/packs/funds/capital_calls/views/capital_calls/show.html.erb` | Modified | Approve item states (`:91-126`), Request approval item |
| ⑥ | `app/packs/funds/capital_calls/views/capital_calls/_show.html.erb` | Modified | "Prepared by" row; label next to Approved (`:153-157`) |
| ⑥ | `app/packs/funds/capital_distributions/views/capital_distributions/show.html.erb` | Modified | Approve item (`:230-240`), Request approval, Prepared by, label (`:166-170`) |
| ⑥ | `app/packs/funds/maker_checker/helpers/maker_checker_helper.rb` | New | `maker_checker_action_summary(record, checkers)` (copy of `DocChecksHelper#doc_check_action_summary` shape) |
| ⑥ | `app/packs/funds/capital_calls/workflow_checks/capital_call/approve_call.rb`, `capital_distributions/workflow_checks/capital_distribution/approve_distribution.rb` | Modified | Fail message suffix when on |
| ⑦ | `app/packs/funds/maker_checker/services/maker_checker_notices.rb` | New | Recipients + `request`, `withdrawn`, `switched_off` |
| ⑦ | `app/packs/funds/maker_checker/notifiers/maker_checker_notifier.rb` | New | `< BaseNotifier`, record = recipient |
| ⑦ | `app/packs/funds/maker_checker/mailers/maker_checker_mailer.rb` + `views/maker_checker_mailer/notice.html.erb` | New | Internal email |
| ⑧ | `app/packs/funds/maker_checker/services/approval_withdraw.rb` | New | Un-approve inside transaction; after-commit journey undo + notice |
| Docs | `docs/user_guides/capital_calls_user_guide.md`, `capital_distributions_user_guide.md`, entity settings guide | Modified | Sections + FAQs |
| Tests | `features/funds/maker_checker/*.feature` (6), `features/security/maker_checker_approval.feature`, `features/step_definitions/maker_checker_steps.rb` | New | F1–F7 |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/funds/maker_checker/...` inside the `funds` pack) and Packwerk boundaries (`core` ← `funds` only)

---

## Schema Detail

**`entity_settings`** (existing): the firm's switch.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `approval_maker_checker` | Added | boolean | — | no | `false` | none (read via `entity_setting` association) | Not null so policies never branch on nil; default false = D6 |

**`approval_makers`** (new): preparers per record.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `id` | Added | bigint | — | no | — | PK | — |
| `entity_id` | Added | bigint | — | no | — | FK `entities`, index | Tenant scope; copied from the record, never from params |
| `approvable_type` | Added | string | 40 | no | — | part of unique | `CapitalCall` / `CapitalDistribution` (class names ≤ 19 chars) |
| `approvable_id` | Added | bigint | — | no | — | part of unique | Record id |
| `user_id` | Added | bigint | — | no | — | FK `users`, index | The preparer |
| `role` | Added | string | 20 | no | — | — | `created` / `edited` / `imported`; validated inclusion |
| `created_at` | Added | datetime | — | no | — | — | First time; no `updated_at` (append-only) |
| unique `[approvable_type, approvable_id, user_id]` | New index | — | — | — | — | `index_approval_makers_on_approvable_and_user` | Idempotent `insert_all … unique_by` |

**Migration safety:** `entity_settings` has one row per entity (~hundreds): instant `ADD COLUMN … DEFAULT 0 NOT NULL`
(MySQL 8 instant DDL). `approval_makers` is new. Both reversible. No backfill (D4). Update `db/schema.rb` **and**
`db/schema_test.rb`; per the local-migrate memory, restore schema files after `db:migrate` and hand-insert the
additions, then `db:clean_schema`. Do not migrate the shared dev DB from a side branch without asking.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and the uniqueness rule is enforced by the unique index
- [ ] `role` limit 20 matches the model's inclusion list; `approvable_type` 40
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

**`WithApprovalMakers`** (Concern on `CapitalCall`, `CapitalDistribution`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `record_preparer!(user, role:)` | `User`, `Symbol` | `true` | — (`insert_all` skips duplicates) | 0–1 INSERT; marks `ApprovalMakerCache` | Yes — cache + unique index |
| `preparer_ids` | — | `Array<Integer>` (memoised) | — | 2 SELECTs first call | Yes |
| `preparers` | — | `Array<User>` ordered by first row `created_at` | — | 1 SELECT | Yes |
| `approved_by_preparer?` | — | Boolean | — | uses `preparer_ids` | Yes |
| `maker_checker_on?` | — | Boolean (`entity.entity_setting&.approval_maker_checker == true`) | — | ≤ 2 SELECTs, memoised | Yes |
| `maker_checker_exempt?` | — | Boolean: `DealingDate.exists?(subscription_call_id: id)` / `redemption_distribution_id` or `evergreen_settlement_flag` | — | 1 SELECT, memoised | Yes |

**`ApprovalFigureWatch`** (Concern on six models)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `approval_parent` | — | the `CapitalCall`/`CapitalDistribution` (self for parents) | — | association read | Yes |
| (callback) `watch_approval_figures` | — | — | re-raises `ActiveRecord::RecordInvalid` from withdrawal | may call `record_preparer!`, `ApprovalWithdraw.call` | Yes — second run finds preparer cached and parent unapproved |

- Recorded actor: `Current.user` only — the support person when impersonating (`with_authentication.rb:255-262`), the
  uploader in import jobs (`ApplicationJob` `:31,88`). Role: `created` on parent create, `imported` when
  `import_upload_id` is set, `edited` otherwise. No second id is recorded ([D9](design.md#d9-support-acting-as-a-user-record-the-real-person-check-both-ids)).

**`MakerCheckerPolicyMethods`** (Policy mixin)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `maker_checker_allows?` | — | `true` unless `record.maker_checker_on? && !record.maker_checker_exempt? && (actor_ids & record.preparer_ids).any?` | — | none | Yes |
| `awaiting_second_approver?` | — | `!record.approved && update? && user.has_cached_role?(:approver) && !maker_checker_allows?` | — | none | Yes |
| `request_approval?` | — | `!record.approved && update? && record.maker_checker_on? && !record.maker_checker_exempt? && !approve?` — offered only to people who cannot approve it themselves | — | none | Yes |

- `actor_ids` = `[user.id, user.support_user_id].compact` (`User#support_user_id` exists — `with_authentication.rb:260-262`).

**`ApprovalWithdraw`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(record:, actor:)` | parent record, `User` | `true` if withdrawn, `false` if already unapproved | `ActiveRecord::RecordInvalid` (rolls back the caller) | `record.lock!`; `approved=false`, `approved_by_user=nil`, `save!`; `record.approval_withdrawn = true`; `after_commit` → `journey_undo_evaluate(note:, actor:, started_at:)` + `MakerCheckerNotices.withdrawn` | Yes — re-checks `approved` after `lock!` |

**`MakerCheckerNotices`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.checkers(record)` | record | `Array<User>` | — | ≤ 3 SELECTs | Yes |
| `.request(record, user)` | record, `User` | `Result(sent:, recipients:, error:)`; `error` ∈ `:no_checker`, `:throttled` (with `asked_at`) | — | `MakerCheckerNotifier.deliver` per recipient | No — but throttled 1 h |
| `.withdrawn(record, actor)` | | `Integer` sent | — | deliveries | Once per withdrawal (callers guarantee) |
| `.switched_off(setting, actor)` | | `Integer` sent | — | deliveries | Once per true → false |

**`MakerCheckerNotifier`** (Notifier `< BaseNotifier`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.with(record: recipient, entity_id:, kind:, approvable_type:, approvable_id:, message:)` `.deliver(recipient)` | | Noticed event | — | email (`MakerCheckerMailer#notice`) + bell | Noticed |
| `custom_notification` | | `nil` (internal) | | | |
| `url` | | `capital_call_path` / `capital_distribution_path` | | | |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (Noticed delivery jobs; `record_preparer!`)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `CapitalCallsController#request_approval` (POST) | none | `request_approval?` via `set_capital_call` | HTML: redirect to call, notice "Approval requested from Ravi Iyer and Priya Nair."; JSON: `{status: "sent", recipients: [ids]}` 200 | `:no_checker` / `:throttled` → redirect with alert (texts in proposal); JSON 422 `{error:}`; Pundit → `deny_access` |
| `CapitalDistributionsController#request_approval` (POST) | none | same | same | same |
| `CapitalCallsController#approve` | unchanged | `approve?` (now with maker clause) | unchanged | `deny_access` → "Access Denied" / 403 |
| `CapitalDistributionsController#approve` | unchanged | same | unchanged | same |
| `EntitiesController#update` | + `entity_setting_attributes[approval_maker_checker]` | `update?` (company admin) | unchanged | unchanged |
| `*#update` (call, distribution, remittance, payment) | unchanged | unchanged | notice + " Its approval was withdrawn because the figures changed — another approver must approve it again." when `approval_withdrawn` | validation errors (incl. X16) |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope` (both new actions sit in `set_*` `only:` lists)
- [ ] Permitted params can't set `approved`, `approved_by_user_id`, or any `approval_makers` field
- [ ] Turbo: `request_approval` deliberately full-redirect (`turbo: false`, like `approve`) — design *Screen standards*
- [ ] Breadcrumbs unchanged (set in `set_capital_call` / `set_capital_distribution`)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `preparer_ids` (rows) | `ApprovalMaker.where(approvable_type:, approvable_id:).pluck(:user_id)` | unique `[approvable_type, approvable_id, user_id]` (prefix) | 1–5 | memo on record |
| `preparer_ids` (creator) | `audits.where(action: "create").order(:created_at).limit(1).pluck(:user_id)` | `auditable_index [auditable_type, auditable_id, version]` | 1 | memo; never loads `audited_changes` |
| `record_preparer!` | `ApprovalMaker.insert_all([...], unique_by: :index_approval_makers_on_approvable_and_user)` | unique | 1–2 rows | `ApprovalMakerCache` |
| `maker_checker_exempt?` | `DealingDate.exists?(subscription_call_id: id)` | `index_dealing_dates_on_subscription_call_id` | 0–1 | memo |
| `checkers` | `User.where(entity_id:, active: true).joins(:roles).where(roles: {name: "approver"}).distinct` + one `AccessRight.where(owner: fund, user_id: ids)` | `index_roles_on_name`; access-rights owner index | ≤ 50 | `includes(:roles)`; no per-user policy query |
| Throttle | `MakerCheckerNotifier.where(created_at: 1.hour.ago..).where("JSON_EXTRACT(params,'$.approvable_id') = ?")` — **LLD decision:** store `approvable_type/id` in params and filter in Ruby over `MakerCheckerNotifier.where(created_at: 1.hour.ago..).where(type:)` (≤ tens of rows/hour firm-wide) to stay MySQL/SQLite neutral | `noticed_events` `created_at`/`type` | < 50 | — |
| Bulk job | `ApprovalMaker.where(approvable: batch).pluck(:approvable_id, :user_id)` | unique prefix | N | one per batch |

**Bypass writers checked** (`update_columns`/`update_all`/bulk insert on the six tables):
- `capital_remittances_counters_job.rb:21` — `update_all(status: "Paid")`: not a figure ✓
- `capital_commitment.rb:291-292` — `update_all(folio_id:)` on remittances/payments: not a figure ✓
- `capital_distribution_create.rb:14`, `capital_distribution_destroy.rb:8` — portfolio investment links: not a figure ✓
- `CapitalCallJob#create_remittances` (`capital_call_job.rb:79-104`) — `CapitalRemittanceCreate` per row: callbacks fire ✓

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by the record's own id
- [ ] No N+1 on list pages (no list page changes); show page ≤ +3 queries
- [ ] Every page / frame / job from design.md's Query budget has its preloads named here
- [ ] The phase's features run clean under Prosopite for this change's code
- [ ] The bypass-writer list above is re-grepped at implementation time

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Figure change + preparer insert | Caller's save transaction | none | — | unique index |
| Withdrawal | Caller's save transaction | `parent.lock!` (one `capital_calls`/`capital_distributions` row) | Two concurrent edits both withdrawing / both alerting | re-check `approved` after lock |
| Approve | unchanged (`CapitalCallApproval` / controller save) | none added | — | `!record.approved` in `approve?` |
| Notices | after commit | none | email inside a rolled-back txn | Noticed event per recipient |

- Lock order: child row (already locked by its own UPDATE) → parent row. Approve locks nothing but the parent's UPDATE;
  no reverse order exists, so no deadlock cycle.

**Reviewer checks**
- [ ] No email or Noticed delivery inside a transaction (`after_commit` only)
- [ ] Lock order child → parent everywhere

---

## Background Jobs

N/A — no new job or cron. Notifications use Noticed's own delivery jobs (as `ComplianceNotifier`). Existing jobs
(`CapitalCallJob`, imports, recompute fees, `CapitalCommitmentRemittanceJob`) run unchanged; they carry the acting user
via `ApplicationJob` (`application_job.rb:31,88`).

**Reviewer checks**
- [ ] A job enqueued before deploy (no `acting_user_id`) records no preparer and withdraws nothing (E10/E45 path)

---

## External Integrations

N/A — no third-party calls (email goes through the existing mailer stack).

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError` | `authorize approve?/request_approval?` | `WithAuthentication#deny_access` | "Access Denied" / 403 JSON | standard |
| `ActiveRecord::RecordInvalid` | `ApprovalWithdraw` `save!` | caller's op/controller (rolls back) | the record's validation messages | `Rails.logger.warn` "[MakerChecker] withdrawal failed call=<id>" |
| (none) figure change on approved record without actor | `ApprovalFigureWatch` | — | nothing | `Rails.logger.warn` "[MakerChecker] unattributed figure change <type>=<id> entity=<id>" |
| Noticed delivery failure | notifier job | Sidekiq retry | — | ExceptionNotification on exhaustion |

**Reviewer checks**
- [ ] No bare `rescue => e` in the new code
- [ ] Log lines carry entity id and record id, never names/emails

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `approve?` + `maker_checker_allows?`; `request_approval?`; both new actions loaded by `find` + `authorize` in `set_*` (existing pattern) |
| Tenant isolation | Setting from `record.entity`; recipients `User.where(entity_id: record.entity_id)`; `approval_makers.entity_id = record.entity_id` |
| Secrets | none |
| Input / output sanitisation | Email/bell messages built from record names, escaped by ERB; tooltip text static |
| Mass assignment | `approved*` not permitted; `approval_maker_checker` only via `ENTITY_SETTING_ATTRIBUTES` (company admins pass `update?`) |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through `approve`, `request_approval`, bulk or the entity form (X2, X9, X13)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | Per-firm `entity_settings.approval_maker_checker`, default off |
| Cron / schedules | None |
| Deploy order | Migrations → code (code tolerates a missing column only after migration; deploy together) |
| Rollback | Revert code; column and table are inert; no data cleanup |
| Enablement | Company admin ticks it; CS outreach list = the 7 self-approving firms with ≥ 2 approvers (query in the change's notes, read-only on the prod copy) |

**Reviewer checks**
- [ ] Safe to deploy with the setting off everywhere; safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| F1 `features/funds/maker_checker/maker_checker_setting.feature` | — | entity, users with roles | `Given the firm has maker–checker {on/off}`; `Then the entity audit shows {user} switched maker–checker {from} to {to}` |
| F2 `…/preparers.feature` | import files under `features/support/import_files/` (reuse call + remittance samples) | call, distribution, remittance, payment | `Then the preparers of {call} are {names}`; `Given a job with no acting user changes …`; `Given support user {name} is acting as {user}` |
| F3 `…/capital_call_approval.feature` | validation rule fixture (reuse) | — | `Then Approve is disabled with {tooltip}` |
| F4 `…/capital_distribution_approval.feature` | — | — | reuse F3 steps |
| F5 `features/security/maker_checker_approval.feature` | bearer token helper (reuse `features/api`) | — | reuse tenant-isolation steps |
| F6 `…/approval_requests.feature` | `travel_to` for the 1-hour throttle | — | `Then {user} receives the maker–checker email {subject}` |
| F7 `…/approval_withdrawal.feature` | — | late commitment | `Then {call} is not approved and the journey note says {text}` |

- Every run: `TEST_ENV_NUMBER=$RANDOM`, Redis on 6379; ActiveJob test adapter leak guard already in an After hook.

---

## Pattern Conformance

| Class | Pattern | Pack | Public interface | Modelled on |
|---|---|---|---|---|
| `ApprovalMaker` | model | funds | associations, `ROLES` | `ComplianceRequest` (decider fields) |
| `WithApprovalMakers` | concern | funds | see contracts | `Workflowable#workflow_default_owner` |
| `ApprovalFigureWatch` | concern (callbacks only) | funds | `FIGURES` constant contract | `CapitalCallAction#invalidate_if_figures_changed` field list |
| `ApprovalMakerCache` | CurrentAttributes | funds | `seen?`/`mark` | `LpPortfolioVisibilityCache` |
| `MakerCheckerPolicyMethods` | policy mixin | funds | three predicates | `WorkflowablePolicyMethods` |
| `ApprovalWithdraw` | service `.call` | funds | `call(record:, actor:)` | `CapitalCallUnapprove` effects |
| `MakerCheckerNotices` | service module | funds | `request`, `withdrawn`, `switched_off`, `checkers` | `ComplianceNotices` |
| `MakerCheckerNotifier` | Noticed notifier | funds | `.with(...).deliver` | `ComplianceNotifier` |
| `MakerCheckerMailer` | mailer | funds | `notice` | `ComplianceMailer#notice` |
| `MakerCheckerHelper` | helper | funds | `maker_checker_action_summary` | `DocChecksHelper#doc_check_action_summary` |

---

## Security Detail

| Action / job / call | Policy method | Loaded through | Permitted params | Tenant checks | Security scenario |
|---|---|---|---|---|---|
| `CapitalCallsController#approve` | `approve?` (+ maker clause) | `CapitalCall.find` + `authorize` | none | `permissioned_employee?` entity + fund | X3, X4, X9, X10, X11 |
| `CapitalDistributionsController#approve` | `approve?` | `CapitalDistribution.find` + `authorize` | none | same | X5, X6 |
| `CapitalCallsController#request_approval` | `request_approval?` | `set_capital_call` | none | same; recipients by `record.entity_id` | X13–X15, E37–E38 |
| `CapitalDistributionsController#request_approval` | `request_approval?` | `set_capital_distribution` | none | same | X13 (distribution variant) |
| `CapitalCallsBulkActionJob` / `CapitalDistributionsBulkActionJob` approve | `approve?` per record | `BulkActionJob` record load (existing) | `bulk_action` | per-record policy | X7, X8 |
| `EntitiesController#update` (switch) | `update?` | existing | `entity_setting_attributes[approval_maker_checker]` | company admin of the entity | X1, X2 |
| `CapitalCallsController#update` etc. (withdrawal) | `update?` (unchanged) | existing | unchanged (`approved*` not permitted) | unchanged | X12, H21 |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `DealingDate.exists?`, `ApprovalMaker…pluck`; no relation `present?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | `checkers` uses `.distinct` (with `unscope(:order)` before any `distinct.pluck` — SQLite hides MySQL errors); no bulk row ops |
| Select only needed columns for `account_entries`; no speculative `includes` | N/A | No `account_entries` reads; creator lookup plucks `user_id` only from `audits` |
| Screen dates via `l(...)`; emails `Mon dd, yyyy`; no human-format `strftime` | Applies | Switch-off email date via `l(date)` in the mailer view; throttle message times via `l(time, format: :time_only)` — confirm format key exists, else add to locale |
| Date inputs via `f.date_field` / `date_field_tag` | N/A | No date inputs |
| Every query entity-scoped; Pundit on every action | Applies | See Security Detail |
| MCP tool surfaces via ontology YAML | N/A | No MCP change; `approved` already in ransackable list, nothing added |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | F1–F7 |
| `bundle exec rubocop` clean incl. `IRM/RelationBlankPresent` | Applies | Task per phase |
| No query inside a row loop; Prosopite clean | Applies | `checkers` filters preloaded roles + one `AccessRight` query; bulk job preloads preparers per batch |
| Screens copy the reference screen; no new CSS | Applies | Existing show pages; popup uses `action_summary_modal.scss` classes |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | Approved / Changes requested | |
