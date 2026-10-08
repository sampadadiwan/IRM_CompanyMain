# Block Capital Calls Without Commitments — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

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

- The guard is a step in `CapitalCallCreate`, not a model validation. Direct `CapitalCall#save` and
  `FactoryBot.create` bypass it on purpose. See [design decision 1](design.md#design-decisions) and
  [Method Contracts](#method-contracts).
- The step must be wired `Output(:failure) => End(:failure)` so it skips `handle_errors`.
  `handle_errors` re-runs `valid?`, which would clear the `:base` error and return success. See
  [Method Contracts](#method-contracts).
- "Applies" is `CapitalCall#applicable_to.exists?`, the same scope `CapitalCallJob#generate` walks. See
  [Queries and Indexes](#queries-and-indexes).
- A nil `fund` passes the guard and fails later on `belongs_to :fund`, so the guard never raises
  `NoMethodError`. See [Error Mapping](#error-mapping-and-logging).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ② Create operation, ③ Commitment check | `app/packs/funds/capital_calls/services/capital_call_create.rb` | Modified | Add `NO_APPLICABLE_COMMITMENTS_MESSAGE` constant and `check_applicable_commitments` step, first in the pipeline |
| ① Create request | `app/packs/funds/capital_calls/controllers/capital_calls_controller.rb` | Unchanged | Already renders `:new` / JSON 422 on failure |
| ① Create request | `app/packs/funds/capital_calls/services/import_capital_call.rb` | Unchanged | Already raises `result["errors"]` |
| ④ Save and remittances | `app/packs/funds/capital_calls/services/capital_call_action.rb` | Unchanged | — |
| ⑤ Error report | `app/packs/funds/capital_calls/views/capital_calls/_form.html.erb` | Unchanged | Error list prints `capital_call.errors` |
| Tests | `features/fund/capital_call_requires_commitments.feature` | New | H1–H3, E1–E2, X1–X5 |
| Tests | `features/step_definitions/capital_call_requires_commitments_steps.rb` | New | Steps not covered by existing files |
| Tests | `public/sample_uploads/capital_calls_no_commitments.xlsx` | New | Two-row import fixture for X5 |
| Docs | `docs/user_guides/capital_calls_user_guide.md` | Modified | One line under creating a call |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/funds/capital_calls/...`); no new cross-pack reference

---

## Schema Detail

N/A — no tables or columns change.

**Reviewer checks**
- [ ] No migration in the diff

---

## Method Contracts

**`CapitalCallCreate`** (Service, `Trailblazer::Operation` via `CapitalCallAction`)

Pipeline after the change, in order:

```ruby
step :check_applicable_commitments, Output(:failure) => End(:failure)
step :save
left :handle_errors, Output(:failure) => End(:failure)
step :generate_capital_remittances
```

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(capital_call:, import_upload: nil)` | unsaved `CapitalCall`; optional `ImportUpload` | `Trailblazer::Operation::Result`; failure carries `result[:errors]` (String) | — | On success: as today | Same as today |
| `#check_applicable_commitments(ctx, capital_call:, **)` | ctx hash, `CapitalCall` | `true` when `capital_call.fund` is nil or `capital_call.applicable_to.exists?`; else `false` | — | On `false`: `capital_call.errors.add(:base, NO_APPLICABLE_COMMITMENTS_MESSAGE)`; `ctx[:errors] = capital_call.errors.full_messages.join(", ")` | Yes, read-only |
| `NO_APPLICABLE_COMMITMENTS_MESSAGE` | — | `"No commitments in this fund apply to this call. Add commitments for the selected fund closes before creating a capital call."` (frozen) | — | — | — |

**`CapitalCall`** (Model): `#applicable_to` is reused unchanged and works on an unsaved record (it reads
only `fund` and `fund_closes`).

**Reviewer checks**
- [ ] The new step is first, so a refused call never reaches `save` and the journey auto-launch never runs
- [ ] The new step's failure goes to `End(:failure)`, not to `handle_errors`
- [ ] `CapitalCallUpdate` and other `CapitalCallAction` subclasses are unchanged
- [ ] `ctx[:errors]` uses the same `full_messages.join(", ")` shape as `handle_errors`, so the importer's `raise result["errors"]` gives the plain message

---

## Controllers, Params and Responses

No action is added. Existing responses for the new failure:

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `CapitalCallsController#create` (HTML) | unchanged `capital_call_params` | `create?` | unchanged 302 | `render :new, status: :unprocessable_entity`, error list shows the message |
| `CapitalCallsController#create` (JSON) | same | same | unchanged 201 | 422, body `{"base":["No commitments in this fund apply…"]}` |

**Reviewer checks**
- [ ] `authorize @capital_call` still runs before the operation
- [ ] The `:new` re-render works without the `new` action's setup (`@bread_crumbs`, custom fields), as for any other validation failure today. Verify X1 renders the form without error

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `check_applicable_commitments` ("All" / nil closes) | `SELECT 1 FROM capital_commitments WHERE fund_id = ? AND deleted_at IS NULL LIMIT 1` | `capital_commitments.fund_id` | 1 | — |
| `check_applicable_commitments` (named closes) | same + `AND fund_close IN (?)` | `capital_commitments.fund_id` | 1 | — |

**Reviewer checks**
- [ ] `exists?`, not `present?`/`any?` on the relation (`IRM/RelationBlankPresent`)
- [ ] Scoped by `fund_id`, so the query is tenant-scoped through the fund

---

## Transactions, Locking and Concurrency

N/A — read-only check before the existing write. A commitment deleted between the check and the save
leaves a call with no remittances, which is today's behaviour. No lock is added; see the
[design FAQ](design.md#key-ideas).

**Reviewer checks**
- [ ] No transaction or lock added

---

## Background Jobs

N/A — no jobs added. A refused call does not queue `CapitalCallJob`.

**Reviewer checks**
- [ ] X3 asserts no `CapitalCallJob` is enqueued on refusal

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| None raised. Failure is the `false` return of the step | `CapitalCallCreate#check_applicable_commitments` | Controller `else` branch | Form error list / JSON 422 | No log: expected user error |
| `RuntimeError(result["errors"])` | `ImportCapitalCall#save_row` (existing `raise`) | `ImportUtil` row processing (existing) | Message in the import result for that row | Existing import logging |
| Nil fund | Guard returns `true` | `belongs_to :fund` validation in `save` → `handle_errors` | "Fund must exist" (existing) | Existing |

**Reviewer checks**
- [ ] No `rescue` added
- [ ] The importer's per-row failure doesn't abort the remaining rows (existing `ImportUtil` behaviour, proven by X5)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged: `CapitalCallPolicy#create?` via `authorize` in the controller |
| Tenant isolation | The check reads commitments by the call's `fund_id`; the fund is authorized (form) or resolved within `import_upload.entity` (import) |
| Secrets | N/A |
| Input / output sanitisation | Static message; rendered through the form's escaped error list |
| Mass assignment | No param change |

**Reviewer checks**
- [ ] The message contains no user-supplied text

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None. The rule applies to every entity on deploy |
| Cron / schedules | None |
| Deploy order | Code only |
| Rollback | Revert the commit. No data to clean up |

**Reviewer checks**
- [ ] Release notes mention that call imports now need commitments imported first (**BREAKING** in the proposal)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/capital_call_requires_commitments.feature` | `allow(UpdateDocumentFolderPathJob).to receive(:perform_later)` (as existing call steps); `public/sample_uploads/capital_calls_no_commitments.xlsx` (columns as `capital_calls_no_remittances.xlsx`; row 1 `Fund Closes` = All, row 2 = Second Close; `Fund` = SAAS Fund) | `:capital_call`, `:capital_commitment`, `:fund` (existing) | `When I submit a new capital call for {string} closes` (UI form); `When I create a capital call through the operation for {string} closes with basis {string}`; `When I post a capital call as JSON for the fund`; `Then no capital call is created`; `Then the capital call create error is shown`; `When I change the capital call closes to {string}` |

Reused: `there is a fund {string} for the entity`, `there is an existing investor …`, `the investors
are added to the fund`, `there are capital commitments of {string} from each investor`,
`I get the error {string}`, `Given I upload {string} file for {string} of the fund with errors`,
`the capital call should fail with error {string}`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `applicable_to.exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | Single existence query |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries` read |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | N/A | No dates shown |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No inputs change |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | Query scoped by authorized fund; controller `authorize` unchanged |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tool changes; no MCP tool creates calls |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | New `.feature`; all runs prefixed |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on the changed service and step file |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
