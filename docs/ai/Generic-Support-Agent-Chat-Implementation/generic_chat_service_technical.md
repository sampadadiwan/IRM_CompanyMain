# Generic Chat Service — Technical Documentation

**Version:** 1.0
**Date:** 2026-02-23
**Pack:** `app/packs/ai/`
**Branch:** `feature/combined_agent_cash_flow`

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Core Components](#3-core-components)
4. [Data Models](#4-data-models)
5. [The GenericChatAgent Pipeline](#5-the-genericchatagent-pipeline)
6. [Chat Provider System](#6-chat-provider-system)
7. [LLM Integration Layer](#7-llm-integration-layer)
8. [API Endpoints](#8-api-endpoints)
9. [Frontend: Stimulus Controller](#9-frontend-stimulus-controller)
10. [Embedding in a New Support Agent](#10-embedding-in-a-new-support-agent)
11. [Conversation Persistence & Memory](#11-conversation-persistence--memory)
12. [Polymorphic Target Design](#12-polymorphic-target-design)
13. [Configuration Reference](#13-configuration-reference)
14. [File Reference](#14-file-reference)

---

## 1. Overview

The **Generic Chat Service** provides a reusable, domain-agnostic conversational AI interface that can be embedded into any Support Agent in the Caphive IRM platform. It is built on top of:

- **Trailblazer Operations** — pipeline-based service composition
- **Langchain::Assistant** — stateful, tool-aware LLM conversation management
- **Polymorphic Sessions** — one `AgentChatSession` per `(analyst, support_agent, chattable)` triple
- **Chat Providers** — pluggable domain context injectors that customise system prompts, build context payloads, and attach tools per agent type

The same `GenericChatAgent` Trailblazer operation handles the full chat lifecycle for every support agent. Domain specialisation lives entirely in the **Chat Provider** layer, not in the agent operation itself.

---

## 2. Architecture Diagram

```
Browser / Stimulus Controller (agent_chat_controller.js)
         |
         | POST /support_agents/:id/chats
         v
SupportAgentChatsController
         |
         | GenericChatAgent.call(...)
         v
┌──────────────────────────────────────────────────────┐
│                   GenericChatAgent                    │
│              (Trailblazer Operation)                  │
│                                                      │
│  Step 1: initialize_chat                             │
│    ├─ Load SupportAgent                              │
│    ├─ Load analyst (User)                            │
│    ├─ Resolve chattable (polymorphic target)         │
│    └─ find_or_create AgentChatSession                │
│                                                      │
│  Step 2: resolve_provider                            │
│    └─ BaseChatProvider.resolve(agent, target, user)  │
│         ├─ CashFlowChatProvider                      │
│         ├─ CallNoticeChatProvider                    │
│         ├─ PortfolioReportChatProvider               │
│         └─ DefaultChatProvider (fallback)            │
│                                                      │
│  Step 3: setup_langchain_assistant                   │
│    ├─ LlmService.langchain_llm(entity:)              │
│    ├─ provider.system_prompt                         │
│    ├─ provider.build_context  (injected into prompt) │
│    ├─ provider.tools          (Langchain tool list)  │
│    └─ Load previous AgentChatMessages into assistant │
│                                                      │
│  Step 4: execute_chat                                │
│    ├─ assistant.add_message(content: user_message)   │
│    └─ assistant.run(auto_tool_execution: true)       │
│                                                      │
│  Step 5: persist_conversation                        │
│    ├─ AgentChatMessage(role: 'user', ...)            │
│    └─ AgentChatMessage(role: 'assistant', ...)       │
└──────────────────────────────────────────────────────┘
         |
         | { success, response, session_id }
         v
Browser / Stimulus Controller
```

---

## 3. Core Components

### 3.1 `GenericChatAgent`
**File:** [app/packs/ai/support_agents/services/generic_chat_agent.rb](app/packs/ai/support_agents/services/generic_chat_agent.rb)

The orchestrating Trailblazer operation. Inherits from `SupportAgentService`. It is **agent-agnostic** — it drives the same five-step pipeline regardless of which `SupportAgent` record is used.

### 3.2 `SupportAgentService`
**File:** [app/packs/ai/support_agents/services/support_agent_service.rb](app/packs/ai/support_agents/services/support_agent_service.rb)

Base class for all support agents. Provides shared infrastructure:
- `initialize_agent` — loads the `SupportAgent` record and constructs the LLM client
- `broadcast_step` / `mark_step_*` — ActionCable progress broadcasting
- `generate_progress_reports` — creates/updates `SupportAgentReport` per target

### 3.3 `BaseChatProvider`
**File:** [app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb)

Abstract base for all domain providers. Defines the three-method contract and contains the factory method `BaseChatProvider.resolve(...)`.

### 3.4 `SupportAgentChatsController`
**File:** [app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb](app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb)

Thin HTTP adapter. Accepts `POST /support_agents/:id/chats`, delegates to `GenericChatAgent.call`, and returns JSON.

### 3.5 `AgentChatSession` / `AgentChatMessage`
**Files:**
- [app/packs/ai/support_agents/models/agent_chat_session.rb](app/packs/ai/support_agents/models/agent_chat_session.rb)
- [app/packs/ai/support_agents/models/agent_chat_message.rb](app/packs/ai/support_agents/models/agent_chat_message.rb)

ActiveRecord models that store conversation history. `AgentChatSession` uses a polymorphic `chattable` association so any domain object can host a chat.

### 3.6 `agent_chat_controller.js`
**File:** [app/javascript/controllers/agent_chat_controller.js](app/javascript/controllers/agent_chat_controller.js)

Hotwire Stimulus controller. Manages the chat panel UI, message rendering, history loading, and session clearing.

---

## 4. Data Models

### 4.1 `agent_chat_sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `support_agent_id` | bigint | FK → `support_agents` |
| `analyst_id` | bigint | FK → `users` (the logged-in user) |
| `chattable_type` | string(50) | Polymorphic class name |
| `chattable_id` | bigint | Polymorphic FK |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**Unique index:** `[support_agent_id, chattable_type, chattable_id, analyst_id]`

One session per user × agent × target combination. Reused across page loads to maintain continuity.

### 4.2 `agent_chat_messages`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `agent_chat_session_id` | bigint | FK → `agent_chat_sessions` |
| `role` | string(20) | `"user"` or `"assistant"` |
| `content` | text | Full message text |
| `metadata` | json | Tool call traces, sources, etc. |
| `created_at` | datetime | |

### 4.3 `support_agents`

Relevant columns for chat configuration:

| Column | Type | Notes |
|---|---|---|
| `agent_type` | string(30) | Class name (`"CashFlowAssistantAgent"`) |
| `json_fields` | json | Contains `chat_config` sub-object |

**`chat_config` sub-object (inside `json_fields`):**
```json
{
  "chat_config": {
    "enabled": true,
    "model": "gpt-4o-mini",
    "system_prompt": "Optional override for DefaultChatProvider"
  }
}
```

**Model helpers:**
```ruby
support_agent.chat_config     # => Hash
support_agent.chat_enabled?   # => Boolean
support_agent.chat_model      # => String (model ID, with fallback chain)
```

---

## 5. The GenericChatAgent Pipeline

All steps are Trailblazer `step` declarations. Each receives the context hash `ctx` plus keyword-splat named arguments.

### Step 1 — `initialize_chat`

```ruby
def initialize_chat(ctx, **)
  @support_agent = SupportAgent.find(ctx[:support_agent_id])
  @analyst       = User.find(ctx[:analyst_id])
  @chattable     = ctx[:target]  # polymorphic domain object

  ctx[:chat_session] = AgentChatSession.find_or_create_by!(
    support_agent: @support_agent,
    analyst:       @analyst,
    chattable:     @chattable
  )
end
```

**Side effect:** Creates a persistent session row on first call. Subsequent calls with the same `(analyst, agent, target)` reuse the same session.

### Step 2 — `resolve_provider`

```ruby
def resolve_provider(ctx, **)
  ctx[:provider] = BaseChatProvider.resolve(
    support_agent: @support_agent,
    target:        @chattable,
    analyst:       @analyst
  )
  ctx[:context_payload] = ctx[:provider].build_context
end
```

The provider is resolved by `agent_type` string using a case/when factory inside `BaseChatProvider`. The resolved provider object is stored in context for use in step 3.

### Step 3 — `setup_langchain_assistant`

```ruby
def setup_langchain_assistant(ctx, **)
  llm          = LlmService.langchain_llm(entity: @support_agent.entity)
  provider     = ctx[:provider]
  instructions = provider.system_prompt

  if (context = ctx[:context_payload]).present?
    instructions += "\n\n## Current Context\n#{context}"
  end

  assistant = Langchain::Assistant.new(
    llm:          llm,
    instructions: instructions,
    tools:        provider.tools
  )

  load_conversation_history(ctx[:chat_session], assistant)
  ctx[:assistant] = assistant
end
```

**Conversation history loading:**
```ruby
def load_conversation_history(session, assistant)
  session.agent_chat_messages.order(:created_at).each do |msg|
    role = msg.role == 'assistant' ? gemini_role_or_assistant : msg.role
    assistant.add_message(role: role, content: msg.content)
  end
end
```

> **Note on Gemini role mapping:** Gemini requires `"model"` instead of `"assistant"` for AI turns. The helper detects the active LLM provider and maps accordingly.

### Step 4 — `execute_chat`

```ruby
def execute_chat(ctx, **)
  user_message = ctx[:user_message]

  # Context prefix on first message in session
  if ctx[:chat_session].agent_chat_messages.none? && ctx[:context_payload].present?
    user_message = "#{ctx[:context_payload]}\n\n#{user_message}"
  end

  ctx[:assistant].add_message(content: user_message)
  ctx[:assistant].run(auto_tool_execution: true)

  ctx[:ai_response] = ctx[:assistant].messages.last.content
end
```

`auto_tool_execution: true` means Langchain will call any attached tools automatically and feed results back into the conversation before returning.

### Step 5 — `persist_conversation`

```ruby
def persist_conversation(ctx, **)
  session = ctx[:chat_session]

  session.agent_chat_messages.create!(role: 'user',      content: ctx[:user_message])
  session.agent_chat_messages.create!(role: 'assistant', content: ctx[:ai_response])
end
```

---

## 6. Chat Provider System

### 6.1 Provider Contract

Every provider must implement three methods:

```ruby
class BaseChatProvider
  # @return [String] System prompt injected as the assistant's identity/instructions
  def system_prompt
    raise NotImplementedError
  end

  # @return [String] Domain-specific context appended to system prompt and first message
  def build_context
    raise NotImplementedError
  end

  # @return [Array] Langchain tool instances to attach to the assistant
  def tools
    []
  end
end
```

### 6.2 Factory Method

```ruby
# @param support_agent [SupportAgent]
# @param target [ActiveRecord::Base] polymorphic domain object
# @param analyst [User]
# @return [BaseChatProvider] resolved provider instance
def self.resolve(support_agent:, target:, analyst:)
  provider_class = case support_agent.agent_type
                   when "CashFlowAssistantAgent"  then CashFlowChatProvider
                   when "CallNoticeAgent"          then CallNoticeChatProvider
                   when "PortfolioReportAgent"     then PortfolioReportChatProvider
                   else                                 DefaultChatProvider
                   end

  provider_class.new(support_agent: support_agent, target: target, analyst: analyst)
end
```

### 6.3 `DefaultChatProvider`
**File:** [app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb)

Used as the fallback for any agent that does not have a dedicated provider. Reads `support_agent.chat_config["system_prompt"]` if set; otherwise generates a generic identity prompt.

```ruby
def system_prompt
  custom = support_agent.chat_config&.dig("system_prompt")
  return custom if custom.present?

  "You are a helpful AI assistant for #{support_agent.entity.name}. " \
  "You are acting as the agent: #{support_agent.name}. " \
  "The user is #{analyst.full_name}. Be professional and concise."
end

def build_context = ""
def tools         = []
```

### 6.4 `CashFlowChatProvider`
**File:** [app/packs/ai/support_agents/services/chat_providers/cash_flow_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/cash_flow_chat_provider.rb)

Fetches the latest `SupportAgentReport` records for the target entity and serialises them into a structured markdown context block:

```ruby
def build_context
  reports = SupportAgentReport
    .where(support_agent: support_agent, status: :completed, owner_type: "Fund")
    .order(created_at: :desc)
    .limit(5)

  reports.map do |r|
    fields = r.json_fields || {}
    <<~MARKDOWN
      ## Fund: #{r.owner_name} (Run: #{r.created_at.strftime('%d %b %Y %H:%M')})
      Status: #{r.status}
      Cash Available: #{fields['currency']} #{fields['total_cash']}
      Investments: #{fields['total_investments']}
      Expenses (monthly): #{fields['monthly_expenses']}
      Runway: #{fields['runway_days']} days
      Net Position: #{fields['net_position']}
    MARKDOWN
  end.join("\n")
end
```

### 6.5 Shared Prompt Helpers (on `BaseChatProvider`)

```ruby
# Prevents the model from answering off-topic questions
def strict_scope_prompt
  "Only answer questions that are directly relevant to your designated role. " \
  "If a question is outside your scope, politely decline and redirect."
end

# Instructs the model to render charts as inline HTML
def chart_rendering_prompt
  "When presenting numerical comparisons or trends, render them as " \
  "self-contained HTML <canvas> charts using Chart.js CDN. " \
  "Do not use external image URLs."
end
```

---

## 7. LLM Integration Layer

### 7.1 `LlmService`
**File:** [app/packs/ai/llm_service.rb](app/packs/ai/llm_service.rb)

```ruby
# Returns a Langchain LLM client for use with Langchain::Assistant
# @param entity [Entity] used to resolve entity-level API key overrides
# @param model [String] model identifier; auto-detects provider
# @param temperature [Float] default 0.7
# @param provider [Symbol] :openai | :anthropic | :gemini (auto-detected if nil)
# @return [Langchain::LLM::Base]
LlmService.langchain_llm(entity:, model: nil, temperature: 0.7, provider: nil)
```

**Provider auto-detection via `detect_provider(model)`:**
| Model prefix pattern | Provider |
|---|---|
| `gpt-*`, `o1-*`, `o3-*` | `:openai` |
| `claude-*` | `:anthropic` |
| `gemini-*` | `:gemini` |
| _(default)_ | `:openai` |

**Model resolution for chat agents:**
```
support_agent.chat_model
  → support_agent.json_fields["chat_config"]["model"]  (if present)
  → entity.entity_setting.default_llm_model             (if set)
  → ENV['DEFAULT_MODEL']
```

**Entity-level API key overrides** (via `EntitySetting`):
- `openai_api_key`
- `gemini_api_key`
- `anthropic_api_key`
- `openrouter_api_key`

---

## 8. API Endpoints

All chat endpoints live under the `support_agents` resource in [config/routes/ai.rb](config/routes/ai.rb).

### `POST /support_agents/:support_agent_id/chats`

Send a user message and receive an AI response.

**Request:**
```json
{
  "message":        "What is our cash runway?",
  "chattable_type": "Fund",
  "chattable_id":   42
}
```

**Response (success):**
```json
{
  "success":    true,
  "response":   "Based on the latest run (23 Feb 2026), your cash runway is 180 days...",
  "session_id": 7,
  "message_id": 29
}
```

**Response (failure):**
```json
{
  "success": false,
  "error":   "Chat is not enabled for this agent."
}
```

### `GET /support_agents/:support_agent_id/chats`

Load conversation history for a given target.

**Query params:** `chattable_type`, `chattable_id`

**Response:**
```json
{
  "session_id": 7,
  "messages": [
    { "id": 27, "role": "user",      "content": "...", "created_at": "..." },
    { "id": 28, "role": "assistant", "content": "...", "created_at": "..." }
  ]
}
```

### `DELETE /support_agents/:support_agent_id/chats/:id`

Destroy an `AgentChatSession` (and its messages via `dependent: :destroy`).

**Response:** `{ "success": true }`

---

## 9. Frontend: Stimulus Controller

**File:** [app/javascript/controllers/agent_chat_controller.js](app/javascript/controllers/agent_chat_controller.js)

### Values (data attributes)

| Value | Type | Description |
|---|---|---|
| `supportAgentId` | Number | The `SupportAgent` record ID |
| `chattableType` | String | ActiveRecord class name of the host object |
| `chattableId` | Number | ID of the host object |
| `sessionId` | Number | Current `AgentChatSession` ID (set after first load) |
| `expanded` | Boolean | Panel open/closed state |

### HTML Embedding

```html
<div
  data-controller="agent-chat"
  data-agent-chat-support-agent-id-value="<%= support_agent.id %>"
  data-agent-chat-chattable-type-value="Fund"
  data-agent-chat-chattable-id-value="<%= @fund.id %>"
>
  <div data-agent-chat-target="panel">
    <div data-agent-chat-target="messages"></div>
    <textarea data-agent-chat-target="input"></textarea>
    <button data-action="click->agent-chat#sendMessage"
            data-agent-chat-target="sendBtn">Send</button>
  </div>
  <button data-action="click->agent-chat#toggle"
          data-agent-chat-target="toggleBtn">Ask AI</button>
</div>
```

### Key Methods

| Method | Description |
|---|---|
| `connect()` | Initialises resize listeners |
| `toggle()` | Opens/closes panel; loads history on first open |
| `sendMessage()` | POSTs to chat endpoint, renders response |
| `loadHistory()` | GETs conversation history and renders it |
| `clearChat()` | DELETEs session and resets UI |
| `appendMessage(role, content)` | Renders a bubble with lightweight Markdown |

### Markdown Rendering (inline, no library)

```javascript
// Bold, italic, inline code, newlines
content
  .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
  .replace(/\*(.*?)\*/g,     '<em>$1</em>')
  .replace(/`(.*?)`/g,       '<code>$1</code>')
  .replace(/\n/g,            '<br>')
```

Sanitisation strips `<script>`, `<iframe>`, and `<style>` tags before insertion.

---

## 10. Embedding in a New Support Agent

Follow these steps to add chat capability to a new or existing support agent.

### Step 1 — Create a Chat Provider

```ruby
# app/packs/ai/support_agents/services/chat_providers/my_domain_chat_provider.rb

class MyDomainChatProvider < BaseChatProvider
  # @return [String]
  def system_prompt
    base = "You are an AI assistant specialising in #{domain_description}. " \
           "You are helping #{analyst.full_name} at #{support_agent.entity.name}. " \
           "Today is #{Date.current.strftime('%d %b %Y')}.\n\n"
    base + strict_scope_prompt
  end

  # @return [String] Serialised domain context injected before first user message
  def build_context
    # Fetch your domain data and format it
    records = MyDomainModel.where(entity: support_agent.entity).recent
    records.map { |r| "- #{r.name}: #{r.summary}" }.join("\n")
  end

  # @return [Array] Optional Langchain tools
  def tools
    # e.g. [LangchainWebSearchTool.new]
    []
  end

  private

  def domain_description
    "my domain area"
  end
end
```

### Step 2 — Register the Provider in the Factory

**File:** [app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb)

```ruby
def self.resolve(support_agent:, target:, analyst:)
  provider_class = case support_agent.agent_type
                   when "CashFlowAssistantAgent" then CashFlowChatProvider
                   when "CallNoticeAgent"         then CallNoticeChatProvider
                   when "MyNewAgent"              then MyDomainChatProvider  # ← add here
                   else                                DefaultChatProvider
                   end

  provider_class.new(support_agent: support_agent, target: target, analyst: analyst)
end
```

### Step 3 — Register the Agent Type

**File:** [app/packs/ai/support_agents/models/support_agent.rb](app/packs/ai/support_agents/models/support_agent.rb)

```ruby
AGENT_TYPES = [
  # ... existing types
  "MyNewAgent"   # ← add here
]
```

### Step 4 — Enable Chat in the SupportAgent Record

Create or update the `SupportAgent` row with `chat_config` inside `json_fields`:

```ruby
SupportAgent.create!(
  name:        "My Domain Assistant",
  agent_type:  "MyNewAgent",
  entity:      entity,
  json_fields: {
    "chat_config" => {
      "enabled"       => true,
      "model"         => "gpt-4o-mini",
      "system_prompt" => nil   # nil = use provider's system_prompt
    }
  }
)
```

### Step 5 — Add the Chat Panel to the View

In the relevant view (e.g., a Fund show page, a Dashboard, any object page):

```erb
<%# Find the applicable SupportAgent for this entity + agent_type %>
<% chat_agent = SupportAgent.find_by(entity: current_entity, agent_type: "MyNewAgent") %>

<% if chat_agent&.chat_enabled? %>
  <%= render 'shared/agent_chat_panel',
        support_agent: chat_agent,
        chattable:     @my_domain_object %>
<% end %>
```

The partial `shared/agent_chat_panel` wires up the Stimulus controller with the correct data attributes. No additional JavaScript is needed.

### Step 6 — (Optional) Write a Full Agent Operation

If `MyNewAgent` also runs automated analysis (not just chat), create a Trailblazer operation alongside the chat provider:

```ruby
# app/packs/ai/support_agents/services/my_new_agent.rb

class MyNewAgent < SupportAgentService
  step :initialize_agent   # inherited
  step :do_analysis
  step :generate_progress_reports  # inherited

  private

  def do_analysis(ctx, model:, support_agent:, **)
    # domain logic
  end
end
```

The `GenericChatAgent` is called separately for chat turns; the full agent operation is called by `SupportAgentJob` for scheduled/manual runs.

---

## 11. Conversation Persistence & Memory

### Session Lifecycle

```
First message
  → AgentChatSession created (find_or_create_by unique index)
  → History is empty; context payload prepended to first user message

Subsequent messages (same session)
  → Session reused
  → ALL previous AgentChatMessages loaded into Langchain::Assistant
  → Full conversation context sent to the LLM on every turn
```

### History Loading Detail

```ruby
def load_conversation_history(session, assistant)
  session.agent_chat_messages.order(:created_at).each do |msg|
    # Gemini expects "model" role; all others expect "assistant"
    role = if msg.role == 'assistant' && llm_is_gemini?
             'model'
           else
             msg.role
           end
    assistant.add_message(role: role, content: msg.content)
  end
end
```

**Implication:** Token usage grows linearly with conversation length. For high-frequency chats on very long conversations, consider adding a `TRUNCATE_HISTORY_AFTER` constant and only loading the last N messages.

### Session Clearing

`DELETE /support_agents/:id/chats/:session_id` destroys the `AgentChatSession` and cascades to all `AgentChatMessages` (`dependent: :destroy`). The UI clears and the next message starts a fresh session.

---

## 12. Polymorphic Target Design

The `chattable` polymorphic association means the chat can be anchored to **any ActiveRecord model** without schema changes.

```
AgentChatSession
  ├── chattable_type: "Fund"
  │   chattable_id:   42
  │   → context = a specific Fund's data
  │
  ├── chattable_type: "CapitalCall"
  │   chattable_id:   7
  │   → context = a specific CapitalCall's data
  │
  ├── chattable_type: "Entity"
  │   chattable_id:   1
  │   → context = entity-wide data
  │
  └── chattable_type: nil  (global agent chat, no specific target)
```

The provider receives the `target` object and can call any methods on it to build context. The unique session index ensures users do not mix up conversations across different target objects.

---

## 13. Configuration Reference

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DEFAULT_MODEL` | — | Fallback LLM model for all agents |
| `CHAT_AGENT_MODEL` | — | Override model specifically for chat agents |
| `AI_CHECKS_PROVIDER` | `"gemini"` | Provider for non-chat LLM calls |
| `AI_CHECKS_MODEL` | `DEFAULT_MODEL` | Model for non-chat LLM calls |
| `OPENAI_API_KEY` | — | OpenAI credentials |
| `GOOGLE_GEMINI_API_KEY` | — | Google Gemini credentials |
| `ANTHROPIC_API_KEY` | — | Anthropic credentials |
| `OPENROUTER_API_KEY` | — | OpenRouter credentials |
| `GEMINI_FALLBACK_MODEL` | `"gemini-2.5-flash"` | Fallback when Gemini model is deprecated |

### Entity-Level Overrides (`EntitySetting`)

Per-entity API keys take precedence over environment variables, allowing multi-tenant deployments where each entity uses its own LLM account:

```ruby
entity.entity_setting.openai_api_key
entity.entity_setting.gemini_api_key
entity.entity_setting.anthropic_api_key
entity.entity_setting.default_llm_model
```

### SupportAgent `json_fields` Schema (Chat Subset)

```json
{
  "chat_config": {
    "enabled":       true,
    "model":         "gpt-4o-mini",
    "system_prompt": null
  }
}
```

| Key | Type | Description |
|---|---|---|
| `enabled` | Boolean | Master switch for chat on this agent |
| `model` | String \| null | Override LLM model; falls back to entity/env defaults |
| `system_prompt` | String \| null | If set, `DefaultChatProvider` uses this instead of its generated prompt; ignored by specialist providers |

---

## 14. File Reference

### Services
| File | Purpose |
|---|---|
| [app/packs/ai/support_agents/services/generic_chat_agent.rb](app/packs/ai/support_agents/services/generic_chat_agent.rb) | Main chat pipeline (Trailblazer operation) |
| [app/packs/ai/support_agents/services/support_agent_service.rb](app/packs/ai/support_agents/services/support_agent_service.rb) | Base class for all agents |
| [app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb) | Abstract provider + factory |
| [app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb) | Generic fallback provider |
| [app/packs/ai/support_agents/services/chat_providers/cash_flow_chat_provider.rb](app/packs/ai/support_agents/services/chat_providers/cash_flow_chat_provider.rb) | Cash flow domain provider |
| [app/packs/ai/llm_service.rb](app/packs/ai/llm_service.rb) | LLM client factory |
| [app/packs/ai/llm_initializer.rb](app/packs/ai/llm_initializer.rb) | Langchain provider initialiser |

### Models
| File | Purpose |
|---|---|
| [app/packs/ai/support_agents/models/support_agent.rb](app/packs/ai/support_agents/models/support_agent.rb) | SupportAgent AR model |
| [app/packs/ai/support_agents/models/agent_chat_session.rb](app/packs/ai/support_agents/models/agent_chat_session.rb) | Chat session |
| [app/packs/ai/support_agents/models/agent_chat_message.rb](app/packs/ai/support_agents/models/agent_chat_message.rb) | Individual message |
| [app/packs/ai/support_agents/models/support_agent_report.rb](app/packs/ai/support_agents/models/support_agent_report.rb) | Agent run report (context source) |

### Controllers & Routes
| File | Purpose |
|---|---|
| [app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb](app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb) | HTTP adapter for chat API |
| [config/routes/ai.rb](config/routes/ai.rb) | AI pack routes |

### Frontend
| File | Purpose |
|---|---|
| [app/javascript/controllers/agent_chat_controller.js](app/javascript/controllers/agent_chat_controller.js) | Stimulus chat panel controller |

### Migrations
| File | Purpose |
|---|---|
| [db/migrate/20260216062746_add_polymorphic_to_ai_chat_sessions.rb](db/migrate/20260216062746_add_polymorphic_to_ai_chat_sessions.rb) | Adds polymorphic support to AI chat sessions |
