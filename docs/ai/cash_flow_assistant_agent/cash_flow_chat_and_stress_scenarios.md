# Cash Flow Assistant — Chat & Stress Scenarios (Phase 2)

## 1. Overview

### Purpose

Extend the Cash Flow Assistant Agent with an **LLM-powered conversational interface** that allows Fund Managers to:

- Ask "what-if" questions about their cash flow data
- Run stress scenarios interactively (expense spikes, delayed realizations)
- Get cross-fund insights and recommendations in natural language
- Generate downloadable stress reports from conversations
- Compare current position against historical runs (last 3 months)

### Design Principles

| Principle | Implementation |
|-----------|----------------|
| Base report stays pure math | LLM chat is layered on top — does not alter the core calculation |
| Configurable per client | `enable_chat` flag in agent config — off by default |
| Chat is exploratory | Base report = source of truth (saved, emailed). Chat/stress = on-demand, downloadable |
| Reuse existing infra | Build on PortfolioChatAgent patterns 

---

## 2. Architecture

### Component Relationship

```
┌─────────────────────────────────────────────────────────────────┐
│                   CASH FLOW ASSISTANT AGENT                      │
│                      (Existing - No Changes)                     │
│  Steps: initialize → staleness → calculate → reports → email    │
│  Output: fund_results saved to SupportAgentReport.json_fields   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ fund_results (computed data)
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CASH FLOW CHAT AGENT (NEW)                      │
│                                                                  │
│  Steps: initialize → load_context → setup_assistant →            │
│         execute_chat → persist_conversation                      │
│                                                                  │
│  Context Injected:                                               │
│    • Current fund_results (all 7 funds)                          │
│    • Last 3 months of SupportAgentReport history                 │
│    • Fund metadata (names, entities, config)                     │
│                                                                  │
│  Tools Available to LLM:                                         │
│    • calculate_stress_scenario — re-run formula with overrides   │
│    • generate_stress_report — produce downloadable HTML          │
│    • compare_historical — diff current vs past runs              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### UI Layout

```
┌──────────────────────────────────┬──────────────────────────────┐
│          LEFT PANE (70%)          │       RIGHT PANE (30%)       │
│                                   │                              │
│  Cash Flow Report (existing)      │  💬 Cash Flow Assistant      │
│                                   │                              │
│  ┌─────────────────────────────┐ │  ┌──────────────────────┐   │
│  │ Computation Fund  Surplus   │ │  │ Ask about your cash  │   │
│  │ Cash: ₹50L                 │ │  │ flow data...         │   │
│  │ Investments: ₹0            │ │  └──────────────────────┘   │
│  │ Expenses: ₹1.98L           │ │                              │
│  │ Net: ₹43.02L               │ │  FM: What if expenses go    │
│  │ Runway: 180+ days          │ │  up 30% across all funds?   │
│  │ ...                         │ │                              │
│  └─────────────────────────────┘ │  🤖: I've run the stress    │
│                                   │  scenario across all 7       │
│  ┌─────────────────────────────┐ │  funds. Here's the impact:  │
│  │ Fund 1  SHORTFALL           │ │                              │
│  │ ...                         │ │  • Computation Fund: stays   │
│  └─────────────────────────────┘ │    surplus (₹43L → ₹42.4L) │
│                                   │  • Fund 1: shortfall grows  │
│  ┌─────────────────────────────┐ │    (₹-499Cr → ₹-514Cr)     │
│  │ Test Fund II  BLOCKED       │ │  • Syndicate 2: flips from  │
│  │ ...                         │ │    shortfall to critical     │
│  └─────────────────────────────┘ │                              │
│                                   │  [📄 Download Stress Report] │
│                                   │                              │
│                                   │  FM: Generate a report for  │
│                                   │  this scenario               │
│                                   │                              │
│                                   │  🤖: Here's your stress     │
│                                   │  report comparing base vs   │
│                                   │  +30% expenses.             │
│                                   │  [⬇ Download PDF]           │
│                                   │                              │
└──────────────────────────────────┴──────────────────────────────┘
```

Chat pane only appears when `enable_chat: true` in agent config.

---

## 3. Data Model

### 3.1 Agent Configuration Changes

Add to `SupportAgent.json_fields`:

```json
{
  "funds": [...],
  "cash_tags": "...",
  "expense_tags": "...",
  "buffer_tags": "...",
  "report_recipients": "...",

  "chat_config": {
    "enabled": false,
    "model": "gpt-4o-mini",
    "historical_months": 3
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `chat_config.enabled` | Boolean | `false` | Show chat pane on report page |
| `chat_config.model` | String | `"gpt-4o-mini"` | LLM model for chat |
| `chat_config.historical_months` | Integer | `3` | Months of past reports to include as context |

### 3.2 Chat Session Storage

**Option A (Recommended): Extend existing AiChatSession to be polymorphic**

Currently `AiChatSession` belongs to `AiPortfolioReport`. Make it polymorphic:

```ruby
# Migration
add_column :ai_chat_sessions, :chatable_type, :string
add_column :ai_chat_sessions, :chatable_id, :bigint
add_index  :ai_chat_sessions, [:chatable_type, :chatable_id]

# Backfill existing records
AiChatSession.update_all(
  chatable_type: "AiPortfolioReport",
  "chatable_id = ai_portfolio_report_id"
)
```

```ruby
# Model
class AiChatSession < ApplicationRecord
  belongs_to :chatable, polymorphic: true  # AiPortfolioReport OR SupportAgentReport
  belongs_to :analyst, class_name: "User"
  has_many :ai_chat_messages, dependent: :destroy
end
```

For Cash Flow chat, `chatable` = the entity-level `SupportAgentReport` (the main execution report, not per-fund reports).

**Session creation:**
- One session per analyst per SupportAgentReport
- Created on first chat interaction
- Persists across page reloads (FM can continue conversation)

### 3.3 No New Tables Required

- `AiChatSession` — reused (polymorphic)
- `AiChatMessage` — reused as-is (role, content, metadata)
- `SupportAgentReport` — already stores fund_results in json_fields (used as context)

---

## 4. CashFlowChatAgent Service

### 4.1 Class Structure

```ruby
class CashFlowChatAgent < SupportAgentService
  step :initialize_chat_agent
  step :load_cash_flow_context
  step :setup_langchain_assistant
  step :execute_chat
  step :persist_conversation

  # Tools available to the LLM
  def calculate_stress_scenario(expense_multiplier: 1.0, exclude_realizations: false, delay_days: 0)
  def generate_stress_report(scenario_label:, overrides:)
  def compare_historical(fund_id: nil, months_back: 3)
end
```

### 4.2 Step: load_cash_flow_context

This is the key step — assembles all data the LLM needs.

```ruby
def load_cash_flow_context(ctx, **)
  report = ctx[:support_agent_report]  # entity-level report
  agent  = ctx[:support_agent]

  # 1. Current fund results (from latest agent run)
  current_results = load_current_fund_results(agent)

  # 2. Historical fund results (last N months)
  history = load_historical_results(agent, months: chat_config["historical_months"] || 3)

  # 3. Agent config (fund names, tags, thresholds)
  config_summary = summarize_agent_config(agent)

  ctx[:cash_flow_context] = {
    current: current_results,
    history: history,
    config: config_summary
  }
end
```

**`load_current_fund_results`**: Reads per-fund `SupportAgentReport` records:

```ruby
def load_current_fund_results(agent)
  agent.json_fields["funds"].filter_map do |fc|
    fund = Fund.find_by(id: fc["fund_id"])
    next unless fund

    report = SupportAgentReport.find_by(owner: fund, support_agent: agent)
    next unless report

    report.json_fields.merge("fund_name" => fund.name, "fund_id" => fund.id)
  end
end
```

**`load_historical_results`**: Queries past report snapshots. Since `SupportAgentReport` currently stores only the latest, we have two options:

- **Option A**: Add a `SupportAgentReportSnapshot` table that archives each run (recommended for history)
- **Option B**: Store history in the report's `json_fields` as an array of past runs (simpler, limited)

Recommended: **Option A** — create a lightweight snapshot table:

```ruby
# Migration
create_table :support_agent_report_snapshots do |t|
  t.references :support_agent, null: false
  t.references :owner, polymorphic: true, null: false  # Fund
  t.json       :json_fields                             # fund_result snapshot
  t.date       :report_date, null: false
  t.timestamps
end
add_index :support_agent_report_snapshots,
          [:support_agent_id, :owner_type, :owner_id, :report_date],
          unique: true, name: 'idx_agent_report_snapshots_unique'
```

The existing `generate_fund_reports` step in CashFlowAssistantAgent saves a snapshot on each run:

```ruby
# Add to generate_fund_reports step (existing agent)
SupportAgentReportSnapshot.create!(
  support_agent: @support_agent,
  owner: fund,
  json_fields: fund_result.deep_stringify_keys,
  report_date: Time.zone.today
)
```

### 4.3 System Prompt Construction

```ruby
def build_system_instructions(cash_flow_context)
  <<~PROMPT
    You are a Cash Flow Assistant for a Fund Manager. You help analyze
    cash flow positions across funds and answer "what-if" questions.

    ## Current Cash Flow Data (as of #{Time.zone.today.strftime('%d-%b-%Y')})

    #{format_current_results(cash_flow_context[:current])}

    ## Historical Comparison (Last #{cash_flow_context[:history].size} runs)

    #{format_historical_results(cash_flow_context[:history])}

    ## Fund Configuration

    #{cash_flow_context[:config]}

    ## Your Capabilities

    You have access to these tools:

    1. **calculate_stress_scenario** — Re-run the cash flow formula with
       modified inputs. Use this when the FM asks "what if" questions.
       Parameters: expense_multiplier (e.g. 1.25 for +25%), exclude_realizations
       (true/false), delay_days (push realization dates forward).

    2. **generate_stress_report** — Create a downloadable HTML report comparing
       base case vs a stress scenario. Use when FM asks to "generate a report"
       or "download" a scenario.

    3. **compare_historical** — Compare current fund results with past runs.
       Use when FM asks about trends, changes, or historical performance.

    ## Guidelines

    - Use actual numbers from the data above. Never fabricate figures.
    - When answering what-if questions, ALWAYS use the calculate_stress_scenario
      tool to get accurate numbers. Do not estimate manually.
    - Present amounts in Indian format (lakhs/crores) matching the fund currency.
    - Be concise. Lead with the answer, then explain.
    - When a scenario flips a fund's status (e.g., surplus → shortfall),
      highlight this prominently.
    - For cross-fund questions, summarize all affected funds in a table.
    - When the FM asks to generate/download a report, use generate_stress_report.
  PROMPT
end
```

**Example context injected for current results:**

```
Fund: Computation Fund (id: 99) — Status: Surplus
  Cash Available: ₹50,00,000 | Upcoming Investments: ₹0
  Estimated Expenses: ₹1,98,000 (via Linear Regression, 6 months)
  Monthly predictions: [₹60,000, ₹63,000, ₹75,000]
  Buffer: ₹5,00,000 | Net Position: ₹43,02,000 | Runway: 180+ days

Fund: Fund 1 (id: 11) — Status: SHORTFALL
  Cash Available: ₹10,00,000 | Upcoming Investments: ₹500,00,00,000
  Estimated Expenses: ₹65,000 (via Linear Regression, 6 months)
  Buffer: ₹1,00,000 | Net Position: ₹-499,29,50,000 | Runway: 0 days
  Recommended Call: ₹499,39,50,000

... (all 7 funds)
```

---

## 5. LLM Tools (Detailed)

### 5.1 calculate_stress_scenario

**Purpose**: Re-runs the net position formula with modified inputs. Returns structured results the LLM can present to the FM.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `expense_multiplier` | Float | `1.0` | Multiply estimated expenses (1.25 = +25%) |
| `exclude_realizations` | Boolean | `false` | Remove sale proceeds (PI < 0) from calculation |
| `delay_days` | Integer | `0` | Push realization dates forward by N days |
| `fund_id` | Integer | `nil` | Apply to specific fund (nil = all funds) |

**Returns:**

```json
{
  "scenario_label": "Expenses +25%",
  "funds": [
    {
      "fund_id": 99,
      "name": "Computation Fund",
      "base_net_position": 4302000,
      "stress_net_position": 4252500,
      "base_runway_days": 999,
      "stress_runway_days": 999,
      "base_status": "surplus",
      "stress_status": "surplus",
      "status_changed": false,
      "delta": -49500
    },
    {
      "fund_id": 102,
      "name": "Syndicate 2",
      "base_net_position": -1500000,
      "stress_net_position": -1662500,
      "base_status": "shortfall",
      "stress_status": "shortfall",
      "status_changed": false,
      "delta": -162500
    }
  ],
  "summary": {
    "funds_affected": 7,
    "status_flips": 1,
    "total_delta": -850000
  }
}
```

**Implementation:**

```ruby
def calculate_stress_scenario(expense_multiplier: 1.0, exclude_realizations: false, delay_days: 0, fund_id: nil)
  results = @current_fund_results.map do |fr|
    next fr if fund_id && fr["fund_id"] != fund_id

    base_expenses    = fr["estimated_expenses"].to_i
    base_investments = fr["upcoming_investments"].to_i
    cash             = fr["cash_available"].to_i
    buffer           = fr["buffer_required"].to_i

    # Apply stress overrides
    stress_expenses = (base_expenses * expense_multiplier).round

    stress_investments = base_investments
    if exclude_realizations
      # Remove any negative PI (sale proceeds) — currently not tracked separately,
      # would need investment_list entries with negative amounts
      stress_investments = base_investments  # Future: filter out realizations
    end

    # Delay: if investments have expected_dates within 90-day window,
    # push them out — some may fall outside the window
    if delay_days > 0
      stress_investments = recalculate_investments_with_delay(fr, delay_days)
    end

    stress_net = cash - stress_investments - stress_expenses - buffer
    stress_daily_outflow = (stress_investments + stress_expenses).to_f / 90
    stress_runway = stress_daily_outflow.positive? ? (cash / stress_daily_outflow).round : 999

    stress_status = if stress_net.negative? then "shortfall"
                    elsif stress_runway < 90 then "watch"
                    else "surplus"
                    end

    {
      fund_id: fr["fund_id"],
      name: fr["name"],
      base_net_position: fr["net_position"],
      stress_net_position: stress_net,
      base_runway_days: fr["runway_days"],
      stress_runway_days: stress_runway,
      base_status: fr["fund_status"],
      stress_status: stress_status,
      status_changed: fr["fund_status"] != stress_status,
      delta: stress_net - fr["net_position"].to_i
    }
  end

  format_stress_results(results)
end
```

### 5.2 generate_stress_report

**Purpose**: Produces a downloadable HTML document comparing base case vs stress scenario.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `scenario_label` | String | Human-readable label, e.g., "Expenses +30%, Realizations delayed 60d" |
| `overrides` | Hash | Same params as calculate_stress_scenario |

**Behavior:**

1. Calls `calculate_stress_scenario` internally with the overrides
2. Renders an HTML template (similar to existing `_cash_flow_fund_report_html.html.erb`) with:
   - Header: "Cash Flow Stress Analysis — {scenario_label}"
   - Timestamp: when the stress report was generated
   - Per-fund table: Base Case vs Stress Case vs Delta
   - Status change highlights
   - Assumptions section (what overrides were applied)
3. Returns the HTML as a downloadable blob (stored temporarily or streamed)
4. Does NOT save to the fund's Reports folder (stress reports are ephemeral)

**Output format in chat:**

```
🤖: I've generated the stress report. Here's a summary:

3 of 7 funds are impacted. Syndicate 2 flips from Watch to Shortfall.

[📄 Download: Stress Analysis - Expenses +30% (13-Feb-2026).html]
```

**HTML Template Structure:**

```html
<!DOCTYPE html>
<html>
<head>
  <title>Cash Flow Stress Analysis — {{scenario_label}}</title>
</head>
<body>
  <h2>Cash Flow Stress Analysis</h2>
  <p>Scenario: {{scenario_label}}</p>
  <p>Generated: {{timestamp}} | Base report date: {{base_report_date}}</p>

  <h3>Portfolio Impact</h3>
  <table>
    <tr>
      <th>Fund</th>
      <th>Base Status</th>
      <th>Stress Status</th>
      <th>Base Net Position</th>
      <th>Stress Net Position</th>
      <th>Delta</th>
    </tr>
    {{#each funds}}
    <tr class="{{#if status_changed}}highlight{{/if}}">
      <td>{{name}}</td>
      <td>{{base_status}}</td>
      <td>{{stress_status}}</td>
      <td>{{base_net_position}}</td>
      <td>{{stress_net_position}}</td>
      <td>{{delta}}</td>
    </tr>
    {{/each}}
  </table>

  <h3>Assumptions</h3>
  <ul>
    <li>Expense multiplier: {{expense_multiplier}}x ({{expense_pct_label}})</li>
    <li>Realizations excluded: {{exclude_realizations}}</li>
    <li>Realization delay: {{delay_days}} days</li>
  </ul>

  <h3>Per-Fund Detail</h3>
  {{#each funds}}
    <h4>{{name}} {{#if status_changed}}⚠️ STATUS CHANGE{{/if}}</h4>
    <table>
      <tr><th>Component</th><th>Base Case</th><th>Stress Case</th></tr>
      <tr><td>Cash Available</td><td>{{cash}}</td><td>{{cash}} (unchanged)</td></tr>
      <tr><td>Upcoming Investments</td><td>{{base_inv}}</td><td>{{stress_inv}}</td></tr>
      <tr><td>Estimated Expenses</td><td>{{base_exp}}</td><td>{{stress_exp}}</td></tr>
      <tr><td>Buffer Required</td><td>{{buffer}}</td><td>{{buffer}} (unchanged)</td></tr>
      <tr><td>Net Position</td><td>{{base_net}}</td><td>{{stress_net}}</td></tr>
      <tr><td>Runway</td><td>{{base_runway}}</td><td>{{stress_runway}}</td></tr>
    </table>
  {{/each}}
</body>
</html>
```

### 5.3 compare_historical

**Purpose**: Retrieves and compares historical report snapshots.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fund_id` | Integer | `nil` | Specific fund (nil = all funds) |
| `months_back` | Integer | `3` | How many months to look back |

**Returns:**

```json
{
  "fund_name": "Computation Fund",
  "trend": [
    {
      "report_date": "2025-12-01",
      "net_position": 3500000,
      "runway_days": 160,
      "status": "surplus",
      "cash_available": 4200000,
      "estimated_expenses": 180000
    },
    {
      "report_date": "2026-01-01",
      "net_position": 3800000,
      "runway_days": 170,
      "status": "surplus",
      "cash_available": 4600000,
      "estimated_expenses": 190000
    },
    {
      "report_date": "2026-02-13",
      "net_position": 4302000,
      "runway_days": 999,
      "status": "surplus",
      "cash_available": 5000000,
      "estimated_expenses": 198000
    }
  ],
  "observations": {
    "net_position_trend": "improving",
    "cash_change_pct": "+19%",
    "expense_change_pct": "+10%"
  }
}
```

**Implementation reads from `SupportAgentReportSnapshot`:**

```ruby
def compare_historical(fund_id: nil, months_back: 3)
  cutoff = months_back.months.ago.to_date

  funds = fund_id ? [{ "fund_id" => fund_id }] : @config["funds"]

  funds.filter_map do |fc|
    fund = Fund.find_by(id: fc["fund_id"])
    next unless fund

    snapshots = SupportAgentReportSnapshot
      .where(support_agent: @support_agent, owner: fund)
      .where("report_date >= ?", cutoff)
      .order(report_date: :asc)
      .pluck(:report_date, :json_fields)

    {
      fund_id: fund.id,
      fund_name: fund.name,
      trend: snapshots.map { |date, data| data.merge("report_date" => date) }
    }
  end
end
```

---

## 6. Conversation Examples

### Example 1: What-if expense spike

```
FM: What happens if expenses increase by 40% next quarter?

🤖: [calls calculate_stress_scenario(expense_multiplier: 1.4)]

With a 40% expense increase across all funds:

| Fund              | Base Net     | Stress Net   | Status Change |
|-------------------|-------------|-------------|---------------|
| Computation Fund  | ₹43.02L    | ₹42.23L    | No (Surplus)  |
| Fund 1            | ₹-499.3Cr  | ₹-499.3Cr  | No (Shortfall)|
| Syndicate 2       | ₹-2.00L    | ₹-2.65L    | No (Shortfall)|
| Syndicate 3       | ₹2.63L     | ₹2.26L     | No (Watch)    |
| Syndicate 4       | Blocked     | Blocked     | —             |
| Test Fund II      | ₹5.35L     | ₹4.74L     | No (Watch)    |
| Demo Fund         | Blocked     | Blocked     | —             |

No fund status changes at +40%. The biggest impact is on Syndicate 2,
where the shortfall deepens by ₹65K. Computation Fund absorbs the
increase easily given its ₹43L surplus.
```

### Example 2: Historical trend

```
FM: How has Fund 1's runway changed over the last 3 months?

🤖: [calls compare_historical(fund_id: 11, months_back: 3)]

Fund 1 runway over the last 3 runs:

| Run Date     | Runway  | Net Position | Status    |
|-------------|---------|-------------|-----------|
| Dec 2025    | 45 days | ₹2.1Cr     | Watch     |
| Jan 2026    | 12 days | ₹-3.2Cr   | Shortfall |
| Feb 2026    | 0 days  | ₹-499Cr   | Shortfall |

The situation has deteriorated significantly. The jump from Jan to Feb
is due to a large proforma investment (₹500Cr) being added. Before
that proforma, the fund was already trending toward shortfall.

I'd recommend reviewing whether that proforma is still expected to
deploy at full amount, or if it can be staged.
```

### Example 3: Generate downloadable report

```
FM: Can you generate a stress report assuming 25% expense increase
    and no sale realizations?

🤖: [calls generate_stress_report(
      scenario_label: "Expenses +25%, No Sale Realizations",
      overrides: { expense_multiplier: 1.25, exclude_realizations: true }
    )]

I've generated the stress report. Here's a quick summary:

• 2 funds impacted by the combined stress
• Total portfolio delta: ₹-12.4L
• No status flips at this level

📄 Download: Cash Flow Stress Analysis - Expenses +25%, No Sale
   Realizations (13-Feb-2026).html
```

---

## 7. Controller & API

### 7.1 New Controller: CashFlowChatController

```ruby
# app/packs/ai/support_agents/controllers/cash_flow_chat_controller.rb

class CashFlowChatController < ApplicationController
  before_action :find_support_agent
  before_action :ensure_chat_enabled

  # POST /support_agents/:support_agent_id/chat
  # Params: { message: "What if expenses go up 30%?" }
  def create
    chat_session = find_or_create_chat_session

    result = CashFlowChatAgent.call(
      support_agent_id: @support_agent.id,
      target: chat_session,
      user_message: params[:message],
      user_id: current_user.id
    )

    render json: {
      response: result[:ai_response],
      downloads: result[:pending_downloads] || []  # Stress report URLs
    }
  end

  # GET /support_agents/:support_agent_id/chat
  # Returns chat history
  def index
    chat_session = current_chat_session
    return render json: { messages: [] } unless chat_session

    messages = chat_session.ai_chat_messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content,
        created_at: msg.created_at,
        downloads: msg.metadata&.dig("downloads")
      }
    end

    render json: { messages: messages }
  end

  # GET /support_agents/:support_agent_id/chat/download_stress_report/:id
  # Serves a previously generated stress report
  def download_stress_report
    # Fetch from temporary storage (Redis/file) by report ID
    # Return as HTML attachment
  end

  private

  def find_support_agent
    @support_agent = SupportAgent.find(params[:support_agent_id])
  end

  def ensure_chat_enabled
    config = @support_agent.json_fields.dig("chat_config") || {}
    unless config["enabled"]
      render json: { error: "Chat not enabled for this agent" }, status: :forbidden
    end
  end

  def find_or_create_chat_session
    # Find latest entity-level report for this agent
    report = SupportAgentReport.find_by(
      support_agent: @support_agent,
      owner: @support_agent.entity
    )

    AiChatSession.find_or_create_by!(
      chatable: report,
      analyst_id: current_user.id
    )
  end

  def current_chat_session
    report = SupportAgentReport.find_by(
      support_agent: @support_agent,
      owner: @support_agent.entity
    )
    return nil unless report

    AiChatSession.find_by(chatable: report, analyst_id: current_user.id)
  end
end
```

### 7.2 Routes

```ruby
# config/routes.rb (within existing support_agents scope)
resources :support_agents do
  resource :cash_flow_chat, only: [:index, :create], controller: 'cash_flow_chat' do
    get 'download_stress_report/:report_id', action: :download_stress_report, as: :download
  end
end
```

---

## 8. Historical Report Snapshots

### 8.1 Migration

```ruby
class CreateSupportAgentReportSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :support_agent_report_snapshots do |t|
      t.references :support_agent, null: false, foreign_key: true
      t.string     :owner_type, null: false
      t.bigint     :owner_id, null: false
      t.json       :json_fields
      t.date       :report_date, null: false
      t.timestamps
    end

    add_index :support_agent_report_snapshots,
              [:support_agent_id, :owner_type, :owner_id, :report_date],
              unique: true,
              name: 'idx_report_snapshots_unique'
  end
end
```

### 8.2 Integration with Existing Agent

Add snapshot creation to `CashFlowAssistantAgent#generate_fund_reports`:

```ruby
# Inside the existing fund_results.each loop, after saving SupportAgentReport:
SupportAgentReportSnapshot.create!(
  support_agent: @support_agent,
  owner: fund,
  json_fields: fund_result.deep_stringify_keys,
  report_date: Time.zone.today
)
```

### 8.3 Cleanup

Retain snapshots for a configurable period (default: 12 months):

```ruby
# In a periodic cleanup job
SupportAgentReportSnapshot
  .where("report_date < ?", 12.months.ago)
  .delete_all
```

---

## 9. What the FM Sees (Report Page Changes)

### 9.1 When `chat_config.enabled = false` (default)

No changes. The report page looks exactly as it does today.

### 9.2 When `chat_config.enabled = true`

The report page gains a collapsible right pane:

```
┌─────────────────────────────────────────────────────┬────────┐
│  Cash Flow Report (existing, unchanged)              │  💬    │ ← toggle button
│                                                      │        │
│  ... all existing fund cards and details ...         │        │
│                                                      │        │
└─────────────────────────────────────────────────────┴────────┘
```

Clicking the chat toggle opens the right pane (30% width):

```
┌────────────────────────────────────────┬────────────────────────┐
│  Cash Flow Report                      │ 💬 Cash Flow Assistant │
│  (shrinks to 70%)                      │                        │
│                                        │  [chat messages...]    │
│                                        │                        │
│                                        │  ┌──────────────────┐ │
│                                        │  │ Ask a question... │ │
│                                        │  └──────────────────┘ │
└────────────────────────────────────────┴────────────────────────┘
```

### 9.3 Chat Message Types

| Type | Rendering |
|------|-----------|
| Text response | Markdown rendered in chat bubble |
| Table data | Formatted HTML table inside chat bubble |
| Downloadable report | Chat bubble with download button/link |
| Status flip warning | Highlighted chat bubble (red/yellow border) |

---

## 10. Stress Scenario Coverage (from BRD)

### BRD Requirement 1: Delayed Realization

> "If there is an expected realization from sale of PI, highlight that a delay in realization will lead to a shortfall"

**Implementation**: `calculate_stress_scenario(exclude_realizations: true)` or `calculate_stress_scenario(delay_days: 60)`

**Requires**: Proforma PortfolioInvestments with negative amounts (PI < 0 = expected sale proceeds). Currently the agent only tracks PI > 0 (outflows). To fully support this:

- Extend `aggregate_investments` to separately track:
  - `upcoming_investments` (PI > 0, outflows)
  - `expected_realizations` (PI < 0, inflows)
- Include `expected_realizations` in the net position formula:
  ```
  Net Position = Cash + Realizations - Investments - Expenses - Buffer
  ```
- The stress tool can then remove or delay realizations independently

### BRD Requirement 2: Expense Spike (+25%)

> "In case expenses for the quarter are 25% more than the average considered, what is the impact on surplus/shortfall"

**Implementation**: `calculate_stress_scenario(expense_multiplier: 1.25)`

Fully covered by the tool. The FM can ask for any multiplier via chat.

### Additional Scenarios (enabled by chat)

The conversational interface naturally supports questions the BRD didn't specify:

- "What if we delay the Deal Alpha investment by 30 days?"
- "How much more cash do we need to cover a 50% expense spike?"
- "Which fund should we prioritize for capital call?"
- "Compare this month's position to last month"

---

## 11. Configuration UI Changes

Add a "Chat Settings" section to the agent configuration page:

```
┌─────────────────────────────────────────────────────────────┐
│  CHAT ASSISTANT SETTINGS                                     │
│  ─────────────────────────────────────────────────────────   │
│                                                              │
│  Enable Chat Assistant:  [Toggle: ON/OFF]                    │
│                                                              │
│  LLM Model:             [ gpt-4o-mini    ▼]                 │
│                          Options: gpt-4o-mini, gpt-4o,       │
│                          claude-sonnet                        │
│                                                              │
│  Historical Context:     [ 3 ] months                        │
│                          How many past reports the chat       │
│                          can reference for trend analysis     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 12. Implementation Plan

### Phase 2a: Foundation (Chat Infrastructure)

| # | Task | Effort |
|---|------|--------|
| 1 | Make `AiChatSession` polymorphic (migration + model change) | Small |
| 2 | Create `SupportAgentReportSnapshot` table + migration | Small |
| 3 | Add snapshot creation to existing `CashFlowAssistantAgent#generate_fund_reports` | Small |
| 4 | Add `chat_config` to agent configuration UI | Small |
| 5 | Create `CashFlowChatAgent` service (steps, context loading) | Medium |
| 6 | Implement `calculate_stress_scenario` tool | Medium |
| 7 | Create `CashFlowChatController` (create, index endpoints) | Medium |
| 8 | Build chat pane UI component (right panel, toggle, message display) | Medium |

### Phase 2b: Stress Reports & History

| # | Task | Effort |
|---|------|--------|
| 9 | Implement `generate_stress_report` tool (HTML template, temp storage) | Medium |
| 10 | Implement `compare_historical` tool | Small |
| 11 | Add download endpoint for stress reports | Small |
| 12 | Display download buttons in chat messages | Small |

### Phase 2c: Realizations Support

| # | Task | Effort |
|---|------|--------|
| 13 | Extend `aggregate_investments` to separate PI > 0 and PI < 0 | Medium |
| 14 | Add `expected_realizations` to fund_result and report template | Small |
| 15 | Update `calculate_stress_scenario` to handle realization delays | Small |
| 16 | Update base report to show realizations section | Small |

### Dependencies

```
Phase 2a [1-8] ← can start immediately, no changes to existing agent logic
Phase 2b [9-12] ← depends on 2a (needs chat working)
Phase 2c [13-16] ← independent, can run in parallel with 2a/2b
```

---

## 13. Cost & Performance Considerations

| Concern | Mitigation |
|---------|------------|
| LLM cost per chat message | Default to `gpt-4o-mini` (cheap, fast). Configurable per client. |
| Context window size | Limit to current run + 3 months history. Cap at ~8K tokens of context. |
| Stress calculation latency | Tool runs pure Ruby math — no DB queries needed (data already in context). Sub-100ms. |
| Stress report generation | HTML template rendering — fast. No PDF conversion needed (HTML is downloadable). |
| Snapshot storage growth | 7 funds × 12 months × ~2KB JSON = ~168KB/year per agent. Negligible. |
| Chat session cleanup | Sessions auto-expire when a new agent run creates a new SupportAgentReport. Old sessions remain readable but new chats attach to latest report. |

---

## 14. Summary

| Feature | Storage | Saved to Fund | Emailed | Interactive |
|---------|---------|---------------|---------|-------------|
| Base Cash Flow Report | SupportAgentReport + fund folder doc | Yes | Yes | No (static) |
| Chat Conversation | AiChatSession + AiChatMessages | No | No | Yes |
| Stress Report (download) | Temporary (Redis/file, 24h TTL) | No | No | Generated on-demand |
| Historical Snapshots | SupportAgentReportSnapshot | N/A | N/A | Read via chat |
