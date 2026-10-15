# Account Entries Index Query Fix — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Status:** implemented on branch `ae-query-optimisation`. Open: EXPLAIN on a production replica (task 3.2) and QA (3.3).

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

- `includes` to `preload(:fund, :investor, :investor_kyc, capital_commitment: :investor_kyc)` in `account_entry_list.rb`. See [Queries and Indexes](#queries-and-indexes).
- New private `ensure_default_fund` in the same service, run after `ensure_default_filters`.
- The portfolio investment page's link to the list now passes `fund_id`.
- `.distinct` in `AccountEntrySearch.perform` is intentionally untouched. See [design risks](design.md#risks-and-open-questions).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Domain | `app/packs/funds/capital_commitments/services/account_entry_list.rb` | Modified | `preload(...)`; `ensure_default_fund` |
| UI | `app/packs/funds/portfolios/views/portfolio_investments/_details.html.erb` | Modified | Link to the list passes `fund_id` |
| Test | `features/fund/account_entries_index_query.feature` | New | Worked examples H1-H2, E1-E3, X1 |
| Test | `features/step_definitions/account_entries_index_query_steps.rb` | New | SQL capture and assertions, fixtures |
| Test | `features/fund/account_entries_default_fund.feature` | New | Worked examples H3-H4, E4-E8, X2 |
| Test | `features/step_definitions/account_entries_default_fund_steps.rb` | New | Open the list with a fund selection or "All Funds"; assert funds listed, filter value, and the Delete Results / Export All links |
| Test | `features/step_definitions/account_entry.rb` | Modified | `I download all the AEs` clicks "Export All" when Download is a dropdown (a fund is in the params) |

**Reviewer checks**
- [ ] App code changes are limited to `AccountEntryList` and the one link
- [ ] The only existing step changed is `I download all the AEs`
- [ ] Files follow the pack layout

---

## Schema Detail

N/A — no schema change.

---

## Method Contracts

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `AccountEntryList#call` | current_user, params, referer | `Result` (unchanged shape) | none new | read-only | Yes |
| `AccountEntryList#ensure_default_fund` (private) | none (uses `@params`, `@current_user`) | nil | none | sets `@params[:fund_id]` when no fund was named; one `Fund` lookup | Yes |

Rules for `#ensure_default_fund`:
1. `@params` has a `fund_id` key (even blank, which is the "All Funds" option): do nothing.
2. Any of `NARROWING_ATTRIBUTES` (`capital_commitment_id investor_id import_upload_id folio_id parent_id`) is present as a top-level param: do nothing.
3. A `fund_id` or narrowing-attribute condition exists in `AccountEntry.ransack(@params[:q]).conditions` (covers the simple hash and the search-builder tree): do nothing.
4. Otherwise `Pundit.policy_scope!(@current_user, Fund).ordered.order("funds.id").first`; when present, set `@params[:fund_id] = fund.id` and `@fund_defaulted = true`.

`Result` gains `fund_defaulted`; the controller exposes it as `@fund_defaulted` and `index.html.erb` shows the notice when it is true and `@fund` is set.
`AccountEntriesController#destroy` redirects to `account_entries_url(fund_id: @account_entry.fund_id)`.
`build_pivot_table` passes `@account_entries` as is: `AccountEntryPivot` strips `:includes` and only plucks.

**Reviewer checks**
- [ ] It runs before `Fund.find(@params[:fund_id])` and `filter_params`, so `@fund` and the fund filter carry the default
- [ ] `Result` keeps its existing members
- [ ] A fund the user selected, one or several, is never modified

---

## Controllers, Params and Responses

No controller, route or param-name change. `fund_id` is now also written by the service when the request has no `fund_id` key, so the view sees it through the shared `params`:

| Reader | Effect |
|---|---|
| `layouts/_filter_ext` | Top "Fund Name" select shows the fund |
| `account_entries/_index` | `@fund` set, so the Download menu / New Account Entry use it; `delete_all_account_entries_path(fund_id: params[:fund_id])` and the export link carry it |
| `index.xlsx.axlsx` | Reads `params[:fund_id]` for the tracking currency column |

Excel downloads return before the service runs (`trigger_model_download`) and keep the parameters of the request. The request is made from the page, so from a default page it carries the default fund and from "All Funds" a blank `fund_id`.

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `AccountEntryList#call` | `AccountEntry` scoped + ransack, `fund_id = F`, ORDER BY id LIMIT per_page+1 | `index_account_entries_on_fund_id`, `idx_ae_report_fund_cumulative_date` and the other `fund_id` composites (confirm with `EXPLAIN`) | per_page+1 | `preload(:fund, :investor, :investor_kyc, capital_commitment: :investor_kyc)` |

Why `:investor_kyc` appears twice: rows read `account_entry.investor_kyc`, a `has_one :through :capital_commitment`. Preloading `capital_commitment: :investor_kyc` fills `capital_commitment.investor_kyc` only, so the through association ran one query per row (the same before this change). Preloading `:investor_kyc` at the top level bounds it. Covered by the page-size scenario in `account_entries_index_query.feature`.

Behaviour to confirm: the policy scope's `joins(:fund)` / `joins(fund: :access_rights)` must stay plain joins. `preload` never adds joins, so `eager_load` is no longer triggered by a `funds.*` WHERE.

**Reviewer checks**
- [ ] Every query is scoped by entity through the unchanged policy scope
- [ ] No N+1 on the list view; association lookups are one query each
- [ ] Views/helpers that render the list read only preloaded associations

---

## Transactions, Locking and Concurrency

N/A — read-only.

---

## Background Jobs

N/A — none.

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| none new | | | | |


**Reviewer checks**
- [ ] No rescue added
- [ ] A non-numeric `fund_id` does not raise in `ensure_default_fund`; the existing `Fund.find` on `params[:fund_id]` is unchanged

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged `authorize AccountEntry` and `policy_scope`. The default fund comes from `Pundit.policy_scope!(user, Fund)` |
| Tenant isolation | Unchanged scope joins and entity filters. A fund id from another entity returns no rows and is not replaced by the default |
| Secrets | N/A |
| Input / output sanitisation | N/A, no new input is parsed or rendered |
| Mass assignment | N/A |

**Reviewer checks**
- [ ] A user from another entity still cannot see entries (X1)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | none |
| Cron / schedules | none |
| Deploy order | code only |
| Rollback | revert the change; no data or schema involved |

**Reviewer checks**
- [ ] After deploy, check the slow log and `SUM_CREATED_TMP_DISK_TABLES` for the account entries digest
- [ ] Tell support and customer success that the report now opens on the first fund, that "All Funds" still works, and that Delete Results and Export All cover the fund shown

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/account_entries_index_query.feature` | none | existing user, entity, fund, commitment, account entry steps | capture SELECT statements during the page load, assert no mixed-table SELECT, assert lookup count independent of page size |
| `features/fund/account_entries_default_fund.feature` | none | existing user, entity, two funds, employee with access right, account entry steps | open the list with no fund, a chosen fund, a blank fund_id ("All Funds") and a fund_id_in filter; assert the entries listed, the filter value and the Delete Results / Export All links |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | no relation checks added |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies | this change removes the eager-load join |
| Screen dates via `l(...)`; emails via `EmailDateLocalization`; no human-format `strftime` | N/A | |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | unchanged |
| MCP tool surfaces changed only via the ontology YAML | N/A | |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
