# Fix Legacy Bulk Generate Fund Filter — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.**

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

- Replace `joins(:portfolio_investments)...distinct` with `where(id: PortfolioInvestment.where(fund_id: fund_ids).select(:portfolio_company_id))` — see [Queries and Indexes](#queries-and-indexes).
- `@portfolio_companies` keeps `order(:investor_name)`; only the `matching` chain changes.
- SQLite tests cannot reproduce the failure — see [Test Plumbing](#test-plumbing).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Controller | `app/packs/funds/portfolios/controllers/portfolio_reports_controller.rb` | Modified | `legacy_bulk_generate` fund-filter line (currently L150) |
| Test | `features/fund/bulk_portfolio_report.feature` | Modified | Fund-filter preview scenarios (design H1, H2, E1-E3) |
| Test | `features/step_definitions/bulk_portfolio_report.rb` | Modified | Steps to preview by fund and read selected options |

**Reviewer checks**
- [ ] Nothing besides the one controller line changes in app code
- [ ] Files follow the pack layout

---

## Schema Detail

N/A — no schema change.

## Method Contracts

N/A — no new or changed public methods; `legacy_bulk_generate` keeps its signature and view assigns (`@matching_ids`, `@portfolio_companies`, `@funds`, tags, sectors).

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `legacy_bulk_generate` | `previewed`, `fund_ids[]`, `tag_list`, `sector` (read directly, unchanged) | `bulk_generate?` | Renders page | Unchanged |

**Reviewer checks**
- [ ] `authorize` call untouched

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `legacy_bulk_generate` | `Investor.where(entity, category).where(id: PortfolioInvestment.where(fund_id:).select(:portfolio_company_id)).order(:investor_name).pluck(:id)` | Existing `portfolio_investments` indexes on `portfolio_company_id` / `fund_id` (verify in schema) | ≤ hundreds | None |

Chaining `with_tag_list` and `in_sector` after it is safe: both are plain `where` scopes (checked in `investor.rb`).

**Reviewer checks**
- [ ] Confirm an index covers `portfolio_investments.fund_id` or `portfolio_company_id`
- [ ] Query is entity-scoped through `@portfolio_companies`
- [ ] No `DISTINCT` remains; run the generated SQL on MySQL

---

## Transactions, Locking and Concurrency

N/A — read-only.

## Background Jobs

N/A.

## External Integrations

N/A.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::StatementInvalid` (the bug) | `pluck(:id)` | Exception notifier | Error page | Email alert; should no longer occur |

**Reviewer checks**
- [ ] No rescue added around the query

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged (`bulk_generate?`) |
| Tenant isolation | Base relation is `current_user.entity.investors`; unchanged |
| Input | `fund_ids` bound as query values, no interpolation |
| Mass assignment | N/A |

**Reviewer checks**
- [ ] No string interpolation of params into SQL

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None |
| Deploy order | Code only |
| Rollback | Revert the commit |

**Reviewer checks**
- [ ] Safe to deploy and roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/bulk_portfolio_report.feature` | None beyond Background | Existing portfolio company, fund, portfolio investments steps; a second company already available via `there is another portfolio company` | Preview with a fund; assert which companies are selected |

SQLite accepts the old query, so these scenarios guard behaviour only. MySQL verification is manual (qa-checklist X1).

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | N/A | Not used |
| Dedup in SQL, batch bulk operations | Applies | Dedup via `IN` subquery |
| Select only needed columns for `account_entries` | N/A | |
| Screen dates via `l(...)` | N/A | |
| Date inputs / JS dates | N/A | |
| Every query entity-scoped; Pundit | Applies | Unchanged |
| MCP ontology | N/A | |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | Used |
| Rubocop clean | Applies | Run on the controller |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
