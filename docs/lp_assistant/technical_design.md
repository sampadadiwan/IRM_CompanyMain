# LP Assistant — Technical Design

## Overview

The LP Assistant is a Rails-native AI chat assistant for the LP (investor) portal. It uses a progressive-disclosure tool architecture — the LLM discovers data domains via skill files, loads only the skill it needs, generates SQL with placeholders that the server substitutes with a trusted scope, and resolves document references through a separate URL tool that re-verifies access server-side.

This design has two core properties:

1. **Single Fund Manager per chat** — each chat session is bound to exactly one FM tenant. The LLM never sees data from any other tenant.
2. **The LLM is treated as untrusted** — every tool call is independently re-validated server-side, so a confused or hijacked LLM cannot leak data outside the LP's scope.

## File map

| Path | Role |
|---|---|
| [app/packs/ai/lp_assistant/services/lp_chat_provider.rb](../../app/packs/ai/lp_assistant/services/lp_chat_provider.rb) | Builds system prompt, context block, and tool instances. The trust anchor of the whole feature. |
| [app/packs/ai/lp_assistant/tools/list_skills_tool.rb](../../app/packs/ai/lp_assistant/tools/list_skills_tool.rb) | Lists available skill files (data domains). |
| [app/packs/ai/lp_assistant/tools/load_skill_tool.rb](../../app/packs/ai/lp_assistant/tools/load_skill_tool.rb) | Returns the markdown body of a named skill. |
| [app/packs/ai/lp_assistant/tools/run_query_tool.rb](../../app/packs/ai/lp_assistant/tools/run_query_tool.rb) | Validates and executes SQL with placeholder substitution. |
| [app/packs/ai/lp_assistant/tools/document_url_tool.rb](../../app/packs/ai/lp_assistant/tools/document_url_tool.rb) | Resolves a `document_id` into a signed S3 URL after re-verifying access. |
| [app/packs/ai/lp_assistant/skills/*.md](../../app/packs/ai/lp_assistant/skills/) | Per-domain runtime skills loaded on demand by the LLM. |
| [features/ai/lp_assistant/lp_assistant.feature](../../features/ai/lp_assistant/lp_assistant.feature) | Cucumber coverage for tools and scope guards. |
| [features/step_definitions/lp_assistant_steps.rb](../../features/step_definitions/lp_assistant_steps.rb) | Step definitions for the above. |

## Single-entity access design

Every LP Assistant chat is hosted by a single `SupportAgent` row, which itself belongs to one `Entity` (the FM tenant). The `LpChatProvider` derives all scope from that one entity:

```ruby
# lp_chat_provider.rb
def accessible_entity_ids
  @accessible_entity_ids ||= [support_agent.entity_id]
end

def accessible_funds
  Fund.for_investor(analyst)
      .where(entity_id: support_agent.entity_id)
      ...
end

def accessible_investor_ids
  Investor.where(
    entity_id: support_agent.entity_id,
    investor_entity_id: analyst&.entity_id,
    deleted_at: nil
  ).pluck(:id)
end
```

Two architectural choices follow from this:

1. **`accessible_entity_ids` is a single-element array, not a scalar.** This keeps the SQL substitution path uniform — `IN ({ENTITY_ID})` works whether the array has one or many ids, so we never need a dedicated single-id code path. Today the array always has length 1; future cross-tenant features (if any) would not require a refactor of the substitution logic.
2. **An LP holding investments across multiple FMs sees multiple chat panels — one per FM.** There is no "global" LP Assistant. The same LP user navigating to Angelia FM and Beta FM gets two `LpChatProvider` instances with two completely disjoint scope sets.

This avoids the entire class of cross-tenant data-leak bugs at design time: the LLM is incapable of seeing data from a tenant that wasn't in `accessible_entity_ids` at chat construction.

## Trust boundaries

```
[LP user session]
       ↓ (Devise auth — authenticated identity)
[LpChatProvider — server-side trust anchor]
   ├─ accessible_entity_ids   = [<FM entity_id>]
   ├─ accessible_fund_ids     = [<funds with AccessRight>]
   └─ accessible_investor_ids = [<this LP org's investor rows in this FM>]
       ↓ (baked into tool instances at construction)
[Tools — RunQueryTool, DocumentUrlTool, ListSkillsTool, LoadSkillTool]
       ↑ (LLM can call these but cannot mutate the scope ids)
[LLM — UNTRUSTED]
       ↑ (sees system prompt + context block; chooses tool calls and arguments)
```

The LLM never receives, and cannot influence, the trusted id sets directly. They are closure-captured on each tool instance at the moment `LpChatProvider#tools` is called. Even if the LLM is jailbroken, the worst it can do is call tools with bad arguments — the tools enforce scope server-side regardless of what the LLM passes.

## Progressive disclosure — workflow per turn

For a typical LP question, the LLM does:

1. `list_skills()` → returns names of the six data domains.
2. `load_skill(skill_name)` → returns the markdown body for one domain.
3. The skill markdown explains the relevant tables, the placeholder contract, and example SQL. The LLM writes a SQL query using `{ENTITY_ID}`, `{FUND_IDS}`, and (when needed) `{INVESTOR_IDS}` placeholders.
4. `run_query(sql)` → server validates the SQL, substitutes placeholders with trusted ids, executes against the read replica, returns rows.
5. If the rows contain a `document_id`, the LLM calls `document_url(document_id: N)` → server re-verifies access and returns a signed S3 URL.
6. The LLM formats the result for the LP — Markdown table for tabular results, Markdown link for documents.

The skill files are loaded on demand (not all upfront) to keep the system prompt small and to make it explicit which domain the LLM is operating in.

## Two server-side enforcement points

The cross-LP guarantee is not enforced once — it is enforced twice, in independent code paths. Either alone would suffice for a correctly-behaving LLM; both together protect against a misbehaving one.

### Enforcement point 1 — `RunQueryTool` placeholder substitution

The LLM's SQL must contain `{ENTITY_ID}` and `{FUND_IDS}` placeholders, and `{INVESTOR_IDS}` for per-LP tables. Before execution, [run_query_tool.rb](../../app/packs/ai/lp_assistant/tools/run_query_tool.rb):

- Rejects any query missing `{ENTITY_ID}` or `{FUND_IDS}`.
- Rejects non-`SELECT` statements.
- Rejects forbidden keywords (`DROP`, `INSERT`, `UPDATE`, etc.).
- Restricts table access to a whitelist.
- Substitutes the placeholders with the trusted ids the tool was constructed with.

The substitution is a literal string replacement, but the trusted clause (`AND cc.investor_id IN (438)` for an LP whose investor id is 438) is added to whatever the LLM wrote — so even SQL that *also* says `OR cc.investor_id IN (439)` will be ANDed against the trusted clause and return only the LP's own rows.

### Enforcement point 2 — `DocumentUrlTool` re-verification

Even if `RunQueryTool` returned only documents the LP can see, the LLM could in principle call `document_url(document_id: <something_else>)` without a prior query. So [document_url_tool.rb](../../app/packs/ai/lp_assistant/tools/document_url_tool.rb) re-verifies on every call:

```ruby
def accessible?(doc)
  case doc.owner_type
  when 'CapitalCommitment'
    CapitalCommitment.exists?(
      id:          doc.owner_id,
      fund_id:     @accessible_fund_ids,
      investor_id: @accessible_investor_ids,    # ← critical for cross-LP isolation
      deleted_at:  nil
    )
  when 'CapitalCall'
    CapitalCall.exists?(id: doc.owner_id, fund_id: @accessible_fund_ids, deleted_at: nil)
  when 'CapitalDistribution'
    CapitalDistribution.exists?(id: doc.owner_id, fund_id: @accessible_fund_ids, deleted_at: nil)
  when 'Fund'
    Fund.where(id: @accessible_fund_ids, deleted_at: nil).exists?(id: doc.owner_id)
  else
    false
  end
end
```

For SOA documents (`owner_type='CapitalCommitment'`), the `investor_id` filter is the **only** thing separating LP-A from LP-B in a shared fund. Drop that one line and you have a silent data-leak vector. The Cucumber scenario in the test suite guards this exact line.

## The cross-LP SOA leak — threat model

Setup:

- Angelia Growth Fund has two LPs: LP-A and LP-B.
- The fund manager generates per-investor SOAs each quarter:
  - SOA-A: `owner_type='CapitalCommitment'`, `owner_id=<LP-A's commitment id>`
  - SOA-B: `owner_type='CapitalCommitment'`, `owner_id=<LP-B's commitment id>`
- Both SOAs live in the same `Investor Statements` folder under the same fund. They differ only by which `CapitalCommitment` they are attached to.

Threat:

- LP-A logs in. Their `accessible_investor_ids = [<LP-A's investor id>]`. Their `accessible_fund_ids = [Angelia Growth Fund]`.
- The LLM, possibly malformed or jailbroken, calls `document_url(document_id: <SOA-B's id>)`.
- Without the `investor_id` clause, the access check would pass (same FM, same fund, valid owner_type) and SOA-B would be served to LP-A.

Defence:

- The `investor_id IN @accessible_investor_ids` clause inside `accessible?` rejects the request because SOA-B's commitment has LP-B's investor id, which is not in LP-A's scope.
- `find_scoped_document` returns `nil`. `execute` returns `"Document <id> not found or not accessible."` and the LLM sees an error string, not a URL.

This guarantee is asymmetric across `owner_type`s:

- For `CapitalCommitment` (SOAs), the `investor_id` filter is **required** because LPs share funds.
- For `CapitalCall`, `CapitalDistribution`, and `Fund`, fund-level scope is sufficient — any LP invested in the fund is entitled to see calls, distribution notices, and fund-level documents (LPA, PPM, fund reports).

Any future addition of a new `owner_type` must explicitly decide which scope axis applies.

## Cucumber coverage

[features/ai/lp_assistant/lp_assistant.feature](../../features/ai/lp_assistant/lp_assistant.feature) covers:

- **`RunQueryTool`** — placeholder enforcement (`{ENTITY_ID}` / `{FUND_IDS}` required), non-SELECT rejection, forbidden-keyword rejection, table whitelist, scope substitution, and the empty-funds short-circuit.
- **`ListSkillsTool` / `LoadSkillTool`** — discovery, content delivery, unknown-skill error, path-traversal rejection.
- **`DocumentUrlTool`** — in-scope Fund document, out-of-scope Fund document, unsupported `owner_type`, and **the cross-LP SOA leak guard** (LP-A cannot resolve a URL for LP-B's SOA in a shared fund).

The cross-LP scenario is the most security-critical; it is the only one that exercises the `investor_id` clause in isolation. To verify it does real work, comment out the `investor_id:` line in `document_url_tool.rb#accessible?` and re-run the scenario — it should fail. Restore the line, the scenario passes again. This round-trip is the proof that the test guards the rule, not just exercises the code.

## Per-tenant LLM model selection

API keys and the default model for the LLM are resolved per FM entity through `EntitySetting` columns (`openai_api_key`, `gemini_api_key`, `anthropic_api_key`, `openrouter_api_key`, `default_llm_model`). Falls back to Rails credentials for any unset key. See [llm_service.rb](../../app/packs/ai/llm_service.rb).

This means LP-A on Angelia FM may transparently be served by Claude, while LP-A on Beta FM may be served by Gemini, depending on each FM's setting.

## Skill files

Each skill file under `app/packs/ai/lp_assistant/skills/` documents one data domain for the LLM to consume at runtime via `load_skill`. The skill format:

```
---
name: <skill name>
description: <one-line summary used by list_skills>
tables:
  - <whitelisted table>
  - ...
---

<markdown body — table schemas, scoping rules, example SQL, anti-patterns>
```

Skill files are version-controlled in the repo and updated through PRs like any other code change. They are **not** stored in the database.

## Future considerations

- **Chat history persistence** — currently per-session; persistence + per-LP audit trail is a candidate for a future phase.
- **Voice / WhatsApp surface** — the same toolset can in principle be reused; would need a transport-layer adapter and per-channel auth mapping.
- **Cross-FM aggregation** — explicitly out of scope today (single-entity access). If introduced, the trust model would need a new layer above `LpChatProvider`.
