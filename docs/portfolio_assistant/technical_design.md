# Portfolio Assistant — Technical Design

## Overview

The Portfolio Assistant is a floating chat bubble UI for the FM portal that answers questions about portfolio companies. It is implemented as a thin **adapter** that bridges two existing AI systems in this codebase:

- the older `BaseAssistant` pattern in [app/packs/ai/assistants/](../../app/packs/ai/assistants/) — already houses `PortfolioCompanyAssistant` (single-company) and `PortfolioAssistant` (cross-company), each with a 13-tool RubyLLM agent;
- the newer support_agents framework in [app/packs/ai/support_agents/](../../app/packs/ai/support_agents/) — provides the floating chat panel UI, per-tenant model selection, and `GenericChatAgent` orchestrator that LP Assistant and Cash Flow Assistant already use.

The adapter ([app/packs/ai/support_agents/services/chat_providers/portfolio_assistant_chat_provider.rb](../../app/packs/ai/support_agents/services/chat_providers/portfolio_assistant_chat_provider.rb)) lets the support_agents harness drive the existing portfolio assistants without modifying their tools, prompts, data managers, or chat orchestration.

This design has two core properties:

1. **Adapter-only.** No tool, prompt, data-manager, or `BaseAssistant#run` changes. The adapter exposes `system_prompt` and `tools` to the harness, and the harness drives the LLM loop.
2. **One agent type, two modes.** A single `SupportAgent::AGENT_TYPES` entry (`PortfolioAssistantAgent`) covers both single-company and cross-company chats. The split happens at chat-open time, decided by the `chattable` (target) the dashboard view passes to the chat panel.

## File map

| Path | Role |
|---|---|
| [app/packs/ai/support_agents/services/chat_providers/portfolio_assistant_chat_provider.rb](../../app/packs/ai/support_agents/services/chat_providers/portfolio_assistant_chat_provider.rb) | The adapter. Delegates `tools` and `system_prompt` to a memoized wrapped assistant; routing decided by `target` type. |
| [app/packs/ai/assistants/services/portfolio_company_assistant.rb](../../app/packs/ai/assistants/services/portfolio_company_assistant.rb) | Wrapped in single mode. Initialized with `portfolio_company:`. 13 tools in `PortfolioCompanyAssistantTools::*`. |
| [app/packs/ai/assistants/services/portfolio_assistant.rb](../../app/packs/ai/assistants/services/portfolio_assistant.rb) | Wrapped in cross mode. Initialized without a portfolio_company. 13 tools in `PortfolioAssistantTools::*`. |
| [app/packs/ai/assistants/services/base_assistant.rb](../../app/packs/ai/assistants/services/base_assistant.rb) | Parent class for both. Owns the `run` / `run_report` / `find_or_create_chat` paths used by the full-page UI and batch report job — **not** used by the chat bubble. |
| [app/packs/ai/support_agents/services/generic_chat_agent.rb](../../app/packs/ai/support_agents/services/generic_chat_agent.rb) | The harness. Resolves the provider, builds a `RubyLLM::Chat`, drives the tool-call loop. |
| [app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb](../../app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb) | Provider base + `resolve()` factory. |
| [app/packs/ai/support_agents/models/support_agent.rb](../../app/packs/ai/support_agents/models/support_agent.rb) | `AGENT_TYPES` registry; `chat_model` per-tenant resolution. |
| [app/packs/core/investors/views/investors/show.html.erb](../../app/packs/core/investors/views/investors/show.html.erb) | Mount point for single-company mode. |
| [app/packs/core/investors/views/investors/_index.html.erb](../../app/packs/core/investors/views/investors/_index.html.erb) | Mount point for cross-company mode. Gated on the Ransack category filter being `"Portfolio Company"` (covers both the visual Filter widget and `RansackQueryBuilder.single`-built URLs). |
| [app/packs/ai/assistants/services/portfolio_assistant_data_manager.rb](../../app/packs/ai/assistants/services/portfolio_assistant_data_manager.rb) | `list_portfolio_investments` — `portfolio_company_id:` made optional after Anthropic-side bug surfaced (see **Known gotchas**). |

## The two parallel AI systems — and why the adapter exists

The codebase has two AI systems that grew at different times under different conventions. Neither is wrong; they were built for different consumer surfaces.

### `app/packs/ai/assistants/` (older)

- `BaseAssistant` parent class with `#run(prompt)` driving its own RubyLLM chat
- Subclasses: `PortfolioCompanyAssistant`, `PortfolioAssistant`, `FundAssistant`, `SpecificFundAssistant`, `CapitalCommitmentAssistant`
- Each has its own `*_data_manager.rb` (active-record-shaped helpers) and 13 `*_tools.rb` files (one tool per file under a per-assistant namespace)
- Chat history written to the `Chat` model with `assistant_type` and `owner` columns
- Launched ad-hoc from controllers (`/assistants/assistant?assistant_type=...&owner_id=...`)
- Default model from class constant `AI_MODEL = ENV.fetch('DEFAULT_MODEL', 'gemini-3-flash')`
- Also runs in batch via [assistant_report_job.rb](../../app/packs/ai/assistants/jobs/assistant_report_job.rb) using `default_report_queries` (e.g. `MONTHLY_REPORT_QUERIES`)

### `app/packs/ai/support_agents/` (newer)

- `SupportAgent` model in the database — one row per (FM entity, agent type)
- `GenericChatAgent` orchestrator builds `RubyLLM::Chat` instances using `support_agent.chat_model`
- Chat providers (e.g. `LpChatProvider`, `CashFlowChatProvider`) supply `system_prompt`, optional `build_context`, and `tools` arrays — but do **not** drive the LLM loop
- Floating chat panel UI ([_chat_panel.html.erb](../../app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb)) with markdown rendering, link sanitization, model selection
- Per-tenant model resolution via `entity_setting.default_llm_model` and per-agent override via `chat_config["model"]`
- Chat history written to `ChatSession` (separate from `Chat`)

### The adapter's job

Treat the two `BaseAssistant` portfolio classes as if they were chat providers:

```
GenericChatAgent → BaseChatProvider.resolve(...) → PortfolioAssistantChatProvider
                                                       │
                                                       │ (memoizes)
                                                       ▼
                                             PortfolioCompanyAssistant.new(...)
                                                       or
                                                  PortfolioAssistant.new(...)
                                                       │
                                                       ▼
                                              .system_prompt → harness
                                              .tools         → harness
```

The harness sees a normal chat provider. The wrapped assistant never knows it's being wrapped — its `tools` and `system_prompt` are read like any other ActiveRecord-style attribute.

## Routing — single vs cross

The mode is decided once per chat by the adapter, based on the `target` passed by the chat panel mount:

```ruby
# portfolio_assistant_chat_provider.rb
def portfolio_company_target?
  target.is_a?(Investor) && target.category == "Portfolio Company"
end

def wrapped_assistant
  @wrapped_assistant ||= if portfolio_company_target?
                           PortfolioCompanyAssistant.new(user: analyst, portfolio_company: target)
                         else
                           PortfolioAssistant.new(user: analyst)
                         end
end
```

Mount sites:

| View | Render gate | `chattable:` | Resulting `target` | Adapter mode |
|---|---|---|---|---|
| Single company show ([show.html.erb](../../app/packs/core/investors/views/investors/show.html.erb)) | `@investor.category == "Portfolio Company"` | `@investor` | `Investor` with `category == "Portfolio Company"` | single |
| Cross-portfolio dashboard ([_index.html.erb](../../app/packs/core/investors/views/investors/_index.html.erb)) | walks `params[:q][:c]` looking for a condition with `name=category, p=eq, value=Portfolio Company` (covers both the visual Filter widget and `RansackQueryBuilder.single`-built URLs from "Actions → Portfolio Dashboard") | `current_user.entity` | `Entity` (FM) | cross |

The `wrapped_assistant` is memoized per chat-provider instance. The harness reads `tools` and `system_prompt` separately, so memoization ensures both calls return work from the same instance and the same `data_manager`.

In single mode, `PortfolioCompanyAssistant`'s system prompt interpolates the company's `investor_name` so the LLM is told explicitly "you are scoped to <company>." This is prompt-level scoping, not server-side enforcement. See **Trust boundaries** below.

## End-to-end request lifecycle

Eight steps from "user clicks send" to "response renders." Each step names the file and approximate line range so a cold reader can navigate without prior context.

### Step 1 — View renders the bubble

Mount sites: [investors/show.html.erb](../../app/packs/core/investors/views/investors/show.html.erb) (single) and [investors/_index.html.erb](../../app/packs/core/investors/views/investors/_index.html.erb) (cross). Each looks up a `SupportAgent` row scoped to `current_user.entity_id`, gates on `enabled` + `chat_enabled?`, and renders [_chat_panel.html.erb](../../app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb) passing the agent row plus a `chattable:` target.

The Stimulus controller [agent_chat_controller.js](../../app/javascript/controllers/agent_chat_controller.js) serializes `chattable_type` (the model class name) and `chattable_id` from the partial's data attributes, and POSTs the user input as JSON.

### Step 2 — Controller entry

[SupportAgentChatsController#create](../../app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb) (lines 26-57):

- `authorize @support_agent, :show?` — Pundit policy on the SupportAgent row.
- `find_chattable` (lines 92-98) — `params[:chattable_type].constantize.find_by(id: params[:chattable_id])`. If either is missing or the constant doesn't resolve, returns `nil`. The controller then falls back to the SupportAgent itself as the target — a defensive default so a misconfigured mount degrades to "no scope" instead of raising.
- Delegates to `GenericChatAgent.call(...)`.

### Step 3 — Harness boots

[GenericChatAgent#initialize_chat](../../app/packs/ai/support_agents/services/generic_chat_agent.rb) (lines 26-39):

- Loads the analyst.
- Finds-or-creates an `AgentChatSession` keyed by `(chattable, support_agent, analyst_id)`.

This is `support_agents`-side persistence and is **distinct** from the `Chat` model used by `BaseAssistant#run` on the full-page UI. Two surfaces, two history tables — see "What was deliberately not changed" below.

### Step 4 — Factory picks the provider

[BaseChatProvider.resolve](../../app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb) (lines 44-57): `case support_agent.agent_type` → `PortfolioAssistantChatProvider.new(support_agent:, target:, analyst:)`.

### Step 5 — Adapter routes single vs cross

[PortfolioAssistantChatProvider](../../app/packs/ai/support_agents/services/chat_providers/portfolio_assistant_chat_provider.rb):

- `mode` is decided once, on first read of `wrapped_assistant`.
- `wrapped_assistant` is **memoized** because the harness asks for `system_prompt` and `tools` separately. Both calls must work off the same instance so they share the same `data_manager` (which itself caches Pundit-scoped relations on its own).
- Logs `[PortfolioAssistantChatProvider] system_prompt for agent #<id>, mode=single|cross` to `log/development.log` — primary diagnostic for routing bugs.

### Step 6 — Harness builds the RubyLLM chat

[GenericChatAgent#setup_ruby_llm_chat](../../app/packs/ai/support_agents/services/generic_chat_agent.rb) (lines 50-65):

```ruby
instructions = provider.system_prompt
instructions += "\n\nCONTEXT:\n#{ctx[:context]}" if ctx[:context].present?

chat = LlmService.ruby_llm_chat(
  entity: @support_agent.entity,
  model: @support_agent.chat_model
)
chat.with_instructions(instructions)
chat.with_tools(*provider.tools) if provider.tools.any?

load_conversation_history(ctx[:chat_session], chat)
```

Critical seam:

- The fresh `RubyLLM::Chat` is built with `model: @support_agent.chat_model` — per-tenant resolution.
- The wrapped `BaseAssistant`'s `AI_MODEL` constant is **never read** on this path. Two separate "model" settings coexist by design.
- `load_conversation_history` (lines 93-97) replays prior `AgentChatMessage`s into the `RubyLLM::Chat` so multi-turn context is preserved across requests — without touching the `Chat` model.

### Step 7 — LLM loop runs

[execute_chat](../../app/packs/ai/support_agents/services/generic_chat_agent.rb) (lines 67-81):

```ruby
response = chat.ask(ctx[:user_message])
```

`RubyLLM::Chat#ask` runs the standard tool-calling loop natively against whatever provider the model maps to (Anthropic, Gemini, OpenAI). Each tool dispatch hits a `PortfolioAssistantTools::*` or `PortfolioCompanyAssistantTools::*` `#execute`, which calls into the wrapped assistant's `data_manager` → ActiveRecord queries scoped by `Pundit.policy_scope`.

Errors are caught at line 78 and logged as `[GenericChatAgent] chat.ask failed: <Class> — <message>`. The user sees a generic "I encountered an error processing your request" string; the real cause is in the log. (Both the `tools.11.custom.description` and the `missing keyword: :portfolio_company_id` bugs we hit during demo testing surfaced this way — see **Known gotchas**.)

### Step 8 — Persist + return

[persist_conversation](../../app/packs/ai/support_agents/services/generic_chat_agent.rb) (lines 83-91): writes two `AgentChatMessage` rows (user + assistant). Controller renders JSON. `_chat_panel` Stimulus controller appends the messages to the bubble's DOM.

### Why the model parameter matters

The model parameter at Step 6 is `support_agent.chat_model`, **not** the wrapped assistant's `AI_MODEL` constant. Per-tenant model selection therefore works without any changes to `BaseAssistant` subclasses — and a tenant on Anthropic surfaces strictness bugs that a tenant on Gemini silently absorbs. See **Known gotchas**.

## Per-tenant model selection

`SupportAgent#chat_model` (defined at [support_agent.rb:50-52](../../app/packs/ai/support_agents/models/support_agent.rb#L50-L52)) resolves in this order:

1. `chat_config["model"]` — per-agent override (JSON column on `support_agents`)
2. `entity.entity_setting.default_llm_model` — FM-wide default
3. `ENV.fetch('DEFAULT_MODEL', 'gpt-4o-mini')` — process-wide fallback

To run a tenant on Claude instead of Gemini, set either of (1) or (2) to a Claude model id (e.g. `claude-opus-4-7`). No code change.

The wrapped `BaseAssistant`'s `AI_MODEL` constant is **only** used by the full-page UI (`AssistantsController` instantiates a fresh `Chat` row with `model: PortfolioCompanyAssistant::AI_MODEL`) and by `AssistantReportJob` (batch report runs through `BaseAssistant#run` → `find_or_create_chat` → `model: self.class::AI_MODEL`). Both paths are deliberately untouched.

## Trust boundaries

| Layer | What it enforces | How |
|---|---|---|
| Tenant (FM) isolation | The chat only sees data for the FM that owns the `SupportAgent` row | `support_agent.entity_id` is the lookup key at mount time; the wrapped assistant's `data_manager` filters all queries by `user.entity_id` |
| Single-company scope (single mode) | The chat answers only about the bound portfolio company | `PortfolioCompanyAssistant`'s `data_manager` is initialized with `portfolio_company:` and pre-applies that filter to every tool call. System prompt also tells the LLM "you are scoped to <name>." |
| Cross-company scope (cross mode) | The chat answers about all companies the user can see | `PortfolioAssistant`'s tools accept `portfolio_company_ids` per call; `data_manager` validates ids belong to the user's entity |

The single-company scope is enforced by the data manager's pre-applied filter — tools cannot accidentally query a different company because the data manager won't let them. The system prompt's "you are scoped to <name>" is a UX hint to the LLM (so it doesn't waste turns trying to discover other companies), not the trust anchor.

The cross-company mode trusts the LLM less — it can pass any `portfolio_company_id` it likes, and the data manager rejects ids outside the user's accessible set. This matches the existing pre-adapter behavior of `PortfolioAssistant`.

## Mount pattern

Both mounts follow the same shape, mirroring [_vc_dashboard.html.erb](../../app/packs/core/entities/views/entities/_vc_dashboard.html.erb#L62-L69) for LP Assistant:

```erb
<% portfolio_agent = SupportAgent.find_by(
     entity_id: <FM_entity_id_for_this_view>,
     agent_type: "PortfolioAssistantAgent",
     enabled: true
   ) %>
<% if portfolio_agent&.chat_enabled? %>
  <%= render "support_agents/chat_panel",
             support_agent: portfolio_agent,
             chattable: <target_for_routing> %>
<% end %>
```

Two gates must both pass for the bubble to render:

- `enabled: true` — column-level on/off
- `chat_enabled?` — JSON `chat_config["enabled"]`, the chat-feature flag specifically

Both are settable from the SupportAgent edit UI without code changes.

For the single-company show page, the mount is wrapped in `<% if @investor.category == "Portfolio Company" %>` so the bubble only appears on portfolio company pages, not on LP, Co-Investor, or Advisor pages (the same `Investor` table holds all of those).

## What was deliberately not changed

| Change considered | Decision | Reason |
|---|---|---|
| Collapse `PortfolioCompanyAssistantTools::*` and `PortfolioAssistantTools::*` into one namespace | Defer | 12 of 13 tools are duplicated; consolidation is mechanical and post-demo cleanup. Avoids touching battle-tested code on the demo path. |
| Replace `AI_MODEL = ENV.fetch(...)` constants with a per-tenant method | Skip | Wrapped assistants' `AI_MODEL` is irrelevant on the chat-bubble path. Changing it would silently shift the full-page UI and batch report job to a different model. |
| Migrate the full-page `/assistants/assistant?...` UI to the bubble | Defer | Old route still works; bubble is additive. Decide whether to retire the full page after a week of bubble usage. |
| Move portfolio chat tools into `app/packs/ai/lp_assistant/tools/`-style skill files | Skip | The user explicitly chose not to introduce skill-based progressive disclosure here. Typed tools stay. |
| Unify `Chat` model and `ChatSession` chat history | Defer | Dual-write is acceptable while usage tells us whether divergence matters. |
| Server-side single-company scope enforcement (vs prompt-level guidance) | Defer | The data manager pre-filter already provides server-side enforcement for tool calls. The "you are scoped to <name>" prompt is a UX optimization for the LLM. Tighten if leaks become real. |

## Verification

### Smoke test — adapter loads and resolver routes correctly

```bash
bundle exec rails runner '
  puts "AGENT_TYPES: #{SupportAgent::AGENT_TYPES.inspect}"
  puts "Provider class loaded: #{PortfolioAssistantChatProvider.ancestors.include?(BaseChatProvider)}"
  agent = SupportAgent.new(agent_type: "PortfolioAssistantAgent")
  provider = BaseChatProvider.resolve(support_agent: agent, target: nil, analyst: nil)
  puts "Resolver picks: #{provider.class.name}"
'
```

Expected:
- `AGENT_TYPES` includes both `LpAssistantAgent` and `PortfolioAssistantAgent`
- `Provider class loaded: true`
- `Resolver picks: PortfolioAssistantChatProvider`

### Mode routing test (manual)

1. Create a `SupportAgent` row from the UI: `agent_type=PortfolioAssistantAgent`, `enabled=true`, `chat_config={"enabled": true, "model": "<chosen model>"}` for the FM entity.
2. Navigate to a portfolio company show page (e.g. `/investors/258`).
3. Click the chat bubble. Watch `log/development.log`:
   ```
   [PortfolioAssistantChatProvider] system_prompt for agent #<id>, mode=single
   ```
4. Navigate to a non-portfolio-company investor show page (LP, Advisor). Confirm the bubble does **not** appear.
5. Navigate to the cross-portfolio dashboard (once Step 6 is mounted). Bubble should render with `mode=cross`.

### Functional test prompts

Single mode:
- "Give me a snapshot of this company." — `GetPortfolioCompanySnapshot`
- "Show me the valuation history." — `ListValuations`
- "Plot a line chart of the valuation over time." — `PlotChartFromQuery` + chart-renderer Stimulus controller
- "What documents do I have for this company?" — `ListDocuments` (link rendering via DOMPurify hook from LP Assistant infra)
- "Show me the cap table for some other company." — scope enforcement

Cross mode:
- "List my portfolio companies." — `ListPortfolioCompanies`
- "Show top 5 portfolio companies by current FMV." — `ListPortfolioCompanies` + aggregation
- "Compare KPIs across all my SaaS-sector companies." — KPI batching workflow

## Known gotchas

Two real bug classes surfaced during demo testing once a tenant was switched from Gemini (`gemini-3-flash`) to Anthropic (`claude-haiku-4-5`). Both apply equally to the wrapped assistants regardless of which surface is calling them — the bubble path just happens to hit them first because it's the only path that uses per-tenant model selection.

### Gotcha 1 — RubyLLM tool descriptions don't inherit across subclasses

The `RubyLLM::Tool` DSL stores `description "..."` as a **class instance variable** on the class itself. Ruby's class instance variables are **not inherited** by subclasses (only true `@@class_vars` and explicitly forwarded ivars are).

In [base_assistant_tools.rb](../../app/packs/ai/assistants/services/base_assistant_tools.rb), `BaseAssistantTools::PlotChart` declares `description "..."` as a class-level DSL call. The portfolio subclasses in [portfolio_company_assistant_tools.rb](../../app/packs/ai/assistants/services/portfolio_company_assistant_tools.rb) and [portfolio_assistant_tools.rb](../../app/packs/ai/assistants/services/portfolio_assistant_tools.rb) override `name` and re-declare `param`s (to mark them `required: true`) but do **not** re-declare `description`. RubyLLM's reflection then returns `nil` for the subclass's description.

| LLM provider | Behavior on `null` tool description |
|---|---|
| Gemini | Tolerates it — `FunctionDeclaration.description` is optional in Gemini's tool schema. Ships the tool with no description. |
| Anthropic | Rejects with `tools.<n>.custom.description: Input should be a valid string`. The whole request fails before any tool runs. |

Fix: every tool subclass must re-declare its own `description` line — even if just copying the parent's text. Already applied to `PortfolioCompanyAssistantTools::PlotChart`, `PortfolioCompanyAssistantTools::PlotChartFromQuery`, `PortfolioAssistantTools::PlotChart`, `PortfolioAssistantTools::PlotChartFromQuery`.

Other subclassed tools in the codebase (`SpecificFundAssistantTools`, `CapitalCommitmentAssistantTools`, `FundAssistantTools`) likely have the same latent bug. They are not on the bubble path today, but will hit it the moment those assistants are adapted as chat providers.

### Gotcha 2 — Cross-mode data manager methods were designed only for single-company calls

`PortfolioAssistantDataManager` (cross mode) inherited some method shapes from per-company callers. `list_portfolio_investments(portfolio_company_id:, ...)` was originally a **required** keyword arg — the typed `ListPortfolioInvestments` tool always supplied it.

When the LLM picks `plot_chart_from_query` with `resource: "portfolio_investments"` (e.g. "plot FMV by portfolio company"), the cross-mode `PlotChartFromQuery#execute` only special-cases `resource == "portfolio_kpis"`. Every other resource falls through to `BaseAssistantTools::PlotChartFromQuery#execute`, which calls `data_manager.send("list_<resource>", query:, scope:, sort:, limit:)` — without `portfolio_company_id`. Result: `ArgumentError — missing keyword: :portfolio_company_id`.

Same bug class as gotcha 1 in the sense that both Gemini and Anthropic hit it, but it only surfaced after fixing gotcha 1 because the request stopped failing earlier in tool validation.

Fix: `portfolio_company_id` is now optional on `list_portfolio_investments`. When nil, the relation is `Pundit.policy_scope(@user, PortfolioInvestment)` unscoped — which is the correct cross-mode behavior. Authorization holds because the policy scope is now applied unconditionally as the base relation, instead of after a `find_by(id: portfolio_company_id)` short-circuit.

Other `PortfolioAssistantDataManager#list_*` methods (`list_valuations`, `list_documents`, etc.) may have the same shape and will fail the same way once the LLM picks them via `plot_chart_from_query`. Address per-resource as you see them in the logs.

## Open follow-ups

1. **Old menu items.** The "Portfolio Assistant" item in the cross-dashboard Actions dropdown and "AI Assistant" in the Misc dropdown of [show.html.erb:93-97](../../app/packs/core/investors/views/investors/show.html.erb#L93-L97) still navigate to `/assistants/assistant?...` full-page. Decide whether to remove after the bubble is bedded in.
2. **Chat history reconciliation.** Decide whether to migrate `Chat` rows (BaseAssistant path) into `AgentChatSession`/`AgentChatMessage` (support_agents path), or vice versa. Currently dual-writes if a user uses both surfaces.
3. **Tool namespace consolidation.** Collapse `PortfolioCompanyAssistantTools::*` and `PortfolioAssistantTools::*` into one namespace once the new framework is bedded in.
4. **Sample question chips.** [support_agent.rb](../../app/packs/ai/support_agents/models/support_agent.rb) does not have a `sample_questions` method. If we want starter chips on the welcome state for `PortfolioAssistantAgent`, add a method that returns suggestions per agent type.
5. **Per-mode tool differences.** `PortfolioCompanyAssistant` has `GetPortfolioCompanySnapshot` (a single-company helper); `PortfolioAssistant` has `ListPortfolioCompanies` (a discovery tool) instead. Otherwise the tool sets overlap. If the consolidated namespace lands, decide whether single mode also gets `ListPortfolioCompanies` (lets the LLM answer "compare this company with my other SaaS companies" in-context).
6. **Audit other `BaseAssistant` subclasses for the description-inheritance bug.** Mechanical sweep: any tool class that inherits from a `BaseAssistantTools::*` parent and doesn't re-declare its own `description` will fail on Anthropic. Five tool files to check (`specific_fund_*`, `capital_commitment_*`, etc.).
7. **Audit other cross-mode data manager `list_*` methods for the required-`portfolio_company_id` shape.** Same fix pattern applies — relax to optional and unconditionally apply Pundit policy scope.
