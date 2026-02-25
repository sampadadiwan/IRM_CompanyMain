# Generic Pluggable Chat Agent - Implementation Plan

## Context

We need a generic, pluggable chat system that any SupportAgent can opt into by setting `chat_config.enabled: true` in its `json_fields`. Today, `PortfolioChatAgent` is tightly coupled to `AiPortfolioReport` — we're building a parallel generic system without touching the existing portfolio chat code. First testing will use a `DefaultChatProvider` (basic LLM chat) on any existing SupportAgent record.

**Key insight:** `GenericChatAgent` is a **service**, not an agent_type. Any SupportAgent (KYC, Portfolio, future CashFlow) can have chat enabled. The controller calls `GenericChatAgent.call()` directly — it's never dispatched via `support_agent.agent.constantize`.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         UI Layer                                 │
│                                                                  │
│  _chat_panel.html.erb  (shared partial)                          │
│  agent_chat_controller.js  (shared Stimulus controller)          │
│         │                                                        │
│         │ POST /support_agents/:id/chats                         │
│         ▼                                                        │
│  SupportAgentChatsController  (single controller)                │
│         │                                                        │
│         ▼                                                        │
│  GenericChatAgent  (Trailblazer::Operation)                      │
│  Steps:                                                          │
│    1. initialize_chat                                            │
│    2. resolve_provider  ──►  BaseChatProvider.resolve(...)        │
│    3. setup_langchain_assistant                                  │
│    4. execute_chat                                               │
│    5. persist_conversation                                       │
│         │                                                        │
│         │ delegates to                                           │
│         ▼                                                        │
│  Context Providers  (one per agent domain)                       │
│    ├── DefaultChatProvider      (basic LLM, no tools)            │
│    ├── CashFlowChatProvider     (future - fund data + stress)    │
│    └── PortfolioReportChatProvider  (future - docs + search)     │
│                                                                  │
│  Data Layer                                                      │
│    AiChatSession  (polymorphic: chattable_type/id)               │
│    AiChatMessage  (role, content, metadata) — unchanged          │
│    SupportAgent   (json_fields.chat_config.enabled)              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Files to Create (7)

| # | File | Purpose |
|---|------|---------|
| 1 | `db/migrate/XXXXXX_add_polymorphic_to_ai_chat_sessions.rb` | Add `chattable_type/id`, `support_agent_id`; make `ai_portfolio_report_id` nullable; drop FK |
| 2 | `app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb` | Abstract interface: `system_prompt`, `build_context`, `tools` + factory `resolve` method |
| 3 | `app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb` | Fallback provider with basic system prompt, no tools |
| 4 | `app/packs/ai/support_agents/services/generic_chat_agent.rb` | Core Trailblazer::Operation — 5 steps: init, resolve provider, setup Langchain, execute, persist |
| 5 | `app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb` | REST API: create (send msg), index (history), destroy (clear) |
| 6 | `app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb` | Reusable chat sidebar partial |
| 7 | `app/javascript/controllers/agent_chat_controller.js` | Stimulus controller for chat UI |

## Files to Modify (3)

| # | File | Change |
|---|------|--------|
| 1 | `app/packs/ai/ai_portfolio_reports/models/ai_chat_session.rb` | Add `optional: true` to `:ai_portfolio_report`, add polymorphic `belongs_to :chattable` and `belongs_to :support_agent` |
| 2 | `app/packs/ai/support_agents/models/support_agent.rb` | Add `chat_enabled?`, `chat_config`, `chat_model` helper methods |
| 3 | `config/routes/ai.rb` | Add `resources :chats, controller: 'support_agent_chats'` nested under `support_agents` |

## Files NOT Touched

- `portfolio_chat_agent.rb` — stays as-is
- `ai_chat_messages_controller.rb` — stays as-is
- `ai_chat_message.rb` — stays as-is
- All existing portfolio report chat UI — stays as-is

---

## Implementation Steps

### Step 1: Migration

**Create** `db/migrate/XXXXXX_add_polymorphic_to_ai_chat_sessions.rb`

```ruby
class AddPolymorphicToAiChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_chat_sessions, :chattable_type, :string, limit: 50
    add_column :ai_chat_sessions, :chattable_id, :bigint
    add_column :ai_chat_sessions, :support_agent_id, :bigint

    change_column_null :ai_chat_sessions, :ai_portfolio_report_id, true
    remove_foreign_key :ai_chat_sessions, :ai_portfolio_reports

    add_index :ai_chat_sessions, [:chattable_type, :chattable_id],
              name: 'index_ai_chat_sessions_on_chattable'
    add_index :ai_chat_sessions, :support_agent_id
  end
end
```

Run `bin/rails db:migrate`.

**Why this is safe:** Existing `AiChatSession` records keep their `ai_portfolio_report_id` values. PortfolioChatAgent creates sessions via `@report.ai_chat_sessions.find_or_create_by!(analyst_id:)` which always sets the FK. Making it nullable + dropping the DB FK doesn't change existing behavior.

---

### Step 2: AiChatSession Model

**Modify** `app/packs/ai/ai_portfolio_reports/models/ai_chat_session.rb`

```ruby
class AiChatSession < ApplicationRecord
  # Existing associations — DO NOT REMOVE
  belongs_to :ai_portfolio_report, optional: true          # was required, now optional
  belongs_to :analyst, class_name: 'User'                  # unchanged
  has_many :ai_chat_messages, dependent: :destroy           # unchanged

  # New: Generic polymorphic target for any chattable record
  belongs_to :chattable, polymorphic: true, optional: true
  belongs_to :support_agent, optional: true

  # A session must belong to either a portfolio report OR a chattable
  validate :must_have_owner

  private

  def must_have_owner
    if ai_portfolio_report_id.blank? && chattable_id.blank?
      errors.add(:base, "Session must belong to either a portfolio report or a chattable record")
    end
  end
end
```

---

### Step 3: SupportAgent Model

**Modify** `app/packs/ai/support_agents/models/support_agent.rb`

Add these methods (don't change existing code):

```ruby
def chat_config
  (json_fields || {}).fetch("chat_config", {})
end

def chat_enabled?
  chat_config["enabled"] == true || chat_config["enabled"] == "true"
end

def chat_model
  chat_config["model"] || ENV.fetch('CHAT_AGENT_MODEL', 'gpt-4o-mini')
end
```

**Config in json_fields:**
```json
{
  "chat_config": {
    "enabled": true,
    "model": "gpt-4o-mini",
    "provider_type": "default",
    "system_prompt": null
  }
}
```

---

### Step 4: BaseChatProvider

**Create** `app/packs/ai/support_agents/services/chat_providers/base_chat_provider.rb`

```ruby
class BaseChatProvider
  attr_reader :support_agent, :target, :analyst

  def initialize(support_agent:, target:, analyst:)
    @support_agent = support_agent
    @target = target
    @analyst = analyst
  end

  # @return [String] system prompt for the LLM
  def system_prompt
    raise NotImplementedError
  end

  # @return [String] additional context to inject
  def build_context
    ""
  end

  # @return [Array] Langchain tool instances
  def tools
    []
  end

  # Factory: resolves the right provider based on agent config
  def self.resolve(support_agent:, target:, analyst:)
    provider_key = support_agent.chat_config["provider_type"]

    provider_class = case provider_key
                     when "cash_flow" then defined?(CashFlowChatProvider) ? CashFlowChatProvider : DefaultChatProvider
                     when "portfolio" then defined?(PortfolioReportChatProvider) ? PortfolioReportChatProvider : DefaultChatProvider
                     else DefaultChatProvider
                     end

    provider_class.new(support_agent: support_agent, target: target, analyst: analyst)
  end
end
```

---

### Step 5: DefaultChatProvider

**Create** `app/packs/ai/support_agents/services/chat_providers/default_chat_provider.rb`

```ruby
class DefaultChatProvider < BaseChatProvider
  def system_prompt
    custom_prompt = support_agent.chat_config["system_prompt"]
    return custom_prompt if custom_prompt.present?

    <<~PROMPT
      You are a helpful AI assistant for #{support_agent.entity&.name || 'the organization'}.
      Agent: #{support_agent.name}
      User: #{analyst&.name || 'Unknown'}

      Guidelines:
      - Be professional and concise
      - Base responses on facts
      - If you don't know something, say so honestly
    PROMPT
  end

  def build_context
    ""
  end

  def tools
    []
  end
end
```

---

### Step 6: GenericChatAgent

**Create** `app/packs/ai/support_agents/services/generic_chat_agent.rb`

```ruby
class GenericChatAgent < SupportAgentService
  STEP_LABELS = {
    initialize_chat: "Initialize",
    resolve_provider: "Load Provider",
    setup_langchain_assistant: "Setup LLM",
    execute_chat: "Execute Chat",
    persist_conversation: "Save Messages"
  }.freeze

  step :initialize_chat
  step :resolve_provider
  step :setup_langchain_assistant
  step :execute_chat
  step :persist_conversation

  private

  def initialize_chat(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent

    analyst = ctx[:analyst_id].present? ? User.find(ctx[:analyst_id]) : nil
    ctx[:analyst] = analyst
    ctx[:chattable] = ctx[:target]

    ctx[:chat_session] = AiChatSession.find_or_create_by!(
      chattable: ctx[:target],
      support_agent: @support_agent,
      analyst_id: analyst&.id
    )
  end

  def resolve_provider(ctx, **)
    ctx[:provider] = BaseChatProvider.resolve(
      support_agent: @support_agent,
      target: ctx[:chattable],
      analyst: ctx[:analyst]
    )
    ctx[:context] = ctx[:provider].build_context
  end

  def setup_langchain_assistant(ctx, **)
    llm = initialize_langchain_llm
    provider = ctx[:provider]

    instructions = provider.system_prompt
    instructions += "\n\nCONTEXT:\n#{ctx[:context]}" if ctx[:context].present?

    assistant = Langchain::Assistant.new(
      llm: llm,
      instructions: instructions,
      tools: provider.tools
    )

    load_conversation_history(ctx[:chat_session], assistant)
    ctx[:assistant] = assistant
  end

  def execute_chat(ctx, **)
    assistant = ctx[:assistant]
    assistant.add_message(content: ctx[:user_message])
    assistant.run(auto_tool_execution: true)
    ctx[:ai_response] = assistant.messages.last.content
  end

  def persist_conversation(ctx, **)
    chat_session = ctx[:chat_session]
    ctx[:assistant].messages.last(2).each do |msg|
      next unless %w[user assistant].include?(msg.role.to_s)
      next if chat_session.ai_chat_messages.exists?(
        role: msg.role, content: msg.content,
        created_at: 5.seconds.ago..Time.current
      )
      chat_session.ai_chat_messages.create!(role: msg.role, content: msg.content, metadata: {})
    end
  end

  def initialize_langchain_llm
    api_key = Rails.application.credentials["OPENAI_API_KEY"] || ENV.fetch('OPENAI_API_KEY', nil)
    raise "OpenAI API key not configured" unless api_key

    Langchain::LLM::OpenAI.new(
      api_key: api_key,
      llm_options: { model: @support_agent.chat_model, temperature: 0.7 }
    )
  end

  def load_conversation_history(chat_session, assistant)
    chat_session.ai_chat_messages.order(:created_at).each do |msg|
      assistant.add_message(role: msg.role, content: msg.content)
    end
  end
end
```

---

### Step 7: Routes

**Modify** `config/routes/ai.rb` — add inside existing `resources :support_agents`:

```ruby
resources :support_agents do
  collection do
    post 'run'
  end
  member do
    post 'run_with_steps'
    post 'cancel'
    get 'status'
    get 'step_details'
  end
  # Generic chat routes
  resources :chats, controller: 'support_agent_chats', only: [:index, :create, :destroy]
end
```

---

### Step 8: SupportAgentChatsController

**Create** `app/packs/ai/support_agents/controllers/support_agent_chats_controller.rb`

```ruby
class SupportAgentChatsController < ApplicationController
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped
  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    @support_agent = SupportAgent.find(params[:support_agent_id])
    target = find_chattable
    return render json: { success: false, error: "Target not found" }, status: :not_found unless target

    result = GenericChatAgent.call(
      support_agent_id: @support_agent.id,
      target: target,
      user_message: params[:message],
      analyst_id: current_user.id
    )

    if result.success?
      session = result[:chat_session]
      ai_msg = session.ai_chat_messages.where(role: 'assistant').last
      render json: { success: true, response: result[:ai_response], message_id: ai_msg&.id, session_id: session.id }
    else
      render json: { success: false, error: "Chat agent execution failed" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[SupportAgentChatsController] #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { success: false, error: "Chat error: #{e.message}" }, status: :internal_server_error
  end

  def index
    @support_agent = SupportAgent.find(params[:support_agent_id])
    target = find_chattable
    session = AiChatSession.find_by(chattable: target, support_agent: @support_agent, analyst_id: current_user.id)

    messages = session ? session.ai_chat_messages.order(:created_at).map { |m|
      { id: m.id, role: m.role, content: m.content, created_at: m.created_at.iso8601 }
    } : []

    render json: { success: true, session_id: session&.id, messages: messages }
  end

  def destroy
    session = AiChatSession.find(params[:id])
    session.destroy!
    render json: { success: true }
  end

  private

  def find_chattable
    return nil unless params[:chattable_type].present? && params[:chattable_id].present?
    params[:chattable_type].constantize.find_by(id: params[:chattable_id])
  rescue NameError
    nil
  end
end
```

---

### Step 9: Stimulus Controller

**Create** `app/javascript/controllers/agent_chat_controller.js`

Key features:
- Values: `supportAgentId`, `chattableType`, `chattableId`, `chatsUrl`, `sessionId`, `expanded`
- Targets: `panel`, `toggleBtn`, `messages`, `input`, `spinner`, `welcome`, `sendBtn`
- `toggle()` — show/hide sidebar, load history on first open
- `sendMessage()` — POST, render user + assistant bubbles
- `loadHistory()` — GET, render existing messages
- `clearChat()` — DELETE session, clear UI
- `handleEnter()` — Enter sends, Shift+Enter newline
- UI helpers matching `voice_chat_controller.js` patterns

---

### Step 10: Chat Panel Partial

**Create** `app/packs/ai/support_agents/views/support_agents/_chat_panel.html.erb`

- Accepts locals: `support_agent`, `chattable`
- Only renders when `support_agent.chat_enabled?`
- Collapsed: floating round button (bottom-right corner)
- Expanded: 400px fixed right sidebar with header, messages, input
- Wired to `data-controller="agent-chat"` with all value attributes

**Mount from any page:**
```erb
<%= render "support_agents/chat_panel", support_agent: @support_agent, chattable: @some_record %>
```

---

## Testing Checkpoints

| After Step | How to Test |
|------------|-------------|
| Step 1 | `bin/rails db:migrate` — verify schema, existing records intact |
| Step 6 | Rails console: `GenericChatAgent.call(support_agent_id: agent.id, target: agent, user_message: "Hello", analyst_id: user.id)` |
| Step 8 | curl `POST /support_agents/:id/chats` with message params |
| Step 10 | Add partial to `support_agents/show.html.erb`, test full UI in browser |

---

## Adding a New Chat Provider (Future Developer Guide)

To make a new agent domain chat-enabled:

1. Create `app/packs/ai/support_agents/services/chat_providers/my_domain_chat_provider.rb`
2. Inherit from `BaseChatProvider`, implement `system_prompt`, `build_context`, `tools`
3. Register in `BaseChatProvider.resolve` with a new `provider_type` key
4. Set `"chat_config": { "enabled": true, "provider_type": "my_domain" }` on the SupportAgent
5. Include `<%= render "support_agents/chat_panel", ... %>` on the relevant page

No new controllers, routes, models, or Stimulus controllers needed.
