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
- **Payout custom fields (Phase 6):** the guard reads marked keys from the key `payout_field` in the existing json
  `form_custom_fields.validation_rules` (no new column; K19 only widens `validation_rules_consistent`) and diffs `attribute_in_database(:json_fields)` vs `json_fields`; marks are written through
  three existing screens that all ask `FormCustomFieldPolicy` ([design D17–D20](design.md#d17-payout-custom-fields--a-mark-on-the-field-definition)).
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
| ⑨ | `app/packs/misc/form_custom_fields/models/form_custom_field.rb` | Modified | `PAYOUT_FIELD_KINDS = %w[code account]`; `PAYOUT_FORM_TYPES = %w[IndividualKyc NonIndividualKyc InvestorKyc]`; virtual attribute `payout_field` / `payout_field=` over `validation_rules["payout_field"]`; `validation_rules_consistent` allows `payout_field` for TextField only (code comment: "not a validation rule — the bank-details mark, see bank-detail-change-controls D17"); validation `payout_field_allowed`; `self.payout_keys_for(form_type_ids)` (Ruby filter) |
| ⑨ | `app/packs/misc/form_custom_fields/policies/form_custom_field_policy.rb` | Modified | `mark_payout_field?`, `unmark_payout_field?`; `permitted_attributes` adds `:payout_field` conditionally; `destroy?` lock |
| ⑨ | `app/packs/misc/form_custom_fields/controllers/form_custom_fields_controller.rb` | Modified | Refuse an unmark (stored `validation_rules["payout_field"]` → blank) for non-support before `update` |
| ⑨ | `app/packs/misc/form_types/models/form_type.rb` | Modified | `self.payout_field_change_allowed?(user, fields, form_type)` beside `calculation_change_allowed?` |
| ⑨ | `app/packs/misc/form_types/controllers/form_types_controller.rb` | Modified | Permit `payout_field` in nested attrs; call the check in `update` (base error) |
| ⑨ | `app/packs/misc/form_types/services/form_type_fields_save.rb` | Modified | `payout_field` value read for KYC text fields; marked fields locked (no unmark, no `_destroy`) unless support |
| ⑨ | `app/packs/misc/form_types/helpers/form_type_fields_helper.rb` | Modified | Row hash gains `payout_field`, `payout_markable`, `payout_locked` |
| ⑨ | `app/packs/misc/form_types/views/form_type_fields/_row.html.erb` | Modified | 🏦 flag + kind select in details; locked chip |
| ⑨ | `app/javascript/controllers/form_type_fields_form_controller.js` (existing panel controller) | Modified | Serialise `payout_field` with the row (no new controller) |
| ⑨ | `app/packs/misc/form_types/views/form_types/_form_custom_fields.html.erb` | Modified | "Payout field" select in the flags block |
| ⑨ | `app/packs/misc/form_custom_fields/views/form_custom_fields/_form.html.erb` | Modified | Same select |
| ⑨ | `lib/tasks/bank_detail_changes.rake` | New | `propose_payout_fields` (dry run; `EXECUTE=1 FIRM_ID=`) |
| ② | `bank_detail_change_guard.rb` (Phase 6 additions) | Modified | `marked_payout_keys`, `changed_payout_custom_fields`; include them in the change test and the record |
| ③④⑦ | `bank_detail_change.rb`, mailer views, `_bank_change_note`, `_verify_bank_change_modal` | Modified | `custom_field_lines` rendered after account/IFSC lines |
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
| `changed_custom_fields` | Added (in the Phase 2 `create_table`; written from Phase 6) | json | — | yes | nil | — | `[{key, label, kind, old, new}]`; `old`/`new` full for `code`, last 4 for `account`, nil for blank (design D19) |

**`form_custom_fields.validation_rules["payout_field"]`** (existing json column — **no schema change**; design K19)

| Key | Change | Type | Values | Absent means | Written by | Why it's needed |
|---|---|---|---|---|---|---|
| `payout_field` | New key allowed | JSON string | `"code"` / `"account"` | not a payout field | `FormCustomField#payout_field=` only (sets or deletes the key; never touches other keys) | The firm's mark (design D17) |

- `payout_field=`: `self.validation_rules = (validation_rules || {}).merge("payout_field" => kind)` for a kind, or
  `.except("payout_field")` for blank — a new hash, so the json attribute is marked dirty; other keys kept as stored.
- `payout_field` is **not** in `VALIDATION_RULE_KEYS` → no `vr_payout_field` input and no generic setter writes it.
- `validation_rules_consistent`: split the `"TextField", "TextArea"` branch so `allowed_keys` for TextField =
  `text_keys + ["payout_field"]`; TextArea keeps `text_keys` (key there → existing "contains invalid keys" error);
  value check `PAYOUT_FIELD_KINDS.include?(rules["payout_field"])` when present.
- `payout_field_allowed` (separate, because `validation_rules_consistent` returns early for types with no rule keys —
  Select, Radio, CheckBox's selection keys aside): key present → `field_type == "TextField"` **and**
  `form_type.name` in `PAYOUT_FORM_TYPES`, else "Only text fields on a KYC form can be payout fields".
- Production check (2026-11-09, counts): the 16 candidate fields have 0 existing rules and 0 `meta_data`.

**`bank_detail_changes` migration is the only migration in this change** (Phase 2).

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

| `marked_payout_keys` | — | `{ "swift_code" => {label:, kind:} }` | — | 0 queries unless `json_fields` changed and a form type is set; then 1 `FormCustomField.payout_keys_for([form_type_id_in_database, form_type_id].compact.uniq)`; memoised per save | Yes |
| `changed_payout_custom_fields` | — | Array of `{key, label, kind, old, new}` (already masked) | — | Compares `normalised(attribute_in_database(:json_fields)[k])` vs `normalised(json_fields[k])` per marked key | Yes |

- Phase 6 rule: "a payout value changed" = an account/IFSC change **or** `changed_payout_custom_fields.any?`; "bank
  change" additionally needs the old value non-blank **for that item** (first fill of IBAN alone → flag clear only).
- `attribute_in_database(:json_fields)` re-parses the stored JSON, so an in-place write (`json_fields[k] = v`,
  `kyc_doc_extractor_agent.rb:177-179`) is still diffed against the stored value; `json_fields_was` would return the
  mutated hash in that path — do not use it.
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
| `custom_field_lines` | — | `["SWIFT Code EBILAEADXXX → NBADAEAAXXX", "IBAN ending 3456 → ending 8901"]` | — | — | Yes |

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

**`FormCustomFieldPolicy`** (Policy, Phase 6)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `mark_payout_field?` | — | `support? \|\| new_policy(record.form_type).update?` (company admin of the form type's firm) | — | 0 queries (cached roles) | Yes |
| `unmark_payout_field?` | — | `support?` | — | — | Yes |
| `permitted_attributes` | — | + `:payout_field` only if `mark_payout_field?` | — | — | Yes |
| `destroy?` | — | `show? && (record.payout_field.blank? \|\| support?)` | — | — | Yes |

**`FormType.payout_field_change_allowed?(user, fields, form_type)`** (class method, beside `calculation_change_allowed?`)

| Input | Returns false when | Query |
|---|---|---|
| Submitted nested `fields` (id, `payout_field`, `_destroy`) | user not support **and** a submitted id is stored marked **and** (its `payout_field` is submitted blank **or** `_destroy` is truthy) | 1: `form_type.form_custom_fields.where(id: ids).pluck(:id, :validation_rules)`, marked ids found in Ruby |

**Rake `bank_detail_changes:propose_payout_fields`**

| Env | Meaning | Default |
|---|---|---|
| `FIRM_ID` | Limit to one entity (required with `EXECUTE=1`) | all firms (dry run only) |
| `EXECUTE` | `1` = save the marks via `update!` (validations run) | dry run |
| Output | Per firm › form type › field: name, label, proposed kind, filled-value **count** (`json_extract … IS NOT NULL` count), never values | — |
| Match | Word match on name or label: `swift`, `bic`, `iban`, `routing`, `sort code`, `aba`; `TextField` only; kind `account` for `iban`, else `code`; already-marked fields skipped | — |

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
| `FormTypesController#update` (Phase 6) | nested `payout_field` | `update?` (company admin) + `FormType.payout_field_change_allowed?` | As today | Base error "Payout fields can only be unmarked by CapHive support."; validation "Only text fields on a KYC form can be payout fields" (422, form re-rendered) |
| `FormTypeFieldsController#save` (side panel) | `fields` JSON item key `payout_field` | `inline_fields?` (unchanged) + `FormTypeFieldsSave` lock | Saved marker | 422 panel with "Payout fields can only be unmarked by CapHive support." |
| `FormCustomFieldsController#create/update` | `payout_field` only if `mark_payout_field?` | `create?` / `update?` | As today | Unmark by non-support: base error, 422 |
| `FormCustomFieldsController#destroy` | — | `destroy?` (marked → support only) | As today | `Pundit::NotAuthorizedError` → existing handler |

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
| Guard marked keys (Phase 6) | `FormCustomField.where(form_type_id: ids, field_type: "TextField").pluck(:name, :label, :validation_rules)` → keep rows whose hash has `payout_field` (Ruby) | `form_type_id` | ≤ a few hundred loaded, 0–3 kept | Only when `json_fields` changed; ImportInvestorKyc memoises per form type id for the run |
| Payout unmark check | `form_type.form_custom_fields.where(id: ids).pluck(:id, :validation_rules)` → ids whose hash has `payout_field` (Ruby) | PK + `form_type_id` | ≤ 200 | once per save |
| Rake proposal | `FormCustomField.joins(:form_type).where(form_types: {name: PAYOUT_FORM_TYPES}, field_type: "TextField")`, already-marked rows dropped in Ruby (or SQL `json_extract(validation_rules, '$.payout_field') IS NULL`) + Ruby regex on name/label; filled count per field: `InvestorKyc.where(form_type_id:).where("json_extract(json_fields, ?) IS NOT NULL", "$.#{name}").count` | `form_type_id` on both | ~20 fields, ~165 values | one count per candidate |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by a KYC id already authorized
- [ ] No N+1 on list pages; no unbounded loads
- [ ] Every page / frame / job in design.md's **Query budget** has its preloads and grouped queries named here
- [ ] No SQL compares the *value* of `validation_rules->payout_field`: MySQL `JSON_EXTRACT` returns `"code"` (quoted) and SQLite `json_extract` returns `code`; only `IS NULL` / `IS NOT NULL` is portable — otherwise filter in Ruby
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
| Feature flag | None — applies to all firms ([design D7, D16](design.md#design-decisions)); payout custom fields act only once a field is marked |
| Rollout task | `bin/rails bank_detail_changes:propose_payout_fields` (dry run) → support ticket with the firm's admin → `EXECUTE=1 FIRM_ID=<id>`; run on production.in and production.us separately (independent envs) |
| Cron / schedules | None |
| Deploy order | Phase 1 code (no migration) → Phase 2 migration + code → Phases 3–5 code → Phase 6 code (no migration: the mark is a `validation_rules` key) → rollout task |
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
| `features/core/bank_detail_payout_fields.feature` (Phase 6) | extractor + doc check setup (existing steps); rake via `Rake::Task` invoke | `:form_custom_field` with `validation_rules: {"payout_field" => "code"}` | `Given "SWIFT Code" is marked as a bank code on the Individual KYC form`, side panel steps (reuse grid-columns-inline-settings steps) |
| `features/security/bank_detail_payout_fields.feature` (Phase 6) | — | Northwind, support user | direct PATCH/DELETE steps for form types / custom fields |

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
| `FormCustomField#payout_field` | Config as data (key in existing json + validation) | misc/form_custom_fields | `payout_field`, `payout_keys_for` | `vr_*` per-key accessors on `validation_rules` |
| `FormCustomFieldPolicy#mark_/unmark_payout_field?` | Policy, parent delegation | misc/form_custom_fields | predicates | `create?` → `parent_in_users_firms?`, `calculation_allowed?` |
| `FormType.payout_field_change_allowed?` | Model class guard | misc/form_types | class method | `calculation_change_allowed?` |
| `bank_detail_changes:propose_payout_fields` | Rake (dry run + EXECUTE=1) | lib/tasks | task | ops rake convention |

- Packwerk: `core/investor_kycs` (guard) reads `FormCustomField` through its public class method `payout_keys_for` — the
  pack already depends on `misc/form_custom_fields` via `WithCustomField`.

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
| Side panel save with `payout_field` | `FormTypePolicy#inline_fields?` + `FormCustomFieldPolicy#mark_/unmark_payout_field?` | `policy_scope(FormType)` / record scope (existing) | `fields` JSON; `payout_field` read only for KYC text fields | form type in user's firm | X16–X18, X20 |
| Form Types › Edit nested `payout_field` | `FormTypePolicy#update?` + `FormType.payout_field_change_allowed?` | `set_form_type` (existing) | `form_type_params` + `payout_field` | `belongs_to_entity?` | X17, X19, X20 |
| Form Custom Fields new/edit/destroy | `FormCustomFieldPolicy` (`permitted_attributes`, `destroy?`) | existing scope (`form_types.entity_id`) | `payout_field` conditional | existing | X16, X18 |
| Rake `propose_payout_fields` | n/a (console, support) | all firms read; writes only with `EXECUTE=1 FIRM_ID` | — | `FIRM_ID` required to write | E78, E79 |

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Awaiting checks use memoised record or `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Readiness agent `unscope(:order).distinct.pluck`; download keeps `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries` access |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Note/warnings `l(date)`; emails bare `l(change.created_at)` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs or JS dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | No new actions; see Security Detail |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP change (`form_custom_fields` has no MCP tool) |
| Ops work as rake tasks: dry run + `EXECUTE=1` | Applies | `propose_payout_fields`; no bash script; per-env run |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Test Plumbing |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Gate per phase |
| No query inside a row loop …; the phase's features clean under `PROSOPITE=1` | Applies | Grouped lookups (Queries) |
| Screens copy the reference screen in design.md *Screen standards* …, no new CSS | Applies | `_request_updates_modal`, `_show` Contact & Banking card |

---

## Built differently (apply, 2026-11-10)

See design.md › "Changed during the build" for the full table. The ones that change a contract above:

| Contract above | As built |
|---|---|
| Guard `before_save`: clears flag, status and response on any payout change | New KYCs keep a create-time tick (C1); a custom-field-only change keeps status / response (C2); a verify by the change's own maker without `bank_change_only_approver` stays unverified (C4) |
| `toggle_verified` action-local rescue | Controller-level `rescue_from Pundit::NotAuthorizedError` → `deny_access_or_explain_bank_change`, falling back to `deny_access` (C3) |
| `VerifyBankJob` `record.with_lock` + reload | Fresh row `find` + `with_lock` + compare (C7); a non-JSON answer stored as `{"unreadable_response" => …}` with a status (C6) |
| `changed_fields` | + `custom_fields` token (C11) |
| `InvestorKycMailer` placeholders | + `bank_change_summary`, `bank_change_maker` (C10) |
| `FormCustomField` | + `payout_markable?`, `PAYOUT_UNMARK_REFUSED`; mark error added on `:base` |

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
