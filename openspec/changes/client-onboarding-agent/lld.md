# Client Onboarding Agent — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/client-onboarding-agent/spec.md) · [Tasks](tasks.md)

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

- The security model rests on Claude Code features (managed settings, Bash sandbox, hook `ask`
  overriding saved allows, `permissions.deny` on Read) — verified by a spike before anything else; see [Configuration and Rollout](#configuration-and-rollout).
- The token lives only in `state/token`, read by the MCP server process (outside the sandbox) — see [Security Review](#security-review).
- "Ours" = records created by uploads listed in `journal.jsonl`; freshness is re-checked by counts, not by trusting state — see [Method Contracts](#method-contracts).
- Reconcile pulls `?all=true` JSON for most types but pages `account_entries` by fund — see [Queries and Indexes](#queries-and-indexes).
- No Rails file changes; the whole thing lives in `onboarding_agent/` and `features/client_onboarding/` — see [File Map](#file-map).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `onboarding_agent/workspace_template/` (`mappings/`, `scripts/`, `out/`, `state/`) | New | Skeleton copied per client by `bin/new_client` |
| ① | `onboarding_agent/bin/new_client` | New | Creates `onboarding/<client>/`, writes `state/token` (mode 600) |
| ③ | `onboarding_agent/claude/settings.json` | New | MCP server, deny rules, hook, sandbox, permission mode |
| ③ | `onboarding_agent/bin/start` | New | Creates workspace, installs its Gemfile, launches `claude` |
| ③ | `.claude/skills/client-onboarding/*` | Modified (exists, draft) | Rules and playbook the assistant follows |
| ④ | `onboarding_agent/workspace_template/Gemfile` | New | `roo`, `caxlsx`, `activesupport` for transforms |
| ⑤ | `onboarding_agent/hooks/pre_tool_use.rb` | New | stdin JSON → `Gate.decide` → stdout decision |
| ⑤ | `onboarding_agent/lib/onboarding_agent/gate.rb` | New | Decision table |
| ⑥ | `onboarding_agent/bin/onboarding_mcp` | New | stdio MCP server (`mcp` gem 1.3) |
| ⑥ | `onboarding_agent/lib/onboarding_agent/{mcp_server,app_client,guards,reconciler,state_store,mapping,import_order}.rb` | New | See Method Contracts |
| ⑥ | `onboarding_agent/lib/onboarding_agent/tools/*.rb` | New | One file per tool |
| tests | `features/client_onboarding/*.feature`, `features/step_definitions/client_onboarding_steps.rb`, `features/support/client_onboarding_server.rb` | New | Cucumber |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here
- [ ] Nothing under `app/`, `config/`, `db/` or `lib/` changes (v1)
- [ ] `onboarding_agent/lib` requires no Rails (`grep -r "Rails\|ActiveRecord" onboarding_agent/lib` empty)

---

## Schema Detail

N/A — no tables or columns. State files:

| File | Format | Writer | Content |
|---|---|---|---|
| `state/progress.yml` | YAML | `StateStore` | `{type => {status, upload_ids[], reconciled_at}}` |
| `state/waivers.yml` | YAML | `StateStore` via `grant_waiver` | `{type => {granted_at}}` |
| `state/journal.jsonl` | JSON lines, append-only | `StateStore#record` | `{at, tool, args_digest, decision, upload_id, result}` |
| `state/token` | text, 0600 | `bin/new_client` | devise-api access token |
| `state/entity` | text | `bin/new_client` | entity id + base URL |

**Reviewer checks**
- [ ] `journal.jsonl` is opened in append mode only; no rewrite path exists

---

## Method Contracts

**`OnboardingAgent::AppClient`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `get(path, params = {})` | String, Hash | parsed JSON | `ApiError(status, body)`, `ApiTimeout` | HTTP | Yes |
| `post_file(path, fields, file_path)` | multipart | parsed JSON | same | creates record | No — guarded by digest (E17) |
| `patch(path, body)` | Hash | parsed JSON | same | updates | Yes |
| `delete(path)` | — | status | same | enqueues delete | No — guarded by journal (X11) |

**`OnboardingAgent::Guards`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `fresh!(entity_json, state)` | | true | `Refused("Entity <id> is not fresh (N investors)")` | — | Yes |
| `sandbox!(entity_json)` | | true | `Refused("Sandbox is off — stopping")`; `GapError(:G9)` if no `entity_setting` | — | Yes |
| `order!(type, progress)` | String | true | `Refused("<type> waits until <earlier> …")` | — | Yes |

**`OnboardingAgent::Gate`** (Service) — `decide(tool_name, tool_input, state) → {decision:, reason:}`; pure.

**`OnboardingAgent::Reconciler`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `check_transform(source, sheet, mapping, out)` | paths | `{ok, columns: {mapped, custom, dropped, total}, rows, totals, problems[]}` | — | none | Yes |
| `reconcile(type, fund_id)` | | `{ok, rows: [src, file, app], totals_by_class}` | `GapError` if amounts absent | progress `reconciled` on ok | Yes |

Money compared in paise (integer) after `scale` (E15).

**`OnboardingAgent::StateStore`** — `progress`, `update(type, **)`, `record(event)`, `waivers`, `grant(type)`.

**Reviewer checks**
- [ ] `Refused` and `GapError` are returned to Claude as tool errors with the exact messages above
- [ ] `upload_import` with the same file digest and type as a journalled upload is refused (E17)

---

## Controllers, Params and Responses

N/A — no controllers added. Calls made to existing ones:

| Call | Params sent | Expected success | Today |
|---|---|---|---|
| `PATCH /entities/:id.json` | `entity[entity_setting_attributes][id, sandbox, sandbox_emails, individual_kyc_doc_list, non_individual_kyc_doc_list]` | 200 entity JSON | works |
| `POST /import_uploads.json` | `import_upload[name, entity_id, owner_type=Entity\|Fund, owner_id, import_type, import_file]` | 201 | works |
| `GET /import_uploads/:id.json` | — | counts + `results_url` | needs G8 |
| `DELETE /import_uploads/:id/delete_data` | — | 202 JSON | 302 until G10; treat 302 as accepted |

---

## Queries and Indexes

| Where | Request | Rows expected | Batching |
|---|---|---|---|
| `Guards#fresh!` | `GET /investors.json?per_page=1`, `/funds.json?per_page=1`, `/users.json?per_page=2` | ≤ 2 | — |
| `Reconciler` investors/KYCs/commitments/calls/remittances/payments | `GET /<type>.json?all=true&fund_id=` | ≤ ~30k | single request; 120 s timeout |
| `Reconciler` account entries | `GET /account_entries.json?fund_id=&per_page=1000&page=n` | ≤ ~90k | pages of 1000 |

**Reviewer checks**
- [ ] No `all=true` on `account_entries` (large-table rule)

---

## Transactions, Locking and Concurrency

| Operation | Guard |
|---|---|
| Two Claude sessions on one workspace | `state/.lock` (flock) held by the MCP server for its lifetime; second server refuses to start |
| Duplicate upload | file digest + type in journal (E17) |

---

## Background Jobs

N/A — none added; `ImportUploadJob` runs in the app as today. Poll every 5 s, give up at 15 min (X12).

---

## External Integrations

| Call | Auth | Timeouts | Error → exception |
|---|---|---|---|
| App `.json` | `Authorization: Bearer <state/token>` | open 5 s, read 30 s (120 s reconcile) | 401/403 → `ApiError` "token expired or no access"; 404 → `ApiError`; 422 → `ApiError` with body (X10); 5xx → `ApiError` |
| Model endpoint | per open question 1 | — | — |

**Reviewer checks**
- [ ] Token never written to journal or logs (journal stores `args_digest`, not headers)

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged |
|---|---|---|---|---|
| `Refused` | Guards, tools | MCP tool wrapper → `isError` result | the exact refusal message | journal `decision: refused` |
| `GapError(:G8/:G9/...)` | Guards, Reconciler | wrapper | "Paused: API gap G8 — …" | journal + progress `paused` |
| `ApiError` | AppClient | wrapper | status + body | journal |
| `ApiTimeout` | AppClient / poll | wrapper | "Upload 9912 still running after 15 min — paused" | journal |

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | App's Pundit as Ravi; tools add no authority |
| Tenant isolation | Ravi's token is for a user of the client entity; every write targets `state/entity` only; owner ids checked against it |
| Secrets | `state/token` 0600; `Read/Edit/Write(/work/state/**)` denied; sandbox denies read of `/work/state`; not in snapshot |
| Input sanitisation | `upload_import` accepts only files under `/work/out` (X9) |
| Self-approval | `waivers.yml` written only by `grant_waiver`, always asked; gate never allows it |

**Reviewer checks**
- [ ] No tool accepts an entity id argument (it comes from `state/entity`)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Spike first (task 1.2) | Confirm: hook `ask` beats saved allow; sandbox blocks network + writes outside workspace + `state/`; deny on Read/Edit/Write |
| Model | Ravi's own Claude Code login (v1) |
| Prerequisites | `bwrap` (present), `socat` (install) |
| Network | Bash: none. ⑥ and Claude Code: normal; ⑥ calls only `state/entity`'s base URL |
| App target | dev app `http://localhost:3000`, dev DB 3306 |
| Rollback | quit Claude; undo uploads via `undo_import` or the UI |

---

## Test Plumbing

| Feature file | Stubs / fixtures | New step definitions |
|---|---|---|
| `entity_guards`, `sandbox`, `import_order`, `imports`, `custom_fields`, `check_transform`, `reconcile`, `failures`, `resume`, `api_gaps`, `gate`, `isolation` | Capybara server booted in `client_onboarding_server.rb`; devise-api token created for Ravi; xlsx fixtures in `features/fixtures/client_onboarding/`; G8/G9 fields stubbed via `@stub_api_gaps` (decorating the JSON in test only) until they land | `Given a fresh entity "Northstar Capital" with ops user Ravi`, `When the onboarding tool "X" is called with …`, `Then the journal records …`, `When the gate decides …` |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | N/A | No ActiveRecord in `onboarding_agent/` |
| Dedup in SQL, batch bulk ops | N/A | — |
| `account_entries` column selection | Applies | Paged JSON only, never `all=true` |
| Date formatting | N/A | No screens or emails |
| Date inputs / JS dates | N/A | — |
| Entity scoping + Pundit | Applies | App's own; tools pin `state/entity` |
| MCP ontology | N/A | The app's MCP server is not touched |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | All tests are features |
| Rubocop clean | Applies | `onboarding_agent/` and rake task |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
