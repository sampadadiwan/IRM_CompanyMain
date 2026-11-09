# Bank Detail Change Controls — Low-Level Design

<!-- STYLE: bullets and diagrams, not prose. One idea per bullet; a diagram per concept (model, lifecycle, flow); table cells a phrase each — longer reasoning goes in bullets under the table. -->

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Business rules](business-rules.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links to its diagrams and worked
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

- **Guard placement:** `before_save` / `after_save` / `after_commit` on `InvestorKyc` — the only layer every write path
  shares ([design D2](design.md#d2-the-rule-sits-in-a-model-concern-on-save)). Check callback order against
  `sync_boolean_fields_from_status` (after_save, `investor_kyc.rb:363`) — see [Method Contracts](#method-contracts).
- **Confirmation inside the guard:** a permitted `verified` false → true save confirms the awaiting row. The *policy*
  decides permission; the guard trusts the save — review that every verify route authorizes first
  ([Security Detail](#security-detail)).
- **`toggle_verified?` becomes direction-aware** and three callers move to `kyc_approver?`
  ([design D15](design.md#d15-new-kyc_approver-toggle_verified-direction-aware)).
- **Record-level `permitted_attributes`** — the controller switches to `policy(@investor_kyc || InvestorKyc)`; for
  `create` (class record) the approver test is user-level ([Controllers](#controllers-params-and-responses)).
- **Stale penny-drop result:** `with_lock` + reload + compare after the HTTP call
  ([Transactions](#transactions-locking-and-concurrency)).
- **Popup idempotency:** popup posts `intent=verify`; a second submit on an already verified KYC is a no-op instead of
  an UnVerify (X12).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/investor_kycs/controllers/investor_kycs_controller.rb` | Modified | Set `bank_change_actor/source` (update, create, create_and_send, compare_kyc_datas, assign_kyc_data, toggle_verified); record policy for params; maker refusal flash; `intent=verify` no-op |
| ① | `app/packs/core/investor_kycs/services/import_investor_kyc.rb` | Modified | Source "import"; bank-change rows never verify; `warn_row` |
| ① | `app/packs/core/investor_kycs/services/doc_checks/kyc.rb` | Modified | `kyc.bank_change_source = "document_checks"` in `save_details!` |
| ① | `app/packs/ai/support_agents/services/kyc_doc_extractor_agent.rb` | Modified | `investor_kyc.bank_change_source = "ai_extraction"` before `save` |
| ② | `app/packs/core/investor_kycs/models/concerns/bank_detail_change_guard.rb` | New | Detect, clear, unverify, record, confirm, enqueue |
| ② | `app/packs/core/investor_kycs/models/investor_kyc.rb` | Modified | `include BankDetailChangeGuard`; `has_many :bank_detail_changes`; `awaiting_bank_change`, `latest_bank_change` (memoised) |
| ② | `app/packs/core/investor_kycs/services/investor_kyc_action.rb` | Modified | `journey_hook` note "Bank details changed" |
| ③ | `app/packs/core/investor_kycs/models/bank_detail_change.rb` | New | Model, scopes, `confirm!`, `replace!`, display helpers |
| ③ | `db/migrate/2026111XXXXXXX_create_bank_detail_changes.rb` | New | Table + indexes |
| ③ | `db/schema.rb`, `db/schema_test.rb` | Modified | Both updated (memory: local migrate drifts) |
| ④ | `app/packs/core/investor_kycs/jobs/bank_detail_change_notify_job.rb` | New | Claims + recipients + deliveries |
| ④ | `app/packs/core/investor_kycs/mailers/investor_kyc_mailer.rb` | Modified | `notify_bank_details_changed`, `notify_bank_change_review`; `set_kyc` loads `@bank_detail_change` |
| ④ | `app/packs/core/investor_kycs/views/investor_kyc_mailer/notify_bank_details_changed.html.erb` | New | Investor email |
| ④ | `app/packs/core/investor_kycs/views/investor_kyc_mailer/notify_bank_change_review.html.erb` | New | Approver email |
| ⑤ | `app/packs/core/investor_kycs/services/bank_name_match.rb` | New | Name rule |
| ⑤ | `app/packs/core/investor_kycs/jobs/verify_bank_job.rb` | Modified | Use `BankNameMatch` for KYCs; stale guard |
| ⑥ | `app/packs/core/investor_kycs/policies/investor_kyc_policy.rb` | Modified | `kyc_approver?`, `toggle_verified?`, `confirm_bank_details?`, `bank_change_maker_blocked?`, `other_kyc_approver?`, `bank_change_only_approver?`, `permitted_attributes` |
| ⑥ | `app/packs/core/investor_kycs/jobs/investor_kycs_bulk_action_job.rb` | Modified | Maker message for "verify" |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/show.html.erb` | Modified | Verify button: popup / greyed / unchanged; Audit Trail item uses `kyc_approver?` |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/_verify_bank_change_modal.html.erb` | New | Immediate Actions popup |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/_bank_change_note.html.erb` | New | Amber / grey note |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/_show.html.erb` | Modified | Render note in Contact & Banking |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/_bank_verification.html.erb` | Modified | "Not verified — bank details changed" |
| ⑦ | `app/packs/core/investor_kycs/views/investor_kycs/_form.html.erb` | Modified | Bank Verified box behind `confirm_bank_details?` + tooltip |
| ⑦ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc_warnings.rb` | Modified | `bank_change_warning` |
| ⑧ | `app/packs/ai/support_agents/services/distribution_readiness_agent.rb` | Modified | `verify_bank_details` fails for awaiting changes |
| ⑧ | `app/packs/funds/capital_distributions/workflow_checks/capital_distribution_warnings.rb` | Modified | `bank_change_warning` |
| ⑧ | `app/packs/funds/capital_distribution_payments/views/capital_distribution_payments/index.xlsx.axlsx` | Modified | Last column "Unconfirmed Bank Change" |
| Docs | `docs/user_guides/…investor_kyc…` (existing KYC guide) | Modified | FAQ: bank changes, second approver, emails (user-guide-faqs skill) |
| Tests | `features/core/bank_detail_change_*.feature`, `features/core/bank_detail_name_match.feature`, `features/funds/bank_detail_change_payout_flags.feature`, `features/security/bank_detail_change_*.feature`, `features/step_definitions/bank_detail_change_steps.rb` | New | See [Test Plumbing](#test-plumbing) |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries (funds/ai read `BankDetailChange` only via its public scope)

---

## Schema Detail

**`bank_detail_changes`** (new): one row per bank change; holds what the KYC row can't (history, maker, stamps).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `id` | Added | bigint | — | no | auto | PK | — |
| `entity_id` | Added | bigint | — | no | — | FK entities; `[entity_id, status]` | Tenant scope; firm-wide payout lookups |
| `investor_kyc_id` | Added | bigint | — | no | — | FK investor_kycs; `[investor_kyc_id, status]` | Per-KYC awaiting lookup |
| `changed_by_id` | Added | bigint | — | yes | nil | FK users, index | Maker; nil = System |
| `changed_by_side` | Added | string | 10 | no | — | — | "investor" / "fund" / "system"; investor-made rows confirmable by any approver |
| `source` | Added | string | 20 | no | "other" | — | Allowlist: screen, api, import, document_checks, ai_extraction, other |
| `changed_fields` | Added | string | 100 | no | — | — | Comma list of `PAYOUT_FIELDS` changed; email wording |
| `old_account_last4` | Added | string | 4 | yes | nil | — | Masked; nil = was blank |
| `new_account_last4` | Added | string | 4 | yes | nil | — | Masked; nil = now blank |
| `old_ifsc` | Added | string | 20 | yes | nil | — | Same limit as `investor_kycs.ifsc_code` |
| `new_ifsc` | Added | string | 20 | yes | nil | — | Same |
| `status` | Added | string | 12 | no | "awaiting" | in both composite idx | awaiting / confirmed / replaced |
| `confirmed_by_id` | Added | bigint | — | yes | nil | FK users, index | Second person |
| `confirmed_at` | Added | datetime | — | yes | nil | — | When |
| `only_approver` | Added | boolean | — | no | false | — | Self-confirmed marker |
| `investor_notified_at` | Added | datetime | — | yes | nil | — | Claim for investor email (at most once) |
| `investor_recipient_ids` | Added | text | — | yes | nil | — | `serialize … type: Array`; who was told |
| `approvers_notified_at` | Added | datetime | — | yes | nil | — | Claim for approver email |
| `deleted_at` | Added | datetime | — | yes | nil | index | `Trackable` → `acts_as_paranoid` |
| `created_at` / `updated_at` | Added | datetime | — | no | — | — | Change time = `created_at` (recipient cut-off) |

**Migration safety:** new table, no backfill, no lock on existing tables; reversible (`create_table`). Update
`db/schema.rb` and `db/schema_test.rb` by hand after migrating (local dev DB drift); never run migrations from a
side branch against the shared dev DB.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index (one-awaiting-per-KYC is enforced by the KYC row lock of the same UPDATE, not an index — MySQL has no partial unique index)
- [ ] Column limits match validation limits (`validates :source, inclusion:`, `:status, inclusion:`)
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

**`BankDetailChangeGuard`** (Concern on `InvestorKyc`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `PAYOUT_FIELDS` | — | `%w[bank_account_number ifsc_code]` | — | — | — |
| `before_save :guard_bank_details` | — | true | never | Sets `bank_verified=false`, `bank_verification_status=nil`, `bank_verification_response=nil` when a payout field's normalised value changes; sets `@bank_change` when persisted and an old value non-blank; if `submission_status_was == "verified"` **or** `submission_status == "verified"` (a verify sent in the same save) sets `submission_status="completed"`, `verified=false`, `verified_by_id=nil`; sets `@confirming_verify` when `verified` goes false → true and no `@bank_change` | Yes (pure on dirty state) |
| `after_save :record_bank_change` | — | true | `ActiveRecord::RecordInvalid` (rolls back the save) | On `@bank_change`: `awaiting.update_all(status: "replaced")`, `BankDetailChange.create!`; on `@confirming_verify`: `awaiting_bank_change&.confirm!(by: bank_change_maker, only_approver: bank_change_only_approver_flag)` | Yes within one save |
| `after_commit :notify_bank_change, on: :update` | — | — | rescues + `notify_exception` | `BankDetailChangeNotifyJob.perform_later(id)` | Job is idempotent |
| `bank_change_maker` | — | `User` or nil | — | Reads `bank_change_actor` → `Current.user` | Yes |
| `normalised(value)` | String/nil | String | — | `value.to_s.gsub(/\s+/, "").upcase` | Yes |

- Callback order: the guard's `after_save` is declared **after** `sync_boolean_fields_from_status` is irrelevant —
  the guard sets `verified` itself in `before_save`, so `sync_boolean_fields_from_status` finds nothing to change.
- `only_approver` flag: `InvestorKycsController#toggle_verified` (and import/bulk) set
  `investor_kyc.bank_change_only_approver = policy.bank_change_only_approver?` before saving.

**`BankDetailChange`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `scope :awaiting` | — | Relation | — | — | — |
| `confirm!(by:, only_approver: false)` | User/nil, Boolean | self | `RecordInvalid` | status, confirmed_by, confirmed_at | Only from `awaiting` (no-op otherwise) |
| `replace!` | — | self | — | status | Only from `awaiting` |
| `old_account_display` / `new_account_display` | — | "ending 4821" / "none" | — | — | Yes |
| `maker_name` | — | "Meera Shah" / "System" | — | — | Yes |

**`BankNameMatch`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(kyc_name:, bank_name:, provider_match:)` | String, String, Boolean | `:match` / `:review` | never | none | Yes |

**`BankDetailChangeNotifyJob`** (Job, queue `:default`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `perform(change_id)` | Integer | — | re-raises unexpected errors (Sidekiq retry) | Claims stamps; `InvestorKycNotifier.deliver_later` per user; writes `investor_recipient_ids` | Yes — claims are conditional UPDATEs |

**`InvestorKycPolicy`** (Policy)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `kyc_approver?` | — | Boolean | — | 0–1 query (existing `permissioned_employee?`) | Yes |
| `toggle_verified?` | — | `kyc_approver? && (record.verified \|\| !bank_change_maker_blocked?)` | — | — | Yes |
| `confirm_bank_details?` | — | `kyc_approver? && !bank_change_maker_blocked?` | — | — | Yes |
| `bank_change_maker_blocked?` | — | maker of awaiting change == user && `other_kyc_approver?` | — | 1 query (memoised awaiting change) | Yes |
| `bank_change_only_approver?` | — | maker == user && !`other_kyc_approver?` | — | — | Yes |
| `other_kyc_approver?` | — | Boolean | — | ≤ 1 + n queries, memoised per policy instance | Yes |
| `permitted_attributes` | — | Array | — | Removes 4 result fields; adds `verified` if `toggle_verified?`, `bank_verified` if `confirm_bank_details?` (class record → user-level approve flag) | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `InvestorKycsController#update` | `policy(@investor_kyc).permitted_attributes` (no `*_verification_*`; `verified`/`bank_verified` per record) | `update?` (unchanged) | As today | As today |
| `#create`, `#create_and_send_kyc_to_investor` | `policy(InvestorKyc)` (class: user-level approve) | `create?` | As today | As today |
| `#compare_kyc_datas` | Same filter | `compare_kyc_datas?` (unchanged) | As today | As today |
| `#toggle_verified` | `intent` (`verify` from popup) | `toggle_verified?` | Redirect, "Investor kyc was successfully verified." | `Pundit::NotAuthorizedError` → for a blocked maker, flash "You changed this KYC's bank details, so another KYC approver must verify it." + redirect to KYC (HTML) / 403 JSON `{error: …}` |
| Bulk "verify" | — | `toggle_verified?` per KYC | Count | Error row "Not verified — you changed the bank details; another approver must verify" |

- Blocked-maker message: rescue `Pundit::NotAuthorizedError` in `toggle_verified` only when
  `policy(@investor_kyc).bank_change_maker_blocked?` (no global rescue change).
- `intent=verify` and the KYC is already verified → redirect with "Investor kyc was successfully verified." and no save (X12).

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields; `bank_change_actor` / `bank_change_source` / `bank_change_only_approver` are attr_accessors never permitted
- [ ] Actions that change one row or card answer `format.turbo_stream` … — N/A: Verify is a full-page redirect today and stays one (design *Screen standards*)
- [ ] Every page action sets breadcrumbs — unchanged (`set_investor_kyc`)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `InvestorKyc#latest_bank_change` | `bank_detail_changes.includes(:changed_by, :confirmed_by).order(id: :desc).first` | `[investor_kyc_id, status]` (prefix) | 1 | memoised |
| `InvestorKyc#awaiting_bank_change` | from `latest_bank_change` if awaiting | — | 1 | memo |
| Guard replace | `BankDetailChange.awaiting.where(investor_kyc_id: id).update_all(status: "replaced", updated_at: now)` | `[investor_kyc_id, status]` | 0–1 | — |
| `other_kyc_approver?` | `entity.employees.active.where.not(id: maker_id)` filtered to company_admin role OR `extended_permissions` approve bit (flag_shih_tzu SQL condition) AND `permissions` enable_kycs bit; then `InvestorKycPolicy.new(u, record).show?` until first true | users entity idx | ≤ 10 | stop at first |
| Notify job, investor | `investor.notification_users(kyc, with_tag: "KYC")` then `investor.approved_investor_accesses.where(user_id: ids).where(created_at: ...change.created_at).pluck(:user_id)` | existing | ≤ 30 | existing includes |
| Notify job, approvers | `entity.employees.not_investor_advisor_roles.active` + advisors with grants (as `notify_kyc`, `investor_kyc.rb:332-345`) filtered by `show?` and `kyc_approver?` | existing | ≤ 50 | as `notify_kyc` |
| Payments download | `BankDetailChange.awaiting.where(investor_kyc_id: CapitalCommitment.where(id: payments.select(:capital_commitment_id)).select(:investor_kyc_id)).group(:investor_kyc_id).maximum(:created_at)` | `[investor_kyc_id, status]` | ≤ 5k | one hash |
| Readiness agent | same, `.distinct.pluck(:investor_kyc_id)` (unscope order first) | same | ≤ 5k | Set |
| Distribution warning | same, `.distinct.count(:investor_kyc_id)` | same | — | — |
| KYC journey warning | `kyc.awaiting_bank_change` | memo | 1 | — |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by a KYC id already authorized
- [ ] No N+1 on list pages; no unbounded loads
- [ ] Every page / frame / job in design.md's **Query budget** has its preloads and grouped queries named here
- [ ] `distinct.pluck` calls `unscope(:order)` first and are run once on dev MySQL (SQLite hides DISTINCT/ORDER errors)
- [ ] The phase's features run clean under Prosopite (`PROSOPITE=1 … cucumber`)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| KYC save with bank change | KYC UPDATE + replace + INSERT | Implicit row lock from the KYC UPDATE | Two concurrent changes both "awaiting" — second UPDATE waits, then replaces the first | — |
| Verify confirming a change | KYC UPDATE + `confirm!` | Same | Double submit (X12) | `status = awaiting` guard + `intent=verify` no-op |
| `VerifyBankJob` save | `record.with_lock` (after HTTP) | `SELECT … FOR UPDATE` on the KYC | Stale result on a newer account (E53) | compare normalised account/IFSC |
| Notify claims | Single conditional UPDATE each | — | Retry double-send (E28) | `investor_notified_at IS NULL`, `approvers_notified_at IS NULL` |

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction (provider call before `with_lock`; `deliver_later` after claims)
- [ ] Lock order is consistent everywhere two rows are locked (only the KYC row is locked)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `BankDetailChangeNotifyJob` | `:default` | `after_commit` of a bank change | Sidekiq default (25, exponential) | `ActiveRecord::RecordNotFound` (change or KYC deleted) | Claim columns | — |
| `VerifyBankJob` (modified) | `:default` | `validate_bank` step (unchanged), bulk "bankverification" | As today | record nil (as today) | Row lock + compare | Provider HTTP default |

- `ApplicationJob` carries `acting_user_id`; `BankDetailChangeNotifyJob` does not need it (the maker is on the row).

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] No cron entries added

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Digio bank verify (unchanged) | `POST {DIGIO_BASE_URL}/client/verify/bank_account` (`kyc_verify.rb:16-18`) | Basic (credentials) | HTTParty default | 0–120 s random delay (unchanged) | Non-JSON → raw body kept (`verify_bank_job.rb:61-67`) |

- Note for the security track (not this change): `KycVerify` has `debug_output $stdout` (`kyc_verify.rb:4`), which
  prints the account number in request bodies to stdout logs.

**Reviewer checks**
- [ ] Secrets never logged; no new provider call added
- [ ] Every non-2xx status maps to the existing `verified: false` path

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordInvalid` on `create!` | Guard `after_save` | Rolls back the KYC save; operation's `handle_errors` | Form error (generic save failure) | `Rails.logger.error` + ExceptionNotifier |
| Enqueue failure | Guard `after_commit` | `rescue StandardError` → `notify_exception` | Note shows "Investor emailed: —" | ExceptionNotifier with KYC id, change id |
| `Pundit::NotAuthorizedError` (blocked maker) | `toggle_verified` | Action-local rescue | Maker refusal flash | info log (KYC id, user id) |
| Stale penny-drop result | `VerifyBankJob` | Drop | Nothing | info log: KYC id, checked last 4 vs current last 4 |
| Notify job error | Job | Sidekiq retry | — | ExceptionNotifier via existing job error reporting |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently (the enqueue rescue reports)
- [ ] Log lines carry entity id, KYC id, change id — and only last 4 digits, never full account numbers

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | All verify routes through `toggle_verified?`; Bank Verified tick through `confirm_bank_details?`; import/bulk call the same policy |
| Tenant isolation | `bank_detail_changes.entity_id` = KYC's (`attr_readonly`); job reloads change → KYC → entity; recipients from the KYC's investor and entity only |
| Secrets | Full account numbers never stored outside `investor_kycs`; emails and logs last 4 only; `filter_parameter_logging` already covers `bank_account_number` |
| Input / output sanitisation | Names and bank names rendered with ERB escaping; status text built from provider string, escaped |
| Mass assignment | Four result fields removed; `verified`/`bank_verified` per record policy; accessors not params |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool (no MCP surface added)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new (Digio unchanged; IN and US independent as today) |
| Feature flag | None — applies to all firms ([design D7, D16](design.md#design-decisions)) |
| Cron / schedules | None |
| Deploy order | Phase 1 code (no migration) → Phase 2 migration + code → Phases 3–5 code |
| Rollback | Revert code; `bank_detail_changes` can stay (additive). Flags cleared by the guard are not restored (audit trail holds old values) |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/bank_detail_change_reset.feature` (Phase 1) | `KycVerify#verify_bank` stub with name/fuzzy args | `:investor_kyc`, `:entity` with `bank_verification` | `Given a verified KYC "Anil Kumar" with account "…4821"`, `Then Bank Verified is off` |
| `features/security/bank_detail_change_fields.feature` (Phase 1) | — | `:user` with flags | `When "Priya" PATCHes the KYC with …` (API token) |
| `features/core/bank_detail_change_record.feature` (Phase 2) | — | — | `Then a bank change "4821 → 7310" by "Meera Shah" is awaiting` |
| `features/core/bank_detail_change_emails.feature` (Phase 2) | ActiveJob inline; mail deliveries | `:investor_access` with tags/created_at | `Then "anil.kumar@example.in" receives "Your bank details …"` (reuse email steps) |
| `features/core/bank_detail_change_second_person.feature` (Phase 3) | — | `:import_upload` | popup card steps; import row warning steps |
| `features/security/bank_detail_change_second_person.feature` (Phase 3) | — | Northwind entity | direct PUT/PATCH steps (reuse `tenant_isolation_batch1.feature` style) |
| `features/core/bank_detail_name_match.feature` (Phase 4) | stub responses per row | Kestrel entity (checks on) | `Given the bank check returns "R KUMAR" without a provider match` |
| `features/funds/bank_detail_change_payout_flags.feature` (Phase 5) | readiness agent setup (existing steps) | distribution with payments | xlsx column steps (reuse payments download steps) |

- Every run: `TEST_ENV_NUMBER=$RANDOM`; Redis up on 6379.

---

## Pattern Conformance

| Class | Pattern | Pack | Public interface | Modelled on |
|---|---|---|---|---|
| `BankDetailChangeGuard` | Model concern | core/investor_kycs | callbacks only | `InvestorKycConcern` |
| `BankDetailChange` | Model (Trackable) | core/investor_kycs | `awaiting`, `confirm!`, `replace!`, display helpers | `AmlReport` (child of KYC) |
| `BankNameMatch` | Service (`.call`) | core/investor_kycs | `.call(kyc_name:, bank_name:, provider_match:)` | `KycVerify` (service in same pack) |
| `BankDetailChangeNotifyJob` | Job | core/investor_kycs | `perform(change_id)` | `NotifyKycJob` |
| `InvestorKycPolicy` additions | Policy | core/investor_kycs | predicates | existing `toggle_verified?` |
| Mailer methods | Mailer + Noticed notifier | core/investor_kycs | `notify_bank_details_changed`, `notify_bank_change_review` | `notify_updates_requested` |

- No class mixes roles: the controller sets accessors and renders; the guard holds the rule; the job holds recipients.

## Security Detail

| Action / job / call | Policy method | Loaded through | Permitted params | Tenant checks | Security scenario |
|---|---|---|---|---|---|
| `PUT toggle_verified` (verify) | `toggle_verified?` | `set_investor_kyc` → `InvestorKyc.find` + `authorize` (existing) | `intent` | `belongs_to_entity?` in `permissioned_employee?` | X7, X10, X11, X12 |
| `PATCH update` with `verified`/`bank_verified` | `update?` + `permitted_attributes` | same | record policy list | same | X8, X9, E11, E12 |
| `PATCH update` with `*_verification_*` | `permitted_attributes` | same | removed | — | X2, X3, X4 |
| Bulk verify | `toggle_verified?` per KYC | bulk job scope (existing H6) | — | existing | E37 |
| Import Update Only | `ImportUploadPolicy#create?` (existing) + `bank_change_maker_blocked?` per row | `import_upload.entity` KYCs (`import_investor_kyc.rb:26-30`) | — | entity-scoped lookup | E40, E41 |
| `BankDetailChangeNotifyJob` | n/a (job) | `BankDetailChange.find` → `investor_kyc` (same entity) | — | recipients filtered by `show?` | E28, E30 |
| `VerifyBankJob` | n/a | `find_by(id:)` (existing) | — | — | E53 |

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Awaiting checks use memoised record or `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Readiness agent `unscope(:order).distinct.pluck`; download keeps `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries` access |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Note/warnings `l(date)`; emails bare `l(change.created_at)` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs or JS dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | No new actions; see Security Detail |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Test Plumbing |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Gate per phase |
| No query inside a row loop …; the phase's features clean under `PROSOPITE=1` | Applies | Grouped lookups (Queries) |
| Screens copy the reference screen in design.md *Screen standards* …, no new CSS | Applies | `_request_updates_modal`, `_show` Contact & Banking card |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
