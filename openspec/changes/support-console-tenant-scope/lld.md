# Support Console tenant scope — Low-Level Design

> **Audience:** the developer reviewing the implementation before coding.
> **Additive to** [design.md](design.md) — links there, does not restate it.

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

## Review Summary

| Decision | Value |
|---|---|
| Link source | `db/schema.rb` of the published revision (design [card ②](design.md#②-link-list)) |
| Link file | `join_map.json` beside `tables_with_entity_id.json` in the code dir |
| Check entry point | `prepareStatement(sql, entityId, tablesWithEntityId, database, joinMap)` — fifth argument added |
| Rewrite | `addScopeColumns(ast, scopedAliases)` runs on the checked AST before `sqlify` |
| Row check | `heldBack(rows, entityId)` replaces `flagRows` |
| Rails change | none to models; `SupportConsoleCodeArchive.join_map` added |
| Failure mode | fail closed: missing map, unknown shape, reserved identifier → refuse |

**Reviewer checks**
- [ ] No path accepts a table without `entity_id` except a map link to a tied table.
- [ ] Every refusal reason is one of: `SELECT only`, `other client`, `add filter`, `table not allowed`, `unreadable`, `join on a real relationship: …`.

## File Map

| File | Change |
|---|---|
| `lib/support_console_code_archive.rb` | `join_map(schema_path)`; `build` writes `join_map.json` |
| `support_console/machine/lib/tables.js` | `loadJoinMap(codeDir)`; `DENIED_TABLES` += `agent_chat_sessions`, `agent_chat_messages` |
| `support_console/machine/lib/sql_rules.js` | link rule in `anchors`; `linksFor`; `addScopeColumns`; `__scope_` reserved; `prepareStatement` 5th arg |
| `support_console/machine/lib/db.js` | load map; call `addScopeColumns`; `heldBack`; event `blocked` + `flagged` |
| `support_console/machine/hooks/scope_guard.js` | pass the map to `prepareStatement` |
| `support_console/machine/scripts/check.js` | ✓/✗ line for `join_map.json` |
| `support_console/machine/claude/` brief | one line on joining by foreign key |
| `support_console/machine/test/sql_rules.test.js`, `db.test.js`, `archive` fixture | `tenant-scope <ID> — …` tests |
| `features/support_console/tenant_scope.feature` + steps | one scenario per H/E/X |

**Reviewer checks**
- [ ] No Rails model, migration or view changes.

## Schema Detail

N/A — no tables or columns change.

## Method Contracts

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `SupportConsoleCodeArchive.join_map` | `(schema_path) → Hash` | `{ "links" => { "doc_shares" => [{ "column" => "document_id", "to" => "documents" }], "action_text_rich_texts" => [{ "column" => "record_id", "polymorphic" => "record_type" }] }, "classes" => { "investors" => "Investor", … } }` | every table's links (the checker reads both directions); `classes` from Rails `classify`, which a polymorphic type must name |
| `tables.loadJoinMap` | `(codeDir) → Map` | empty Map when the file is missing | fail closed |
| `sql_rules.linksFor` | `(table, joinMap) → Array` | links usable to tie `table` | used for the refusal text |
| `sql_rules.addScopeColumns` | `(ast, scoped) → string[]` | the hidden names added; the AST gains `__scope_<alias>` (or `_min`/`_max` when grouped; positional `__scope_1…` across UNION arms, padded with the arm's own first scope value) | throws `Refusal("unreadable")` for INTERSECT / EXCEPT |
| `sql_rules.heldBack` | `(rows, entityId) → boolean` | true if any non-null `__scope_*` ≠ entityId | string compare |
| `sql_rules.withoutScope` | `(rows, columns) → {rows, columns}` | the result without `__scope_*` | used by `db.runLookup` |

Polymorphic class check: `classes[table]` from the link list (Rails `classify`, so `investors` →
`Investor`); compared to the literal in `<alias>.<name>_type = '…'` (case-sensitive).

**Reviewer checks**
- [ ] `join_map` reads `add_foreign_key "<from>", "<to>"` and `column:`; naming fallback only for `<name>_id` whose plural is a table.
- [ ] A polymorphic pair is recorded only when both `<name>_type` and `<name>_id` exist.

## Controllers, Params and Responses

N/A — no controller changes.

## Queries and Indexes

N/A — the hidden columns add no joins; no new indexes.

## Transactions, Locking and Concurrency

N/A — read-only lookups; the map is read once per MCP process start and per hook call.

## Background Jobs

N/A — unchanged `SupportConsoleTurnJob` records the event.

## External Integrations

| Integration | Change |
|---|---|
| Relay query event | unchanged shape; `outcome: "blocked"`, `flagged: true`, `reason: "rows from another client"` for held-back lookups |

## Error Mapping and Logging

| Condition | Reason to Claude | Query event |
|---|---|---|
| table without `entity_id`, no links | `table not allowed` | `blocked` |
| linked table, link not used | `join on a real relationship: <table> can be joined by <a> = <b>[, …]` | `blocked` |
| reserved `__scope_` identifier / unknown shape | `unreadable` | `blocked` |
| another client's row | `blocked: rows from another client` | `blocked`, `flagged: true` |

**Reviewer checks**
- [ ] The refusal lists at most 3 links, in schema order.

## Security Review

- Fail closed on missing `join_map.json`, unknown rewrite shapes and reserved identifiers.
- `*_entity_id` columns are never hidden-column sources (design [card ⑦](design.md#⑦-row-check)).
- The map can only narrow: a link still needs its other end tied to the client.

**Reviewer checks**
- [ ] An `entities` row reached through `*_entity_id` adds no `__scope_*` column.
- [ ] A scoped table reached through `investor_entity_id` is refused ("add filter").

## Configuration and Rollout

| Item | Value |
|---|---|
| Config | none |
| Rollout | deploy → `publish_code` writes `join_map.json` → machine syncs within 5 minutes; `machine_check` shows ✓ link list |
| Rollback | redeploy the previous revision |

## Test Plumbing

Node tests named `tenant-scope <ID> — …`; Cucumber runs them with "the support machine tests
matching "tenant-scope <ID> —" run" / "they pass". Fixture schema for `join_map`:
`support_console/machine/test/fixtures/schema_links.rb` (or a Rails-side tmp file in the step).

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | no relation code |
| Dedup in SQL, batch bulk operations | N/A | no bulk work |
| Select only needed columns on `account_entries`; no speculative `includes` | N/A | — |
| Screen dates via `l(...)`; email date format | N/A | no dates rendered |
| Date inputs / JS dates | N/A | — |
| Every query entity-scoped; Pundit on every action | Applies | this change *is* the entity scoping of the console's SQL; no new actions |
| MCP tool surfaces via the ontology YAML | N/A | the support machine's db tool is not the app's MCP server |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | `tenant_scope.feature` |
| `bundle exec rubocop` clean | Applies | `support_console_code_archive.rb` |

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
