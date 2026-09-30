# [Feature Name] — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions (types, limits,
> indexes, locks, retries, error mappings) and ends with **Reviewer checks** to tick. Short
> snippets (a signature, a query shape, a config line) are fine. Full class bodies and full
> migrations are not.

> **Scale to the change.** **CORE** sections are always present. **CONDITIONAL** sections say when
> they apply. Otherwise keep the heading with `N/A — <reason>`.

---

## Contents

<!-- CORE. Links to every ## and ### heading, in order. Update it whenever headings change. -->

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

<!-- CORE. 3-6 bullets: the decisions most likely to be wrong or contested, each linking to its
     section below. This is where the reviewer starts. -->

- <!-- e.g. Keyset batching on X instead of offset — see Queries and Indexes -->

---

## File Map

<!-- CORE. Every new and modified file, grouped by the design's Component Boundaries. Tasks
     reference these rows. -->

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| <!-- UI --> | <!-- `app/packs/<domain>/<sub>/controllers/x_controller.rb` --> | <!-- New --> | <!-- one line --> |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries

---

## Schema Detail

<!-- CONDITIONAL: include when tables or columns change. Column-level detail the ER diagram
     omits. One table per database table. -->

**`table_name`** (<!-- new / existing -->)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| <!-- `status` --> | <!-- string --> | <!-- 20 --> | <!-- no --> | <!-- "draft" --> | <!-- composite idx --> | <!-- enum values --> |

**Migration safety:** <!-- table size in prod, lock/DDL impact, backfill needed?, reversible?, order
of migrations; schema.rb / schema_test.rb both updated -->

**Reviewer checks**
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

<!-- CORE. One table per class from the design's class diagram: the public methods other
     classes call. -->

**`ClassName`** (<!-- Service / Model / Job -->)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| <!-- `.call(record, user:)` --> | <!-- types --> | <!-- Result / record --> | <!-- errors --> | <!-- writes, enqueues, emails --> | <!-- Yes / No, and why --> |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

<!-- CONDITIONAL: include when controller actions are added. Extends the design's route table
     with the implementation detail. -->

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| <!-- `ThingsController#create` --> | <!-- `thing: [:name, :kind]` --> | <!-- `create?` --> | <!-- redirect / turbo_stream --> | <!-- 422 + form errors --> |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields

---

## Queries and Indexes

<!-- CONDITIONAL: include when the feature reads the database. The actual query shape, with the
     index it relies on and the expected row count. -->

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| <!-- `Svc#call` --> | <!-- `Thing.where(entity_id:, status:)` --> | <!-- `[entity_id, status]` --> | <!-- ≤ 30 --> | <!-- `includes(:parent)` / `find_each` --> |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not
- [ ] No N+1 on list pages. No unbounded loads (use `find_each` / `in_batches`)

---

## Transactions, Locking and Concurrency

<!-- CONDITIONAL: include for multi-row writes or anything two processes can do at once. -->

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| <!-- filing --> | <!-- notes + meeting --> | <!-- `meeting.lock!` --> | <!-- double-file --> | <!-- unique index on X --> |

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Lock order is consistent everywhere two rows are locked

---

## Background Jobs

<!-- CONDITIONAL: include when jobs or cron entries are added. -->

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| <!-- `ThingJob` --> | <!-- `:low` --> | <!-- cron every 15 min --> | <!-- 5, polynomial --> | <!-- `RecordNotFound` --> | <!-- claim column --> | <!-- --> |

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] Cron entries are registered where they actually run (sidekiq-cron initializer, non-local envs)

---

## External Integrations

<!-- CONDITIONAL: include when calling a third-party API. -->

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| <!-- list items --> | <!-- `GET /v1/items` --> | <!-- Bearer key --> | <!-- 10s / 30s --> | <!-- 429 Retry-After --> | <!-- 401 → AuthError --> |

**Reviewer checks**
- [ ] Secrets never logged, and the request/response logging level is appropriate
- [ ] Every non-2xx status maps to a named exception

---

## Error Mapping and Logging

<!-- CORE. Technical side of the design's Exception Handling table: exception → handling → what
     the user sees → log/alert. -->

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| <!-- `AuthError` --> | <!-- client --> | <!-- connection failure handler --> | <!-- needs attention --> | <!-- warn log + notifier --> |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (entity, record, external id)

---

## Security Review

<!-- CORE. -->

| Concern | Decision |
|---|---|
| Authorization | <!-- policy per action, scope rule --> |
| Tenant isolation | <!-- how every read/write is entity-scoped --> |
| Secrets | <!-- storage (encrypts?), display masking, log filtering --> |
| Input / output sanitisation | <!-- HTML escaping, markdown rendering, file uploads --> |
| Mass assignment | <!-- permitted params --> |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool

---

## Configuration and Rollout

<!-- CORE. -->

| Item | Value / location |
|---|---|
| Credentials / env vars | <!-- per environment; IN and US are independent --> |
| Feature flag | <!-- if any --> |
| Cron / schedules | <!-- --> |
| Deploy order | <!-- migrations → code → cron --> |
| Rollback | <!-- how to turn it off, and whether data must be cleaned up --> |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

<!-- CORE. What the Cucumber features in design.md's Worked Examples need to run. -->

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| <!-- `features/<domain>/x.feature` --> | <!-- WebMock stub helper --> | <!-- `:thing` --> | <!-- `Given a connected ...` --> |

---

## Project Rules Checklist

<!-- CORE. This repo's standing rules (CLAUDE.md). Mark each Applies / N/A with a one-line
     reason. -->

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | | |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | | |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | | |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | | |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | | |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | | |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | | |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | | |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | | |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | <!-- Approved / Changes requested --> | |
