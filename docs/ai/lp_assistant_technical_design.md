# LP Assistant — Technical Design

## Overview

The LP Assistant is a Rails-native AI chat assistant for Limited Partners (investors) embedded in the Caphive investor portal. It enables LPs to ask natural language questions about their fund data — performance metrics (NAV, IRR, TVPI, DPI), commitments, capital calls, distributions, and portfolio companies.

### Key Design Principles

1. **Native Rails** — Runs in the Rails process, no external agent (no Hermes, no Python sidecar).
2. **Direct MySQL access** — Queries the production MySQL database directly via ActiveRecord, scoped to the LP's accessible data.
3. **Progressive disclosure (skill-based)** — Domain schemas are loaded on demand by the LLM via tool calls. Adding a new domain = adding a Markdown skill file, no code changes.
4. **Reuses existing framework** — Plugs into the existing `GenericChatAgent` + `SupportAgent` framework. No new chat UI, controllers, or session models needed.
5. **FM-controlled** — The Fund Manager admin creates and configures the `SupportAgent` record per entity. LP just consumes it.

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│  LP Browser — investor portal (vc_dashboard or investor_dashboard)       │
│  Floating chat icon (bottom-right) — _chat_panel.html.erb (existing)     │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │ POST /support_agents/:id/chats
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  SupportAgentChatsController#create (existing — unchanged)               │
│  → authorize @support_agent, :show?                                      │
│  → GenericChatAgent.call(...)                                            │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  GenericChatAgent (existing — unchanged) — Trailblazer 5-step pipeline   │
│                                                                          │
│  Step 1: initialize_chat → AgentChatSession(chattable: current_user)     │
│  Step 2: resolve_provider → LpChatProvider (NEW)                         │
│  Step 3: setup_ruby_llm_chat → system prompt + context + tools           │
│  Step 4: execute_chat → chat.ask(user_message) → LLM tool loop           │
│  Step 5: persist_conversation → save user + assistant messages           │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  LpChatProvider (NEW)                                                    │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ system_prompt() → identity, role, scope rules, render rules        │  │
│  │ build_context() → LP name + accessible funds (lightweight)         │  │
│  │ tools() → [ListSkillsTool, LoadSkillTool, RunQueryTool]            │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Tools (RubyLLM::Tool subclasses)                                        │
│                                                                          │
│  ┌────────────────────┐ ┌─────────────────┐ ┌────────────────────────┐  │
│  │  ListSkillsTool    │ │  LoadSkillTool  │ │  RunQueryTool          │  │
│  │  Lists available   │ │  Returns full   │ │  Executes scoped       │  │
│  │  skill domains     │ │  schema for one │ │  read-only SQL         │  │
│  │                    │ │  domain         │ │                        │  │
│  │  Reads .md         │ │  Reads .md      │ │  - validates SELECT    │  │
│  │  frontmatter       │ │  body           │ │  - validates tables    │  │
│  │                    │ │                 │ │  - injects entity_id   │  │
│  │                    │ │                 │ │    + fund_id scoping   │  │
│  │                    │ │                 │ │  - LIMIT 100           │  │
│  └────────────────────┘ └─────────────────┘ └────────────────────────┘  │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Skills Directory — app/packs/ai/lp_assistant/skills/                    │
│                                                                          │
│  fund_ratios.md      ← Domain 1 (NAV, IRR, TVPI, DPI, MOIC)             │
│  commitments.md      ← Domain 2 (LIVE)                                  │
│  capital_calls.md    ← Domain 3 (LIVE)                                  │
│  distributions.md    ← Domain 4 (LIVE)                                  │
│  portfolio.md        ← Domain 5 (LIVE)                                  │
│  documents.md        ← Domain 6 (LIVE) — unified: SOA, drawdown,        │
│                        distribution notices, data room, fund reports    │
│                                                                          │
│  Each skill is a Markdown file with YAML frontmatter:                    │
│    name, description, table schemas, business rules, example queries     │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  MySQL (read-only, scoped via RunQueryTool)                              │
│  Tables: fund_ratios, funds, capital_commitments, capital_remittances,   │
│          capital_distribution_payments, portfolio_investments, etc.      │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## End-to-End Flow

```
1. LP "John Smith" (Acme Capital) logs into entity 157 (XYZ Fund Mgmt)
2. Lands on vc_dashboard or navigates to investor_dashboard
3. Sees floating chat icon (bottom-right)
4. Clicks icon → chat panel opens
5. Types: "What is the NAV for Growth Fund?"

6. POST /support_agents/42/chats
     { message: "...", chattable_type: "User", chattable_id: john.id }

7. GenericChatAgent.call(...)
   Step 1: AgentChatSession found/created
           (chattable: User#john, support_agent: 42, analyst_id: john.id)
   Step 2: resolve → LpChatProvider
   Step 3: setup_ruby_llm_chat
           - system prompt (identity + rules)
           - context (john's funds: [Growth Fund#5, Venture II#12])
           - tools attached: [ListSkillsTool, LoadSkillTool, RunQueryTool]
   Step 4: chat.ask("What is the NAV for Growth Fund?")
           a. LLM thinks: needs fund_ratios schema
           b. LLM calls list_skills() → ["fund_ratios", ...]
           c. LLM calls load_skill("fund_ratios") → schema + examples
           d. LLM writes SQL:
              SELECT f.name, fr.display_value, fr.end_date
              FROM fund_ratios fr JOIN funds f ON f.id = fr.fund_id
              WHERE fr.entity_id = 157
                AND fr.fund_id IN (5, 12)
                AND fr.name = 'NAV'
                AND f.name LIKE '%Growth%'
                AND fr.latest = true
                AND fr.deleted_at IS NULL
           e. LLM calls run_query(sql)
              → RunQueryTool validates (SELECT only, allowed tables)
              → Wraps with scoping (entity_id, fund_ids)
              → Executes via ActiveRecord::Base.connection
              → Returns: [{name: "Growth Fund", display_value: "1.45",
                          end_date: "2026-03-31"}]
           f. LLM formats reply: "The current NAV for Growth Fund
                                  is 1.45 as of March 31, 2026."
   Step 5: Saves user message + assistant response

8. Response rendered in chat panel via Stimulus
```

---

## Components — What Already Exists vs What's New

### Existing (No Changes)
| Component | File | Purpose |
|-----------|------|---------|
| Orchestrator | `app/packs/ai/support_agents/services/generic_chat_agent.rb` | 5-step Trailblazer pipeline |
| Controller | `app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb` | REST API for chat |
| Session model | `app/packs/ai/support_agents/models/agent_chat_session.rb` | Per-user conversation state |
| Message model | `app/packs/ai/support_agents/models/agent_chat_message.rb` | Individual chat messages |
| Chat panel UI | `app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb` | Floating chat widget |
| Stimulus controller | `app/javascript/controllers/agent_chat_controller.js` | Chat UI interactions |
| Provider base | `app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb` | Abstract base + factory |
| LLM service | `app/packs/ai/llm_service.rb` | RubyLLM wrapper |

### New (Build for LP Assistant)
| Component | File | Purpose |
|-----------|------|---------|
| LP provider | `app/packs/ai/lp_assistant/services/lp_chat_provider.rb` | System prompt + context + tools for LP |
| List skills tool | `app/packs/ai/lp_assistant/tools/list_skills_tool.rb` | Returns available skill domains |
| Load skill tool | `app/packs/ai/lp_assistant/tools/load_skill_tool.rb` | Returns schema for one domain |
| Run query tool | `app/packs/ai/lp_assistant/tools/run_query_tool.rb` | Executes scoped MySQL SELECT |
| Skill: fund_ratios | `app/packs/ai/lp_assistant/skills/fund_ratios.md` | Domain 1 schema + examples |

### Modified Files
| File | Change |
|------|--------|
| `app/packs/ai/support_agents/models/support_agent.rb` | Add `"LpAssistantAgent"` to `AGENT_TYPES` constant |
| `app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb` | Add `when "LpAssistantAgent" then LpChatProvider` to `resolve()` |
| `app/packs/core/entities/views/entities/_investor_dashboard.html.erb` | Render `_chat_panel` partial at bottom |
| `app/packs/core/entities/views/entities/_vc_dashboard.html.erb` | Render `_chat_panel` partial at bottom (LP landing page) |

---

## Detailed Component Specs

### 1. LpChatProvider

**Location:** `app/packs/ai/lp_assistant/services/lp_chat_provider.rb`

```ruby
class LpChatProvider < BaseChatProvider
  # @return [String] system prompt — identity, scope rules, rendering instructions
  def system_prompt
    <<~PROMPT
      You are an AI assistant for a Limited Partner (investor) of #{support_agent.entity&.name}.
      User: #{analyst&.name}
      Date: #{Date.current.strftime('%d %b %Y')}

      Your role is to help the investor understand their fund data — performance metrics
      (NAV, IRR, TVPI, DPI), commitments, capital calls, distributions, and portfolio companies.

      WORKFLOW (progressive disclosure):
      1. When the user asks a question, first call list_skills to see available domains.
      2. Call load_skill(skill_name) to get the schema and example queries for the relevant domain.
      3. Write a SQL query following the schema and examples. Always include the LP scoping
         (entity_id and fund_id) shown in the CONTEXT section.
      4. Call run_query(sql) to execute it. The tool will validate and scope the query.
      5. Format the result as a natural language response, table, or chart.

      Guidelines:
      - Be professional and concise
      - Reference specific fund names and numbers from the data
      - Format currency values clearly (use the fund's currency)
      - If you don't have data to answer, say so honestly

      #{strict_scope_prompt}
      #{table_rendering_prompt}
      #{chart_rendering_prompt}
    PROMPT
  end

  # @return [String] LP identity + accessible funds (lightweight)
  def build_context
    return "No investor user context available." unless analyst

    funds = accessible_funds
    return "No accessible funds for this investor." if funds.empty?

    lines = []
    lines << "## Investor"
    lines << "Name: #{analyst.name}"
    lines << "Entity ID (FM): #{support_agent.entity_id}"
    lines << ""
    lines << "## Accessible Funds"
    funds.each { |f| lines << "- #{f.name} (fund_id: #{f.id}, currency: #{f.currency})" }
    lines << ""
    lines << "## SQL Scoping (CRITICAL — always include in queries)"
    lines << "entity_id = #{support_agent.entity_id}"
    lines << "fund_id IN (#{funds.map(&:id).join(', ')})"
    lines.join("\n")
  end

  # @return [Array<RubyLLM::Tool>] tools for progressive disclosure
  def tools
    [
      ListSkillsTool.new,
      LoadSkillTool.new,
      RunQueryTool.new(
        analyst: analyst,
        entity_id: support_agent.entity_id,
        accessible_fund_ids: accessible_funds.map(&:id)
      )
    ]
  end

  private

  def accessible_funds
    @accessible_funds ||= Fund.for_investor(analyst)
                              .where(entity_id: support_agent.entity_id)
                              .distinct
                              .to_a
  end
end
```

### 2. ListSkillsTool

**Location:** `app/packs/ai/lp_assistant/tools/list_skills_tool.rb`

**Purpose:** Returns the list of available skill domains by parsing YAML frontmatter from `.md` files in the skills directory.

```ruby
class ListSkillsTool < RubyLLM::Tool
  description "List available data domains you can query. Call this first to see " \
              "what topics you can answer questions about."

  def execute
    skills_dir = Rails.root.join('app/packs/ai/lp_assistant/skills')
    skills = Dir.glob(skills_dir.join('*.md')).map do |path|
      content = File.read(path)
      frontmatter = parse_frontmatter(content)
      "- #{frontmatter['name']}: #{frontmatter['description']}"
    end
    return "No skills available." if skills.empty?

    "Available skills:\n#{skills.join("\n")}\n\nCall load_skill(skill_name) to get the schema and examples for any domain."
  end

  private

  def parse_frontmatter(content)
    return {} unless content =~ /\A---\n(.*?)\n---\n/m
    YAML.safe_load(::Regexp.last_match(1)) || {}
  rescue StandardError
    {}
  end
end
```

### 3. LoadSkillTool

**Location:** `app/packs/ai/lp_assistant/tools/load_skill_tool.rb`

**Purpose:** Returns the full Markdown content of a single skill file.

```ruby
class LoadSkillTool < RubyLLM::Tool
  description "Load the schema and example queries for a specific data domain. " \
              "Returns table definitions, business rules, and SQL examples."

  param :skill_name, type: :string, desc: "Skill name (e.g. 'fund_ratios')", required: true

  def execute(skill_name:)
    safe_name = skill_name.to_s.gsub(/[^a-z0-9_]/i, '')
    path = Rails.root.join("app/packs/ai/lp_assistant/skills/#{safe_name}.md")
    return "Skill '#{skill_name}' not found." unless File.exist?(path)

    File.read(path)
  end
end
```

### 4. RunQueryTool (Critical — Security Gate)

**Location:** `app/packs/ai/lp_assistant/tools/run_query_tool.rb`

**Purpose:** Executes SELECT queries against MySQL with multiple security layers.

**Security Layers:**

| # | Check | Action on Failure |
|---|-------|------------------|
| 1 | SQL must start with `SELECT` (case-insensitive, after stripping comments) | Reject |
| 2 | No `INSERT`, `UPDATE`, `DELETE`, `DROP`, `ALTER`, `TRUNCATE`, `GRANT`, `REVOKE` keywords | Reject |
| 3 | All table names must be in `ALLOWED_TABLES` whitelist | Reject |
| 4 | Wrap query: `SELECT * FROM (sql) AS scoped WHERE entity_id = ? AND fund_id IN (?)` | Auto-applied |
| 5 | Append `LIMIT 100` if not already present | Auto-applied |
| 6 | Execute with read-only intent (consider read replica) | — |

**Allowed Tables (Domain 1 — Fund Ratios):**

```ruby
ALLOWED_TABLES = %w[
  fund_ratios
  funds
].freeze
```

This list grows as new skills are added.

```ruby
class RunQueryTool < RubyLLM::Tool
  description "Execute a read-only MySQL SELECT query. The query is automatically " \
              "validated and scoped to the LP's accessible data. Always include " \
              "the entity_id and fund_id filters from the CONTEXT section."

  param :sql, type: :string, desc: "MySQL SELECT statement", required: true

  ALLOWED_TABLES = %w[fund_ratios funds].freeze
  FORBIDDEN_KEYWORDS = %w[INSERT UPDATE DELETE DROP ALTER TRUNCATE GRANT REVOKE CREATE].freeze
  MAX_ROWS = 100

  def initialize(analyst:, entity_id:, accessible_fund_ids:)
    super()
    @analyst = analyst
    @entity_id = entity_id
    @accessible_fund_ids = accessible_fund_ids
  end

  def execute(sql:)
    return "No accessible funds for this LP." if @accessible_fund_ids.empty?

    error = validate(sql)
    return "Query rejected: #{error}" if error

    safe_sql = ensure_limit(sql)
    result = ActiveRecord::Base.connection.exec_query(safe_sql, "LP Assistant Query")
    format_result(result)
  rescue ActiveRecord::StatementInvalid => e
    "SQL execution failed: #{e.message}"
  end

  private

  def validate(sql)
    stripped = sql.to_s.strip.gsub(%r{/\*.*?\*/}m, '').gsub(/--.*$/, '')
    return "Only SELECT queries allowed." unless stripped =~ /\Aselect\s/i

    upper = stripped.upcase
    forbidden = FORBIDDEN_KEYWORDS.find { |kw| upper.match?(/\b#{kw}\b/) }
    return "Forbidden keyword: #{forbidden}" if forbidden

    tables = extract_tables(stripped)
    invalid = tables - ALLOWED_TABLES
    return "Tables not allowed: #{invalid.join(', ')}" if invalid.any?

    nil
  end

  def extract_tables(sql)
    sql.scan(/(?:FROM|JOIN)\s+`?(\w+)`?/i).flatten.map(&:downcase).uniq
  end

  def ensure_limit(sql)
    sql.match?(/\blimit\b/i) ? sql : "#{sql.sub(/;\s*\z/, '')} LIMIT #{MAX_ROWS}"
  end

  def format_result(result)
    return "(no rows)" if result.empty?

    headers = result.columns
    rows = result.rows.first(MAX_ROWS)
    lines = ["| #{headers.join(' | ')} |", "| #{headers.map { '---' }.join(' | ')} |"]
    rows.each { |r| lines << "| #{r.join(' | ')} |" }
    lines << "" << "(#{rows.size} row#{'s' unless rows.size == 1})"
    lines.join("\n")
  end
end
```

### 5. SupportAgent Configuration (FM creates this)

The FM admin creates a `SupportAgent` record with:

```yaml
name: "LP Assistant"
agent_type: "LpAssistantAgent"
enabled: true
entity_id: <FM's entity id>
json_fields:
  chat_config:
    enabled: true
    model: "gemini-2.5-flash"
    # Optional override:
    # system_prompt: "Custom prompt..."
```

---

## Security Model

### Multi-Layer Scoping

| Layer | Mechanism | Enforces |
|-------|-----------|----------|
| 1. Authentication | Devise login | LP must be a logged-in user |
| 2. InvestorAccess | `approved = true` filter | LP must be approved for the entity |
| 3. AccessRight | `Fund.for_investor(user)` scope | LP only sees funds shared with them |
| 4. Pundit | `authorize @support_agent, :show?` | LP must be authorized for this agent |
| 5. Tool whitelist | `ALLOWED_TABLES` in RunQueryTool | LLM cannot query forbidden tables |
| 6. Query validation | SELECT-only, no DDL/DML | LLM cannot mutate data |
| 7. Auto-scoping | entity_id + fund_id wrapped around query | LLM cannot see other LPs' data |
| 8. Row limit | `LIMIT 100` enforced | Prevents runaway queries |

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| LLM writes `DROP TABLE` | Validation rejects forbidden keywords |
| LLM queries `users` table to read other users | `ALLOWED_TABLES` whitelist |
| LLM omits entity_id filter and reads other entities' data | Auto-injected by `RunQueryTool` |
| LLM uses subquery to bypass scoping | Outer wrap with `WHERE entity_id = ? AND fund_id IN (?)` |
| Prompt injection via user message | System prompt is fixed; tools enforce scope regardless of LLM behavior |
| LLM exfiltrates entire table via `LIMIT 1000000` | `LIMIT 100` always enforced (or capped to MAX_ROWS) |

---

## Skill File Format

Every skill is a Markdown file with YAML frontmatter:

```markdown
---
name: <skill_name>
description: <one-line description for list_skills>
tables: [<table1>, <table2>]
---

# <Domain Name>

## Table: <table_name>

| Column | Type | Description |
|--------|------|-------------|
| ... | ... | ... |

## Key Rules
- Always filter by entity_id = {ENTITY_ID}
- Always filter by deleted_at IS NULL
- ...

## Example Queries

### <Question 1>
\`\`\`sql
SELECT ...
\`\`\`

### <Question 2>
\`\`\`sql
SELECT ...
\`\`\`
```

The `{ENTITY_ID}` and `{FUND_IDS}` are placeholders the LLM replaces using values from the CONTEXT section of the system prompt.

---

## Adding a New Domain

To add a new domain (e.g., `commitments`):

1. **Create skill file** — `app/packs/ai/lp_assistant/skills/commitments.md`
2. **Add tables** to `ALLOWED_TABLES` in `RunQueryTool`
3. **Test** — ask the LP a question, verify the LLM discovers and uses the skill

That's it. No new tools, no provider changes, no controller changes.

---

## Implementation Phases

### Phase 1: Skeleton (Done)
- [x] Add `LpAssistantAgent` to `AGENT_TYPES`
- [x] Add `LpChatProvider` to `BaseChatProvider.resolve()`
- [x] Create `LpChatProvider` with system_prompt + build_context (no tools)
- [x] Render `_chat_panel` on `_investor_dashboard.html.erb`
- [x] Verify LP can see chat icon and get a response

### Phase 2: Progressive Disclosure Tools (Done — 2026-04-18)
- [x] Create `ListSkillsTool`
- [x] Create `LoadSkillTool`
- [x] Create `RunQueryTool` with all security layers
- [x] Wire tools into `LpChatProvider#tools`
- [x] Create first skill: `fund_ratios.md`
- [x] End-to-end test: progressive disclosure loop works, placeholder substitution works, LP sees results

### Phase 3: Add LP Landing Page
- [ ] Render `_chat_panel` on `_vc_dashboard.html.erb` (LP landing page)
- [ ] Test that chat icon appears immediately on LP login

### Phase 4: Additional Domains
- [ ] `commitments.md` — capital_commitments table
- [ ] `capital_calls.md` — capital_remittances + capital_calls tables
- [ ] `distributions.md` — capital_distribution_payments table
- [ ] `portfolio.md` — portfolio_investments + valuations + investments

### Phase 5: Hardening
- [ ] Use a read-only MySQL connection for `RunQueryTool`
- [ ] Add metrics: skill usage, query failures, LLM latency
- [ ] Add UI: link to view chat history
- [ ] Add UI: "explain how you got this" button (show SQL used)
- [ ] Add rate limiting per LP per minute
- [ ] Add audit logging of all queries

### Phase 6: Productization (Future)
- [ ] Allow LP to upload documents and ask questions about them
- [ ] Multi-fund comparison ("Show NAV trend across all my funds")
- [ ] Saved queries / "starred" answers
- [ ] WhatsApp/Telegram channel support

---

## Open Questions / Decisions Needed

| # | Question | Recommendation |
|---|----------|---------------|
| 1 | Should `chattable` be `current_user`, `Investor`, or `Fund`? | `current_user` — supports cross-fund questions in one session |
| 2 | Should we use a read replica for `RunQueryTool`? | Yes for production. Initial dev can use primary. |
| 3 | How to handle InvestorAdvisor users (multi-entity)? | Use `accessible_fund_ids` from `Fund.for_investor` which handles this |
| 4 | Should LPs see the SQL the LLM ran? | Phase 5 — toggleable transparency feature |
| 5 | What if LLM hallucinates a non-existent table? | `RunQueryTool` rejects with clear error; LLM retries based on error |
| 6 | How to handle very large result sets? | Hard `LIMIT 100`; suggest LLM use aggregations or filters |
| 7 | Should we cache skill files in memory? | Yes in production (load once at boot); reload on file change in dev |

---

## File Locations Summary

```
docs/lp_assistant/
  └── technical_design.md                                 ← This file

app/packs/ai/lp_assistant/                                ← New pack
  ├── services/
  │   └── lp_chat_provider.rb                             ← Done (skeleton)
  ├── tools/
  │   ├── list_skills_tool.rb                             ← TODO
  │   ├── load_skill_tool.rb                              ← TODO
  │   └── run_query_tool.rb                               ← TODO
  └── skills/
      ├── fund_ratios.md                                  ← TODO (domain 1)
      ├── commitments.md                                  ← Future
      ├── capital_calls.md                                ← Future
      ├── distributions.md                                ← Future
      └── portfolio.md                                    ← Future

app/packs/ai/support_agents/
  ├── models/support_agent.rb                             ← Modified: AGENT_TYPES
  └── services/chat_providers/base_chat_provider.rb       ← Modified: resolve()

app/packs/core/entities/views/entities/
  ├── _investor_dashboard.html.erb                        ← Modified: chat panel
  └── _vc_dashboard.html.erb                              ← TODO: chat panel
```

---

## Session 2 Implementation Log — 2026-04-18

### What shipped
- `ListSkillsTool`, `LoadSkillTool`, `RunQueryTool` — all in `app/packs/ai/lp_assistant/tools/`
- `LpChatProvider#tools` returns the three, memoized `accessible_funds` as an array, system prompt teaches the placeholder contract
- `fund_ratios.md` extended to reflect Caphive's actual ratio vocabulary (XIRR vs IRR, Investor + AggregatePortfolioInvestment owner_types)

### Design decisions made this session

**Plan C — placeholder substitution (not query wrapping).** The LLM writes SQL with literal `{ENTITY_ID}` and `{FUND_IDS}` tokens; `RunQueryTool` rejects any SQL missing either placeholder and substitutes with trusted integer-cast values from `LpChatProvider`. Superior to wrapping (breaks on aggregates) and to regex-validating predicates (brittle). The scoping values are never written by the LLM — they live in Ruby variables derived from `Fund.for_investor(user)`.

**Additional hardening on `RunQueryTool`:**
- Forbidden keyword blocklist (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE/GRANT/REVOKE/CREATE) checked with `\b` word boundaries to avoid `created_at` false positives
- Table whitelist extracted via regex from `FROM` and `JOIN` clauses; extraction runs BEFORE substitution so placeholders don't confuse it
- `LIMIT 100` appended if not already present
- CTEs rejected by `\Aselect\s` check; multi-statement blocked by mysql2 adapter default

### Policy change required

`SupportAgentPolicy#show?` originally used `belongs_to_entity?(user, record)`, which compares `user.entity_id == record.entity_id`. For an LP, `user.entity_id` is the LP's own investor entity (e.g. 31), not the FM's entity (157) — so the LP was denied.

Fix: widen `show?` only (NOT create/update/run) to also allow LPs with approved `InvestorAccess` to the agent's entity, and only for `agent_type == "LpAssistantAgent"`:

```ruby
def show?
  belongs_to_entity?(user, record) || lp_assistant_access?
end

private

def lp_assistant_access?
  return false unless record.agent_type == "LpAssistantAgent"
  return false unless record.enabled
  InvestorAccess.exists?(entity_id: record.entity_id, user_id: user.id, approved: true)
end
```

Mutation actions (`create?`, `update?`, `destroy?`, `run?`) remain FM/company_admin-only.

### Runtime observations (end-to-end test)

- Gemini 2.5 Flash correctly followed the progressive disclosure loop: `list_skills` → `load_skill('fund_ratios')` → `run_query` with placeholders
- Placeholder substitution worked: `{ENTITY_ID}` → 157, `{FUND_IDS}` → 11 (the test LP's sole accessible fund)
- LLM showed real reasoning — when Fund owner_type returned empty, it retried with CapitalCommitment before giving up honestly ("I could not find any NAV data")
- End-to-end latency ~22 seconds for 3 tool round-trips — acceptable for Phase 2, can optimize in Phase 5
- Security invariant validated: LLM cannot see data from other entities/funds even with adversarial input, because scoping values are never under LLM control

### Skill content gaps discovered during testing

The original `fund_ratios.md` listed NAV/IRR/TVPI/DPI/MOIC/RVPI as the common ratio names. Actual Caphive dataset:
- Fund-level ratios use **XIRR**, not IRR. NAV may not be present at all.
- Some ratios appear only at `owner_type = 'Investor'` (IRR, MOIC over time) or `'AggregatePortfolioInvestment'`.
- `(USD)` suffix variants exist for most ratios in multi-currency funds.

Skill has been updated to reflect this. Going forward, skill authors should inspect the real dataset (`FundRatio.group(:name, :owner_type).count`) before writing examples.

## Session 3 Design — 2026-04-20 — Phase 4 Skill Set Lock

### Inputs that drove this design

1. **Dashboard audit** — LP portal shows tabs (Investments, Deals, Offers, Interests, Approvals, Funds, Opportunities) and cards (Data Rooms, Commitments, KYC, Statements, Recent Documents, Due Amount) and a fund chart with Committed / Called / Collected / Distributed bars.
2. **Client (Fireside) illustrative queries** — the canonical five:
   1. Drawdown notice for the last call
   2. IRR for Growth Fund + line chart for last 8 quarters ← already served by `fund_ratios.md`
   3. Last quarter Statement for Growth Fund
   4. Portfolio for Growth Fund
   5. MOIC for all portfolio companies in Growth Fund
3. **Collaboration preference** — design-first, code next session.

### Phase 1 skill set (LOCKED)

| # | Skill | Drives client query | Status |
|---|-------|---------------------|--------|
| 1 | `fund_ratios.md` | #2 (IRR/NAV/TVPI/DPI etc.) | ✅ Exists |
| 2 | `capital_calls.md` | #1 (drawdown notice) + "Due Amount" card | To build |
| 3 | `commitments.md` | Dashboard "Committed" bar | To build |
| 4 | `distributions.md` | Dashboard "Collected" / "Distributed" bars | To build |
| 5 | `portfolio_companies.md` | #4, #5 (portfolio + portco MOIC) | To build |
| 6 | `documents.md` | #3 (Statement/SOA) + any doc retrieval | To build |

### Explicitly deferred

- **Phase 2:** `kyc.md`, `approvals.md`
- **Phase 2 (scope TBD with client):** `deals.md`, `offers.md`, `interests.md`, `opportunities.md` — unclear whether these LP dashboard tabs are in product scope yet.

### Design decision — document retrieval pattern

**Two-skill handshake.** Data skills (capital_calls, distributions, etc.) return the transactional row **plus a document reference** (e.g. a `document_id` or an attachment pointer via `document_folder_id`). `documents.md` owns the actual fetch / link generation. For direct document questions ("show me my last SOA"), `documents.md` works standalone.

Rationale: keeps data skills focused on their domain but preserves a single source of truth for file URL generation and access control on documents.

### Design decision — scoping pattern (unchanged from Phase 2)

Every new skill reuses the `{ENTITY_ID}` + `{FUND_IDS}` placeholder contract established in `fund_ratios.md`:

- `{ENTITY_ID}` = the **fund manager's entity** (the tenant). NOT the LP's entity.
- `{FUND_IDS}` = the set of fund ids this LP can access, **pre-computed by `LpChatProvider#accessible_funds`** which applies the full `ForInvestor` + `AccessRight` + `InvestorAccess.approved` chain.

Therefore **no skill needs extra access-rights joins** — fund-id filtering is already access-gated upstream. Skills only need to add domain-specific filters.

### Design decision — per-skill extra filters raw SQL must add

Rails default scopes don't apply to raw SQL emitted by the LLM. Skills that touch the following tables MUST add explicit filters:

| Table | Required filter | Reason |
|-------|-----------------|--------|
| `portfolio_investments` | `pi.proforma = false` | Rails default_scope not honored in raw SQL |
| `portfolio_investments` / `aggregate_portfolio_investments` (investor-context) | `f.show_portfolios = true` | Pundit investor-role gate, see [portfolio_investment_policy.rb:4-5](app/packs/funds/portfolios/policies/portfolio_investment_policy.rb#L4-L5) |
| Any table | `deleted_at IS NULL` | Soft-delete |
| `fund_ratios` | `scenario = 'Default'` | Exclude what-if scenarios |

### Design decision — portfolio_companies data model (critical gotcha)

A "portfolio company" is **not its own table** — it is an `investors` row whose `investor_entity_id` points to the portco's own entity. `portfolio_investments` is a **transaction log** (one row per buy/sell/round), not a portco list. Scoping chain for LP queries:

```
LP (via {FUND_IDS})
  → portfolio_investments.fund_id
  → portfolio_investments.portfolio_company_id
  → investors.id   ← the portco; investor_name is the display name
```

For portco-level performance: `fund_ratios.owner_type = 'PortfolioCompany'` and `fund_ratios.owner_id = investors.id`.

**Worked example — Arjun Gupta, Growth Fund (fund_id=9), Caphive FM (entity_id=1):**

Sample `portfolio_investments` rows (abridged):

| id | entity_id | fund_id | portfolio_company_id | portfolio_company_name | investment_date | amount_cents | proforma | deleted_at |
|----|-----------|---------|----------------------|------------------------|-----------------|--------------|----------|------------|
| 501 | 1 | 9 | 101 | Acme Corp | 2023-06-01 | 50,000,000 | false | NULL |
| 502 | 1 | 9 | 101 | Acme Corp | 2024-09-15 | 30,000,000 | false | NULL |
| 503 | 1 | 9 | 102 | BetaTech | 2024-01-20 | 25,000,000 | false | NULL |
| 504 | 1 | 9 | 103 | GammaLabs | 2025-03-10 | 40,000,000 | false | NULL |
| 505 | 1 | 9 | 104 | OldCo | 2021-01-10 | 10,000,000 | false | **2025-12-01** |
| 506 | 1 | 9 | 105 | TestCo | 2026-01-01 | 20,000,000 | **true** | NULL |

Listing portcos → must use `DISTINCT` (Acme has two rows = two rounds), must drop row 505 (soft-deleted) and row 506 (proforma scenario).

### Reference SQL — portfolio_companies.md

**List portcos in Growth Fund (client query #4):**

```sql
SELECT DISTINCT
  i.id            AS portco_id,
  i.investor_name AS portco_name,
  f.name          AS fund_name
FROM portfolio_investments pi
JOIN funds     f ON f.id = pi.fund_id
JOIN investors i ON i.id = pi.portfolio_company_id
WHERE pi.entity_id = {ENTITY_ID}
  AND pi.fund_id IN ({FUND_IDS})
  AND f.name LIKE '%Growth%'
  AND f.show_portfolios = true
  AND pi.proforma = false
  AND pi.deleted_at IS NULL
  AND f.deleted_at IS NULL
ORDER BY i.investor_name
```

**MOIC for all portcos in Growth Fund (client query #5 — cross-skill join with fund_ratios):**

```sql
SELECT
  i.investor_name  AS portco_name,
  fr.display_value AS moic,
  fr.end_date
FROM fund_ratios fr
JOIN investors i              ON i.id = fr.owner_id
JOIN portfolio_investments pi ON pi.portfolio_company_id = i.id
JOIN funds f                  ON f.id = pi.fund_id
WHERE fr.entity_id = {ENTITY_ID}
  AND fr.fund_id IN ({FUND_IDS})
  AND fr.owner_type = 'PortfolioCompany'
  AND fr.name = 'MOIC'
  AND fr.latest = true
  AND fr.scenario = 'Default'
  AND f.name LIKE '%Growth%'
  AND f.show_portfolios = true
  AND pi.proforma = false
  AND fr.deleted_at IS NULL
  AND pi.deleted_at IS NULL
GROUP BY i.id, i.investor_name, fr.display_value, fr.end_date
ORDER BY i.investor_name
```

### Per-skill build notes (next-session prep)

Each skill file follows the same shape as `fund_ratios.md`: YAML frontmatter with `name`, `description`, `tables`, then Markdown body with concept, table schemas, CRITICAL rules, example queries, anti-patterns, cross-skill references.

**capital_calls.md**
- Tables: `capital_calls`, `capital_call_investors` (or equivalent per-LP allocation), `funds`, optionally `documents` / `attachments` for the notice PDF
- Concept: a capital call is a drawdown notice issued by the fund; each call has a date, amount, due date, and an attached notice doc. Per-LP due amounts derive from the LP's allocation of the call.
- Critical rules: `fund_id IN ({FUND_IDS})`, scope to the LP's allocation (per-LP due/paid filtering), `deleted_at IS NULL`
- Document ref: return `document_id` / `document_folder_id` pointing at the drawdown notice so `documents.md` can resolve the URL
- Client query covered: #1 "drawdown notice for last call" — ORDER BY call_date DESC LIMIT 1
- Cross-refs: `commitments.md` (for committed amount context), `documents.md` (for the PDF link)

**commitments.md**
- Tables: `capital_commitments`, `funds`
- Concept: an LP's commitment to a fund; a single row per (investor_entity, fund). Called/distributed aggregates may also live here or be computed from calls/distributions.
- Critical rules: scope by LP's own `investor` / entity linkage; `fund_id IN ({FUND_IDS})`; `deleted_at IS NULL`
- Client query covered: dashboard "Committed" card
- Cross-refs: `capital_calls.md`, `distributions.md`, `fund_ratios.md` (for commitment-level ratios — `owner_type = 'CapitalCommitment'`)

**distributions.md**
- Tables: `capital_distributions` (or similar), per-LP allocation table, `funds`
- Concept: payouts from the fund to LPs. Breakdown by type (return of capital, gains, income) may exist.
- Critical rules: same scoping pattern; `deleted_at IS NULL`
- Client query covered: dashboard "Collected" / "Distributed" bars; "total distributions received" questions
- Cross-refs: `commitments.md` (for DPI context), `documents.md` (for distribution notice PDFs)

**portfolio_companies.md**
- Tables: `portfolio_investments`, `investors`, `funds` (and optionally `aggregate_portfolio_investments`, `valuations` for history)
- Concept: portco = `investors` row; `portfolio_investments` is a transaction log; LP sees portcos transitively via fund ownership.
- Critical rules: `DISTINCT` for listing; `pi.proforma = false`; `f.show_portfolios = true`; standard scoping + soft-delete filters. Warn LLM that `portfolio_company_name` on PI is denormalized — prefer joining `investors`.
- Client queries covered: #4 portfolio list, #5 portco MOIC (cross-join with `fund_ratios`)
- Cross-refs: `fund_ratios.md` (for MOIC / IRR of portcos), `documents.md` (for portco reports if applicable)
- Anti-patterns: querying `portfolio_companies` as a table (doesn't exist); forgetting `DISTINCT`; forgetting `show_portfolios` / `proforma`

**documents.md**
- Tables: `documents`, `document_folders`, `attachments` (TBD — confirm actual document model this session OR next)
- Concept: the canonical resolver for any document link. Takes a document reference (id or folder+type) and returns URL + metadata. Also handles direct listing queries ("show all my SOAs").
- Critical rules: scope by LP's accessible folders / funds; access-rights on document entities if applicable
- Client queries covered: #3 SOA ("last quarter Statement for Growth Fund"); also the partner-skill for doc references returned by capital_calls / distributions / commitments.
- Cross-refs: every data skill returns references that `documents.md` resolves
- Open question: exact document model + access-rights layer — to be audited in next session before writing the skill.

### RunQueryTool updates for Phase 4

- Add to `ALLOWED_TABLES`: `portfolio_investments`, `investors`, `capital_calls`, `capital_commitments`, `capital_distributions`, `documents`, `document_folders`, plus any per-LP allocation tables surfaced during skill authoring. Concrete list to be finalized in build session.
- Consider deriving `ALLOWED_TABLES` from the union of `tables:` frontmatter across all skill files, removing the code-change step when adding a new domain.

---

## Session 4 Discussion — 2026-04-20 — Multi-Tenancy Correction + SupportAgent Redesign (DECISIONS PENDING)

### Correction to prior assumption

The multi-tenancy model recorded at the end of Session 3 was **incorrect**. Confirmed with Mohith (product) on 2026-04-20:

- **One LP = one human = one login**, regardless of how many FMs they invest in.
- Caphive **merges investor records across FMs** (keyed on email) behind the scenes into a single investor entity.
- The LP dashboard **shows funds across all FMs the LP has touched** — the unified view is intentional, not a bug.
- The "Emp1 user seeing Golden Angels + Demo Fund" in local dev is the **real production pattern**, not a test artifact.
- **Future UX plan (not yet built):** per-FM subdomain routing (`kedara.caphive.com`) where the dashboard defaults scope to one FM with a dropdown to switch. Out of scope for now.

### What this breaks in the current Phase 2 implementation

1. **`LpChatProvider#accessible_funds`** uses `Fund.for_investor(user).where(entity_id: support_agent.entity_id)` — the `entity_id` filter restricts to one FM's funds. An LP with cross-FM funds silently loses the rest.
2. **`{ENTITY_ID}` placeholder** assumes a single FM entity — invalid for cross-FM LPs.
3. **`SupportAgentPolicy#show?`** logic is tied to a single-entity agent — conceptually misaligned with a cross-FM LP Assistant.

Good news: `Fund.for_investor(user)` already walks the full `AccessRight` + `InvestorAccess.approved` chain across entities correctly — the LP-level access-rights plumbing does NOT need to change; only how the assistant consumes it.

### Billing question (raised — pending commercial decision)

Because an LP's assistant may touch multiple FMs' data in a single conversation, **who pays for the LLM tokens?** `LlmService.ruby_llm_chat(entity: @support_agent.entity)` today uses the agent's entity as the credential source. Three billing models were discussed:

| Model | Description | Pros | Cons |
|-------|-------------|------|------|
| **A — Caphive absorbs** | Platform master key on a "Caphive Platform" entity. Recovered via FM subscription tier. | Simplest; standard SaaS pattern; no attribution logic. | Caphive bears variable cost. |
| **B — Per-FM enablement** | Only FMs that pay for AI have their funds included in LP Assistant scope. Disabled FMs' funds filtered out. | Clean commercial alignment. | Degraded LP UX if some FMs aren't enabled; cross-FM attribution still arbitrary. |
| **C — Caphive pays, bills FMs back monthly** | Telemetry logs `funds_touched` per query; aggregated monthly into per-FM invoice. | Fair attribution. | Most infra to build; overkill until spend is material. |

**Recommendation (pending Mohith's confirmation):** start with **Model A** + day-1 telemetry, migrate to Model B when token spend justifies commercial separation.

### SupportAgent configuration options — three paths

**Option 1 — Make `entity_id` nullable (schema migration).**
- `change_column_null :support_agents, :entity_id, true`
- `belongs_to :entity, optional: true`
- Policy + nil-safety audit across every `support_agent.entity` / `support_agent.entity_id` call site (see impact list below).
- Pros: semantically honest.
- Cons: touches schema, policy, and nil-dereference risk across many files.

**Option 2 — Dedicated "Caphive Platform" entity row (no schema change).**
- `Entity.create!(name: "Caphive Platform", ...)` — global LP agents point at it.
- `support_agent.entity_id = <platform entity id>` — always non-null, non-FK-violating.
- LLM key lives on that entity.
- Policy: widen `show?` for `agent_type == "LpAssistantAgent"` such that any LP with at least one approved `InvestorAccess` anywhere can access it.
- `LpChatProvider`: drop `.where(entity_id: support_agent.entity_id)` — `Fund.for_investor(user)` is the only gate.
- Pros: zero migration; preserves existing `belongs_to` plumbing; LLM key lookup works unchanged.
- Cons: a harmless-but-fake entity row sits in the table.

**Option 3 — Add a `scope` flag column + make entity_id nullable (hybrid of 1 + readability).**
- Migration adds `scope` enum (`"local"` / `"global"`), nullable `entity_id`.
- Model validates: `scope == "local"` requires `entity_id`; `scope == "global"` allows nil.
- Policy branches on `scope`.
- Pros: self-documenting; future-proof.
- Cons: larger change; still requires the nil-safety audit.

### Impact audit — `support_agent.entity` dereferences

Call sites that will break if the agent's entity is nil or missing (relevant to Options 1 and 3):

- [generic_chat_agent.rb:57](app/packs/ai/support_agents/services/generic_chat_agent.rb#L57) — `entity: @support_agent.entity` → LLM credential lookup
- [support_agent_service.rb:35](app/packs/ai/support_agents/services/support_agent_service.rb#L35) — same
- [portfolio_report_agent.rb:294,1155](app/packs/ai/support_agents/services/portfolio_report_agent.rb#L294) — same
- [fund_stats_agent.rb:45,90,99](app/packs/funds/funds/services/fund_stats_agent.rb#L45) — `.entity.investors / .investor_kycs / .documents.generated`
- [fund_stats_mailer/fund_stats_update.html.erb:14](app/packs/funds/funds/views/fund_stats_mailer/fund_stats_update.html.erb#L14) — `@support_agent.entity.name`
- [support_agent_job.rb:71,102,122](app/packs/ai/support_agents/jobs/support_agent_job.rb#L71) — `.entity` and `.entity_id`
- [default_chat_provider.rb:11](app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb#L11) + peers — already uses `support_agent.entity&.name || 'the organization'` nil-safe pattern (good template)

Option 2 avoids this audit entirely by keeping a real entity row at all times.

### Scoping placeholder redesign (implied by multi-FM correction)

Whatever SupportAgent option is chosen, the **skill-file placeholder contract needs to evolve**:

- Drop `{ENTITY_ID}` from fund-scoped skills (`fund_ratios`, `capital_calls`, `commitments`, `distributions`, `portfolio_companies`). `fund_id IN ({FUND_IDS})` is sufficient — the fund_id list already gates across FMs correctly, and every fund belongs to exactly one FM, so `entity_id` is transitively implied.
- Introduce `{USER_ENTITY_ID}` (singular — the LP's own investor entity) for LP-personal skills (`kyc`, personal documents) where scoping is by the LP's own record, not by fund.
- Update `RunQueryTool` placeholder-required check to accept `{FUND_IDS}` alone for fund-scoped queries.
- Update `fund_ratios.md` examples to drop the `fr.entity_id = {ENTITY_ID}` line.

### Status: PENDING CONFIRMATION WITH MOHITH

None of the above is locked. The following decisions are pending a product discussion:

1. **SupportAgent architecture choice:** Option 1, 2, or 3? (Recommend Option 2 — least disruptive.)
2. **Billing model:** A, B, or C? (Recommend A with telemetry for now.)
3. **Per-FM dropdown UX:** build now, or defer until the subdomain-routing feature ships?
4. **Scope of `Fund.for_investor`** when `scope == "global"`: does it stay as-is (all FMs the LP can access) or gain any FM-filter hook for the future dropdown?

Sampada will discuss these with Mohith; decisions get recorded in a Session 5 section before implementation.

### Tuesday demo target (interim — does NOT wait for the above decisions)

Sampada's focus for the 2026-04-21 demo:

1. **SOA skill** (`documents.md` — at minimum the "show me my last Statement of Account" path). This is the most-requested client query.
2. **Fund ratios** — already live; verify it still works after the `chart_rendering_prompt` typo fix.
3. **Scoping for the demo**: acceptable to demo with current single-FM scoping (logged-in LP happens to have funds under one FM in the demo data). The cross-FM correctness fix lands after Mohith's decisions.

Nothing in the Phase 4 skill-set design from Session 3 is invalidated by this session — only the agent-configuration layer above it. Skill file authoring can proceed.

---

## Continuing Next Session (Phase 4 build)

**Before implementation:**
1. Confirm SupportAgent architecture with Mohith (Option 1 / 2 / 3) and billing model (A / B / C). Record decisions in a Session 5 section.
2. Apply the scoping placeholder redesign (drop `{ENTITY_ID}`, add `{USER_ENTITY_ID}`) — or decide to defer.

**Implementation order (post-decisions):**
1. Audit exact schemas for: `capital_calls` + allocation table, `capital_commitments`, `capital_distributions` + allocation table, `documents` / `document_folders` model.
2. Author `documents.md` first (Tuesday demo priority — SOA query).
3. Author `capital_calls.md` (Fireside query #1: drawdown notice).
4. Author `commitments.md` and `distributions.md` — share structural shape with capital_calls.
5. Author `portfolio_companies.md` using the reference SQL already in this doc.
6. Extend `RunQueryTool::ALLOWED_TABLES` (or move to frontmatter-derived list).
7. Phase 3 carryover — render `_chat_panel` on `_vc_dashboard.html.erb` so LP lands directly on chat.

**Demo-day interim (2026-04-21):**
- Ship `documents.md` for SOA retrieval.
- Verify `fund_ratios.md` still works after the `chart_rendering_prompt` typo fix.
- Defer all SupportAgent redesign work until after Mohith's call.

The user (sampada) implements all code changes. Claude's role is to design, guide step-by-step, and provide exact file paths + content. Per CLAUDE.md collaboration mode: **discuss and align on approach first, then provide implementation steps**.

---

## Session 5 — Cross-FM Scoping Shipped (2026-04-21, post-demo)

### Decisions from Mohith (WhatsApp, 2026-04-21)

The 3-option SupportAgent redesign documented in Session 4 is **obsolete**. Mohith's answers closed both questions:

1. **"No most [support agents] are per entity"** → SupportAgent stays per-entity. **Option A** (Caphive Platform entity with a global SupportAgent row) is KILLED. No new global concept. No nullable `entity_id`. No scope flag on SupportAgent.
2. **"They would use our keys"** → LP Assistant billing = **Model A** (Caphive absorbs LLM token cost). No per-FM metering required. Day-1 telemetry counters (`lp_assistant.tokens_total`, `lp_assistant.queries_total` per LP user) remain a nice-to-have for visibility but are not a billback requirement.

`SupportAgent.entity_id` is now explicitly a **routing/config anchor** ("which FM's LP Assistant config does this chat session use?"), NOT a scope gate. Funds visible in the session are determined entirely by `Fund.for_investor(user)`.

### Root cause of the cross-FM bug

Single clause in `LpChatProvider#accessible_funds`:

```ruby
# Before (broken — single FM):
Fund.for_investor(analyst).where(entity_id: support_agent.entity_id).distinct.to_a

# After (cross-FM):
Fund.for_investor(analyst).includes(:entity).distinct.to_a
```

`Fund.for_investor(user)` already traverses `access_rights` + `investor_accesses` and spans every FM entity the LP has approved access with. The extra `.where(entity_id: support_agent.entity_id)` was redundant belt-and-suspenders that silently dropped cross-FM funds. Removed.

### Placeholder semantics widened

| Placeholder | Before | After |
|-------------|--------|-------|
| `{ENTITY_ID}` | Scalar, `= {ENTITY_ID}` | Comma-joined set, `IN ({ENTITY_ID})` — distinct entity_ids across `accessible_funds` |
| `{FUND_IDS}` | Comma-joined set (unchanged) | Same — now naturally spans FMs since `accessible_funds` does |
| `{INVESTOR_IDS}` | Investor rows for `support_agent.entity_id` only | Investor rows for `entity_id IN (accessible_entity_ids)` AND matching `investor_entity_id: analyst.entity_id` — returns e.g. `[301, 402]` for an LP with one row in Kedara's books and one in Fireside's |

`RunQueryTool#validate` still REQUIRES the `{ENTITY_ID}` placeholder (defense-in-depth against polymorphic owner mix-ups and missing scope). Substitution is comma-joined integer cast; empty `{INVESTOR_IDS}` becomes literal `NULL` → `IN (NULL)` → zero rows (safe default).

### Grouped-by-FM context block

`LpChatProvider#build_context` now groups accessible funds by their FM entity so the LLM can answer "Kedara funds only" questions without ever writing a literal `entity_id`:

```
## Investor
Name: Jane Doe
Accessible FM entity_ids: 100, 200

## Accessible Funds (grouped by Fund Manager)

### Kedara Ventures (entity_id: 100)
- Kedara Growth Fund (fund_id: 11, currency: INR)
- Kedara Seed Fund  (fund_id: 12, currency: INR)

### Fireside Capital (entity_id: 200)
- Fireside Seed II (fund_id: 33, currency: USD)

## LP Org Investor IDs (use in {INVESTOR_IDS} placeholder)
investor_ids: 301, 402
```

`accessible_funds` uses `.includes(:entity)` to avoid N+1 on the FM name/id lookup.

### SCOPE vs NARROW — two-layer filtering (added to system prompt)

Problem: "What are the IRR for Kedara funds?" — how does the LLM narrow without breaking the security model?

Solution: **two separate filter layers** in the same SQL query:

```sql
-- Trusted SCOPE (security ceiling — never drop)
WHERE fr.entity_id IN ({ENTITY_ID})
  AND fr.fund_id   IN ({FUND_IDS})
  AND fr.investor_id IN ({INVESTOR_IDS})

-- LLM-written NARROW (user intent — literal ids from grouped context)
  AND fr.fund_id IN (11, 12)   -- the fund_ids listed under "### Kedara Ventures"
```

Rules (encoded in the system prompt):
- Trusted placeholders are never narrowed or dropped.
- For FM-level narrowing, pick fund_ids under that FM's heading in the context — **never** write `entity_id = 100`.
- Intersection keeps it safe: if the LLM tries to widen beyond the placeholder set, the trusted `IN ({FUND_IDS})` still filters it out.
- If the LP asks about ALL their funds, skip the narrow — `{FUND_IDS}` alone covers everything.

### Tool kwarg rename

Both `RunQueryTool` and `DocumentUrlTool` switched from `entity_id:` (scalar) to `entity_ids:` (array). `DocumentUrlTool#find_scoped_document` uses `where(entity_id: @entity_ids, ...)` — ActiveRecord automatically expands to `IN (?)`.

### Skills migration

All 6 runtime skills replaced `= {ENTITY_ID}` with `IN ({ENTITY_ID})`:

```
fund_ratios.md, commitments.md, capital_calls.md, distributions.md, portfolio.md, documents.md

(`soa.md` merged into unified `documents.md` — 2026-04-22. The unified skill covers SOA + drawdown notices + distribution notices + fund data room + fund reports + recent-docs browsing via six filter-signature patterns over the same polymorphic `documents` table. Rationale: LPs see one mixed document stream on the dashboard, not per-type silos.)
```

(`sed -i 's/= {ENTITY_ID}/IN ({ENTITY_ID})/g'` on the skills directory. Verified: 0 `= {ENTITY_ID}` remaining, 45 `IN ({ENTITY_ID})` across all skills.)

### Session 5 status

- Code: `lp_chat_provider.rb`, `run_query_tool.rb`, `document_url_tool.rb` — done.
- Skills: all 6 migrated to IN-list syntax — done.
- SKILL.md + memory updated — done.
- **Still pending:** end-to-end test with an LP who has funds under 2 FMs; Phase 3 chat panel on `_vc_dashboard.html.erb`; audit logging / telemetry counters for Model A billing visibility.

---

## Session 6 — Unified `documents` skill + multi-owner `DocumentUrlTool` (2026-04-22)

### What changed

- **Merged `soa.md` into `documents.md`.** Rationale: the LP dashboard already shows a mixed document stream (`capital_commitment.docs_for_investor` — generated-approved SOAs + user uploads + untagged). Splitting the assistant per document type would fight the LP's mental model and force the LLM to route ambiguous asks ("show me my last document") to the wrong skill. One skill = one top-down routing decision, with 6 filter-signature patterns below.
- **Patterns in `documents.md`:**
  1. SOA / Statement of Account (`owner_type='CapitalCommitment'` + 5-marker)
  2. Drawdown / Capital Call Notice (`owner_type='CapitalCall'`)
  3. Distribution Notice / Payment Advice (`owner_type='CapitalDistribution'` / `CapitalDistributionPayment`)
  4. Fund Data Room (`owner_type='Fund'`, folder subtree of `funds.data_room_folder_id`)
  5. Fund Report / Update (`owner_type='Fund'`, outside Data Room, name-hint filters)
  6. Recent / Unified (union across owner types, no `owner_type` filter)
- **`DocumentUrlTool` extended to multi-owner.** Previous version hard-joined `capital_commitments` and returned nil for Fund/Call/Distribution docs. New version:
  - Loads the `Document` row, checks `entity_id IN @entity_ids` + `deleted_at IS NULL`.
  - Rejects unsupported `owner_type` (`SUPPORTED_OWNER_TYPES = %w[CapitalCommitment CapitalCall CapitalDistribution Fund]`).
  - Calls `accessible?(doc)` which branches per owner_type: each branch re-verifies against `@accessible_fund_ids` (and `@accessible_investor_ids` for `CapitalCommitment`). Uses `.exists?` — no row hydration.
  - `Fund` branch: `Fund.where(id: doc.owner_id, deleted_at: nil).exists?(id: @accessible_fund_ids)` — Rails chains the two `id` conditions, producing the intersection.
- **Relaxed empty-investor_ids guard.** `@accessible_investor_ids.empty?` no longer short-circuits the whole tool — Fund/Call/Distribution docs don't need it. SOA path still fails closed because `investor_id IN (NULL)` returns zero rows.

### Test cases (Rails console) — DocumentUrlTool × 6 patterns

Use a real LP with accessible funds. Example: LP 49, entity 157, fund 11.

```ruby
# 1. Bootstrap provider + tool
support_agent = SupportAgent.find_by(agent_type: 'LpAssistantAgent')
lp            = User.find(49)                  # or find_by(email: ...)

provider = LpChatProvider.new(
  support_agent: support_agent,
  target:        lp,
  analyst:       lp
)

accessible_fund_ids     = provider.send(:accessible_funds).map(&:id)
accessible_entity_ids   = provider.send(:accessible_entity_ids)
accessible_investor_ids = provider.send(:accessible_investor_ids)

tool = DocumentUrlTool.new(
  entity_ids:              accessible_entity_ids,
  accessible_fund_ids:     accessible_fund_ids,
  accessible_investor_ids: accessible_investor_ids
)
```

**Test 1 — SOA (`owner_type='CapitalCommitment'`)**

```ruby
soa = Document.joins('JOIN capital_commitments cc ON cc.id = documents.owner_id')
              .where(owner_type: 'CapitalCommitment', owner_tag: 'Generated',
                     approved: true, template: false, deleted_at: nil)
              .where(cc: { fund_id: accessible_fund_ids,
                           investor_id: accessible_investor_ids })
              .last
puts tool.execute(document_id: soa.id)
# Expected: signed S3 URL
```

**Test 2 — Capital Call Notice (`owner_type='CapitalCall'`)**

```ruby
good_call = CapitalCall.where(fund_id: accessible_fund_ids, deleted_at: nil).first
cc_doc    = Document.where(owner_type: 'CapitalCall', owner_id: good_call.id,
                           deleted_at: nil).last
puts tool.execute(document_id: cc_doc.id)
# Expected: signed S3 URL
```

**Test 3 — Distribution Notice (`owner_type='CapitalDistribution'`)**

```ruby
good_dist = CapitalDistribution.where(fund_id: accessible_fund_ids, deleted_at: nil).first
dist_doc  = Document.where(owner_type: 'CapitalDistribution', owner_id: good_dist.id,
                           deleted_at: nil).last
puts tool.execute(document_id: dist_doc.id)
# Expected: signed S3 URL
```

**Test 4 — Fund Data Room (`owner_type='Fund'`)**

```ruby
fund_doc = Document.where(owner_type: 'Fund', owner_id: accessible_fund_ids,
                          deleted_at: nil).last
puts tool.execute(document_id: fund_doc.id)
# Expected: signed S3 URL
```

**Test 5 — Fund Report / Update (same owner_type as Data Room — differs by folder path)**

Same as Test 4 structurally; filter on folder name in the skill query, not in the tool.

**Test 6 — Negative: doc from an inaccessible fund**

```ruby
other = Document.where(owner_type: 'CapitalCall', deleted_at: nil)
                .where.not(owner_id: CapitalCall.where(fund_id: accessible_fund_ids)
                                                .pluck(:id))
                .first
puts tool.execute(document_id: other.id)
# Expected: "Document <id> not found or not accessible."
```

**Test 7 — Unsupported owner_type**

```ruby
weird = Document.where.not(owner_type: %w[CapitalCommitment CapitalCall
                                          CapitalDistribution Fund]).first
puts tool.execute(document_id: weird.id) if weird
# Expected: "Document <id> not found or not accessible."
```

**Test 8 — Document with no file attached**

```ruby
orphan = Document.where(owner_type: 'Fund', owner_id: accessible_fund_ids,
                        deleted_at: nil)
                 .find { |d| d.file.blank? }
puts tool.execute(document_id: orphan.id) if orphan
# Expected: "Document <id> has no file attached."
```

### Gotcha observed during verification (2026-04-22)

First run picked `Document.where(owner_type: 'CapitalCall').last` — which returned doc 38, a capital-call doc in a fund the LP 49 does NOT have a commitment in. The tool correctly rejected it as "not found or not accessible". **Always intersect with `accessible_fund_ids` when choosing a test document** — otherwise a rejection will look like a tool bug when it's actually the security contract firing correctly.

### Session 6 status

- `documents.md` — written, 6 patterns covered.
- `DocumentUrlTool` — extended to 4 owner_types, `.exists?` based, rubocop-clean.
- `soa.md` — **pending deletion** (do after live smoke test confirms `documents.md` routes correctly).
- End-to-end verified: SOA + Fund + CapitalCall + CapitalDistribution paths + negative case.
- **Still pending:** delete `soa.md`; Phase 3 chat panel on `_vc_dashboard.html.erb`; audit logging; the 2-FM cross-FM end-to-end.

